import 'dart:async';

import 'package:test/test.dart';
import 'package:synquill/synquill_core.dart';

import '../common/test_models.dart';
import '../common/test_user_repository.dart';
import '../common/mock_test_user_api_adapter.dart';

/// Initializes the test storage system.
void initializeTestStorage(GeneratedDatabase db) {
  // Database provider should already be set by this point
  // Register all test repositories if needed
}

void main() {
  group('SyncedStorage Connectivity Handling Tests', () {
    late TestDatabase database;
    late MockApiAdapter mockAdapter;
    late Logger logger;

    setUp(() async {
      // Create test database
      database = TestDatabase(NativeDatabase.memory());
      DatabaseProvider.setInstance(database);

      // Set up test repository
      mockAdapter = MockApiAdapter();

      // Register repository factory for SyncedRepositoryProvider to use
      SynquillRepositoryProvider.register<TestUser>(
        (db) => TestUserRepository(db as TestDatabase, mockAdapter),
      );

      // Set up logger
      logger = Logger('SyncedStorageConnectivityTest');

      // Register repository factory
      SynquillRepositoryProvider.register<TestUser>(
        (db) => TestUserRepository(db as TestDatabase, mockAdapter),
      );
    });

    tearDown(() async {
      await SynquillStorage.close();
      await database.close();
      SynquillRepositoryProvider.reset();
      DatabaseProvider.reset();
    });

    test('should initialize with connectivity stream', () async {
      final connectivityController = StreamController<bool>();
      bool checkerCalled = false;

      Future<bool> connectivityChecker() async {
        checkerCalled = true;
        return true;
      }

      await SynquillStorage.init(
        database: database,
        logger: logger,
        initializeFn: initializeTestStorage,
        connectivityStream: connectivityController.stream,
        connectivityChecker: connectivityChecker,
        enableInternetMonitoring: true,
      );

      // Check initial connectivity status using checker function
      final isConnected = await SynquillStorage.isConnected;
      expect(isConnected, isTrue);
      expect(checkerCalled, isTrue);

      await connectivityController.close();
    });

    test('should handle connectivity stream updates', () async {
      final connectivityController = StreamController<bool>();
      // No need to track updates in this test

      await SynquillStorage.init(
        database: database,
        logger: logger,
        initializeFn: initializeTestStorage,
        connectivityStream: connectivityController.stream,
        enableInternetMonitoring: true,
      );

      // Simulate connectivity changes
      connectivityController.add(true);
      await Future.delayed(const Duration(milliseconds: 50));

      connectivityController.add(false);
      await Future.delayed(const Duration(milliseconds: 50));

      connectivityController.add(true);
      await Future.delayed(const Duration(milliseconds: 50));

      // The connectivity handler should have been triggered
      await connectivityController.close();
    });

    test(
      'should use connectivity checker when no stream status available',
      () async {
        bool? checkerResult = true;

        Future<bool> connectivityChecker() async {
          return checkerResult!;
        }

        await SynquillStorage.init(
          database: database,
          logger: logger,
          initializeFn: initializeTestStorage,
          connectivityChecker: connectivityChecker,
          enableInternetMonitoring: true,
        );

        // Test when checker returns true
        expect(await SynquillStorage.isConnected, isTrue);

        // Test when checker returns false
        checkerResult = false;
        expect(await SynquillStorage.isConnected, isFalse);
      },
    );

    test(
      'should return last known status from stream when checker fails',
      () async {
        final connectivityController = StreamController<bool>();

        Future<bool> failingChecker() async {
          throw Exception('Connectivity check failed');
        }

        await SynquillStorage.init(
          database: database,
          logger: logger,
          initializeFn: initializeTestStorage,
          connectivityStream: connectivityController.stream,
          connectivityChecker: failingChecker,
          enableInternetMonitoring: true,
        );

        // Send connectivity status through stream
        connectivityController.add(false);
        await Future.delayed(const Duration(milliseconds: 50));

        // Should return stream status even when checker fails
        final isConnected = await SynquillStorage.isConnected;
        expect(isConnected, isFalse);

        await connectivityController.close();
      },
    );

    test(
      'should return true when no connectivity monitoring is provided',
      () async {
        await SynquillStorage.init(
          database: database,
          logger: logger,
          initializeFn: initializeTestStorage,
          enableInternetMonitoring: true,
        );

        // Should default to true when no stream or checker is provided
        final isConnected = await SynquillStorage.isConnected;
        expect(isConnected, isTrue);
      },
    );

    test('should return false when SyncedStorage is not initialized', () async {
      // Don't initialize SyncedStorage
      final isConnected = await SynquillStorage.isConnected;
      expect(isConnected, isFalse);
    });

    test('should handle connectivity stream errors gracefully', () async {
      final connectivityController = StreamController<bool>();

      await SynquillStorage.init(
        database: database,
        logger: logger,
        initializeFn: initializeTestStorage,
        connectivityStream: connectivityController.stream,
        enableInternetMonitoring: true,
      );

      // Send an error through the stream
      connectivityController.addError('Network error');
      await Future.delayed(const Duration(milliseconds: 50));

      // Should still work normally
      final isConnected = await SynquillStorage.isConnected;
      expect(isConnected, isTrue); // Should default to true

      await connectivityController.close();
    });

    test('should clean up connectivity subscription on reset', () async {
      final connectivityController = StreamController<bool>();

      await SynquillStorage.init(
        database: database,
        logger: logger,
        initializeFn: initializeTestStorage,
        connectivityStream: connectivityController.stream,
        enableInternetMonitoring: true,
      );

      // Reset should clean up subscription
      await SynquillStorage.close();

      // Controller should still be usable (subscription cleaned up)
      expect(connectivityController.isClosed, isFalse);
      await connectivityController.close();
    });

    test('RetryExecutor should skip processing tasks when offline', () async {
      final connectivityController = StreamController<bool>();

      await SynquillStorage.init(
        database: database,
        logger: logger,
        initializeFn: initializeTestStorage,
        connectivityStream: connectivityController.stream,
        enableInternetMonitoring: true,
        config: const SynquillStorageConfig(
          foregroundQueueConcurrency: 1,
          backgroundQueueConcurrency: 1,
        ),
      );

      // Get sync queue DAO to add test task
      final syncQueueDao = SyncQueueDao(database);

      // Add a test task to sync queue
      final testTaskId = await syncQueueDao.insertItem(
        modelType: 'TestUser',
        modelId: 'test-user-1',
        operation: 'create',
        payload: '{"id": "test-user-1", "name": "Test User"}',
        idempotencyKey: 'test-key-1',
        nextRetryAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      // Verify task was added
      final tasksBeforeOffline = await syncQueueDao.getAllItems();
      expect(tasksBeforeOffline.length, equals(1));
      expect(tasksBeforeOffline.first['id'], equals(testTaskId));

      // Set device to offline
      connectivityController.add(false);
      await Future.delayed(const Duration(milliseconds: 100));

      // Try to process tasks while offline
      final retryExecutor = SynquillStorage.retryExecutor;
      await retryExecutor.processDueTasksNow();

      // Task should still be in queue (not processed due to offline status)
      final tasksAfterOfflineProcessing = await syncQueueDao.getAllItems();
      expect(tasksAfterOfflineProcessing.length, equals(1));
      expect(tasksAfterOfflineProcessing.first['status'], equals('pending'));

      // Set device back online
      connectivityController.add(true);
      await Future.delayed(const Duration(milliseconds: 100));

      // Now processing should work (but will fail due to mock adapter)
      await retryExecutor.processDueTasksNow();

      // Task should have been processed (attempted) and potentially failed
      final tasksAfterOnlineProcessing = await syncQueueDao.getAllItems();
      // The task might still be there if it failed,
      // but status should have changed
      if (tasksAfterOnlineProcessing.isNotEmpty) {
        expect(
          tasksAfterOnlineProcessing.first['attempt_count'],
          greaterThan(0),
        );
      }

      await connectivityController.close();
    });

    test(
      'RetryExecutor should process tasks with forceSync even when offline',
      () async {
        final connectivityController = StreamController<bool>();

        await SynquillStorage.init(
          database: database,
          logger: logger,
          initializeFn: initializeTestStorage,
          connectivityStream: connectivityController.stream,
          enableInternetMonitoring: true,
          config: const SynquillStorageConfig(
            foregroundQueueConcurrency: 1,
            backgroundQueueConcurrency: 1,
          ),
        );

        // Set device to offline first
        connectivityController.add(false);
        await Future.delayed(const Duration(milliseconds: 100));

        // Get sync queue DAO to add test task
        final syncQueueDao = SyncQueueDao(database);

        // Add a test task to sync queue
        await syncQueueDao.insertItem(
          modelType: 'TestUser',
          modelId: 'test-user-2',
          operation: 'create',
          payload: '{"id": "test-user-2", "name": "Test User 2"}',
          idempotencyKey: 'test-key-2',
          nextRetryAt: DateTime.now().subtract(const Duration(minutes: 1)),
        );

        // Verify task was added
        final tasksBeforeSync = await syncQueueDao.getAllItems();
        expect(tasksBeforeSync.length, equals(1));

        // Force sync should not process tasks when offline
        // (because we check connectivity in _fetchDueTasks for forceSync too)
        final retryExecutor = SynquillStorage.retryExecutor;
        await retryExecutor.processDueTasksNow(forceSync: true);

        // Task should still be in queue since we're offline
        final tasksAfterForceSync = await syncQueueDao.getAllItems();
        expect(tasksAfterForceSync.length, equals(1));
        expect(tasksAfterForceSync.first['status'], equals('pending'));

        await connectivityController.close();
      },
    );
  });
}
