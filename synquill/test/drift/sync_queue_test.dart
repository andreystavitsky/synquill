import 'package:synquill/synquill_core.dart';
import 'package:test/test.dart';
import 'dart:convert' as convert;

// Minimal test database that manually creates the sync queue table
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
        // Manually create the sync_queue_items table for testing
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
      },
    );
  }
}

// For testing, we'll create a working database by using a simpler approach
// that directly provides the sync queue functionality without dealing with
// complex Drift type requirements

void main() {
  late GeneratedDatabase db;
  late SyncQueueDao dao;

  setUp(() {
    // Create a minimal in-memory database for testing
    db = _TestDatabase(NativeDatabase.memory());
    dao = SyncQueueDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('SyncQueueTable schema', () {
    test('create table and verify columns', () async {
      // Execute a query that returns table info
      final tableInfo =
          await db.customSelect("PRAGMA table_info('sync_queue_items')").get();

      // Verify the table exists with correct columns
      expect(tableInfo.length, greaterThan(0));

      // Get column names
      final columns =
          tableInfo.map((row) => row.data['name'] as String).toList();

      // Verify required columns from spec
      expect(columns, contains('id'));
      expect(columns, contains('model_type'));
      expect(columns, contains('payload'));
      expect(columns, contains('op'));
      expect(columns, contains('attempt_count'));
      expect(columns, contains('last_error'));
      expect(columns, contains('next_retry_at'));
      expect(columns, contains('idempotency_key'));
    });
  });

  group('SyncQueueDao CRUD operations', () {
    test('insert and retrieve item', () async {
      // Insert test item
      final itemId = await dao.insertItem(
        modelId: '123',
        modelType: 'TestModel',
        payload: '{"id": "123", "name": "Test Item"}',
        operation: 'create',
      );

      expect(itemId, isA<int>());
      expect(itemId, greaterThan(0));

      // Retrieve all items
      final items = await dao.getAllItems();
      expect(items.length, equals(1));
      expect(items.first['model_type'], equals('TestModel'));
      expect(
        items.first['payload'],
        equals('{"id": "123", "name": "Test Item"}'),
      );
      expect(items.first['op'], equals('create'));
      expect(items.first['attempt_count'], equals(0));

      // Retrieve by ID
      final item = await dao.getItemById(itemId);
      expect(item?['id'], equals(itemId));
    });

    test('update item', () async {
      // Insert test item
      final itemId = await dao.insertItem(
        modelId: '321',
        modelType: 'TestModel',
        payload: '{"id": "123", "name": "Test Item"}',
        operation: 'create',
      );

      // Update the item
      final updateCount = await dao.updateItem(
        id: itemId,
        payload: '{"updated": true}',
        operation: 'update',
        attemptCount: 1,
        lastError: 'Test error',
        nextRetryAt: DateTime.now().add(const Duration(minutes: 5)),
      );

      expect(updateCount, equals(1));

      // Retrieve updated item
      final retrievedItem = await dao.getItemById(itemId);
      expect(retrievedItem?['payload'], equals('{"updated": true}'));
      expect(retrievedItem?['op'], equals('update'));
      expect(retrievedItem?['attempt_count'], equals(1));
      expect(retrievedItem?['last_error'], equals('Test error'));
      expect(retrievedItem?['next_retry_at'] != null, isTrue);
    });

    test('delete item', () async {
      // Insert test item
      final itemId = await dao.insertItem(
        modelId: '2225',
        modelType: 'TestModel',
        payload: '{"id": "123", "name": "Test Item"}',
        operation: 'create',
      );

      // Verify item exists
      final item = await dao.getItemById(itemId);
      expect(item != null, isTrue);

      // Delete it
      final deleted = await dao.deleteTask(itemId);
      expect(deleted, equals(1));

      // Verify it's gone
      final deletedItem = await dao.getItemById(itemId);
      expect(deletedItem == null, isTrue);
    });
  });

  group('SyncQueueDao specialized queries', () {
    test(
      'getItemsReadyForProcessing returns items with no retry delay',
      () async {
        // Insert item with no retry delay
        final readyItemId = await dao.insertItem(
          modelId: '5787',
          modelType: 'TestModel',
          payload: '{"ready": true}',
          operation: 'create',
        );

        // Insert item with future retry delay
        await dao.insertItem(
          modelId: '5432',
          modelType: 'TestModel',
          payload: '{"delayed": true}',
          operation: 'create',
          nextRetryAt: DateTime.now().add(const Duration(hours: 1)),
        );

        final readyItems = await dao.getDueTasks();
        expect(readyItems.length, equals(1));
        expect(readyItems.first['id'], equals(readyItemId));
      },
    );

    test('getItemsByModelType filters by model type', () async {
      // Insert items of different types
      await dao.insertItem(
        modelId: '123445',
        modelType: 'UserModel',
        payload: '{"type": "user"}',
        operation: 'create',
      );

      await dao.insertItem(
        modelId: '45545',
        modelType: 'ProductModel',
        payload: '{"type": "product"}',
        operation: 'create',
      );

      final userItems = await dao.getItemsByModelType('UserModel');
      expect(userItems.length, equals(1));
      expect(userItems.first['model_type'], equals('UserModel'));
    });
  });

  group('SyncQueueDao headers and extra persistence', () {
    test('headers and extra persist between retries', () async {
      // Test data for headers and extra
      final headers = {
        'Authorization': 'Bearer token123',
        'X-Client-Version': '1.0.0',
      };
      final extra = {
        'retryCount': 0,
        'priority': 'high',
        'userContext': {'userId': '12345'},
      };

      // Insert test item with headers and extra
      final itemId = await dao.insertItem(
        modelId: 'test-item-with-headers',
        modelType: 'TestModel',
        payload: '{"id": "test-item-with-headers", "name": "Test Item"}',
        operation: 'create',
        headers: convert.jsonEncode(headers),
        extra: convert.jsonEncode(extra),
      );

      expect(itemId, isA<int>());
      expect(itemId, greaterThan(0));

      // Retrieve the item and verify headers and extra are stored
      final retrievedItem = await dao.getItemById(itemId);
      expect(retrievedItem, isNotNull);
      expect(retrievedItem!['headers'], equals(convert.jsonEncode(headers)));
      expect(retrievedItem['extra'], equals(convert.jsonEncode(extra)));

      // Parse and verify the stored JSON
      final storedHeaders =
          convert.jsonDecode(retrievedItem['headers']) as Map<String, dynamic>;
      final storedExtra =
          convert.jsonDecode(retrievedItem['extra']) as Map<String, dynamic>;

      expect(storedHeaders['Authorization'], equals('Bearer token123'));
      expect(storedHeaders['X-Client-Version'], equals('1.0.0'));
      expect(storedExtra['retryCount'], equals(0));
      expect(storedExtra['priority'], equals('high'));
      expect(storedExtra['userContext']['userId'], equals('12345'));

      // Simulate a retry scenario - update attempt count and retry time
      final updateCount = await dao.updateItem(
        id: itemId,
        attemptCount: 1,
        lastError: 'Network timeout - will retry',
        nextRetryAt: DateTime.now().add(const Duration(minutes: 5)),
      );

      expect(updateCount, equals(1));

      // Retrieve updated item and verify headers/extra are preserved
      final updatedItem = await dao.getItemById(itemId);
      expect(updatedItem, isNotNull);
      expect(updatedItem!['attempt_count'], equals(1));
      expect(updatedItem['last_error'], equals('Network timeout - will retry'));
      expect(updatedItem['next_retry_at'] != null, isTrue);

      // Most importantly: verify headers and extra are still there unchanged
      expect(updatedItem['headers'], equals(convert.jsonEncode(headers)));
      expect(updatedItem['extra'], equals(convert.jsonEncode(extra)));

      // Parse again to double-check
      final persistedHeaders =
          convert.jsonDecode(updatedItem['headers']) as Map<String, dynamic>;
      final persistedExtra =
          convert.jsonDecode(updatedItem['extra']) as Map<String, dynamic>;

      expect(persistedHeaders['Authorization'], equals('Bearer token123'));
      expect(persistedHeaders['X-Client-Version'], equals('1.0.0'));
      expect(persistedExtra['retryCount'], equals(0));
      expect(persistedExtra['priority'], equals('high'));
      expect(persistedExtra['userContext']['userId'], equals('12345'));
    });

    test(
      'headers and extra can be updated independently during retries',
      () async {
        // Initial headers and extra
        final initialHeaders = {'Authorization': 'Bearer initial-token'};
        final initialExtra = {'attempt': 1};

        // Insert test item
        final itemId = await dao.insertItem(
          modelId: 'test-item-updates',
          modelType: 'TestModel',
          payload: '{"id": "test-item-updates", "name": "Test Item"}',
          operation: 'create',
          headers: convert.jsonEncode(initialHeaders),
          extra: convert.jsonEncode(initialExtra),
        );

        // Update headers and extra independently
        final updatedHeaders = {
          'Authorization': 'Bearer refreshed-token',
          'X-Retry-Count': '1',
        };
        final updatedExtra = {'attempt': 2, 'lastError': 'timeout'};

        final updateCount = await dao.updateItem(
          id: itemId,
          attemptCount: 1,
          headers: convert.jsonEncode(updatedHeaders),
          extra: convert.jsonEncode(updatedExtra),
        );

        expect(updateCount, equals(1));

        // Verify the updates
        final updatedItem = await dao.getItemById(itemId);
        expect(updatedItem, isNotNull);

        final persistedHeaders =
            convert.jsonDecode(updatedItem!['headers']) as Map<String, dynamic>;
        final persistedExtra =
            convert.jsonDecode(updatedItem['extra']) as Map<String, dynamic>;

        expect(
          persistedHeaders['Authorization'],
          equals('Bearer refreshed-token'),
        );
        expect(persistedHeaders['X-Retry-Count'], equals('1'));
        expect(persistedExtra['attempt'], equals(2));
        expect(persistedExtra['lastError'], equals('timeout'));
      },
    );

    test('null headers and extra are handled correctly', () async {
      // Insert item without headers and extra
      final itemId = await dao.insertItem(
        modelId: 'test-item-null',
        modelType: 'TestModel',
        payload: '{"id": "test-item-null", "name": "Test Item"}',
        operation: 'create',
        // headers and extra are null (default)
      );

      // Retrieve and verify null values
      final retrievedItem = await dao.getItemById(itemId);
      expect(retrievedItem, isNotNull);
      expect(retrievedItem!['headers'], isNull);
      expect(retrievedItem['extra'], isNull);

      // Update with actual headers and extra
      final headers = {'Authorization': 'Bearer new-token'};
      final extra = {'added': 'later'};

      final updateCount = await dao.updateItem(
        id: itemId,
        headers: convert.jsonEncode(headers),
        extra: convert.jsonEncode(extra),
      );

      expect(updateCount, equals(1));

      // Verify the addition
      final updatedItem = await dao.getItemById(itemId);
      expect(updatedItem, isNotNull);
      expect(updatedItem!['headers'], equals(convert.jsonEncode(headers)));
      expect(updatedItem['extra'], equals(convert.jsonEncode(extra)));
    });

    test('empty headers and extra objects are preserved', () async {
      // Test with empty but valid JSON objects
      final emptyHeaders = <String, String>{};
      final emptyExtra = <String, dynamic>{};

      final itemId = await dao.insertItem(
        modelId: 'test-item-empty',
        modelType: 'TestModel',
        payload: '{"id": "test-item-empty", "name": "Test Item"}',
        operation: 'create',
        headers: convert.jsonEncode(emptyHeaders),
        extra: convert.jsonEncode(emptyExtra),
      );

      // Retrieve and verify empty objects are preserved
      final retrievedItem = await dao.getItemById(itemId);
      expect(retrievedItem, isNotNull);
      expect(retrievedItem!['headers'], equals('{}'));
      expect(retrievedItem['extra'], equals('{}'));

      // Parse and verify they're valid empty objects
      final parsedHeaders =
          convert.jsonDecode(retrievedItem['headers']) as Map<String, dynamic>;
      final parsedExtra =
          convert.jsonDecode(retrievedItem['extra']) as Map<String, dynamic>;

      expect(parsedHeaders, isEmpty);
      expect(parsedExtra, isEmpty);
    });
  });
}
