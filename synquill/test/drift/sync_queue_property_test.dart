// Property-based / parametrised tests for sync queue edge cases.
//
// These are data-driven tests with many input combinations — hand-rolled
// parametrised testing rather than a third-party library.
//
// All tests run against an in-memory SQLite database (drift/tier) with no
// SynquillStorage.init required.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:test/test.dart';
import 'package:synquill/synquill.dart';

// ---------------------------------------------------------------------------
// Minimal test database (same schema as TestDatabase in common/)
// ---------------------------------------------------------------------------

class _PropertyTestDatabase extends GeneratedDatabase {
  _PropertyTestDatabase(super.e);

  @override
  Iterable<TableInfo<Table, DataClass>> get allTables => [];

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await customStatement('''
            CREATE TABLE sync_queue_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              model_type TEXT NOT NULL,
              model_id TEXT NOT NULL,
              temporary_client_id TEXT,
              id_negotiation_status TEXT DEFAULT 'complete',
              payload TEXT NOT NULL,
              op TEXT NOT NULL,
              attempt_count INTEGER NOT NULL DEFAULT 0,
              last_error TEXT,
              next_retry_at INTEGER,
              idempotency_key TEXT,
              status TEXT NOT NULL DEFAULT 'pending',
              created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
              headers TEXT,
              extra TEXT
            )
          ''');
        },
      );
}

// ---------------------------------------------------------------------------
// Generators / data
// ---------------------------------------------------------------------------

final _rng = Random(42); // fixed seed for reproducibility

/// Generates a random alphanumeric string of length [length].
String _randomString(int length) {
  const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  return List.generate(length, (_) => chars[_rng.nextInt(chars.length)]).join();
}

/// A handful of tricky model ID strings including SQL special characters.
final _trickySqlIds = [
  "it's tricky", // single quote
  'double"quote',
  'semi;colon',
  'dash--comment',
  'slash\\backslash',
  'null\x00char',
  '%wildcard%',
  '_underscore_',
  '', // Empty string — unusual but the DB allows it
  'a' * 512, // Very long id
];

/// Generates a JSON payload of approximately [targetBytes] bytes.
String _largePayload(int targetBytes) {
  final data = <String, dynamic>{
    'id': 'bulk-model',
    'data': 'x' * max(0, targetBytes - 50),
  };
  return jsonEncode(data);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _PropertyTestDatabase db;
  late SyncQueueDao dao;

  setUp(() {
    db = _PropertyTestDatabase(NativeDatabase.memory());
    dao = SyncQueueDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Insertion robustness', () {
    test('1 000 items with random model IDs all insert successfully', () async {
      for (var i = 0; i < 1000; i++) {
        final modelId = _randomString(16 + _rng.nextInt(16));
        final id = await dao.insertItem(
          modelId: modelId,
          modelType: 'BulkModel',
          payload: jsonEncode({'id': modelId, 'seq': i}),
          operation: 'create',
          idempotencyKey: 'bulk-$i',
        );
        expect(id, isA<int>());
        expect(id, greaterThan(0));
      }

      final all = await dao.getAllItems();
      expect(all, hasLength(1000));
    });

    test(
        'model IDs with SQL special characters are stored and retrieved intact',
        () async {
      for (final trickyId in _trickySqlIds) {
        if (trickyId.isEmpty) continue; // skip genuinely empty ids
        final payloadJson = jsonEncode({'id': trickyId});
        final inserted = await dao.insertItem(
          modelId: trickyId,
          modelType: 'TrickyModel',
          payload: payloadJson,
          operation: 'create',
          idempotencyKey: 'tricky-${trickyId.hashCode}',
        );

        final retrieved = await dao.getItemById(inserted);
        expect(retrieved, isNotNull,
            reason: 'Expected to retrieve item with id "$trickyId"');
        expect(retrieved!['model_id'], equals(trickyId),
            reason: 'model_id should round-trip without mutation');
        expect(retrieved['payload'], equals(payloadJson));
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('getDueTasks ordering', () {
    test(
        'past-scheduled items are returned before future-scheduled items '
        'regardless of insertion order', () async {
      final now = DateTime.now();
      final past = now.subtract(const Duration(minutes: 5));
      final future = now.add(const Duration(hours: 1));

      // Insert future items first, then past items.
      for (var i = 0; i < 5; i++) {
        await dao.insertItem(
          modelId: 'future-$i',
          modelType: 'OrderModel',
          payload: '{}',
          operation: 'create',
          nextRetryAt: future,
          idempotencyKey: 'future-$i',
        );
      }
      for (var i = 0; i < 5; i++) {
        await dao.insertItem(
          modelId: 'past-$i',
          modelType: 'OrderModel',
          payload: '{}',
          operation: 'create',
          nextRetryAt: past,
          idempotencyKey: 'past-$i',
        );
      }

      final due = await dao.getDueTasks();

      // Only past-scheduled items should appear.
      expect(due, hasLength(5));
      for (final item in due) {
        expect(
          (item['model_id'] as String).startsWith('past-'),
          isTrue,
          reason: 'Only past-scheduled items should be returned as due',
        );
      }
    });

    test('items with null next_retry_at are always considered due', () async {
      // Null means "ready immediately".
      await dao.insertItem(
        modelId: 'null-retry',
        modelType: 'NullModel',
        payload: '{}',
        operation: 'create',
        // nextRetryAt omitted → null
      );

      final due = await dao.getDueTasks();
      expect(due.any((i) => i['model_id'] == 'null-retry'), isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Status transition consistency', () {
    test(
        'insert → updateItem(attemptCount++) × 3 → deleteTask '
        'leaves queue empty', () async {
      final id = await dao.insertItem(
        modelId: 'transition-model',
        modelType: 'TransitionModel',
        payload: '{}',
        operation: 'create',
        idempotencyKey: 'transition-key',
      );

      for (var attempt = 1; attempt <= 3; attempt++) {
        final updated = await dao.updateItem(
          id: id,
          attemptCount: attempt,
          lastError: 'Attempt $attempt failed',
          nextRetryAt: DateTime.now().add(Duration(minutes: attempt)),
        );
        expect(updated, equals(1));

        final item = await dao.getItemById(id);
        expect(item!['attempt_count'], equals(attempt));
      }

      final deleted = await dao.deleteTask(id);
      expect(deleted, equals(1));

      expect(await dao.getItemById(id), isNull);
      expect(await dao.getAllItems(), isEmpty);
    });

    for (final op in ['create', 'update', 'delete', 'read']) {
      test('operation "$op" round-trips correctly', () async {
        final id = await dao.insertItem(
          modelId: 'op-test-$op',
          modelType: 'OpModel',
          payload: '{"op":"$op"}',
          operation: op,
          idempotencyKey: 'op-$op',
        );

        final item = await dao.getItemById(id);
        expect(item!['op'], equals(op));

        await dao.deleteTask(id);
      });
    }
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Idempotency key uniqueness', () {
    test('two items with the same idempotency_key produce two independent rows',
        () async {
      // SyncQueueDao does NOT enforce uniqueness — that is the job of
      // RequestQueueManager.  Two rows with the same key should be storable.
      final id1 = await dao.insertItem(
        modelId: 'ik-model-1',
        modelType: 'IkModel',
        payload: '{}',
        operation: 'create',
        idempotencyKey: 'shared-key',
      );
      final id2 = await dao.insertItem(
        modelId: 'ik-model-2',
        modelType: 'IkModel',
        payload: '{}',
        operation: 'create',
        idempotencyKey: 'shared-key',
      );

      expect(id1, isNot(equals(id2)),
          reason: 'Each insert must produce a unique row id');

      final all = await dao.getAllItems();
      final rows = all.where((r) => r['idempotency_key'] == 'shared-key');
      expect(rows, hasLength(2));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Payload round-trip', () {
    for (final size in [1024, 16 * 1024, 64 * 1024, 256 * 1024]) {
      test('payload of ~${size ~/ 1024} KB survives insert/retrieve', () async {
        final payload = _largePayload(size);
        final id = await dao.insertItem(
          modelId: 'large-${size}b',
          modelType: 'LargeModel',
          payload: payload,
          operation: 'create',
          idempotencyKey: 'large-$size',
        );

        final retrieved = await dao.getItemById(id);
        expect(retrieved, isNotNull);
        expect(retrieved!['payload'], equals(payload),
            reason: 'Payload of $size bytes should be stored verbatim');
      });
    }
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Concurrent inserts', () {
    test('50 parallel insertItem calls all succeed and produce distinct IDs',
        () async {
      final futures = List.generate(
        50,
        (i) => dao.insertItem(
          modelId: 'concurrent-$i',
          modelType: 'ConcurrentModel',
          payload: '{"seq":$i}',
          operation: 'create',
          idempotencyKey: 'concurrent-$i',
        ),
      );

      final ids = await Future.wait(futures);

      // All IDs must be positive integers.
      expect(ids.every((id) => id > 0), isTrue);

      // All IDs must be distinct.
      expect(ids.toSet(), hasLength(50),
          reason: 'Each concurrent insert must produce a unique row id');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Edge case: attempt count progression', () {
    test(
        'attempt_count increments correctly through 10 retries '
        'and item persists throughout', () async {
      final id = await dao.insertItem(
        modelId: 'retry-edge',
        modelType: 'RetryModel',
        payload: '{}',
        operation: 'create',
        idempotencyKey: 'retry-edge',
      );

      for (var attempt = 1; attempt <= 10; attempt++) {
        await dao.updateItem(
          id: id,
          attemptCount: attempt,
          lastError: 'Error $attempt',
          nextRetryAt: DateTime.now().add(Duration(seconds: attempt)),
        );

        final item = await dao.getItemById(id);
        expect(item, isNotNull,
            reason: 'Item must still exist after attempt $attempt');
        expect(item!['attempt_count'], equals(attempt));
      }
    });
  });
}
