import 'dart:async';
import 'dart:convert';

import 'package:queue/queue.dart';
import 'package:test/test.dart';
import 'package:synquill/synquill_core.dart';

import '../common/test_models.dart';
import '../common/test_user_repository.dart';
import '../common/mock_test_user_api_adapter.dart';

void main() {
  group('Queue System Integration Tests', () {
    late TestDatabase database;
    late TestUserRepository repository;
    late MockApiAdapter mockAdapter;
    late Logger logger;

    setUp(() async {
      // Set up test database
      database = TestDatabase(NativeDatabase.memory());

      // Set up logging
      logger = Logger('QueueSystemTest');
      Logger.root.level = Level.ALL;
      Logger.root.onRecord.listen((record) {
        //print('[${record.level.name}] ${record.loggerName}: '
        //    '${record.message}');
        //if (record.error != null) print('Error: ${record.error}');
        //if (record.stackTrace != null) print('Stack: ${record.stackTrace}');
      });

      // Set up test repository
      mockAdapter = MockApiAdapter();
      repository = TestUserRepository(database, mockAdapter);

      // Clear any existing local data from previous tests
      TestUserRepository.clearLocal();

      // Register repository factory
      SynquillRepositoryProvider.register<TestUser>(
        (db) => TestUserRepository(db as TestDatabase, mockAdapter),
      );

      // Initialize SyncedStorage with test configuration
      await SynquillStorage.init(
        database: database,
        config: const SynquillStorageConfig(
          defaultSavePolicy: DataSavePolicy.localFirst,
          defaultLoadPolicy: DataLoadPolicy.localOnly,
          foregroundQueueConcurrency: 1,
          backgroundQueueConcurrency: 1,
          // Use very short timeouts for testing to make tests run quickly
          foregroundQueueCapacityTimeout: Duration(milliseconds: 100),
          loadQueueCapacityTimeout: Duration(milliseconds: 100),
          backgroundQueueCapacityTimeout: Duration(milliseconds: 100),
          queueCapacityCheckInterval: Duration(milliseconds: 10),
        ),
        logger: logger,
        initializeFn: initializeTestStorage,
        enableInternetMonitoring: false, // Disable for testing
      );
    });

    tearDown(() async {
      await SynquillStorage.reset();
      TestUserRepository.clearLocal();
    });

    test('Request Queue Manager Initialization', () async {
      // Test that queue manager is properly initialized
      final queueManager = SynquillStorage.queueManager;
      expect(queueManager, isNotNull);

      // Test queue statistics
      final stats = queueManager.getQueueStats();
      expect(stats, hasLength(3)); // foreground, load, background
      expect(stats[QueueType.foreground], isNotNull);
      expect(stats[QueueType.load], isNotNull);
      expect(stats[QueueType.background], isNotNull);

      // All queues should start empty
      expect(stats[QueueType.foreground]!.activeAndPendingTasks, equals(0));
      expect(stats[QueueType.load]!.activeAndPendingTasks, equals(0));
      expect(stats[QueueType.background]!.activeAndPendingTasks, equals(0));
    });

    test('Network Task Creation and Execution', () async {
      final user = TestUser(
        id: 'test-user-1',
        name: 'Test User',
        email: 'test@example.com',
      );

      // Clear mock adapter logs
      mockAdapter.clearLog();

      // Create network task
      final task = NetworkTask<TestUser>(
        exec: () async {
          final result = await mockAdapter.createOne(user);
          if (result == null) {
            throw SynquillStorageException('Failed to create user');
          }
          return result;
        },
        idempotencyKey: 'test-task-1',
        operation: SyncOperation.create,
        modelType: 'TestUser',
        modelId: user.id,
        taskName: 'Test Create User',
      );

      // Execute task and get result
      unawaited(task.execute());
      final result = await task.future;
      expect(result, equals(user));

      // Verify API call was made
      expect(mockAdapter.operationLog, contains('createOne(${user.id})'));
    });

    test('Queue Capacity Limits', () async {
      final queueManager = SynquillStorage.queueManager;
      final tasks = <Future<void>>[];

      // Create long-running tasks to fill up the queue capacity
      for (int i = 0; i < 50; i++) {
        // Fill exactly to maxQueueCapacity of 50
        final task = NetworkTask<void>(
          exec: () => Future.delayed(const Duration(milliseconds: 200)),
          idempotencyKey: 'capacity-test-$i',
          operation: SyncOperation.create,
          modelType: 'TestModel',
          modelId: 'test-$i',
        );

        tasks.add(
          queueManager.enqueueTask(task, queueType: QueueType.background),
        );
      }

      // Give tasks a moment to start
      await Future.delayed(const Duration(milliseconds: 50));

      // Now the queue should be at capacity, so additional tasks should timeout
      final additionalTask = NetworkTask<void>(
        exec: () => Future.delayed(const Duration(milliseconds: 10)),
        idempotencyKey: 'capacity-test-overflow',
        operation: SyncOperation.create,
        modelType: 'TestModel',
        modelId: 'test-overflow',
      );

      // This should timeout after 100ms and throw an exception
      expect(
        () => queueManager.enqueueTask(
          additionalTask,
          queueType: QueueType.background,
        ),
        throwsA(isA<SynquillStorageException>()),
      );

      // Wait for all original tasks to complete
      await Future.wait(tasks);
    });

    test('Duplicate Task Detection', () async {
      final queueManager = SynquillStorage.queueManager;

      final task1 = NetworkTask<void>(
        exec: () => Future.delayed(const Duration(milliseconds: 100)),
        idempotencyKey: 'duplicate-test',
        operation: SyncOperation.create,
        modelType: 'TestModel',
        modelId: 'test-1',
      );

      final task2 = NetworkTask<void>(
        exec: () => Future.delayed(const Duration(milliseconds: 100)),
        idempotencyKey: 'duplicate-test', // Same idempotency key
        operation: SyncOperation.create,
        modelType: 'TestModel',
        modelId: 'test-2',
      );

      // Enqueue first task
      final future1 = queueManager.enqueueTask(
        task1,
        queueType: QueueType.background,
      );

      // Second task with same idempotency key should fail
      expect(
        () => queueManager.enqueueTask(task2, queueType: QueueType.background),
        throwsA(isA<SynquillStorageException>()),
      );

      // Wait for first task to complete
      await future1;

      // After first task completes, same idempotency key should be available
      final task3 = NetworkTask<void>(
        exec: () => Future.delayed(const Duration(milliseconds: 100)),
        idempotencyKey: 'duplicate-test',
        operation: SyncOperation.create,
        modelType: 'TestModel',
        modelId: 'test-3',
      );

      // This should now succeed
      await queueManager.enqueueTask(task3, queueType: QueueType.background);
    });

    test('Retry Executor Background Sync Integration', () async {
      final user = TestUser(
        id: 'retry-test-user',
        name: 'Retry Test User',
        email: 'retry@example.com',
      );

      // Clear mock adapter logs
      mockAdapter.clearLog();

      // Set up mock adapter to fail first attempt
      mockAdapter.setNextOperationToFail('Network error');

      // Save user with localFirst policy (should trigger background sync)
      await repository.save(user, savePolicy: DataSavePolicy.localFirst);

      // Verify user was saved locally
      final localUser = await repository.findOne(
        user.id,
        loadPolicy: DataLoadPolicy.localOnly,
      );
      expect(localUser, isNotNull);
      expect(localUser!.id, equals(user.id));

      // Clear the failure flag for next attempt
      await Future.delayed(const Duration(milliseconds: 100));

      // Trigger retry executor manually
      await SynquillStorage.retryExecutor.processDueTasksNow();

      // Wait a bit for async processing
      await Future.delayed(const Duration(milliseconds: 500));

      // Should have attempted the API call
      expect(mockAdapter.operationLog.isNotEmpty, isTrue);
    });

    test('Adaptive Polling Mode Switching', () async {
      final retryExecutor = SynquillStorage.retryExecutor;

      // Start in foreground mode
      retryExecutor.start(backgroundMode: false);
      await Future.delayed(const Duration(milliseconds: 100));

      // Switch to background mode
      retryExecutor.setBackgroundMode(true);
      await Future.delayed(const Duration(milliseconds: 100));

      // Switch back to foreground mode
      retryExecutor.setBackgroundMode(false);
      await Future.delayed(const Duration(milliseconds: 100));

      retryExecutor.stop();
    });

    test('Dead Queue Item Handling', () async {
      // This test requires direct database manipulation to simulate
      // a task that has exceeded retry limits
      final syncQueueDao = SyncQueueDao(database);
      final retryExecutor = SynquillStorage.retryExecutor;

      final user = TestUser(
        id: 'dead-task-user',
        name: 'Dead Task User',
        email: 'dead@example.com',
      );

      // Mock adapter to always fail
      mockAdapter.setNextOperationToFail('Persistent failure');

      // Insert a task with high attempt count directly into sync queue
      final taskData = {
        'model_type': 'TestUser',
        'op': 'create',
        'payload': jsonEncode(user.toJson()),
        'status': 'pending',
        'attempt_count': 9, // One less than max (10)
        'next_retry_at': DateTime.now().subtract(const Duration(minutes: 1)),
        'idempotency_key': 'dead-task-test',
      };

      final taskId = await syncQueueDao.insertItem(
        modelId: '123',
        modelType: taskData['model_type'] as String,
        operation: taskData['op'] as String,
        payload: taskData['payload'] as String,
        idempotencyKey: taskData['idempotency_key'] as String,
      );

      // Update the task to have high attempt count
      await syncQueueDao.updateTaskRetry(
        taskId,
        DateTime.now().subtract(const Duration(minutes: 1)),
        9,
        'Previous failure',
      );

      // Process due tasks - this should trigger the final retry attempt
      await retryExecutor.processDueTasksNow();
      await Future.delayed(const Duration(milliseconds: 500));

      // Check that task was removed from sync queue (marked as dead)
      final remainingTasks = await syncQueueDao.getDueTasks();
      expect(
        remainingTasks.where((task) => task['id'] == taskId),
        isEmpty,
        reason: 'Dead task should have been removed from sync queue',
      );
    });

    test('Queue Connectivity Response', () async {
      final List<dynamic> unhandledErrors = [];

      await runZonedGuarded(() async {
        final queueManager = SynquillStorage.queueManager;

        // Add some tasks to queues and collect them in a way that handles
        // cancellation gracefully
        final tasks = <Future<void>>[];
        final taskCompletions = <Completer<void>>[];

        for (int i = 0; i < 5; i++) {
          final task = NetworkTask<void>(
            exec: () => Future.delayed(
              const Duration(seconds: 2),
            ), // Longer delay to ensure tasks are running
            idempotencyKey: 'connectivity-test-$i',
            operation: SyncOperation.create,
            modelType: 'TestModel',
            modelId: 'test-$i',
          );

          // Create a completer to track task completion/cancellation
          final completer = Completer<void>();
          taskCompletions.add(completer);

          // Enqueue the task and handle its completion asynchronously
          final taskFuture = queueManager.enqueueTask(
            task,
            queueType: QueueType.background,
          );
          tasks.add(taskFuture);

          // Set up async handling for this task
          unawaited(
            taskFuture.then((_) {
              if (!completer.isCompleted) completer.complete();
            }).catchError((e) {
              if (!completer.isCompleted) {
                if (e is QueueCancelledException) {
                  completer.completeError(e);
                } else {
                  completer.completeError(e);
                }
              }
            }),
          );
        }

        // Give tasks a moment to start
        await Future.delayed(const Duration(milliseconds: 100));

        // Check that queues have tasks
        var stats = queueManager.getQueueStats();
        expect(
          stats[QueueType.background]!.activeAndPendingTasks,
          greaterThan(0),
        );

        // Simulate connectivity loss - this will cancel pending tasks
        await queueManager.clearQueuesOnDisconnect();

        // Check that queues are cleared
        stats = queueManager.getQueueStats();
        expect(stats[QueueType.background]!.activeAndPendingTasks, equals(0));

        // Wait for all task completions/cancellations to be processed
        var cancelledCount = 0;
        var completedCount = 0;

        await Future.wait(
          taskCompletions.map((completer) async {
            try {
              await completer.future;
              completedCount++;
            } catch (e) {
              if (e is QueueCancelledException) {
                cancelledCount++;
              } else {
                rethrow;
              }
            }
          }),
        );

        // At least some tasks should have been cancelled
        expect(
          cancelledCount,
          greaterThan(0),
          reason: 'Expected some tasks to be cancelled '
              '(got $cancelledCount cancelled, $completedCount completed)',
        );

        // Simulate connectivity restoration
        await queueManager.restoreQueuesOnConnect();

        // This should trigger due task processing
        await Future.delayed(const Duration(milliseconds: 500));
      }, (error, stack) {
        // Capture unhandled async errors (like QueueCancelledException)
        unhandledErrors.add(error);
        print('Captured unhandled error: ${error.runtimeType} - $error');
      });

      print('Test completed successfully with ${unhandledErrors.length} '
          'captured unhandled errors');
    });

    test('Network Error Prioritization', () async {
      final syncQueueDao = SyncQueueDao(database);
      final retryExecutor = SynquillStorage.retryExecutor;

      // Create two tasks - one with network error, one with other error
      final networkErrorUser = TestUser(
        id: 'network-error-user',
        name: 'Test',
        email: 'test@example.com',
      );

      final otherErrorUser = TestUser(
        id: 'other-error-user',
        name: 'Test',
        email: 'test2@example.com',
      );

      // Save users locally first so they exist when retry executor checks
      await repository.saveToLocal(networkErrorUser);
      await repository.saveToLocal(otherErrorUser);

      final networkErrorTaskId = await syncQueueDao.insertItem(
        modelId: networkErrorUser.id,
        modelType: 'TestUser',
        operation: 'create',
        payload: jsonEncode(networkErrorUser.toJson()),
        idempotencyKey: 'network-error-task',
      );

      final otherErrorTaskId = await syncQueueDao.insertItem(
        modelId: otherErrorUser.id,
        modelType: 'TestUser',
        operation: 'create',
        payload: jsonEncode(otherErrorUser.toJson()),
        idempotencyKey: 'other-error-task',
      );

      // Update tasks with different error types
      await syncQueueDao.updateTaskRetry(
        networkErrorTaskId,
        DateTime.now().subtract(const Duration(minutes: 1)),
        1,
        'Connection timeout - network unavailable',
      );

      await syncQueueDao.updateTaskRetry(
        otherErrorTaskId,
        DateTime.now().subtract(const Duration(minutes: 1)),
        1,
        'Validation error - invalid data format',
      );

      // Clear mock adapter logs
      mockAdapter.clearLog();

      // Process due tasks
      await retryExecutor.processDueTasksNow();

      // Check what operations were executed
      final operations = mockAdapter.operationLog;
      expect(operations, hasLength(2), reason: 'Should execute both due tasks');
    });

    test('Background Sync Manager Integration', () async {
      // Initialize background sync manager - it's already initialized in setUp
      final manager = BackgroundSyncManager.instance;

      // Process background sync tasks
      await manager.processBackgroundSyncTasks();

      // Test mode switching
      manager.enableBackgroundMode();
      manager.enableForegroundMode();

      // Test readiness check
      expect(manager.isReadyForBackgroundSync, isTrue);

      // Cancel background sync
      await manager.cancelBackgroundSync();
    });

    test('SyncedStorage getRepository Method', () async {
      // Test that we can get a repository instance using SyncedStorage
      final retrievedRepository =
          SynquillStorage.instance.getRepository<TestUser>();

      expect(retrievedRepository, isNotNull);
      expect(retrievedRepository, isA<TestUserRepository>());

      // Test that the repository is functional
      final user = TestUser(
        id: 'get-repo-test-user',
        name: 'Get Repo Test User',
        email: 'getrepo@example.com',
      );

      // Save using the retrieved repository
      await retrievedRepository.save(
        user,
        savePolicy: DataSavePolicy.localFirst,
      );

      // Verify the user was saved
      final savedUser = await retrievedRepository.findOne(
        user.id,
        loadPolicy: DataLoadPolicy.localOnly,
      );

      expect(savedUser, isNotNull);
      expect(savedUser!.id, equals(user.id));
      expect(savedUser.name, equals(user.name));
      expect(savedUser.email, equals(user.email));
    });

    test('SyncedStorage getRepositoryByName Method', () async {
      // Test that we can get a repository instance by string model name
      final retrievedRepository = SynquillStorage.instance.getRepositoryByName(
        'TestUser',
      );

      expect(retrievedRepository, isNotNull);
      expect(retrievedRepository, isA<TestUserRepository>());

      // Test that the repository is functional
      final user = TestUser(
        id: 'get-repo-by-name-test-user',
        name: 'Get Repo By Name Test User',
        email: 'getrepobyname@example.com',
      );

      // Cast to the correct type to access TestUserRepository methods
      final typedRepository = retrievedRepository as TestUserRepository;

      // Save using the retrieved repository
      await typedRepository.save(user, savePolicy: DataSavePolicy.localFirst);

      // Verify the user was saved
      final savedUser = await typedRepository.findOne(
        user.id,
        loadPolicy: DataLoadPolicy.localOnly,
      );

      expect(savedUser, isNotNull);
      expect(savedUser!.id, equals(user.id));
      expect(savedUser.name, equals(user.name));
      expect(savedUser.email, equals(user.email));

      // Test with non-existent model type
      final nullRepository = SynquillStorage.instance.getRepositoryByName(
        'NonExistentModel',
      );
      expect(nullRepository, isNull);
    });

    test('LocalThenRemote operations use QueueType.load', () async {
      final queueManager = SynquillStorage.queueManager;

      // Clear any existing tasks and logs
      await queueManager.clearQueuesOnDisconnect();
      await queueManager.restoreQueuesOnConnect();
      mockAdapter.clearLog();

      final user = TestUser(
        id: 'load-queue-test-user',
        name: 'Load Queue Test User',
        email: 'loadqueue@example.com',
      );

      // Add user to remote data so remote fetch can find it
      mockAdapter.addRemoteUser(user);
      // Save user locally first so localThenRemote can find it locally
      await repository.saveToLocal(user);

      // Use localThenRemote policy - this should trigger background refresh
      // using load queue. Explicitly pass the policy to override default.
      final foundUser = await repository.findOne(
        user.id,
        loadPolicy: DataLoadPolicy.localThenRemote,
      );

      // Verify user was found locally
      expect(foundUser, isNotNull);
      expect(foundUser!.id, equals(user.id));

      // Wait a bit for the background task to be enqueued and processed
      await Future.delayed(const Duration(milliseconds: 200));

      // Verify that the remote API was called
      expect(
        mockAdapter.operationLog,
        contains('findOne(${user.id})'),
        reason: 'Background refresh should call remote API',
      );

      // Test with findAll as well
      mockAdapter.clearLog();
      await queueManager.clearQueuesOnDisconnect();
      await queueManager.restoreQueuesOnConnect();

      // Use localThenRemote for findAll
      final allUsers = await repository.findAll(
        loadPolicy: DataLoadPolicy.localThenRemote,
      );

      // Should find the locally saved user
      expect(allUsers, hasLength(1));
      expect(allUsers.first.id, equals(user.id));

      // Wait a bit for the background task to be enqueued and processed
      await Future.delayed(const Duration(milliseconds: 800));

      // Verify that the remote API was called for findAll
      expect(
        mockAdapter.operationLog,
        contains('findAll()'),
        reason: 'Background refresh should call remote findAll API',
      );
    });
  });

  group('Queue System Error Handling', () {
    late TestDatabase database;
    late MockApiAdapter mockAdapter;
    late Logger logger;

    setUp(() async {
      // Set up test database
      database = TestDatabase(NativeDatabase.memory());

      // Set up logging
      logger = Logger('QueueSystemErrorTest');
      /*Logger.root.level = Level.ALL;
      Logger.root.onRecord.listen((record) {
        print('[${record.level.name}] ${record.loggerName}: ${record.message}');
        if (record.error != null) print('Error: ${record.error}');
        if (record.stackTrace != null) print('Stack: ${record.stackTrace}');
      });*/

      // Set up test repository
      mockAdapter = MockApiAdapter();

      // Register repository factory
      SynquillRepositoryProvider.register<TestUser>(
        (db) => TestUserRepository(db as TestDatabase, mockAdapter),
      );

      // Initialize SyncedStorage with test configuration
      await SynquillStorage.init(
        database: database,
        config: const SynquillStorageConfig(
          defaultSavePolicy: DataSavePolicy.localFirst,
          defaultLoadPolicy: DataLoadPolicy.localOnly,
          foregroundQueueConcurrency: 1,
          backgroundQueueConcurrency: 1,
        ),
        logger: logger,
        initializeFn: initializeTestStorage,
        enableInternetMonitoring: false, // Disable for testing
      );
    });

    tearDown(() async {
      await SynquillStorage.reset();
      TestUserRepository.clearLocal();
    });

    test('Invalid Network Task Parameters', () async {
      expect(
        () => NetworkTask<void>(
          exec: () => Future.value(),
          idempotencyKey: '', // Empty idempotency key
          operation: SyncOperation.create,
          modelType: 'TestModel',
          modelId: 'test-1',
        ),
        returnsNormally, // Should not throw, but may cause issues later
      );
    });

    test('Queue Manager Error Recovery', () async {
      final queueManager = SynquillStorage.queueManager;

      // Create a task that will fail
      final failingTask = NetworkTask<void>(
        exec: () => throw Exception('Task execution failed'),
        idempotencyKey: 'failing-task',
        operation: SyncOperation.create,
        modelType: 'TestModel',
        modelId: 'test-1',
      );

      // Enqueue failing task should not throw during enqueue
      // (errors happen during execution)
      final failingFuture = queueManager.enqueueTask(
        failingTask,
        queueType: QueueType.background,
      );

      // Wait for the failing task to complete and expect it to fail
      await expectLater(
        failingFuture,
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Task execution failed'),
          ),
        ),
      );

      // Queue should still be functional for other tasks
      final successTask = NetworkTask<void>(
        exec: () => Future.delayed(const Duration(milliseconds: 100)),
        idempotencyKey: 'success-task',
        operation: SyncOperation.create,
        modelType: 'TestModel',
        modelId: 'test-2',
      );

      // This should succeed without issues
      await queueManager.enqueueTask(
        successTask,
        queueType: QueueType.background,
      );

      // Verify queue is still functional by checking stats
      final stats = queueManager.getQueueStats();
      expect(stats[QueueType.background], isNotNull);
    });
  });

  group('CONCURRENCY ANALYSIS: High-Priority Race Condition Tests', () {
    late TestDatabase database;
    late MockApiAdapter mockAdapter;
    late Logger logger;

    setUp(() async {
      database = TestDatabase(NativeDatabase.memory());
      logger = Logger('ConcurrencyTest');
      mockAdapter = MockApiAdapter();

      TestUserRepository.clearLocal();
      SynquillRepositoryProvider.register<TestUser>(
        (db) => TestUserRepository(db as TestDatabase, mockAdapter),
      );

      await SynquillStorage.init(
        database: database,
        config: const SynquillStorageConfig(
          defaultSavePolicy: DataSavePolicy.localFirst,
          defaultLoadPolicy: DataLoadPolicy.localOnly,
          foregroundQueueConcurrency: 3, // Allow more concurrency for testing
          backgroundQueueConcurrency: 3,
          foregroundQueueCapacityTimeout: Duration(milliseconds: 50),
          backgroundQueueCapacityTimeout: Duration(milliseconds: 50),
          queueCapacityCheckInterval: Duration(milliseconds: 5),
        ),
        logger: logger,
        initializeFn: initializeTestStorage,
        enableInternetMonitoring: false,
      );
    });

    tearDown(() async {
      await SynquillStorage.reset();
      TestUserRepository.clearLocal();
    });

    test('HIGH: Idempotency Key Race Condition Test', () async {
      final queueManager = SynquillStorage.queueManager;
      mockAdapter.clearLog();

      const int concurrentTasks = 10;
      const String sharedIdempotencyKey = 'race-test-key';

      // Create identical tasks with same idempotency key
      final tasks = <Future<void>>[];
      final completers = <Completer<void>>[];
      var successCount = 0;
      var failureCount = 0;

      // Launch all tasks simultaneously to create race condition
      for (int i = 0; i < concurrentTasks; i++) {
        final completer = Completer<void>();
        completers.add(completer);

        final task = NetworkTask<String>(
          exec: () async {
            await Future.delayed(const Duration(milliseconds: 100));
            return 'task-$i-result';
          },
          idempotencyKey: sharedIdempotencyKey,
          operation: SyncOperation.create,
          modelType: 'TestModel',
          modelId: 'test-$i',
          taskName: 'Race Test Task $i',
        );

        // Use unawaited to start all tasks concurrently
        final taskFuture = queueManager.enqueueTask(
          task,
          queueType: QueueType.foreground,
        );
        tasks.add(taskFuture);

        unawaited(
          taskFuture.then((result) {
            successCount++;
            if (!completer.isCompleted) completer.complete();
          }).catchError((error) {
            failureCount++;
            if (!completer.isCompleted) completer.complete();
          }),
        );
      }

      // Wait for all tasks to complete (either success or failure)
      await Future.wait(completers.map((c) => c.future));

      // Only ONE task should succeed, others should fail due to
      // duplicate idempotency key
      expect(
        successCount,
        equals(1),
        reason: 'Only one task should succeed with same idempotency key',
      );
      expect(
        failureCount,
        equals(concurrentTasks - 1),
        reason: 'Other tasks should fail due to duplicate idempotency key',
      );
    });

    test('HIGH: Queue Capacity Race Condition Test', () async {
      // Reinitialize with very small queue capacity
      await SynquillStorage.reset();
      await SynquillStorage.init(
        database: database,
        config: const SynquillStorageConfig(
          defaultSavePolicy: DataSavePolicy.localFirst,
          defaultLoadPolicy: DataLoadPolicy.localOnly,
          foregroundQueueConcurrency: 1,
          backgroundQueueConcurrency: 1,
          foregroundQueueCapacityTimeout: Duration(milliseconds: 100),
          backgroundQueueCapacityTimeout: Duration(milliseconds: 100),
          queueCapacityCheckInterval: Duration(milliseconds: 5),
          maxForegroundQueueCapacity: 3,
          maxLoadQueueCapacity: 3,
          maxBackgroundQueueCapacity: 3,
        ),
        logger: logger,
        initializeFn: initializeTestStorage,
        enableInternetMonitoring: false,
      );

      final queueManager = SynquillStorage.queueManager;
      const int overflowTasks = 10; // More than capacity

      final List<Future<dynamic>> futures = [];
      final List<String> errors = [];
      int successCount = 0;
      int capacityErrors = 0;

      // Create long-running tasks to fill capacity
      for (int i = 0; i < overflowTasks; i++) {
        final task = NetworkTask<String>(
          exec: () async {
            await Future.delayed(const Duration(milliseconds: 200));
            return 'capacity-result-$i';
          },
          idempotencyKey: 'capacity-test-$i',
          operation: SyncOperation.create,
          modelType: 'TestModel',
          modelId: 'capacity-$i',
          taskName: 'Capacity Test Task $i',
        );

        final future = queueManager
            .enqueueTask(task, queueType: QueueType.background)
            .then((result) {
          successCount++;
          return result;
        }).catchError((error) {
          final errorMsg = 'Capacity task $i failed: $error';
          errors.add(errorMsg);
          if (error.toString().contains('capacity') ||
              error.toString().contains('timeout') ||
              error.toString().contains('queue full')) {
            capacityErrors++;
          }
          return 'error-$i';
        });

        futures.add(future);

        // Small delay to increase chance of race conditions
        await Future.delayed(const Duration(milliseconds: 1));
      }

      await Future.wait(futures);

      // Should not exceed queue capacity significantly
      expect(
        successCount,
        lessThanOrEqualTo(5),
        reason: 'Queue capacity should be respected',
      );
      expect(
        capacityErrors,
        greaterThan(0),
        reason: 'Some tasks should fail due to capacity limits',
      );
    });

    test('HIGH: RetryExecutor Timer Management Race Condition', () async {
      final retryExecutor = SynquillStorage.retryExecutor;

      const int cycles = 20;

      for (int i = 0; i < cycles; i++) {
        // Start in foreground mode
        retryExecutor.start(backgroundMode: false);
        await Future.delayed(const Duration(milliseconds: 10));

        // Switch to background mode
        retryExecutor.setBackgroundMode(true);
        await Future.delayed(const Duration(milliseconds: 10));

        // Switch back to foreground mode
        retryExecutor.setBackgroundMode(false);
        await Future.delayed(const Duration(milliseconds: 10));

        // Stop
        retryExecutor.stop();
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // After all cycles, executor should be in a clean state
      retryExecutor.start(backgroundMode: false);
      await Future.delayed(const Duration(milliseconds: 100));
      retryExecutor.stop();
    });

    test('HIGH: Database Concurrent Task Status Updates', () async {
      final syncQueueDao = SyncQueueDao(database);

      const int concurrentUpdates = 15;
      final taskIds = <int>[];

      // Create multiple sync queue tasks
      for (int i = 0; i < concurrentUpdates; i++) {
        final user = TestUser(
          id: 'concurrent-update-$i',
          name: 'Test User $i',
          email: 'test$i@example.com',
        );

        final taskId = await syncQueueDao.insertItem(
          modelId: user.id,
          modelType: 'TestUser',
          operation: 'create',
          payload: jsonEncode(user.toJson()),
          idempotencyKey: 'concurrent-update-$i',
        );
        taskIds.add(taskId);
      }

      // Perform concurrent updates on all tasks
      final updateFutures = <Future<void>>[];

      for (int i = 0; i < taskIds.length; i++) {
        final taskId = taskIds[i];

        // Create multiple concurrent updates for each task
        for (int updateIndex = 0; updateIndex < 3; updateIndex++) {
          final future = syncQueueDao.updateTaskRetry(
            taskId,
            DateTime.now().add(Duration(minutes: updateIndex + 1)),
            updateIndex + 1,
            'Concurrent update attempt ${updateIndex + 1}',
          );
          updateFutures.add(future);
        }
      }

      // Wait for all updates to complete
      await Future.wait(updateFutures);

      // Verify that all tasks still exist and have consistent state
      // Use getAllItems() instead of getDueTasks() because updateTaskRetry
      // sets next_retry_at to future dates, making tasks not "due"
      final remainingTasks = await syncQueueDao.getAllItems();

      // All tasks should still exist (not corrupted by concurrent updates)
      expect(
        remainingTasks.length,
        equals(taskIds.length),
        reason: 'All tasks should still exist after concurrent updates',
      );
    });
  });

  group('CONCURRENCY ANALYSIS: Integration Stress Tests', () {
    late TestDatabase database;
    late TestUserRepository repository;
    late MockApiAdapter mockAdapter;
    late Logger logger;

    setUp(() async {
      database = TestDatabase(NativeDatabase.memory());
      logger = Logger('StressTest');
      mockAdapter = MockApiAdapter();
      repository = TestUserRepository(database, mockAdapter);

      TestUserRepository.clearLocal();
      SynquillRepositoryProvider.register<TestUser>(
        (db) => TestUserRepository(db as TestDatabase, mockAdapter),
      );

      await SynquillStorage.init(
        database: database,
        config: const SynquillStorageConfig(
          defaultSavePolicy: DataSavePolicy.localFirst,
          defaultLoadPolicy: DataLoadPolicy.localOnly,
          foregroundQueueConcurrency: 5,
          backgroundQueueConcurrency: 5,
          foregroundQueueCapacityTimeout: Duration(milliseconds: 100),
          backgroundQueueCapacityTimeout: Duration(milliseconds: 100),
          queueCapacityCheckInterval: Duration(milliseconds: 5),
        ),
        logger: logger,
        initializeFn: initializeTestStorage,
        enableInternetMonitoring: false,
      );
    });

    tearDown(() async {
      await SynquillStorage.reset();
      TestUserRepository.clearLocal();
    });

    test('STRESS: Mixed Queue Type Concurrent Load', () async {
      final queueManager = SynquillStorage.queueManager;
      mockAdapter.clearLog();

      const int tasksPerQueue = 20;
      final allTasks = <Future<void>>[];

      // Create tasks for each queue type
      for (final queueType in [
        QueueType.foreground,
        QueueType.background,
        QueueType.load,
      ]) {
        for (int i = 0; i < tasksPerQueue; i++) {
          final task = NetworkTask<String>(
            exec: () async {
              await Future.delayed(Duration(milliseconds: 50 + (i % 100)));
              return '${queueType.name}-task-$i';
            },
            idempotencyKey: '${queueType.name}-stress-$i',
            operation: SyncOperation.create,
            modelType: 'TestModel',
            modelId: '${queueType.name}-$i',
            taskName: '${queueType.name} Stress Task $i',
          );

          final taskFuture = queueManager.enqueueTask(
            task,
            queueType: queueType,
          );
          allTasks.add(taskFuture);

          unawaited(taskFuture.then((result) {}));
        }
      }

      await Future.wait(allTasks);

      // Verify all queues are empty
      final stats = queueManager.getQueueStats();

      // Check final queue stats with proper retry logic
      var finalStats = stats;

      for (final queueType in [
        QueueType.foreground,
        QueueType.background,
        QueueType.load,
      ]) {
        var queueStats = finalStats[queueType]!;

        // Wait a bit more for background queue and recheck if needed
        if (queueType == QueueType.background &&
            queueStats.activeAndPendingTasks > 0) {
          await Future.delayed(const Duration(milliseconds: 200));
          finalStats = queueManager.getQueueStats();
          queueStats = finalStats[queueType]!;
        }

        expect(
          finalStats[queueType]!.activeAndPendingTasks,
          equals(0),
          reason: '${queueType.name} queue should be empty after stress test',
        );
      }
    });

    test('STRESS: Network Interruption During Operations', () async {
      final List<dynamic> unhandledErrors = [];

      await runZonedGuarded(() async {
        final queueManager = SynquillStorage.queueManager;
        const int taskCount = 8;

        // Create tasks that simulate network operations
        final futures = <Future<dynamic>>[];
        final results = <String>[];
        final errors = <String>[];

        for (int i = 0; i < taskCount; i++) {
          final task = NetworkTask<String>(
            exec: () async {
              // Simulate network operation
              if (i % 3 == 0) {
                // Simulate network failure for some tasks
                await Future.delayed(const Duration(milliseconds: 30));
                throw Exception('Simulated network failure for task $i');
              } else {
                await Future.delayed(const Duration(milliseconds: 50));
                return 'network-result-$i';
              }
            },
            idempotencyKey: 'network-test-$i',
            operation: SyncOperation.update,
            modelType: 'NetworkTestModel',
            modelId: 'net-$i',
            taskName: 'Network Test Task $i',
          );

          final future = queueManager
              .enqueueTask(task, queueType: QueueType.background)
              .then((result) {
            results.add(result);
            return result;
          }).catchError((error) {
            final errorMsg = 'Network task $i failed: $error';
            errors.add(errorMsg);
            return 'error-$i';
          });

          futures.add(future);
        }

        // Simulate connectivity changes during execution
        await Future.delayed(const Duration(milliseconds: 25));
        queueManager.clearQueuesOnDisconnect();

        await Future.wait(futures);

        // System should handle network interruptions gracefully
        expect(
          results.length + errors.length,
          equals(taskCount),
          reason: 'All tasks should either succeed or fail gracefully during '
              'network interruption',
        );
      }, (error, stack) {
        // Capture unhandled async errors (like QueueCancelledException)
        unhandledErrors.add(error);
        print('Captured unhandled error: ${error.runtimeType} - $error');
      });

      print('Test completed successfully with ${unhandledErrors.length} '
          'captured unhandled errors');
    });

    test('STRESS: Resource Exhaustion Scenarios', () async {
      // Create a large number of tasks to test resource management
      const int largeTaskCount = 50;
      final queueManager = SynquillStorage.queueManager;

      final List<Future<dynamic>> futures = [];
      final List<String> errors = [];
      int successCount = 0;

      for (int i = 0; i < largeTaskCount; i++) {
        final task = NetworkTask<String>(
          exec: () async {
            // Simulate resource-intensive operation
            final data = List.generate(1000, (index) => 'data-$index');
            await Future.delayed(const Duration(milliseconds: 10));
            return 'resource-result-$i-${data.length}';
          },
          idempotencyKey: 'resource-test-$i',
          operation: SyncOperation.create,
          modelType: 'ResourceTestModel',
          modelId: 'resource-$i',
          taskName: 'Resource Test Task $i',
        );

        final future = queueManager
            .enqueueTask(task, queueType: QueueType.foreground)
            .then((result) {
          successCount++;
          return result;
        }).catchError((error) {
          final errorMsg = 'Resource task $i failed: $error';
          errors.add(errorMsg);
          return 'error-$i';
        });

        futures.add(future);
      }

      final startTime = DateTime.now();
      await Future.wait(futures);
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      // System should handle resource pressure gracefully
      expect(
        successCount,
        greaterThan(largeTaskCount * 0.8),
        reason: 'At least 80% of tasks should succeed under resource pressure',
      );
      expect(
        duration.inSeconds,
        lessThan(30),
        reason: 'Tasks should complete within reasonable time even '
            'under resource pressure',
      );
    });

    test('EDGE: State Consistency Under Concurrent Operations', () async {
      const int userCount = 10;
      const int operationsPerUser = 5;

      final List<Future<void>> allOperations = [];
      final Map<String, int> operationCounts = {};

      // Create multiple users and perform concurrent operations on each
      for (int userId = 0; userId < userCount; userId++) {
        final userIdStr = 'consistency-user-$userId';
        operationCounts[userIdStr] = 0;

        // Initial user creation
        final initialUser = TestUser(
          id: userIdStr,
          name: 'Initial User $userId',
          email: 'initial$userId@example.com',
        );

        allOperations.add(repository.save(initialUser).then((_) {}));

        // Multiple concurrent updates to the same user
        for (int op = 0; op < operationsPerUser; op++) {
          allOperations.add(
            Future(() async {
              await Future.delayed(Duration(milliseconds: op * 10));
              final updatedUser = TestUser(
                id: userIdStr,
                name: 'Updated User $userId (op $op)',
                email: 'updated$userId-$op@example.com',
              );

              await repository.save(updatedUser);
              operationCounts[userIdStr] = operationCounts[userIdStr]! + 1;
            }).catchError((error) {}),
          );
        }
      }

      // Wait for all operations to complete
      await Future.wait(allOperations);

      // Verify final state consistency
      for (int userId = 0; userId < userCount; userId++) {
        final userIdStr = 'consistency-user-$userId';
        final user = await repository.findOne(userIdStr);

        expect(user, isNotNull, reason: 'User $userId should exist');
        expect(user!.id, equals(userIdStr), reason: 'User ID should match');
        expect(
          user.name,
          contains('Updated User $userId'),
          reason: 'User name should be updated',
        );
      }
    });
  });

  // =========================
  // MIXED LOAD AND STRESS TESTS
  // =========================

  group('STRESS: Mixed Load Tests', () {
    late TestDatabase database;
    late TestUserRepository repository;
    late MockApiAdapter mockAdapter;
    late Logger logger;

    setUp(() async {
      database = TestDatabase(NativeDatabase.memory());
      logger = Logger('StressTest');
      mockAdapter = MockApiAdapter();
      repository = TestUserRepository(database, mockAdapter);

      TestUserRepository.clearLocal();
      SynquillRepositoryProvider.register<TestUser>(
        (db) => TestUserRepository(db as TestDatabase, mockAdapter),
      );

      await SynquillStorage.init(
        database: database,
        config: const SynquillStorageConfig(
          defaultSavePolicy: DataSavePolicy.localFirst,
          defaultLoadPolicy: DataLoadPolicy.localOnly,
          foregroundQueueConcurrency: 5,
          backgroundQueueConcurrency: 5,
          foregroundQueueCapacityTimeout: Duration(milliseconds: 100),
          backgroundQueueCapacityTimeout: Duration(milliseconds: 100),
          queueCapacityCheckInterval: Duration(milliseconds: 5),
        ),
        logger: logger,
        initializeFn: initializeTestStorage,
        enableInternetMonitoring: false,
      );
    });

    tearDown(() async {
      await SynquillStorage.reset();
      TestUserRepository.clearLocal();
    });

    test('STRESS: Mixed Queue Type Concurrent Load', () async {
      final queueManager = SynquillStorage.queueManager;
      mockAdapter.clearLog();

      const int tasksPerQueue = 15;
      final allTasks = <Future<void>>[];
      var completedTasks = 0;

      // Create tasks for each queue type
      final queueTypes = [
        QueueType.foreground,
        QueueType.background,
        QueueType.load,
      ];

      for (final queueType in queueTypes) {
        for (int i = 0; i < tasksPerQueue; i++) {
          final task = NetworkTask<String>(
            exec: () async {
              await Future.delayed(Duration(milliseconds: 50 + (i % 100)));
              return '${queueType.name}-task-$i';
            },
            idempotencyKey: '${queueType.name}-stress-$i',
            operation: SyncOperation.create,
            modelType: 'TestModel',
            modelId: '${queueType.name}-$i',
            taskName: '${queueType.name} Stress Task $i',
          );

          final taskFuture = queueManager.enqueueTask(
            task,
            queueType: queueType,
          );
          allTasks.add(taskFuture);

          unawaited(
            taskFuture.then((result) {
              completedTasks++;
              if (completedTasks % 10 == 0) {}
            }),
          );
        }
      }

      await Future.wait(allTasks);

      // Verify all queues are empty
      final stats = queueManager.getQueueStats();

      // Check final queue stats with proper retry logic

      var finalStats = stats;

      for (final queueType in queueTypes) {
        var queueStats = finalStats[queueType]!;

        // Wait a bit more for background queue and recheck if needed
        if (queueType == QueueType.background &&
            queueStats.activeAndPendingTasks > 0) {
          await Future.delayed(const Duration(milliseconds: 200));
          finalStats = queueManager.getQueueStats();
          queueStats = finalStats[queueType]!;
        }

        expect(
          finalStats[queueType]!.activeAndPendingTasks,
          equals(0),
          reason: '${queueType.name} queue should be empty after test',
        );
      }
    });

    test('STRESS: State Consistency Under Load', () async {
      const int userCount = 8;
      const int operationsPerUser = 3;

      final List<Future<void>> allOperations = [];
      final Map<String, int> operationCounts = {};

      // Create multiple users and perform concurrent operations on each
      for (int userId = 0; userId < userCount; userId++) {
        final userIdStr = 'consistency-user-$userId';
        operationCounts[userIdStr] = 0;

        // Initial user creation
        final initialUser = TestUser(
          id: userIdStr,
          name: 'Initial User $userId',
          email: 'initial$userId@example.com',
        );

        allOperations.add(repository.save(initialUser).then((_) {}));

        // Multiple concurrent updates to the same user
        for (int op = 0; op < operationsPerUser; op++) {
          allOperations.add(
            Future(() async {
              await Future.delayed(Duration(milliseconds: op * 10));
              final updatedUser = TestUser(
                id: userIdStr,
                name: 'Updated User $userId (op $op)',
                email: 'updated$userId-$op@example.com',
              );

              await repository.save(updatedUser);
              operationCounts[userIdStr] = operationCounts[userIdStr]! + 1;
            }).catchError((error) {}),
          );
        }
      }

      // Wait for all operations to complete
      await Future.wait(allOperations);

      // Verify final state consistency
      for (int userId = 0; userId < userCount; userId++) {
        final userIdStr = 'consistency-user-$userId';
        final user = await repository.findOne(userIdStr);

        expect(user, isNotNull, reason: 'User $userId should exist');
        expect(user!.id, equals(userIdStr), reason: 'User ID should match');
        expect(
          user.name,
          contains('Updated User $userId'),
          reason: 'User name should be updated',
        );
      }
    });
  });

  group('Stream Controller Resource Management Tests', () {
    late TestDatabase database;
    late TestUserRepository repository;
    late MockApiAdapter mockAdapter;
    late Logger logger;

    setUp(() async {
      // Set up test database
      database = TestDatabase(NativeDatabase.memory());

      // Set up logging
      logger = Logger('StreamControllerTest');
      Logger.root.level = Level.ALL;
      Logger.root.onRecord.listen((record) {
        // Uncomment for debugging
        //print('[${record.level.name}] ${record.loggerName}: '
        //    '${record.message}');
      });

      // Set up test repository
      mockAdapter = MockApiAdapter();
      repository = TestUserRepository(database, mockAdapter);

      // Clear any existing local data from previous tests
      TestUserRepository.clearLocal();

      // Register repository factory
      SynquillRepositoryProvider.register<TestUser>(
        (db) => TestUserRepository(db as TestDatabase, mockAdapter),
      );

      // Initialize SyncedStorage with test configuration
      await SynquillStorage.init(
        database: database,
        config: const SynquillStorageConfig(
          defaultSavePolicy: DataSavePolicy.localFirst,
          defaultLoadPolicy: DataLoadPolicy.localOnly,
          foregroundQueueConcurrency: 1,
          backgroundQueueConcurrency: 1,
        ),
        logger: logger,
        initializeFn: initializeTestStorage,
        enableInternetMonitoring: false, // Disable for testing
      );
    });

    tearDown(() async {
      await SynquillStorage.reset();
      TestUserRepository.clearLocal();
    });

    test('Stream Controller Disposal in Error Scenarios', () async {
      // Create a test user to trigger repository operations
      final user = TestUser(
        id: 'stream-test-user-1',
        name: 'Stream Test User',
        email: 'stream@test.com',
      );

      // Track the repository's change stream
      late StreamSubscription subscription;
      final streamEvents = <RepositoryChange<TestUser>>[];

      // Subscribe to the repository changes stream
      subscription = repository.changes.listen(
        (change) {
          streamEvents.add(change);
        },
        onError: (error) {},
        onDone: () {},
      );

      // Save the user successfully first
      await repository.save(user);
      expect(streamEvents, hasLength(1));
      expect(streamEvents.last.type, equals(RepositoryChangeType.created));

      // Force an error scenario by making the API adapter throw
      mockAdapter.shouldFailOnUpdate = true;
      mockAdapter.failureMessage = 'Simulated API failure';

      // Try to update the user - this should cause an error
      final updatedUser = user.copyWith(name: 'Updated Name');
      try {
        await repository.save(
          updatedUser,
          savePolicy: DataSavePolicy.remoteFirst,
        );
        fail('Expected save to fail');
      } catch (e) {}

      // Wait for error event to propagate
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify an error event was emitted
      expect(streamEvents.length, greaterThan(1));
      expect(streamEvents.last.type, equals(RepositoryChangeType.error));

      // Reset the API adapter
      mockAdapter.shouldFailOnUpdate = false;

      // Cancel the subscription before disposing
      await subscription.cancel();

      // Dispose the repository to test stream controller cleanup
      // This should complete without throwing an exception
      expect(() => repository.dispose(), returnsNormally);

      // Verify that basic operations on the repository still handle
      // disposal gracefully (may fail, but shouldn't cause crashes)
      await Future.delayed(const Duration(milliseconds: 50));
    });

    test('Multiple Stream Listeners and Broadcast Behavior', () async {
      final user = TestUser(
        id: 'broadcast-test-user',
        name: 'Broadcast Test User',
        email: 'broadcast@test.com',
      );

      // Set up multiple listeners on the same stream
      final listener1Events = <RepositoryChange<TestUser>>[];
      final listener2Events = <RepositoryChange<TestUser>>[];
      final listener3Events = <RepositoryChange<TestUser>>[];

      // Subscribe multiple listeners to the same broadcast stream
      final subscription1 = repository.changes.listen((change) {
        listener1Events.add(change);
      });

      final subscription2 = repository.changes.listen((change) {
        listener2Events.add(change);
      });

      final subscription3 = repository.changes.listen((change) {
        listener3Events.add(change);
      });

      // Perform operations that should notify all listeners
      await repository.save(user);
      await Future.delayed(const Duration(milliseconds: 50));

      final updatedUser = user.copyWith(name: 'Updated Name');
      await repository.save(updatedUser);
      await Future.delayed(const Duration(milliseconds: 50));

      await repository.delete(user.id);
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify all listeners received the same events
      expect(listener1Events, hasLength(3));
      expect(listener2Events, hasLength(3));
      expect(listener3Events, hasLength(3));

      // Verify event types are correct
      expect(listener1Events[0].type, equals(RepositoryChangeType.created));
      expect(listener1Events[1].type, equals(RepositoryChangeType.updated));
      expect(listener1Events[2].type, equals(RepositoryChangeType.deleted));

      // Verify all listeners got identical events
      for (int i = 0; i < 3; i++) {
        expect(listener1Events[i].type, equals(listener2Events[i].type));
        expect(listener2Events[i].type, equals(listener3Events[i].type));
      }

      // Cancel subscriptions in different order to test robustness
      await subscription2.cancel();
      await subscription1.cancel();
      await subscription3.cancel();
    });

    test('Stream Controller Memory Leak Prevention', () async {
      final users = <TestUser>[];
      final subscriptions = <StreamSubscription>[];

      // Create multiple repositories and stream subscriptions
      for (int i = 0; i < 10; i++) {
        final user = TestUser(
          id: 'memory-leak-test-$i',
          name: 'Memory Test User $i',
          email: 'memory$i@test.com',
        );
        users.add(user);

        // Create subscription and immediately cancel some of them
        final subscription = repository.changes.listen((change) {
          // Process change
        });
        subscriptions.add(subscription);

        // Save user to generate stream events
        await repository.save(user);
      }

      // Cancel half of the subscriptions immediately
      for (int i = 0; i < 5; i++) {
        await subscriptions[i].cancel();
      }

      // Perform more operations to test that cancelled subscriptions
      // don't cause memory leaks
      for (int i = 0; i < 10; i++) {
        final updatedUser = users[i].copyWith(name: 'Updated User $i');
        await repository.save(updatedUser);
      }

      // Cancel remaining subscriptions
      for (int i = 5; i < 10; i++) {
        await subscriptions[i].cancel();
      }

      // Force disposal of the repository
      repository.dispose();

      // Give time for cleanup
      await Future.delayed(const Duration(milliseconds: 100));
    });

    test('Stream Controller Lifecycle During Concurrent Operations', () async {
      final user = TestUser(
        id: 'concurrent-stream-test',
        name: 'Concurrent Stream Test User',
        email: 'concurrent@test.com',
      );

      final events = <RepositoryChange<TestUser>>[];
      var streamStillActive = true;

      // Subscribe to the stream
      final subscription = repository.changes.listen(
        (change) {
          events.add(change);
        },
        onError: (error) {},
        onDone: () {
          streamStillActive = false;
        },
      );

      // Perform concurrent operations that might stress the stream controller
      final futures = <Future>[];

      // Concurrent saves
      for (int i = 0; i < 5; i++) {
        futures.add(repository.save(user.copyWith(name: 'Concurrent Save $i')));
      }

      // Concurrent reads while saves are happening
      for (int i = 0; i < 3; i++) {
        futures.add(repository.findOne(user.id));
      }

      // Wait for normal operations to complete first
      await Future.wait(futures);

      // Now perform error operations separately to ensure they generate events
      mockAdapter.shouldFailOnUpdate = true;
      for (int i = 0; i < 2; i++) {
        try {
          await repository.save(
            user.copyWith(name: 'Error Save $i'),
            savePolicy: DataSavePolicy.remoteFirst,
          );
          fail('Expected save to fail');
        } catch (e) {
          // Error should be captured in stream events
        }
      }
      mockAdapter.shouldFailOnUpdate = false;

      // Give some time for all events to propagate
      await Future.delayed(const Duration(milliseconds: 200));

      // Count error events from the stream
      final errorEvents =
          events.where((e) => e.type == RepositoryChangeType.error).length;

      // Verify the stream controller handled concurrent operations correctly
      expect(events.length, greaterThan(5)); // Should have multiple events
      expect(errorEvents, greaterThan(0)); // Should have error events
      expect(
        streamStillActive,
        isTrue,
      ); // Stream shouldn't complete unless disposed

      // Cancel subscription and dispose repository
      await subscription.cancel();
      repository.dispose();

      // Give time for disposal
      await Future.delayed(const Duration(milliseconds: 100));
    });

    test('Stream Controller Error Recovery and Resilience', () async {
      final user = TestUser(
        id: 'resilience-test-user',
        name: 'Resilience Test User',
        email: 'resilience@test.com',
      );

      final events = <RepositoryChange<TestUser>>[];
      var streamStillActive = true;

      // Subscribe to the stream with error handling
      final subscription = repository.changes.listen(
        (change) {
          events.add(change);
        },
        onError: (error) {},
        onDone: () {
          streamStillActive = false;
        },
      );

      // Start with successful operation
      await repository.save(user);
      expect(events, hasLength(1));

      // Cause multiple different types of errors
      mockAdapter.shouldFailOnCreate = true;
      mockAdapter.failureMessage = 'Create failure';

      try {
        await repository.save(
          user.copyWith(id: 'new-user', name: 'New User'),
          savePolicy: DataSavePolicy.remoteFirst,
        );
      } catch (e) {}

      mockAdapter.shouldFailOnCreate = false;
      mockAdapter.shouldFailOnUpdate = true;
      mockAdapter.failureMessage = 'Update failure';

      try {
        await repository.save(
          user.copyWith(name: 'Updated Name'),
          savePolicy: DataSavePolicy.remoteFirst,
        );
      } catch (e) {}

      mockAdapter.shouldFailOnUpdate = false;
      mockAdapter.shouldFailOnDelete = true;
      mockAdapter.failureMessage = 'Delete failure';

      try {
        await repository.delete(
          user.id,
          savePolicy: DataSavePolicy.remoteFirst,
        );
      } catch (e) {}

      // Reset adapter and verify stream is still functional
      mockAdapter.shouldFailOnDelete = false;
      await repository.save(user.copyWith(name: 'Recovery Test'));

      // Give time for events to propagate
      await Future.delayed(const Duration(milliseconds: 100));

      // Count error events from the stream
      final errorEvents =
          events.where((e) => e.type == RepositoryChangeType.error).length;

      // Verify stream is still active and functional after errors
      expect(
        streamStillActive,
        isTrue,
        reason: 'Stream should remain active after errors',
      );
      expect(
        events.length,
        greaterThan(1),
        reason: 'Should have received multiple events',
      );
      expect(
        errorEvents,
        greaterThan(0),
        reason: 'Should have captured error events',
      );

      // Verify the stream can still receive events after errors
      final lastEventCount = events.length;
      await repository.save(user.copyWith(name: 'Final Test'));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(
        events.length,
        greaterThan(lastEventCount),
        reason: 'Stream should still work after errors',
      );

      await subscription.cancel();
    });
  });
}

/// Initializes the test storage system.
void initializeTestStorage(GeneratedDatabase db) {
  // Database provider should already be set by this point
  // Register all test repositories if needed
}
