// Tests for IdConflictResolver collision/merge strategies.
//
// IdConflictResolver takes a GeneratedDatabase directly so we can test it
// in the drift/ tier without full SynquillStorage.init.
//
// ModelInfoRegistryProvider.reset() in tearDown keeps FK/cascade registrations
// from leaking between tests.

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:test/test.dart';
import 'package:synquill/synquill.dart';

// ---------------------------------------------------------------------------
// Minimal test database
//   test_entities – the "model" table IdConflictResolver operates on
//   sync_queue_items – required by SyncQueueDao used inside the resolver
// ---------------------------------------------------------------------------

class _ConflictTestDatabase extends GeneratedDatabase {
  _ConflictTestDatabase(super.e);

  @override
  Iterable<TableInfo<Table, DataClass>> get allTables => [];

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          // Model table: snake_case plural of 'TestEntity' → 'test_entities'
          await customStatement('''
            CREATE TABLE test_entities (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              description TEXT,
              created_at INTEGER,
              updated_at INTEGER,
              sync_status TEXT DEFAULT 'synced'
            )
          ''');

          // Sync queue table
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
// Helpers
// ---------------------------------------------------------------------------

const _modelType = 'TestEntity';

Future<void> _insertEntity(
  _ConflictTestDatabase db,
  String id,
  String name, {
  String? description,
  DateTime? createdAt,
  DateTime? updatedAt,
}) =>
    db.customStatement(
      'INSERT INTO test_entities '
      '(id, name, description, created_at, updated_at)'
      ' VALUES (?, ?, ?, ?, ?)',
      [
        id,
        name,
        description,
        (createdAt ?? DateTime.now()).millisecondsSinceEpoch,
        (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
      ],
    );

Future<Map<String, dynamic>?> _getEntity(
    _ConflictTestDatabase db, String id) async {
  final rows = await db.customSelect(
    'SELECT * FROM test_entities WHERE id = ?',
    variables: [Variable.withString(id)],
  ).get();
  if (rows.isEmpty) return null;
  return rows.first.data;
}

Future<int> _insertSyncQueueItem(
  _ConflictTestDatabase db, {
  required String modelId,
  String modelType = _modelType,
  String idNegotiationStatus = 'pending',
  String? temporaryClientId,
}) async {
  final dao = SyncQueueDao(db);
  final id = await dao.insertItem(
    modelId: modelId,
    modelType: modelType,
    payload: jsonEncode({'id': modelId}),
    operation: 'create',
    idempotencyKey: 'key-$modelId',
  );
  // Update id_negotiation_status
  await db.customStatement(
    'UPDATE sync_queue_items SET id_negotiation_status = ?, '
    'temporary_client_id = ? WHERE id = ?',
    [idNegotiationStatus, temporaryClientId, id],
  );
  return id;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _ConflictTestDatabase db;
  late IdConflictResolver resolver;

  setUp(() {
    db = _ConflictTestDatabase(NativeDatabase.memory());
    resolver = IdConflictResolver(db);
    ModelInfoRegistryProvider.reset();
  });

  tearDown(() async {
    ModelInfoRegistryProvider.reset();
    await db.close();
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('resolveIdConflict – clean path (no collision)', () {
    test('returns proposedServerId when it does not exist locally', () async {
      await _insertEntity(db, 'temp-1', 'My Entity');

      final result = await resolver.resolveIdConflict(
        temporaryId: 'temp-1',
        proposedServerId: 'server-1',
        modelType: _modelType,
      );

      expect(result, equals('server-1'));
    });

    test('returns proposedServerId when no concurrent operations are pending',
        () async {
      await _insertEntity(db, 'temp-2', 'Entity 2');
      // No sync queue entries at all → no concurrency.

      final result = await resolver.resolveIdConflict(
        temporaryId: 'temp-2',
        proposedServerId: 'server-2',
        modelType: _modelType,
      );

      expect(result, equals('server-2'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('_handleIdCollision – same record (isSameRecord = true)', () {
    test(
        'returns proposedServerId and deletes temporary record '
        'when fields match', () async {
      // Both records have the same non-ID fields.
      await _insertEntity(db, 'temp-3', 'Same Entity',
          description: 'desc', createdAt: DateTime(2024));
      await _insertEntity(db, 'server-3', 'Same Entity',
          description: 'desc', createdAt: DateTime(2024));

      final result = await resolver.resolveIdConflict(
        temporaryId: 'temp-3',
        proposedServerId: 'server-3',
        modelType: _modelType,
      );

      expect(result, equals('server-3'));

      // Temporary record should have been cleaned up.
      final tempRecord = await _getEntity(db, 'temp-3');
      expect(tempRecord, isNull,
          reason:
              'Temporary record should be deleted after collision resolution');
    });

    test(
        'Strategy 2: retries and eventually completes when colliding with '
        'a temporary record that is resolved in between', () async {
      await _insertEntity(db, 'temp-4', 'Entity 4');
      // existing record is also a "temporary" record (has pending sync task)
      await _insertEntity(db, 'server-4', 'Entity 4 Existing');

      // Add a sync queue item for 'server-4' to make it look temporary
      await _insertSyncQueueItem(
        db,
        modelId: 'server-4',
        idNegotiationStatus: 'pending',
      );

      // The resolver should see 'server-4' as temporary, wait, and retry.
      // We'll simulate resolution by deleting the sync queue item and the
      // entity after a short delay.
      unawaited(Future.delayed(const Duration(milliseconds: 200), () async {
        await db.customStatement('DELETE FROM sync_queue_items');
        await db.customStatement(
            'DELETE FROM test_entities WHERE id = ?', ['server-4']);
      }));

      final result = await resolver.resolveIdConflict(
        temporaryId: 'temp-4',
        proposedServerId: 'server-4',
        modelType: _modelType,
      );

      // Should have retried and eventually completed (clean path or merge).
      expect(result, equals('server-4'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('_handleIdCollision – merge strategy', () {
    test(
        'merges temp record into existing when temp is newer, '
        'cleans up temp, returns existingId', () async {
      final older = DateTime(2024, 1, 1);
      final newer = DateTime(2024, 6, 1);

      // existing record (older)
      await _insertEntity(db, 'server-4', 'Old Name',
          description: 'old desc', createdAt: older);

      // temporary record (newer — should win the merge)
      await _insertEntity(db, 'temp-4', 'New Name',
          description: 'new desc', createdAt: newer);

      final result = await resolver.resolveIdConflict(
        temporaryId: 'temp-4',
        proposedServerId: 'server-4',
        modelType: _modelType,
      );

      // Merge uses the existing ID.
      expect(result, equals('server-4'));

      // Temporary record should be gone.
      expect(await _getEntity(db, 'temp-4'), isNull);

      // Existing record should have been updated with temp's data.
      final merged = await _getEntity(db, 'server-4');
      expect(merged, isNotNull);
      expect(merged!['name'], equals('New Name'));
      expect(merged['description'], equals('new desc'));
    });

    test(
        'does not merge when temporary is older than existing '
        '– returns proposedServerId from clean-path fallback '
        'via isSameRecord false', () async {
      final older = DateTime(2024, 1, 1);
      final newer = DateTime(2024, 6, 1);

      // Existing is newer → temp cannot win the merge.
      await _insertEntity(db, 'server-5', 'Existing Name', createdAt: newer);
      // Temporary record is older but fields differ (not same record).
      await _insertEntity(db, 'temp-5', 'Different Name', createdAt: older);

      // When merge fails and no other strategy works, the resolver throws
      // IdConflictException (per spec: Strategy 4 marks as conflicted and
      // throws).
      await expectLater(
        resolver.resolveIdConflict(
          temporaryId: 'temp-5',
          proposedServerId: 'server-5',
          modelType: _modelType,
        ),
        throwsA(isA<IdConflictException>()),
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('_handleIdCollision – marks sync queue as conflicted', () {
    test(
        'sets idNegotiationStatus = conflict on sync queue item '
        'when all strategies fail', () async {
      // Existing record with different data → same record check = false.
      await _insertEntity(db, 'server-6', 'Existing');
      // Temporary record — older, different fields.
      await _insertEntity(db, 'temp-6', 'Temp', createdAt: DateTime(2020));

      // Add a sync queue item for the temporary record.
      await _insertSyncQueueItem(
        db,
        modelId: 'temp-6',
        idNegotiationStatus: 'pending',
        temporaryClientId: 'temp-6',
      );

      // Expect IdConflictException.
      try {
        await resolver.resolveIdConflict(
          temporaryId: 'temp-6',
          proposedServerId: 'server-6',
          modelType: _modelType,
        );
      } on IdConflictException {
        // Expected
      }

      // Verify the sync queue item was marked as conflicted.
      final rows = await db.customSelect(
        'SELECT id_negotiation_status FROM sync_queue_items '
        'WHERE model_id = ?',
        variables: [Variable.withString('temp-6')],
      ).get();

      expect(rows, isNotEmpty);
      expect(
        rows.first.data['id_negotiation_status'],
        equals('conflict'),
        reason: 'Sync queue item should be marked as conflicted',
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('concurrent operations detection', () {
    test(
        'retries and eventually throws IdConflictException '
        'when concurrent pending negotiations are detected', () async {
      await _insertEntity(db, 'temp-7', 'Entity 7');

      // Insert 2 sync queue items with pending id_negotiation_status for the
      // same model → triggers _hasConcurrentOperations.
      await _insertSyncQueueItem(db,
          modelId: 'temp-7', idNegotiationStatus: 'pending');
      await _insertSyncQueueItem(db,
          modelId: 'temp-7', idNegotiationStatus: 'pending');

      // Resolver should retry up to maxRetryAttempts then throw.
      await expectLater(
        resolver.resolveIdConflict(
          temporaryId: 'temp-7',
          proposedServerId: 'server-7',
          modelType: _modelType,
        ),
        throwsA(isA<IdConflictException>()),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('_validateForeignKeyIntegrity', () {
    test('completes without error when FK validation detects a conflict',
        () async {
      // The implementation logs a warning but continues (Strategy 3.5 in logs).
      // We seed a FK relation.
      ModelInfoRegistryProvider.registerForeignKeyRelations(_modelType, [
        const ForeignKeyRelation(
          sourceTable: 'other_table',
          fieldName: 'testEntityId',
          targetType: _modelType,
        ),
      ]);

      // Create the other table.
      await db.customStatement(
          'CREATE TABLE other_table (id TEXT, test_entity_id TEXT)');
      await db.customStatement(
          'INSERT INTO other_table (id, test_entity_id) VALUES (?, ?)',
          ['o1', 'server-X']);

      await _insertEntity(db, 'temp-X', 'Temp X');

      // Should not throw even if conflict exists in other_table.
      final result = await resolver.resolveIdConflict(
        temporaryId: 'temp-X',
        proposedServerId: 'server-X',
        modelType: _modelType,
      );

      expect(result, equals('server-X'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Deadlock potential detection', () {
    test(
        'Strategy 5: triggers alternative strategy when high number of '
        'related tasks are pending', () async {
      ModelInfoRegistryProvider.registerCascadeDeleteRelations(_modelType, [
        const CascadeDeleteRelation(
          targetType: 'RelatedModel',
          fieldName: 'id',
          mappedBy: 'parentId',
        ),
      ]);

      // Seed > 5 tasks for RelatedModel.
      for (var i = 0; i < 6; i++) {
        await _insertSyncQueueItem(
          db,
          modelId: 'related-$i',
          modelType: 'RelatedModel',
        );
      }

      await _insertEntity(db, 'temp-8', 'Temp 8');

      // Should trigger alternative strategy.
      // Current alternative strategy waits then throws IdConflictException
      // if deadlock still persists.
      await expectLater(
        resolver.resolveIdConflict(
          temporaryId: 'temp-8',
          proposedServerId: 'server-8',
          modelType: _modelType,
        ),
        throwsA(isA<IdConflictException>()),
      );
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  // ─────────────────────────────────────────────────────────────────────────

  group('IdConflictException', () {
    test('toString includes all three identifying fields', () {
      const ex = IdConflictException(
        'Some conflict message',
        temporaryId: 'temp-id',
        proposedServerId: 'server-id',
        modelType: 'Widget',
      );

      final str = ex.toString();
      expect(str, contains('temp-id'));
      expect(str, contains('server-id'));
      expect(str, contains('Widget'));
      expect(str, contains('Some conflict message'));
    });

    test('fields are preserved after construction', () {
      const ex = IdConflictException(
        'msg',
        temporaryId: 'tid',
        proposedServerId: 'sid',
        modelType: 'Gizmo',
      );

      expect(ex.message, equals('msg'));
      expect(ex.temporaryId, equals('tid'));
      expect(ex.proposedServerId, equals('sid'));
      expect(ex.modelType, equals('Gizmo'));
    });
  });
}
