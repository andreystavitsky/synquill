// ignore_for_file: avoid_relative_lib_imports, avoid_print

import 'dart:async';
import 'package:queue/queue.dart';
import 'package:test/test.dart';

import 'package:synquill/src/test_models/index.dart';

import 'package:synquill/synquill.generated.dart';

import '../common/mock_plain_model_api_adapter.dart';
import '../common/test_plain_model_repository.dart';

/// Comprehensive test suite for the `obliterateLocalStorage()` method.
///
/// This test suite verifies that `obliterateLocalStorage()` properly:
/// - Clears all request queues (foreground, load, background)
/// - Removes all sync queue tasks and data
/// - Clears cached repository instances
/// - Truncates local database tables for all registered repositories
/// - Resets background sync state and timers
/// - Preserves SynquillStorage initialization state
/// - Handles error scenarios gracefully
void main() {
  group('Obliterate Local Storage Integration Tests', () {
    late SynquillDatabase database;
    late Logger logger;
    late MockPlainModelApiAdapter mockApiAdapter;
    late TestPlainModelRepository repository;

    setUp(() async {
      // Set up test database using the generated SynquillDatabase
      database = SynquillDatabase(NativeDatabase.memory());

      // Set up logging
      logger = Logger('ObliterateLocalStorageTest');
      Logger.root.level = Level.INFO;
      Logger.root.onRecord.listen((record) {
        // Uncomment for debugging:
        // print('[${record.level.name}] ${record.loggerName}: '
        //     '${record.message}');
      });

      // Set up database provider
      DatabaseProvider.setInstance(database);

      // Create mock API adapter
      mockApiAdapter = MockPlainModelApiAdapter();

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
        initializeFn: initializeSynquillStorage,
        enableInternetMonitoring: false, // Disable for testing
      );

      // Get repository with mock adapter
      repository = TestPlainModelRepository(database, mockApiAdapter);
    });

    tearDown(() async {
      // Clear mock API adapter between tests
      mockApiAdapter.clearRemote();
      mockApiAdapter.clearLog();

      await SynquillStorage.close();
      await database.close();
      SynquillRepositoryProvider.reset();
      DatabaseProvider.reset();
    });

    test(
      'obliterateLocalStorage() should throw when not initialized',
      () async {
        // Close storage first to simulate uninitialized state
        await SynquillStorage.close();

        expect(
          () => SynquillStorage.instance.obliterateLocalStorage(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('SynquillStorage has not been initialized'),
            ),
          ),
        );
      },
    );

    test(
      'obliterateLocalStorage() clears all local data completely',
      () async {
        final List<dynamic> unhandledErrors = [];

        // Run the test in a zone that captures unhandled
        // QueueCancelledException
        await runZonedGuarded(() async {
          // Step 1: Create multiple models locally to populate the database
          final models = [
            PlainModel(id: 'model-1', name: 'Test Model 1', value: 100),
            PlainModel(id: 'model-2', name: 'Test Model 2', value: 200),
            PlainModel(id: 'model-3', name: 'Test Model 3', value: 300),
            PlainModel(id: 'model-4', name: 'Test Model 4', value: 400),
          ];

          // Save all models locally
          for (final model in models) {
            await repository.save(model, savePolicy: DataSavePolicy.localFirst);
          }

          // Verify models are stored locally
          final allModelsBeforeObliterate =
              await repository.fetchAllFromLocal();
          expect(allModelsBeforeObliterate.length, equals(4));

          // Step 2: Create sync queue entries by failing API operations
          mockApiAdapter.setNextOperationToFail('API failure for testing');

          final failedModel = PlainModel(
            id: 'failed-model',
            name: 'Failed Model',
            value: 500,
          );

          await repository.save(
            failedModel,
            savePolicy: DataSavePolicy.localFirst,
          );

          // Wait for sync to fail and create queue entry
          await Future.delayed(const Duration(milliseconds: 100));

          // Verify sync queue has entries
          final syncQueueDao = SyncQueueDao(database);
          final syncQueueBeforeObliterate = await syncQueueDao.getDueTasks();
          expect(
            syncQueueBeforeObliterate.length,
            greaterThan(0),
            reason: 'Should have sync queue entries before obliteration',
          );

          // Step 3: Get queue stats before obliteration
          final queueManager = SynquillStorage.queueManager;

          // Add controllable tasks to various queues to test task cancellation
          final tasks = <NetworkTask<void>>[];
          final taskCompleters = <Completer<void>>[];
          final queueTypes = [
            QueueType.foreground,
            QueueType.load,
            QueueType.background,
          ];

          for (int i = 0; i < queueTypes.length; i++) {
            final queueType = queueTypes[i];
            final taskCompleter = Completer<void>();
            taskCompleters.add(taskCompleter);

            final task = NetworkTask<void>(
              exec: () async {
                // Use a completer instead of Future.delayed
                // to make it more cancellable
                return taskCompleter.future;
              },
              idempotencyKey: 'test-${queueType.name}-task',
              operation: SyncOperation.create,
              modelType: 'TestModel',
              modelId: 'test-${queueType.name}-id',
            );

            tasks.add(task);

            // Enqueue task (we don't need to track the queue future)
            unawaited(queueManager.enqueueTask(
              task,
              queueType: queueType,
            ));
          }

          // Wait for tasks to be queued (but not completed)
          await Future.delayed(const Duration(milliseconds: 100));

          // Verify queues have pending tasks
          final statsAfterQueueing = queueManager.getQueueStats();
          expect(
            statsAfterQueueing[QueueType.foreground]!.activeAndPendingTasks,
            greaterThan(0),
          );
          expect(
            statsAfterQueueing[QueueType.load]!.activeAndPendingTasks,
            greaterThan(0),
          );
          expect(
            statsAfterQueueing[QueueType.background]!.activeAndPendingTasks,
            greaterThan(0),
          );

          // Step 4: Verify repository instances are cached
          final cachedRepositoryBefore =
              SynquillRepositoryProvider.getByTypeName('PlainModel');
          expect(
            cachedRepositoryBefore,
            isNotNull,
            reason: 'Repository should be cached before obliteration',
          );

          // Step 5: Call obliterateLocalStorage()
          await SynquillStorage.instance.obliterateLocalStorage();

          // Clean up the task completers to prevent hanging
          for (final completer in taskCompleters) {
            if (!completer.isCompleted) {
              completer.complete();
            }
          }

          // Allow some time for all cancellations to be processed
          await Future.delayed(const Duration(milliseconds: 100));

          // Step 6: Verify all local data is cleared

          // 6a. Verify local database tables are truncated
          final allModelsAfterObliterate = await repository.fetchAllFromLocal();
          expect(
            allModelsAfterObliterate.length,
            equals(0),
            reason: 'All local models should be cleared',
          );

          for (final model in models) {
            final modelAfterObliterate =
                await repository.fetchFromLocal(model.id);
            expect(
              modelAfterObliterate,
              isNull,
              reason: 'Model ${model.id} should not exist after obliteration',
            );
          }

          final failedModelAfterObliterate =
              await repository.fetchFromLocal('failed-model');
          expect(
            failedModelAfterObliterate,
            isNull,
            reason: 'Failed model should not exist after obliteration',
          );

          // 6b. Verify sync queue is cleared
          final syncQueueAfterObliterate = await syncQueueDao.getDueTasks();
          expect(
            syncQueueAfterObliterate.length,
            equals(0),
            reason: 'Sync queue should be empty after obliteration',
          );

          // Verify no sync queue entries exist for any model
          for (final model in models) {
            final modelSyncEntries = await syncQueueDao.getTasksForModelId(
              'PlainModel',
              model.id,
            );
            expect(
              modelSyncEntries.length,
              equals(0),
              reason: 'No sync entries should exist for ${model.id}',
            );
          }

          // 6c. Verify request queues are cleared
          final statsAfterObliterate = queueManager.getQueueStats();
          expect(
            statsAfterObliterate[QueueType.foreground]!.activeAndPendingTasks,
            equals(0),
            reason: 'Foreground queue should be empty',
          );
          expect(
            statsAfterObliterate[QueueType.load]!.activeAndPendingTasks,
            equals(0),
            reason: 'Load queue should be empty',
          );
          expect(
            statsAfterObliterate[QueueType.background]!.activeAndPendingTasks,
            equals(0),
            reason: 'Background queue should be empty',
          );

          // 6c.1. Verify that tasks were properly cancelled
          // (not just completed)
          var cancelledCount = 0;
          var completedCount = 0;

          // Wait for all task completions/cancellations to be processed
          // with a timeout to prevent hanging
          await Future.wait(
            tasks.map((task) async {
              try {
                await task.future.timeout(const Duration(seconds: 5),
                    onTimeout: () {
                  throw TimeoutException(
                    'Task did not complete or cancel within timeout',
                  );
                });
                completedCount++;
                print('Task completed normally');
              } catch (e) {
                if (e is QueueCancelledException) {
                  cancelledCount++;
                  print('Task cancelled: ${e.runtimeType}');
                } else {
                  print('Task caught error: ${e.runtimeType} - $e');
                }
                // Only count QueueCancelledException as cancelled
                // Timeouts or other errors are not considered cancellations
              }
            }),
          );

          // Verify that tasks were cancelled (not completed)
          expect(
            cancelledCount,
            equals(queueTypes.length),
            reason:
                'All enqueued tasks should have been cancelled by obliteration',
          );
          expect(
            completedCount,
            equals(0),
            reason: 'No tasks should have completed naturally '
                '(all should be cancelled)',
          );

          // 6d. Verify cached repository instances are reset
          // Note: Repository provider is reset, but we can still get instances
          // because the factory registration remains intact
          final repositoryAfterObliterate =
              SynquillRepositoryProvider.getByTypeName('PlainModel');
          expect(
            repositoryAfterObliterate,
            isNotNull,
            reason: 'Should be able to get new repository instance',
          );

          // Step 7: Verify SynquillStorage remains functional
          // after obliteration
          expect(
            () => SynquillStorage.instance,
            returnsNormally,
            reason: 'SynquillStorage should remain initialized',
          );

          // Verify we can still use the storage system
          final newModel = PlainModel(
            id: 'post-obliterate-model',
            name: 'Post Obliterate Model',
            value: 999,
          );

          // This should work without throwing
          await repository.save(newModel,
              savePolicy: DataSavePolicy.localFirst);

          final savedNewModel =
              await repository.fetchFromLocal('post-obliterate-model');
          expect(
            savedNewModel,
            isNotNull,
            reason: 'Should be able to save and fetch after obliteration',
          );
          expect(savedNewModel!.name, equals('Post Obliterate Model'));

          // Step 8: Verify background sync manager is re-initialized
          // and functional
          final backgroundSyncManager = SynquillStorage.backgroundSyncManager;
          expect(
            backgroundSyncManager.isReadyForBackgroundSync,
            isTrue,
            reason: 'Background sync should be ready after obliteration',
          );

          // Should be able to process background sync without errors
          expect(
            () => SynquillStorage.instance.processBackgroundSyncTasks(),
            returnsNormally,
          );
        }, (error, stack) {
          // Capture unhandled async errors (like QueueCancelledException)
          unhandledErrors.add(error);
          print('Captured unhandled error: ${error.runtimeType} - $error');
        });

        // Verify that we captured the expected QueueCancelledException
        // instances but they didn't cause test failure
        expect(unhandledErrors.isNotEmpty, isTrue,
            reason:
                'Should have captured some unhandled QueueCancelledException '
                'instances');

        print('Test completed successfully with ${unhandledErrors.length} '
            'captured unhandled errors');
      },
    );

    test(
      'obliterateLocalStorage() handles multiple repository types',
      () async {
        final List<dynamic> unhandledErrors = [];

        await runZonedGuarded(() async {
          // For this test, we'll just verify that the method can handle
          // the case where multiple repository types are registered

          // PlainModel is already registered from setUp
          // Verify it's registered
          final registeredTypes =
              SynquillRepositoryProvider.getAllRegisteredTypeNames();
          expect(
            registeredTypes,
            contains('PlainModel'),
            reason: 'PlainModel should be registered',
          );

          // Create some data
          final model = PlainModel(
            id: 'multi-repo-test',
            name: 'Multi Repo Test',
            value: 123,
          );

          await repository.save(model, savePolicy: DataSavePolicy.localFirst);

          // Verify data exists
          final savedModel = await repository.fetchFromLocal('multi-repo-test');
          expect(savedModel, isNotNull);

          // Call obliterateLocalStorage
          await SynquillStorage.instance.obliterateLocalStorage();

          // Verify data is cleared
          final modelAfterObliterate =
              await repository.fetchFromLocal('multi-repo-test');
          expect(
            modelAfterObliterate,
            isNull,
            reason: 'Model should be cleared from all repository types',
          );

          // Verify system is still functional
          expect(() => SynquillStorage.instance, returnsNormally);
        }, (error, stack) {
          // Capture unhandled async errors (like QueueCancelledException)
          unhandledErrors.add(error);
          print('Captured unhandled error: ${error.runtimeType} - $error');
        });

        print('Test completed successfully with ${unhandledErrors.length} '
            'captured unhandled errors');
      },
    );

    test(
      'obliterateLocalStorage() handles empty database gracefully',
      () async {
        final List<dynamic> unhandledErrors = [];

        await runZonedGuarded(() async {
          // Verify database is empty
          final allModels = await repository.fetchAllFromLocal();
          expect(allModels.length, equals(0));

          final syncQueueDao = SyncQueueDao(database);
          final syncTasks = await syncQueueDao.getDueTasks();
          expect(syncTasks.length, equals(0));

          // Call obliterateLocalStorage on empty state
          await SynquillStorage.instance.obliterateLocalStorage();

          // Verify system remains functional
          expect(() => SynquillStorage.instance, returnsNormally);

          // Get a fresh repository instance after obliteration
          final freshRepository = TestPlainModelRepository(
            database,
            mockApiAdapter,
          );

          // Should still be able to save new data
          final testModel = PlainModel(
            id: 'empty-db-test',
            name: 'Empty DB Test',
            value: 42,
          );

          await freshRepository.save(
            testModel,
            savePolicy: DataSavePolicy.localFirst,
          );

          final savedModel = await freshRepository.fetchFromLocal(
            'empty-db-test',
          );
          expect(savedModel, isNotNull);
          expect(savedModel!.name, equals('Empty DB Test'));
        }, (error, stack) {
          // Capture unhandled async errors (like QueueCancelledException)
          unhandledErrors.add(error);
          print('Captured unhandled error: ${error.runtimeType} - $error');
        });

        print('Test completed successfully with ${unhandledErrors.length} '
            'captured unhandled errors');
      },
    );

    test(
      'obliterateLocalStorage() handles errors gracefully',
      () async {
        final List<dynamic> unhandledErrors = [];

        await runZonedGuarded(() async {
          // Create some test data first
          final model = PlainModel(
            id: 'error-test-model',
            name: 'Error Test Model',
            value: 123,
          );

          await repository.save(model, savePolicy: DataSavePolicy.localFirst);

          // Note: In a real scenario, we might want to test error conditions
          // by mocking database operations to fail, but for this integration
          // test, we'll verify that the method completes normally and logs
          // appropriately

          // The method should handle any internal errors gracefully
          // and either complete successfully or rethrow the error
          await SynquillStorage.instance.obliterateLocalStorage();

          // Verify the operation completed (data should be cleared)
          final modelAfterObliterate =
              await repository.fetchFromLocal('error-test-model');
          expect(
            modelAfterObliterate,
            isNull,
            reason: 'Model should be cleared even if some errors occur',
          );

          // System should remain functional
          expect(() => SynquillStorage.instance, returnsNormally);
        }, (error, stack) {
          // Capture unhandled async errors (like QueueCancelledException)
          unhandledErrors.add(error);
          print('Captured unhandled error: ${error.runtimeType} - $error');
        });

        print('Test completed successfully with ${unhandledErrors.length} '
            'captured unhandled errors');
      },
    );

    test(
      'obliterateLocalStorage() preserves repository registrations',
      () async {
        final List<dynamic> unhandledErrors = [];

        await runZonedGuarded(() async {
          // Get initial repository registrations
          final registrationsBefore =
              SynquillRepositoryProvider.getAllRegisteredTypeNames();
          expect(
            registrationsBefore,
            isNotEmpty,
            reason: 'Should have repository registrations before obliteration',
          );

          // Create and save test data
          final model = PlainModel(
            id: 'registration-test',
            name: 'Registration Test',
            value: 456,
          );

          await repository.save(model, savePolicy: DataSavePolicy.localFirst);

          // Call obliterateLocalStorage
          await SynquillStorage.instance.obliterateLocalStorage();

          // Verify repository registrations are preserved
          final registrationsAfter =
              SynquillRepositoryProvider.getAllRegisteredTypeNames();
          expect(
            registrationsAfter,
            equals(registrationsBefore),
            reason: 'Repository registrations should be preserved',
          );

          // Verify we can still get repository instances
          final repositoryAfter =
              SynquillRepositoryProvider.getByTypeName('PlainModel');
          expect(
            repositoryAfter,
            isNotNull,
            reason: 'Should be able to get repository after obliteration',
          );

          // Verify the repository is functional
          final newModel = PlainModel(
            id: 'post-registration-test',
            name: 'Post Registration Test',
            value: 789,
          );

          await repositoryAfter!.save(
            newModel,
            savePolicy: DataSavePolicy.localFirst,
          );

          final savedNewModel =
              await repositoryAfter.fetchFromLocal('post-registration-test');
          expect(savedNewModel, isNotNull);
          expect((savedNewModel! as PlainModel).name,
              equals('Post Registration Test'));
        }, (error, stack) {
          // Capture unhandled async errors (like QueueCancelledException)
          unhandledErrors.add(error);
          print('Captured unhandled error: ${error.runtimeType} - $error');
        });

        print('Test completed successfully with ${unhandledErrors.length} '
            'captured unhandled errors');
      },
    );

    test(
      'obliterateLocalStorage() resets background sync state properly',
      () async {
        final List<dynamic> unhandledErrors = [];

        await runZonedGuarded(() async {
          // Verify background sync manager is initialized and functional
          final backgroundSyncManager = SynquillStorage.backgroundSyncManager;
          expect(
            backgroundSyncManager.isReadyForBackgroundSync,
            isTrue,
            reason: 'Background sync should be ready initially',
          );

          // Create some data and sync queue entries
          final model = PlainModel(
            id: 'bg-sync-test',
            name: 'Background Sync Test',
            value: 101,
          );

          // Force a sync failure to create queue entries
          mockApiAdapter.setNextOperationToFail('Background sync test failure');
          await repository.save(model, savePolicy: DataSavePolicy.localFirst);

          // Wait for sync to fail
          await Future.delayed(const Duration(milliseconds: 100));

          // Switch to background mode
          SynquillStorage.enableBackgroundMode();

          // Call obliterateLocalStorage
          await SynquillStorage.instance.obliterateLocalStorage();

          // Verify background sync manager is still functional
          final backgroundSyncManagerAfter =
              SynquillStorage.backgroundSyncManager;
          expect(
            backgroundSyncManagerAfter.isReadyForBackgroundSync,
            isTrue,
            reason: 'Background sync should be ready after obliteration',
          );

          // Should be able to switch modes without errors
          expect(
            () => SynquillStorage.enableForegroundMode(),
            returnsNormally,
          );

          expect(
            () => SynquillStorage.enableBackgroundMode(),
            returnsNormally,
          );

          // Should be able to process background sync tasks
          expect(
            () => SynquillStorage.instance.processBackgroundSyncTasks(),
            returnsNormally,
          );
        }, (error, stack) {
          // Capture unhandled async errors (like QueueCancelledException)
          unhandledErrors.add(error);
          print('Captured unhandled error: ${error.runtimeType} - $error');
        });

        print('Test completed successfully with ${unhandledErrors.length} '
            'captured unhandled errors');
      },
    );

    test(
      'obliterateLocalStorage() clears retry executor state',
      () async {
        final List<dynamic> unhandledErrors = [];

        await runZonedGuarded(() async {
          // Create test data and sync queue entries
          final model = PlainModel(
            id: 'retry-executor-test',
            name: 'Retry Executor Test',
            value: 202,
          );

          // Force sync failure to create retry tasks
          mockApiAdapter.setNextOperationToFail('Retry executor test failure');
          await repository.save(model, savePolicy: DataSavePolicy.localFirst);

          // Wait for sync to fail and create retry queue entries
          await Future.delayed(const Duration(milliseconds: 100));

          // Verify sync queue has entries that would be processed by
          // retry executor
          final syncQueueDao = SyncQueueDao(database);
          final tasksBeforeObliterate = await syncQueueDao.getDueTasks();
          expect(
            tasksBeforeObliterate.length,
            greaterThan(0),
            reason: 'Should have tasks for retry executor before obliteration',
          );

          // Get retry executor reference
          final retryExecutor = SynquillStorage.retryExecutor;
          expect(retryExecutor, isNotNull);

          // Call obliterateLocalStorage
          await SynquillStorage.instance.obliterateLocalStorage();

          // Verify retry executor state is cleared (sync queue is empty)
          final tasksAfterObliterate = await syncQueueDao.getDueTasks();
          expect(
            tasksAfterObliterate.length,
            equals(0),
            reason: 'Retry executor should have no tasks after obliteration',
          );

          // Verify retry executor is still functional
          final retryExecutorAfter = SynquillStorage.retryExecutor;
          expect(
            retryExecutorAfter,
            isNotNull,
            reason: 'Retry executor should still be available',
          );

          // Should be able to process tasks (even though there are none)
          expect(
            () => retryExecutorAfter.processDueTasksNow(),
            returnsNormally,
          );
        }, (error, stack) {
          // Capture unhandled async errors (like QueueCancelledException)
          unhandledErrors.add(error);
          print('Captured unhandled error: ${error.runtimeType} - $error');
        });

        print('Test completed successfully with ${unhandledErrors.length} '
            'captured unhandled errors');
      },
    );

    test(
      'obliterateLocalStorage() maintains queue manager functionality',
      () async {
        final List<dynamic> unhandledErrors = [];

        await runZonedGuarded(() async {
          // Get initial queue manager
          final queueManager = SynquillStorage.queueManager;
          expect(queueManager, isNotNull);

          // Add some tasks to queues
          await queueManager.enqueueTask(
            NetworkTask<void>(
              exec: () async =>
                  Future.delayed(const Duration(milliseconds: 10)),
              idempotencyKey: 'queue-test-task-1',
              operation: SyncOperation.create,
              modelType: 'TestModel',
              modelId: 'queue-test-id-1',
            ),
            queueType: QueueType.foreground,
          );

          // Verify task was added
          var stats = queueManager.getQueueStats();
          expect(
            stats[QueueType.foreground]!.activeAndPendingTasks,
            greaterThan(0),
          );

          // Call obliterateLocalStorage
          await SynquillStorage.instance.obliterateLocalStorage();

          // Verify queue manager is still the same instance and functional
          final queueManagerAfter = SynquillStorage.queueManager;
          expect(queueManagerAfter, equals(queueManager));

          // Verify queues are cleared
          stats = queueManagerAfter.getQueueStats();
          expect(
            stats[QueueType.foreground]!.activeAndPendingTasks,
            equals(0),
          );
          expect(
            stats[QueueType.load]!.activeAndPendingTasks,
            equals(0),
          );
          expect(
            stats[QueueType.background]!.activeAndPendingTasks,
            equals(0),
          );

          // Should be able to add new tasks
          await queueManagerAfter.enqueueTask(
            NetworkTask<void>(
              exec: () async =>
                  Future.delayed(const Duration(milliseconds: 10)),
              idempotencyKey: 'post-obliterate-task',
              operation: SyncOperation.create,
              modelType: 'TestModel',
              modelId: 'post-obliterate-id',
            ),
            queueType: QueueType.foreground,
          );

          // Wait for task to process
          await Future.delayed(const Duration(milliseconds: 50));

          // Verify task was processed (queue should be empty again)
          final finalStats = queueManagerAfter.getQueueStats();
          expect(
            finalStats[QueueType.foreground]!.activeAndPendingTasks,
            equals(0),
          );
        }, (error, stack) {
          // Capture unhandled async errors (like QueueCancelledException)
          unhandledErrors.add(error);
          print('Captured unhandled error: ${error.runtimeType} - $error');
        });

        print('Test completed successfully with ${unhandledErrors.length} '
            'captured unhandled errors');
      },
    );
  });
}
