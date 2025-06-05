// ignore_for_file: avoid_relative_lib_imports

import 'package:test/test.dart';
import 'package:synquill/synquill_core.dart';
import 'dart:convert';

import 'package:synquill/src/test_models/index.dart';

import 'package:synquill/synquill.generated.dart';

import '../common/mock_plain_model_api_adapter.dart';

void main() {
  group('Sync Queue Integration Tests', () {
    late SynquillDatabase database;
    late Logger logger;
    late MockPlainModelApiAdapter mockApiAdapter;
    late _TestPlainModelRepository repository;

    setUp(() async {
      // Set up test database using the generated SynquillDatabase
      database = SynquillDatabase(NativeDatabase.memory());

      // Set up logging
      logger = Logger('SyncQueueIntegrationTest');
      Logger.root.level = Level.ALL;
      Logger.root.onRecord.listen((record) {
        // Uncomment for debugging:
        // print('[${record.level.name}] ${record.loggerName}: '
        //     '${record.message}');
      });

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

      // Get repository with mock adapter by manually overriding the API adapter
      // Since generated repository uses a default adapter, we need to manually
      // create a custom repository for testing that uses our mock adapter
      repository = _TestPlainModelRepository(database, mockApiAdapter);

      // Register the custom repository factory with the global system
      // so RetryExecutor can find it
      SynquillRepositoryProvider.register<PlainModel>(
        (db) => _TestPlainModelRepository(db, mockApiAdapter),
      );
    });

    tearDown(() async {
      await SynquillStorage.reset();
      SynquillRepositoryProvider.reset();
    });

    test(
      'Scenario 1: Create model with API failure, then delete with remoteFirst',
      () async {
        // Set up API to fail on create
        mockApiAdapter.setNextOperationToFail('API create failure');

        // Create a model with localFirst policy -
        // API will fail but save should succeed
        final model = PlainModel(
          id: 'test-model-1',
          name: 'Test Model',
          value: 42,
        );

        // localFirst should succeed even when API fails (fire-and-forget)
        final savedModel = await repository.save(
          model,
          savePolicy: DataSavePolicy.localFirst,
        );

        expect(savedModel.id, equals('test-model-1'));
        expect(savedModel.name, equals('Test Model'));
        expect(savedModel.value, equals(42));

        // Wait a bit to ensure sync queue processing completes
        await Future.delayed(const Duration(milliseconds: 100));

        // Verification 1: Check that sync queue has CREATE entry
        final syncQueueDao = SyncQueueDao(database);
        final pendingTasks = await syncQueueDao.getDueTasks();

        expect(pendingTasks.length, 1);
        expect(pendingTasks.first['model_type'], 'PlainModel');
        expect(pendingTasks.first['model_id'], 'test-model-1');
        expect(pendingTasks.first['op'], 'create');

        // Verification 2: Delete the model with remoteFirst policy
        // This should remove the CREATE sync queue entry
        await repository.delete(
          'test-model-1',
          savePolicy: DataSavePolicy.remoteFirst,
        );

        // Check that sync queue CREATE entry is removed
        final pendingTasksAfterDelete = await syncQueueDao.getDueTasks();

        // Should be empty since delete with remoteFirst should handle
        // smart delete
        expect(pendingTasksAfterDelete.length, 0);
      },
    );

    test('Scenario 2: Create model with API failure, then update - '
        'should merge payloads', () async {
      // Set up API to fail on create
      mockApiAdapter.setNextOperationToFail('API create failure');

      // Create a model with localFirst policy - should succeed locally
      // even though API fails (fire-and-forget behavior)
      final originalModel = PlainModel(
        id: 'test-model-2',
        name: 'Original Name',
        value: 100,
      );

      // localFirst should succeed even when API fails
      final savedModel = await repository.save(
        originalModel,
        savePolicy: DataSavePolicy.localFirst,
      );

      expect(savedModel.id, equals('test-model-2'));
      expect(savedModel.name, equals('Original Name'));
      expect(savedModel.value, equals(100));

      // Wait a bit to ensure sync queue processing completes
      await Future.delayed(const Duration(milliseconds: 100));

      // Check that sync queue has CREATE entry
      final syncQueueDao = SyncQueueDao(database);
      final pendingTasksAfterCreate = await syncQueueDao.getDueTasks();

      expect(pendingTasksAfterCreate.length, 1);
      expect(pendingTasksAfterCreate.first['op'], 'create');

      // Parse original payload
      final originalPayload = json.decode(
        pendingTasksAfterCreate.first['payload'],
      );
      expect(originalPayload['name'], 'Original Name');
      expect(originalPayload['value'], 100);

      // Set up API to fail on the next operation too (update attempt)
      mockApiAdapter.setNextOperationToFail('API update failure');

      // Update the same model with new data
      final updatedModel = PlainModel(
        id: 'test-model-2',
        name: 'Updated Name',
        value: 200,
      );

      // localFirst should succeed even when API fails
      final updatedSavedModel = await repository.save(
        updatedModel,
        savePolicy: DataSavePolicy.localFirst,
      );

      expect(updatedSavedModel.id, equals('test-model-2'));
      expect(updatedSavedModel.name, equals('Updated Name'));
      expect(updatedSavedModel.value, equals(200));

      // Wait a bit to ensure sync queue processing completes
      await Future.delayed(const Duration(milliseconds: 100));

      // Check that there's still only ONE sync queue entry
      // (CREATE with updated payload)
      final pendingTasksAfterUpdate = await syncQueueDao.getDueTasks();

      expect(
        pendingTasksAfterUpdate.length,
        1,
        reason: 'Should have exactly one sync queue entry after update',
      );
      expect(
        pendingTasksAfterUpdate.first['op'],
        'create',
        reason: 'Should remain as CREATE operation, not UPDATE',
      );

      // Verify that the payload has been updated with new data
      final updatedPayload = json.decode(
        pendingTasksAfterUpdate.first['payload'],
      );
      expect(
        updatedPayload['name'],
        'Updated Name',
        reason: 'Payload should contain updated name',
      );
      expect(
        updatedPayload['value'],
        200,
        reason: 'Payload should contain updated value',
      );
      expect(updatedPayload['id'], 'test-model-2');

      // Verify that the sync queue entry is the same one (updated, not new)
      expect(
        pendingTasksAfterUpdate.first['id'],
        pendingTasksAfterCreate.first['id'],
        reason: 'Should be the same sync queue entry, just updated',
      );
    });

    test(
      'Edge case: Multiple updates should keep updating the same CREATE entry',
      () async {
        // Set up API to always fail
        mockApiAdapter.setNextOperationToFail('API create failure');

        // Create a model with localFirst policy - should succeed locally
        final model1 = PlainModel(
          id: 'test-model-3',
          name: 'Version 1',
          value: 1,
        );

        final savedModel1 = await repository.save(
          model1,
          savePolicy: DataSavePolicy.localFirst,
        );

        expect(savedModel1.id, equals('test-model-3'));
        expect(savedModel1.name, equals('Version 1'));
        expect(savedModel1.value, equals(1));

        await Future.delayed(const Duration(milliseconds: 50));

        // Update 1 - should also succeed locally
        mockApiAdapter.setNextOperationToFail('API update failure 1');
        final model2 = PlainModel(
          id: 'test-model-3',
          name: 'Version 2',
          value: 2,
        );

        final savedModel2 = await repository.save(
          model2,
          savePolicy: DataSavePolicy.localFirst,
        );

        expect(savedModel2.id, equals('test-model-3'));
        expect(savedModel2.name, equals('Version 2'));
        expect(savedModel2.value, equals(2));

        await Future.delayed(const Duration(milliseconds: 50));

        // Update 2 - should also succeed locally
        mockApiAdapter.setNextOperationToFail('API update failure 2');
        final model3 = PlainModel(
          id: 'test-model-3',
          name: 'Version 3',
          value: 3,
        );

        final savedModel3 = await repository.save(
          model3,
          savePolicy: DataSavePolicy.localFirst,
        );

        expect(savedModel3.id, equals('test-model-3'));
        expect(savedModel3.name, equals('Version 3'));
        expect(savedModel3.value, equals(3));

        await Future.delayed(const Duration(milliseconds: 50));

        // Verify that there's still only one CREATE entry with the latest data
        final syncQueueDao = SyncQueueDao(database);
        final pendingTasks = await syncQueueDao.getDueTasks();

        expect(pendingTasks.length, 1);
        expect(pendingTasks.first['op'], 'create');

        final finalPayload = json.decode(pendingTasks.first['payload']);
        expect(finalPayload['name'], 'Version 3');
        expect(finalPayload['value'], 3);
      },
    );

    test(
      'Delete with failed API creates delete sync entry, '
      'then full refresh should not restore model due to pending delete',
      () async {
        // Step 1: Create a model successfully (no API failure)
        final model = PlainModel(
          id: 'test-model-delete-conflict',
          name: 'Model to Delete',
          value: 123,
        );

        // Add the model to remote API data first to simulate it existing
        // remotely
        mockApiAdapter.addRemoteModel(model);

        // Save the model successfully first (this will sync to remote)
        await repository.save(model, savePolicy: DataSavePolicy.localFirst);

        // Verify it's in local storage
        final savedModel = await repository.findOne(
          'test-model-delete-conflict',
        );
        expect(savedModel, isNotNull);
        expect(savedModel!.name, equals('Model to Delete'));

        // Wait for initial sync to complete
        await Future.delayed(const Duration(milliseconds: 100));

        // Step 2: Delete the model with localFirst policy
        // This should succeed locally and queue a delete sync operation
        await repository.delete(
          'test-model-delete-conflict',
          savePolicy: DataSavePolicy.localFirst,
        );

        // Verify model is deleted locally
        final deletedModel = await repository.findOne(
          'test-model-delete-conflict',
        );
        expect(deletedModel, isNull);

        // Wait for sync queue processing
        await Future.delayed(const Duration(milliseconds: 100));

        // Verify that sync queue has a DELETE entry
        final syncQueueDao = SyncQueueDao(database);
        final pendingTasks = await syncQueueDao.getDueTasks();

        expect(pendingTasks.length, 1);
        expect(pendingTasks.first['model_type'], 'PlainModel');
        expect(pendingTasks.first['model_id'], 'test-model-delete-conflict');
        expect(pendingTasks.first['op'], 'delete');

        // Step 3: The model is still in remote API because the delete operation
        // failed or hasn't been retried yet. This simulates a scenario where
        // the delete sync operation failed.

        // Step 4: Trigger a full refresh from cloud (findAll())
        final remoteModels = await repository.fetchAllFromRemote();
        expect(remoteModels.length, 1);
        expect(remoteModels.first.id, 'test-model-delete-conflict');

        // Step 5: Update local cache with remote data
        await repository.updateLocalCache(remoteModels);

        // Step 6: Verify expected behavior
        // The model should NOT appear in local DB because there's a
        // pending delete
        final modelAfterRefresh = await repository.findOne(
          'test-model-delete-conflict',
        );
        expect(
          modelAfterRefresh,
          isNull,
          reason:
              'Model should not be restored to local cache due to '
              'pending delete operation',
        );

        // Verify that the delete entry is still in sync queue
        final pendingTasksAfterRefresh = await syncQueueDao.getDueTasks();
        expect(pendingTasksAfterRefresh.length, 1);
        expect(pendingTasksAfterRefresh.first['op'], 'delete');
        expect(
          pendingTasksAfterRefresh.first['model_id'],
          'test-model-delete-conflict',
        );

        // Verify that the retry time was updated (should be approximately
        // current time) - only if retry_after_timestamp is not null
        final retryTimestamp =
            pendingTasksAfterRefresh.first['retry_after_timestamp'];
        if (retryTimestamp != null) {
          final retryTime = DateTime.parse(retryTimestamp);
          final now = DateTime.now();
          final timeDifference = now.difference(retryTime).abs();
          expect(
            timeDifference.inSeconds < 5,
            isTrue,
            reason:
                'Retry time should be updated to approximately current time',
          );
        }
      },
    );

    test('Control test: Successful operations should not create '
        'sync queue entries', () async {
      // Don't set up API failure - operations should succeed

      final model = PlainModel(
        id: 'test-model-success',
        name: 'Success Model',
        value: 999,
      );

      // Save with localFirst - should succeed and not leave
      // sync queue entries
      await repository.save(model, savePolicy: DataSavePolicy.localFirst);

      // Check that no sync queue entries remain
      final syncQueueDao = SyncQueueDao(database);
      final pendingTasks = await syncQueueDao.getDueTasks();

      expect(
        pendingTasks.length,
        0,
        reason: 'Successful operations should not leave sync queue entries',
      );
    });

    test('Local update pending in sync_queue while full refresh downloads '
        'older remote copy - local update should take precedence', () async {
      // Step 1: Create and sync a model successfully
      final originalModel = PlainModel(
        id: 'test-model-update-conflict',
        name: 'Original Name',
        value: 100,
      );

      // Add to remote and save locally
      mockApiAdapter.addRemoteModel(originalModel);
      await repository.save(
        originalModel,
        savePolicy: DataSavePolicy.localFirst,
      );

      // Wait for sync to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Step 2: Set API to fail for next update operation
      mockApiAdapter.setNextOperationToFail('API update failure');

      // Step 3: Update the model locally with API failure
      final updatedModel = PlainModel(
        id: originalModel.id,
        name: 'Updated Name',
        value: 200,
      );

      await repository.save(
        updatedModel,
        savePolicy: DataSavePolicy.localFirst,
      );

      // Wait a bit to ensure sync queue processing attempts
      await Future.delayed(const Duration(milliseconds: 100));

      // Step 4: Verify update is pending in sync queue due to API failure
      final syncQueueDao = SyncQueueDao(database);
      final pendingTasks = await syncQueueDao.getDueTasks();

      expect(pendingTasks.length, 1);
      expect(pendingTasks.first['op'], 'update');
      expect(pendingTasks.first['model_id'], 'test-model-update-conflict');

      final updatePayload = json.decode(pendingTasks.first['payload']);
      expect(updatePayload['name'], 'Updated Name');
      expect(updatePayload['value'], 200);

      // Step 5: Simulate that remote still has old data (common in eventual
      // consistency scenarios)
      // Keep the original model in remote API
      // (don't update remote with new data)

      // Step 6: Trigger full refresh which would normally overwrite
      // local data
      final remoteModels = await repository.fetchAllFromRemote();
      expect(remoteModels.length, 1);
      expect(remoteModels.first.name, 'Original Name'); // Still old data
      expect(remoteModels.first.value, 100);

      // Step 7: Update local cache with remote data
      await repository.updateLocalCache(remoteModels);

      // Step 8: Verify that local model was NOT overwritten by older
      // remote data
      final localModel = await repository.findOne('test-model-update-conflict');
      expect(localModel, isNotNull);
      expect(
        localModel!.name,
        'Updated Name',
        reason:
            'Local updated data should take precedence over older '
            'remote data when update is pending in sync queue',
      );
      expect(
        localModel.value,
        200,
        reason:
            'Local updated data should take precedence over older '
            'remote data when update is pending in sync queue',
      );

      // Step 9: Verify that the update operation is still in sync queue
      final pendingTasksAfterRefresh = await syncQueueDao.getDueTasks();
      expect(pendingTasksAfterRefresh.length, 1);
      expect(pendingTasksAfterRefresh.first['op'], 'update');
      expect(
        pendingTasksAfterRefresh.first['model_id'],
        'test-model-update-conflict',
      );

      final finalPayload = json.decode(
        pendingTasksAfterRefresh.first['payload'],
      );
      expect(finalPayload['name'], 'Updated Name');
      expect(finalPayload['value'], 200);
    });

    test(
      'TST-FINDALL-01: findAll with remoteFirst should filter sync queue items',
      () async {
        // Step 1: Arrange an in-memory database with three local rows
        final modelA = PlainModel(id: 'model-a', name: 'Model A', value: 100);
        final modelB = PlainModel(id: 'model-b', name: 'Model B', value: 200);
        final modelC = PlainModel(id: 'model-c', name: 'Model C', value: 300);

        // Save all models locally first
        await repository.save(modelA, savePolicy: DataSavePolicy.localFirst);
        await repository.save(modelB, savePolicy: DataSavePolicy.localFirst);
        await repository.save(modelC, savePolicy: DataSavePolicy.localFirst);

        // Wait for sync queue processing
        await Future.delayed(const Duration(milliseconds: 100));

        // Create sync queue entries for B (pending update) and C (pending
        // create)
        final syncQueueDao = SyncQueueDao(database);

        // Clear existing sync queue entries first
        final existingTasks = await syncQueueDao.getDueTasks();
        for (final task in existingTasks) {
          await syncQueueDao.deleteTask(task['id'] as int);
        }

        // Add pending update for model B
        final updatedModelB = PlainModel(
          id: 'model-b',
          name: 'Updated Model B',
          value: 250,
        );
        await syncQueueDao.insertItem(
          modelType: 'PlainModel',
          modelId: 'model-b',
          operation: SyncOperation.update.name,
          payload: json.encode(updatedModelB.toJson()),
          idempotencyKey:
              'model-b-update-'
              '${DateTime.now().millisecondsSinceEpoch}',
        );

        // Add pending create for model C (simulating a local create that
        // hasn't synced)
        await syncQueueDao.insertItem(
          modelType: 'PlainModel',
          modelId: 'model-c',
          operation: SyncOperation.create.name,
          payload: json.encode(modelC.toJson()),
          idempotencyKey:
              'model-c-create-'
              '${DateTime.now().millisecondsSinceEpoch}',
        );

        // Step 2: Stub the ApiAdapter.findAll() to return updated versions
        final modelAPrime = PlainModel(
          id: 'model-a',
          name: 'Updated Model A',
          value: 150,
        );
        final modelBPrime = PlainModel(
          id: 'model-b',
          name: 'Remote Updated Model B',
          value: 260,
        );
        final modelCPrime = PlainModel(
          id: 'model-c',
          name: 'Remote Updated Model C',
          value: 350,
        );

        // Clear remote data and add updated versions
        mockApiAdapter.clearRemote();
        mockApiAdapter.addRemoteModel(modelAPrime);
        mockApiAdapter.addRemoteModel(modelBPrime);
        mockApiAdapter.addRemoteModel(modelCPrime);

        // Track API calls
        mockApiAdapter.clearOperationLog();

        // Step 3: Call repository.findAll(loadPolicy: remoteFirst)
        final results = await repository.findAll(
          loadPolicy: DataLoadPolicy.remoteFirst,
        );

        // Step 4: Assert API method called exactly once
        final operationLog = mockApiAdapter.getOperationLog();
        final findAllCalls =
            operationLog.where((op) => op['operation'] == 'findAll').toList();
        expect(
          findAllCalls.length,
          equals(1),
          reason: 'API findAll should be called exactly once',
        );

        // Step 5: Assert returned list contains only A' (not B' or C' due to
        // sync queue)
        expect(
          results.length,
          equals(1),
          reason: 'Should return only items without pending sync operations',
        );
        expect(results.first.id, equals('model-a'));
        expect(results.first.name, equals('Updated Model A'));
        expect(results.first.value, equals(150));

        // Step 6: Verify Drift cache state
        // A' should be in the local cache (overwritten)
        final localModelA = await repository.fetchFromLocal('model-a');
        expect(localModelA, isNotNull);
        expect(localModelA!.name, equals('Updated Model A'));
        expect(localModelA.value, equals(150));

        // B and C should remain unchanged in local cache (filtered due to
        // sync queue)
        final localModelB = await repository.fetchFromLocal('model-b');
        expect(localModelB, isNotNull);
        expect(
          localModelB!.name,
          equals('Model B'),
          reason:
              'Model B should not be updated due to pending sync '
              'operation',
        );
        expect(localModelB.value, equals(200));

        final localModelC = await repository.fetchFromLocal('model-c');
        expect(localModelC, isNotNull);
        expect(
          localModelC!.name,
          equals('Model C'),
          reason:
              'Model C should not be updated due to pending sync '
              'operation',
        );
        expect(localModelC.value, equals(300));

        // Step 7: Verify sync queue still contains entries for B and C
        final remainingTasks = await syncQueueDao.getDueTasks();
        expect(
          remainingTasks.length,
          equals(2),
          reason:
              'Sync queue should still contain pending operations for '
              'B and C',
        );
        final taskIds = remainingTasks.map((task) => task['model_id']).toSet();
        expect(taskIds, contains('model-b'));
        expect(taskIds, contains('model-c'));
      },
    );

    test('TST-FINDALL-02: findAll with localThenRemote should schedule '
        'background sync and merge respecting pending ops', () async {
      // Step 1: Arrange local DB with rows A, B, C
      final modelA = PlainModel(id: 'model-a', name: 'Model A', value: 100);
      final modelB = PlainModel(id: 'model-b', name: 'Model B', value: 200);
      final modelC = PlainModel(id: 'model-c', name: 'Model C', value: 300);

      // Save all models locally first
      await repository.save(modelA, savePolicy: DataSavePolicy.localFirst);
      await repository.save(modelB, savePolicy: DataSavePolicy.localFirst);
      await repository.save(modelC, savePolicy: DataSavePolicy.localFirst);

      // Step 2: Create a pending operation for B by updating it
      // Set API to fail to ensure sync queue entry is created
      mockApiAdapter.setNextOperationToFail('API update failure for B');

      final updatedModelB = PlainModel(
        id: 'model-b',
        name: 'Updated Model B',
        value: 200,
      );
      await repository.save(
        updatedModelB,
        savePolicy: DataSavePolicy.localFirst,
      );

      // Wait for sync queue processing to fail and create pending entry
      await Future.delayed(const Duration(milliseconds: 100));

      // Step 3: Set up API to return [A', B', D] after async delay
      mockApiAdapter.clearRemote();
      mockApiAdapter.addRemoteModel(
        PlainModel(id: 'model-a', name: 'Updated Model A', value: 150),
      );
      mockApiAdapter.addRemoteModel(
        PlainModel(id: 'model-b', name: 'Remote Model B', value: 250),
      );
      mockApiAdapter.addRemoteModel(
        PlainModel(id: 'model-d', name: 'Model D', value: 400),
      );

      // Step 4: Set up stream listening to watch for changes
      final streamEmissions = <List<PlainModel>>[];
      final streamSubscription = repository.watchAll().listen((models) {
        streamEmissions.add(List.from(models));
      });

      // Wait for initial stream emission
      await Future.delayed(const Duration(milliseconds: 10));
      expect(
        streamEmissions.length,
        equals(1),
        reason: 'Should have initial emission from watchAll()',
      );

      // Step 5: Call findAll with localThenRemote and capture immediate
      // return
      final immediateResults = await repository.findAll(
        loadPolicy: DataLoadPolicy.localThenRemote,
      );

      // Step 6: Verify immediate return contains local snapshot [A, B, C]
      expect(
        immediateResults.length,
        equals(3),
        reason: 'Should immediately return all local models',
      );

      final returnedIds = immediateResults.map((m) => m.id).toSet();
      expect(returnedIds, contains('model-a'));
      expect(returnedIds, contains('model-b'));
      expect(returnedIds, contains('model-c'));

      // Verify returned B has local pending version
      final returnedB = immediateResults.firstWhere((m) => m.id == 'model-b');
      expect(
        returnedB.name,
        equals('Updated Model B'),
        reason: 'Should return local pending version of B',
      );

      // Step 7: Verify a background task was scheduled
      // We can check this by verifying that after some processing time,
      // the remote data gets integrated
      await Future.delayed(const Duration(milliseconds: 100));

      // Step 8: Verify API was called for background sync
      final operationLog = mockApiAdapter.getOperationLog();
      final findAllCalls =
          operationLog.where((op) => op['operation'] == 'findAll').toList();
      expect(
        findAllCalls.length,
        equals(1),
        reason: 'API findAll should be called once for background sync',
      );

      // Step 9: Wait for stream update indicating merge completion
      await Future.delayed(const Duration(milliseconds: 200));
      expect(
        streamEmissions.length,
        greaterThan(1),
        reason: 'Should have additional emission after background sync',
      );

      // Step 10: Verify final local state after merge
      // Should contain A', B (local pending), C, D
      final finalLocalModels = await repository.findAll(
        loadPolicy: DataLoadPolicy.localOnly,
      );

      expect(
        finalLocalModels.length,
        equals(4),
        reason: 'Should have A\', B (pending), C, D after merge',
      );

      final finalIds = finalLocalModels.map((m) => m.id).toSet();
      expect(
        finalIds,
        containsAll(['model-a', 'model-b', 'model-c', 'model-d']),
      );

      // Verify A' was merged from remote
      final finalA = finalLocalModels.firstWhere((m) => m.id == 'model-a');
      expect(finalA.name, equals('Updated Model A'));
      expect(finalA.value, equals(150));

      // Verify B retains local pending version (not remote B')
      final finalB = finalLocalModels.firstWhere((m) => m.id == 'model-b');
      expect(
        finalB.name,
        equals('Updated Model B'),
        reason: 'B should retain local pending version',
      );
      expect(finalB.value, equals(200));

      // Verify C remains unchanged
      final finalC = finalLocalModels.firstWhere((m) => m.id == 'model-c');
      expect(finalC.name, equals('Model C'));
      expect(finalC.value, equals(300));

      // Verify D was added from remote
      final finalD = finalLocalModels.firstWhere((m) => m.id == 'model-d');
      expect(finalD.name, equals('Model D'));
      expect(finalD.value, equals(400));

      // Step 11: Verify sync queue still contains pending operation for B
      // only
      final syncQueueDao = SyncQueueDao(database);
      final remainingTasks = await syncQueueDao.getDueTasks();
      expect(
        remainingTasks.length,
        equals(1),
        reason: 'Should have only one pending task for B',
      );
      expect(remainingTasks.first['model_id'], equals('model-b'));

      await streamSubscription.cancel();
    });

    test('Update fallback to create when API returns 404', () async {
      // Step 1: Create a model locally but don't add it to remote API
      // This simulates a scenario where local model exists but remote doesn't
      final model = PlainModel(
        id: 'test-model-fallback',
        name: 'Fallback Test Model',
        value: 100,
      );

      // Save locally first without adding to remote
      await repository.save(model, savePolicy: DataSavePolicy.localFirst);

      // Wait for initial sync attempt to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Step 2: Configure API adapter to return 404 for update operations
      // but allow create operations to succeed
      mockApiAdapter.setUpdateToReturn404();

      // Step 3: Update the model locally
      final updatedModel = PlainModel(
        id: 'test-model-fallback',
        name: 'Updated Fallback Model',
        value: 200,
      );

      await repository.save(
        updatedModel,
        savePolicy: DataSavePolicy.localFirst,
      );

      // Step 4: Manually trigger sync processing to ensure tasks are processed
      final retryExecutor = SynquillStorage.retryExecutor;
      await retryExecutor.processDueTasksNow();

      // Wait for sync processing to complete
      await Future.delayed(const Duration(milliseconds: 200));

      // Step 5: Verify that the sync operation eventually succeeded
      // by checking that there are no pending sync queue entries
      final syncQueueDao = SyncQueueDao(database);
      final pendingTasks = await syncQueueDao.getDueTasks();

      expect(
        pendingTasks.length,
        0,
        reason:
            'Fallback from update to create should have succeeded, '
            'leaving no pending sync tasks',
      );

      // Step 5: Verify that the model was created in the remote API
      final remoteModel = await mockApiAdapter.findOne('test-model-fallback');
      expect(remoteModel, isNotNull);
      expect(remoteModel!.name, 'Updated Fallback Model');
      expect(remoteModel.value, 200);

      // Step 6: Verify that the create operation was logged
      final operationLog = mockApiAdapter.getOperationLog();
      final updateCalls =
          operationLog.where((op) => op['operation'] == 'updateOne').toList();
      final createCalls =
          operationLog.where((op) => op['operation'] == 'createOne').toList();

      expect(
        updateCalls.length,
        greaterThan(0),
        reason: 'Should have attempted update operation first',
      );
      expect(
        createCalls.length,
        greaterThan(0),
        reason: 'Should have fallen back to create operation',
      );
    });

    test(
      'Update fallback fails when both update and create return 404',
      () async {
        // Step 1: Create a model locally
        final model = PlainModel(
          id: 'test-model-double-404',
          name: 'Double 404 Test Model',
          value: 100,
        );

        await repository.save(model, savePolicy: DataSavePolicy.localFirst);

        // Wait for initial sync
        await Future.delayed(const Duration(milliseconds: 100));

        // Step 2: Configure API to return 404 for both update AND create
        // operations
        mockApiAdapter.setBothUpdateAndCreateToReturn404();

        // Step 3: Update the model locally
        final updatedModel = PlainModel(
          id: 'test-model-double-404',
          name: 'Updated Double 404 Model',
          value: 200,
        );

        await repository.save(
          updatedModel,
          savePolicy: DataSavePolicy.localFirst,
        );

        // Step 4: Manually trigger sync processing
        // to ensure tasks are processed
        final retryExecutor = SynquillStorage.retryExecutor;
        await retryExecutor.processDueTasksNow();

        // Wait for sync processing attempts
        await Future.delayed(const Duration(milliseconds: 300));

        // Step 5: Verify that the sync operation failed and is still pending
        final syncQueueDao = SyncQueueDao(database);
        final pendingTasks = await syncQueueDao.getDueTasks();

        expect(
          pendingTasks.length,
          1,
          reason:
              'When both update and create fail with 404, '
              'task should remain in sync queue for retry',
        );

        final task = pendingTasks.first;
        expect(task['op'], 'update');
        expect(task['model_id'], 'test-model-double-404');

        // Verify that the error message indicates both operations failed
        final lastError = task['last_error'] as String?;
        expect(
          lastError,
          isNotNull,
          reason: 'Should have error message indicating fallback failure',
        );
        expect(
          lastError!.toLowerCase(),
          contains('fallback failed'),
          reason: 'Error message should indicate fallback failure',
        );
        expect(
          lastError.toLowerCase(),
          contains('404'),
          reason: 'Error message should mention 404 errors',
        );

        // Step 5: Verify that both operations were attempted
        final operationLog = mockApiAdapter.getOperationLog();
        final updateCalls =
            operationLog.where((op) => op['operation'] == 'updateOne').toList();
        final createCalls =
            operationLog.where((op) => op['operation'] == 'createOne').toList();

        expect(
          updateCalls.length,
          greaterThan(0),
          reason: 'Should have attempted update operation',
        );
        expect(
          createCalls.length,
          greaterThan(0),
          reason: 'Should have attempted create operation as fallback',
        );
      },
    );

    test(
      'Fallback success updates sync queue operation type to create',
      () async {
        // Step 1: Create a model but don't sync it to remote
        final model = PlainModel(
          id: 'test-model-operation-change',
          name: 'Operation Change Test',
          value: 100,
        );

        await repository.save(model, savePolicy: DataSavePolicy.localFirst);
        await Future.delayed(const Duration(milliseconds: 100));

        // Step 2: Clear sync queue to start fresh
        final syncQueueDao = SyncQueueDao(database);
        final existingTasks = await syncQueueDao.getDueTasks();
        for (final task in existingTasks) {
          await syncQueueDao.deleteTask(task['id'] as int);
        }

        // Step 3: Configure API to fail update with 404, but allow create
        mockApiAdapter.setUpdateToReturn404();

        // Step 4: Force an update operation by directly adding to sync queue
        final idempotencyKey =
            'test-operation-change-'
            '${DateTime.now().millisecondsSinceEpoch}';
        await syncQueueDao.insertItem(
          modelType: 'PlainModel',
          modelId: 'test-model-operation-change',
          operation: SyncOperation.update.name,
          payload: json.encode(model.toJson()),
          idempotencyKey: idempotencyKey,
        );

        // Step 5: Process the sync queue task manually using the global
        // RetryExecutor that has access to registered repositories
        final retryExecutor = SynquillStorage.retryExecutor;
        await retryExecutor.processDueTasksNow();

        // Wait for processing
        await Future.delayed(const Duration(milliseconds: 200));

        // Step 6: Verify that no sync queue entries remain (operation
        // succeeded)
        final remainingTasks = await syncQueueDao.getDueTasks();
        expect(
          remainingTasks.length,
          0,
          reason: 'Successful fallback should remove task from sync queue',
        );

        // Step 7: Verify that the create operation was called
        final operationLog = mockApiAdapter.getOperationLog();
        final createCalls =
            operationLog.where((op) => op['operation'] == 'createOne').toList();

        expect(
          createCalls.length,
          greaterThan(0),
          reason: 'Should have called create operation as fallback',
        );

        // Step 8: Verify model exists in remote
        final remoteModel = await mockApiAdapter.findOne(
          'test-model-operation-change',
        );
        expect(remoteModel, isNotNull);
        expect(remoteModel!.name, 'Operation Change Test');
      },
    );

    // ...existing code...
  });
}

/// Custom test repository that uses the mock API adapter
class _TestPlainModelRepository extends SynquillRepositoryBase<PlainModel>
    with RepositoryHelpersMixin<PlainModel> {
  final MockPlainModelApiAdapter _mockAdapter;
  late final PlainModelDao _dao;

  /// Creates a new PlainModel repository instance
  ///
  /// [db] The database instance to use for data operations
  _TestPlainModelRepository(super.db, this._mockAdapter) {
    _dao = PlainModelDao(db as SynquillDatabase);
  }

  @override
  ApiAdapterBase<PlainModel> get apiAdapter => _mockAdapter;

  @override
  Future<PlainModel?> fetchFromRemote(
    String id, {
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return await _mockAdapter.findOne(id, queryParams: queryParams);
  }

  @override
  Future<List<PlainModel>> fetchAllFromRemote({
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return await _mockAdapter.findAll(queryParams: queryParams);
  }

  @override
  DatabaseAccessor<GeneratedDatabase> get dao => _dao;
}
