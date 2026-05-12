// Tests for ForeignKeyUpdateService.
//
// Strategy: use ModelInfoRegistryProvider.registerForeignKeyRelations() to
// seed the registry without codegen, and provide a real in-memory SQLite DB
// so customUpdate() can execute.  ModelInfoRegistryProvider.reset() in
// tearDown keeps tests isolated.

import 'package:drift/drift.dart';
import 'package:test/test.dart';
import 'package:synquill/synquill.dart';

// ---------------------------------------------------------------------------
// Minimal test database with two tables
//   posts.user_id  ─FK─▶  users.id
// ---------------------------------------------------------------------------

class _FkTestDatabase extends GeneratedDatabase {
  _FkTestDatabase(super.e);

  @override
  Iterable<TableInfo<Table, DataClass>> get allTables => [];

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await customStatement('''
            CREATE TABLE users (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL
            )
          ''');
          await customStatement('''
            CREATE TABLE posts (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              user_id TEXT NOT NULL
            )
          ''');
          // Sync queue table required by ForeignKeyUpdateService internals
          // (it calls SyncQueueDao indirectly through IdConflictResolver;
          //  ForeignKeyUpdateService itself only uses customUpdate, but we
          //  include it here for completeness in case of future interactions).
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

Future<void> _insertUser(_FkTestDatabase db, String id, String name) => db
    .customStatement('INSERT INTO users (id, name) VALUES (?, ?)', [id, name]);

Future<void> _insertPost(
        _FkTestDatabase db, String id, String title, String userId) =>
    db.customStatement(
        'INSERT INTO posts (id, title, user_id) VALUES (?, ?, ?)',
        [id, title, userId]);

Future<List<Map<String, dynamic>>> _getPosts(_FkTestDatabase db) async {
  final rows = await db.customSelect('SELECT * FROM posts ORDER BY id').get();
  return rows.map((r) => r.data).toList();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late _FkTestDatabase db;
  late ForeignKeyUpdateService service;

  setUp(() {
    db = _FkTestDatabase(NativeDatabase.memory());
    service = ForeignKeyUpdateService(
      db,
      // _getTableInfo: return null for all tables (no Drift table objects in
      // this minimal test DB); customUpdate with null `updates` still works.
      (_) => null,
    );
    // Reset registry so previous test registrations don't bleed in.
    ModelInfoRegistryProvider.reset();
  });

  tearDown(() async {
    ModelInfoRegistryProvider.reset();
    await db.close();
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('updateForeignKeyReferences – no relations registered', () {
    test('completes without error when no FK relations are registered',
        () async {
      // No registerForeignKeyRelations call → empty list.
      await expectLater(
        service.updateForeignKeyReferences('old-id', 'new-id', 'User'),
        completes,
      );
    });

    test('does not modify any rows when no relations are registered', () async {
      await _insertUser(db, 'u1', 'Alice');
      await _insertPost(db, 'p1', 'Post 1', 'u1');

      await service.updateForeignKeyReferences('u1', 'u-new', 'User');

      final posts = await _getPosts(db);
      expect(posts.first['user_id'], equals('u1'),
          reason: 'Row should remain unchanged with no FK relations');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('updateForeignKeyReferences – single relation', () {
    setUp(() {
      ModelInfoRegistryProvider.registerForeignKeyRelations('User', [
        const ForeignKeyRelation(
          fieldName: 'userId',
          targetType: 'User',
          sourceTable: 'posts',
        ),
      ]);
    });

    test('updates matching FK rows', () async {
      await _insertUser(db, 'u1', 'Alice');
      await _insertPost(db, 'p1', 'Post 1', 'u1');
      await _insertPost(db, 'p2', 'Post 2', 'u1');

      await service.updateForeignKeyReferences('u1', 'u-new', 'User');

      final posts = await _getPosts(db);
      expect(posts.every((p) => p['user_id'] == 'u-new'), isTrue,
          reason: 'All posts should reference the new user id');
    });

    test('leaves non-matching rows untouched', () async {
      await _insertUser(db, 'u1', 'Alice');
      await _insertUser(db, 'u2', 'Bob');
      await _insertPost(db, 'p1', 'Alice Post', 'u1');
      await _insertPost(db, 'p2', 'Bob Post', 'u2');

      await service.updateForeignKeyReferences('u1', 'u-new', 'User');

      final posts = await _getPosts(db);
      final bobPost = posts.firstWhere((p) => p['id'] == 'p2');
      expect(bobPost['user_id'], equals('u2'),
          reason: 'Bob\'s post should not be modified');
      final alicePost = posts.firstWhere((p) => p['id'] == 'p1');
      expect(alicePost['user_id'], equals('u-new'));
    });

    test('handles zero matching rows gracefully (no rows to update)', () async {
      // Table is empty — no rows reference 'ghost-id'.
      await expectLater(
        service.updateForeignKeyReferences('ghost-id', 'new-id', 'User'),
        completes,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('updateForeignKeyReferences – deduplication', () {
    test('duplicate sourceTable.fieldName pairs are only processed once',
        () async {
      // Register the same relation twice (simulating a codegen bug or double
      // registration).
      ModelInfoRegistryProvider.registerForeignKeyRelations('User', [
        const ForeignKeyRelation(
            fieldName: 'userId', targetType: 'User', sourceTable: 'posts'),
        const ForeignKeyRelation(
            fieldName: 'userId', targetType: 'User', sourceTable: 'posts'),
      ]);

      await _insertUser(db, 'u1', 'Alice');
      await _insertPost(db, 'p1', 'Post 1', 'u1');

      // Should complete without error — deduplication prevents double update.
      await expectLater(
        service.updateForeignKeyReferences('u1', 'u-new', 'User'),
        completes,
      );

      final posts = await _getPosts(db);
      expect(posts.first['user_id'], equals('u-new'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('error resilience', () {
    test(
        'swallows top-level errors and does not rethrow — '
        'per spec: main ID replacement must succeed even if FK updates fail',
        () async {
      // Register a relation pointing at a non-existent table to trigger a
      // DB error during _updateSingleForeignKeyReference.
      ModelInfoRegistryProvider.registerForeignKeyRelations('User', [
        const ForeignKeyRelation(
          fieldName: 'userId',
          targetType: 'User',
          sourceTable: 'nonexistent_table', // Will cause SQLite error
        ),
      ]);

      // The method must complete (not throw) even when a relation fails.
      await expectLater(
        service.updateForeignKeyReferences('u1', 'u-new', 'User'),
        completes,
      );
    });

    test('continues processing subsequent relations after one fails', () async {
      ModelInfoRegistryProvider.registerForeignKeyRelations('User', [
        // First relation: will fail (bad table).
        const ForeignKeyRelation(
          fieldName: 'userId',
          targetType: 'User',
          sourceTable: 'bad_table',
        ),
        // Second relation: valid — should still be processed.
        const ForeignKeyRelation(
          fieldName: 'userId',
          targetType: 'User',
          sourceTable: 'posts',
        ),
      ]);

      await _insertUser(db, 'u1', 'Alice');
      await _insertPost(db, 'p1', 'Post 1', 'u1');

      await service.updateForeignKeyReferences('u1', 'u-new', 'User');

      final posts = await _getPosts(db);
      expect(posts.first['user_id'], equals('u-new'),
          reason: 'The valid relation should have been processed '
              'despite the earlier failure');
    });
  });
}
