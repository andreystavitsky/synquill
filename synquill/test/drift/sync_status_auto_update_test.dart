import 'package:synquill/synquill_core.dart';
import 'package:test/test.dart';

// Test database that manually creates the sync queue table
// and a test model table
class _TestDatabase extends GeneratedDatabase {
  _TestDatabase(super.e);

  @override
  Iterable<TableInfo<Table, DataClass>> get allTables => [];

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        // Create sync_queue_items table
        await customStatement('''
          CREATE TABLE sync_queue_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            model_type TEXT NOT NULL,
            model_id TEXT NOT NULL,
            payload TEXT NOT NULL,
            op TEXT NOT NULL,
            attempt_count INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            next_retry_at INTEGER,
            idempotency_key TEXT,
            headers TEXT,
            extra TEXT,
            status TEXT NOT NULL DEFAULT 'pending',
            created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
          )
        ''');

        // Create test model table with syncStatus field
        await customStatement('''
          CREATE TABLE test_models (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            value INTEGER NOT NULL,
            sync_status TEXT NOT NULL DEFAULT 'pending',
            created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
            updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
            last_synced_at INTEGER
          )
        ''');
      },
    );
  }
}

void main() {
  late GeneratedDatabase db;
  late SyncQueueDao dao;

  setUp(() async {
    db = _TestDatabase(NativeDatabase.memory());
    dao = SyncQueueDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('SyncStatus Auto-Update Tests', () {
    test('inserting sync queue item sets model syncStatus to pending',
        () async {
      // Insert a test model
      await db.customStatement('''
        INSERT INTO test_models (id, name, value, sync_status) 
        VALUES ('test-1', 'Test Model', 100, 'synced')
      ''');

      // Verify initial status
      final initialResult = await db.customSelect(
        'SELECT sync_status FROM test_models WHERE id = ?',
        variables: [Variable.withString('test-1')],
      ).get();
      expect(initialResult.first.data['sync_status'], equals('synced'));

      // Insert sync queue item - should update model to pending
      await dao.insertItem(
        modelType: 'TestModel',
        modelId: 'test-1',
        payload: '{"id": "test-1", "name": "Test Model", "value": 100}',
        operation: 'update',
      );

      // Verify syncStatus was updated to pending
      final result = await db.customSelect(
        'SELECT sync_status FROM test_models WHERE id = ?',
        variables: [Variable.withString('test-1')],
      ).get();
      expect(result.first.data['sync_status'], equals('pending'));
    });

    test('deleting sync queue item sets model syncStatus to synced', () async {
      // Insert test model
      await db.customStatement('''
        INSERT INTO test_models (id, name, value, sync_status) 
        VALUES ('test-2', 'Test Model 2', 200, 'synced')
      ''');

      // Insert sync queue item
      final taskId = await dao.insertItem(
        modelType: 'TestModel',
        modelId: 'test-2',
        payload: '{"id": "test-2", "name": "Test Model 2", "value": 200}',
        operation: 'create',
      );

      // Verify model is pending
      var result = await db.customSelect(
        'SELECT sync_status FROM test_models WHERE id = ?',
        variables: [Variable.withString('test-2')],
      ).get();
      expect(result.first.data['sync_status'], equals('pending'));

      // Delete sync queue item
      await dao.deleteTask(taskId);

      // Verify syncStatus was updated to synced
      result = await db.customSelect(
        'SELECT sync_status FROM test_models WHERE id = ?',
        variables: [Variable.withString('test-2')],
      ).get();
      expect(result.first.data['sync_status'], equals('synced'));
    });

    test('marking task as dead sets model syncStatus to dead', () async {
      // Insert test model
      await db.customStatement('''
        INSERT INTO test_models (id, name, value, sync_status) 
        VALUES ('test-3', 'Test Model 3', 300, 'pending')
      ''');

      // Insert sync queue item
      final taskId = await dao.insertItem(
        modelType: 'TestModel',
        modelId: 'test-3',
        payload: '{"id": "test-3", "name": "Test Model 3", "value": 300}',
        operation: 'update',
      );

      // Mark task as dead
      await dao.markTaskAsDead(taskId, 'Failed after max retries');

      // Verify syncStatus was updated to dead
      final result = await db.customSelect(
        'SELECT sync_status FROM test_models WHERE id = ?',
        variables: [Variable.withString('test-3')],
      ).get();
      expect(result.first.data['sync_status'], equals('dead'));
    });

    test('multiple pending tasks keep model as pending', () async {
      // Insert test model
      await db.customStatement('''
        INSERT INTO test_models (id, name, value, sync_status) 
        VALUES ('test-4', 'Test Model 4', 400, 'synced')
      ''');

      // Insert first sync queue item
      await dao.insertItem(
        modelType: 'TestModel',
        modelId: 'test-4',
        payload: '{"id": "test-4", "name": "Test Model 4", "value": 400}',
        operation: 'update',
      );

      // Insert second sync queue item
      await dao.insertItem(
        modelType: 'TestModel',
        modelId: 'test-4',
        payload: '{"id": "test-4", "name": "Test Model 4", "value": 400}',
        operation: 'create',
      );

      // Verify syncStatus is pending
      final result = await db.customSelect(
        'SELECT sync_status FROM test_models WHERE id = ?',
        variables: [Variable.withString('test-4')],
      ).get();
      expect(result.first.data['sync_status'], equals('pending'));
    });

    test('dead task takes precedence over pending tasks', () async {
      // Insert test model
      await db.customStatement('''
        INSERT INTO test_models (id, name, value, sync_status) 
        VALUES ('test-5', 'Test Model 5', 500, 'synced')
      ''');

      // Insert pending task
      await dao.insertItem(
        modelType: 'TestModel',
        modelId: 'test-5',
        payload: '{"id": "test-5", "name": "Test Model 5", "value": 500}',
        operation: 'update',
      );

      // Insert another task and mark it as dead
      final deadTaskId = await dao.insertItem(
        modelType: 'TestModel',
        modelId: 'test-5',
        payload: '{"id": "test-5", "name": "Test Model 5", "value": 500}',
        operation: 'create',
      );
      await dao.markTaskAsDead(deadTaskId, 'Failed permanently');

      // Verify syncStatus is dead (dead takes precedence)
      final result = await db.customSelect(
        'SELECT sync_status FROM test_models WHERE id = ?',
        variables: [Variable.withString('test-5')],
      ).get();
      expect(result.first.data['sync_status'], equals('dead'));
    });

    test('deleting all tasks for model sets syncStatus to synced', () async {
      // Insert test model
      await db.customStatement('''
        INSERT INTO test_models (id, name, value, sync_status) 
        VALUES ('test-6', 'Test Model 6', 600, 'synced')
      ''');

      // Insert multiple sync queue items
      await dao.insertItem(
        modelType: 'TestModel',
        modelId: 'test-6',
        payload: '{"id": "test-6", "name": "Test Model 6", "value": 600}',
        operation: 'update',
      );
      await dao.insertItem(
        modelType: 'TestModel',
        modelId: 'test-6',
        payload: '{"id": "test-6", "name": "Test Model 6", "value": 600}',
        operation: 'create',
      );

      // Delete all tasks for this model
      await dao.deleteTasksForModelId('TestModel', 'test-6');

      // Verify syncStatus was updated to synced
      final result = await db.customSelect(
        'SELECT sync_status FROM test_models WHERE id = ?',
        variables: [Variable.withString('test-6')],
      ).get();
      expect(result.first.data['sync_status'], equals('synced'));
    });

    test('modelTypeToTableName converts correctly', () {
      expect(dao.modelTypeToTableName('User'), equals('users'));
      expect(dao.modelTypeToTableName('TodoItem'), equals('todo_items'));
      expect(dao.modelTypeToTableName('UserProfile'), equals('user_profiles'));
      expect(dao.modelTypeToTableName('Post'), equals('posts'));
    });
  });
}
