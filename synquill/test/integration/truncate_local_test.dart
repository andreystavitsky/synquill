// ignore_for_file: avoid_relative_lib_imports

import 'package:test/test.dart';
import 'package:synquill/synquill_core.dart';
import 'dart:convert';

import 'package:synquill/src/test_models/index.dart';

import 'package:synquill/synquill.generated.dart';

import '../common/mock_plain_model_api_adapter.dart';

void main() {
  group('TruncateLocal Integration Tests', () {
    late SynquillDatabase database;
    late Logger logger;
    late MockPlainModelApiAdapter mockApiAdapter;
    late _TestPlainModelRepository repository;

    setUp(() async {
      // Set up test database using the generated SynquillDatabase
      database = SynquillDatabase(NativeDatabase.memory());

      // Set up logging
      logger = Logger('TruncateLocalIntegrationTest');
      Logger.root.level = Level.ALL;
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
      repository = _TestPlainModelRepository(database, mockApiAdapter);
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
      'truncateLocal() clears all local data but preserves sync queue',
      () async {
        // Step 1: Create multiple models locally
        final model1 = PlainModel(
          id: 'model-1',
          name: 'Test Model 1',
          value: 100,
        );

        final model2 = PlainModel(
          id: 'model-2',
          name: 'Test Model 2',
          value: 200,
        );

        final model3 = PlainModel(
          id: 'model-3',
          name: 'Test Model 3',
          value: 300,
        );

        // Save models locally
        await repository.save(model1, savePolicy: DataSavePolicy.localFirst);
        await repository.save(model2, savePolicy: DataSavePolicy.localFirst);
        await repository.save(model3, savePolicy: DataSavePolicy.localFirst);

        // Verify models are stored locally
        final allModelsBeforeTruncate = await repository.fetchAllFromLocal();
        expect(allModelsBeforeTruncate.length, equals(3));

        final model1BeforeTruncate = await repository.fetchFromLocal('model-1');
        expect(model1BeforeTruncate, isNotNull);
        expect(model1BeforeTruncate!.name, equals('Test Model 1'));

        // Step 2: Create some sync queue entries by failing API operations
        mockApiAdapter.setNextOperationToFail('API failure for testing');

        final model4 = PlainModel(
          id: 'model-4',
          name: 'Failed Model',
          value: 400,
        );

        await repository.save(model4, savePolicy: DataSavePolicy.localFirst);

        // Wait for sync to fail and create queue entry
        await Future.delayed(const Duration(milliseconds: 100));

        // Verify sync queue has entries
        final syncQueueDao = SyncQueueDao(database);
        final syncQueueBeforeTruncate = await syncQueueDao.getDueTasks();
        expect(syncQueueBeforeTruncate.length, greaterThan(0));

        // Step 3: Call truncateLocal()
        await repository.truncateLocal();

        // Step 4: Verify local data is cleared
        final allModelsAfterTruncate = await repository.fetchAllFromLocal();
        expect(allModelsAfterTruncate.length, equals(0));

        final model1AfterTruncate = await repository.fetchFromLocal('model-1');
        expect(model1AfterTruncate, isNull);

        final model2AfterTruncate = await repository.fetchFromLocal('model-2');
        expect(model2AfterTruncate, isNull);

        final model3AfterTruncate = await repository.fetchFromLocal('model-3');
        expect(model3AfterTruncate, isNull);

        final model4AfterTruncate = await repository.fetchFromLocal('model-4');
        expect(model4AfterTruncate, isNull);

        // Step 5: Verify sync queue is preserved
        final syncQueueAfterTruncate = await syncQueueDao.getDueTasks();
        expect(
          syncQueueAfterTruncate.length,
          equals(syncQueueBeforeTruncate.length),
        );

        // Verify the specific sync queue entry for model-4 is still there
        final model4SyncEntries =
            syncQueueAfterTruncate
                .where((task) => task['model_id'] == 'model-4')
                .toList();
        expect(model4SyncEntries.length, equals(1));
        expect(model4SyncEntries.first['op'], equals('create'));
      },
    );

    test('truncateLocal() emits correct repository change event', () async {
      // Step 1: Set up a model
      final model = PlainModel(
        id: 'test-model',
        name: 'Test Model',
        value: 123,
      );

      await repository.save(model, savePolicy: DataSavePolicy.localFirst);

      // Verify model exists
      final savedModel = await repository.fetchFromLocal('test-model');
      expect(savedModel, isNotNull);

      // Step 2: Listen to repository changes
      RepositoryChange<PlainModel>? changeEvent;
      final subscription = repository.changes.listen((change) {
        changeEvent = change;
      });

      // Step 3: Call truncateLocal()
      await repository.truncateLocal();

      // Wait for event propagation
      await Future.delayed(const Duration(milliseconds: 50));

      // Step 4: Verify change event
      expect(changeEvent, isNotNull);
      expect(changeEvent!.type, equals(RepositoryChangeType.deleted));
      expect(changeEvent!.id, equals('*')); // '*' indicates all items deleted
      expect(changeEvent!.item, isNull);
      expect(changeEvent!.error, isNull);

      await subscription.cancel();
    });

    test('truncateLocal() handles empty repository gracefully', () async {
      // Step 1: Verify repository is empty
      final allModels = await repository.fetchAllFromLocal();
      expect(allModels.length, equals(0));

      // Step 2: Call truncateLocal() on empty repository
      expect(() => repository.truncateLocal(), returnsNormally);

      await repository.truncateLocal();

      // Step 3: Verify repository is still empty
      final allModelsAfter = await repository.fetchAllFromLocal();
      expect(allModelsAfter.length, equals(0));
    });

    test('truncateLocal() does not affect sync queue entries for different '
        'model types', () async {
      // This test simulates having sync queue entries for different model types
      // and verifies that truncateLocal() only affects the specific model type

      // Step 1: Create a model and save it
      final model = PlainModel(
        id: 'test-model',
        name: 'Test Model',
        value: 100,
      );

      await repository.save(model, savePolicy: DataSavePolicy.localFirst);

      // Step 2: Manually create sync queue entries for different model types
      final syncQueueDao = SyncQueueDao(database);

      // Add a fake sync entry for a different model type
      await syncQueueDao.insertItem(
        modelId: 'different-model-1',
        modelType: 'DifferentModel', // Different model type
        payload: json.encode({'id': 'different-model-1', 'name': 'Different'}),
        operation: 'create',
        idempotencyKey: 'different-key-1',
      );

      // Add another sync entry for PlainModel
      mockApiAdapter.setNextOperationToFail('API failure');
      final failingModel = PlainModel(
        id: 'failing-model',
        name: 'Failing Model',
        value: 999,
      );
      await repository.save(
        failingModel,
        savePolicy: DataSavePolicy.localFirst,
      );

      await Future.delayed(const Duration(milliseconds: 100));

      // Step 3: Verify sync queue has entries for both model types
      final allSyncTasks = await syncQueueDao.getDueTasks();
      expect(allSyncTasks.length, equals(2));

      final plainModelTasks =
          allSyncTasks
              .where((task) => task['model_type'] == 'PlainModel')
              .toList();
      expect(plainModelTasks.length, equals(1));

      final differentModelTasks =
          allSyncTasks
              .where((task) => task['model_type'] == 'DifferentModel')
              .toList();
      expect(differentModelTasks.length, equals(1));

      // Step 4: Call truncateLocal() for PlainModel repository
      await repository.truncateLocal();

      // Step 5: Verify local PlainModel data is cleared
      final allModels = await repository.fetchAllFromLocal();
      expect(allModels.length, equals(0));

      // Step 6: Verify sync queue still has all entries
      // (truncateLocal should not affect sync queue at all)
      final syncTasksAfterTruncate = await syncQueueDao.getDueTasks();
      expect(syncTasksAfterTruncate.length, equals(2));

      // Both PlainModel and DifferentModel sync entries should still exist
      final plainModelTasksAfter =
          syncTasksAfterTruncate
              .where((task) => task['model_type'] == 'PlainModel')
              .toList();
      expect(plainModelTasksAfter.length, equals(1));

      final differentModelTasksAfter =
          syncTasksAfterTruncate
              .where((task) => task['model_type'] == 'DifferentModel')
              .toList();
      expect(differentModelTasksAfter.length, equals(1));
    });

    test('truncateLocal() allows data refresh workflow', () async {
      // This test verifies the intended use case: clearing local data
      // and refreshing from remote. All the models that present in the
      // sync_queue with operation == create or operation == update
      // should be recreated in the local storage from the sync_queue metadata.

      // Clear any remote data from previous tests
      mockApiAdapter.clearRemote();

      // Set API to fail initially to prevent background sync from adding
      // old data
      mockApiAdapter.setNextOperationToFail('Initial API failure');

      // Step 1: Set up some initial local data
      final oldModel1 = PlainModel(
        id: 'model-1',
        name: 'Old Model 1',
        value: 100,
      );

      final oldModel2 = PlainModel(
        id: 'model-2',
        name: 'Old Model 2',
        value: 200,
      );

      await repository.save(oldModel1, savePolicy: DataSavePolicy.localFirst);
      await repository.save(oldModel2, savePolicy: DataSavePolicy.localFirst);

      // Wait for failed sync attempts to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify old data exists locally
      final oldData = await repository.fetchAllFromLocal();
      expect(oldData.length, equals(2));

      // Step 2: Set up fresh data in remote API
      final freshModel1 = PlainModel(
        id: 'model-4',
        name: 'Fresh Model 4',
        value: 150,
      );

      final freshModel3 = PlainModel(
        id: 'model-3',
        name: 'Fresh Model 3', // New model
        value: 300,
      );

      // Note: model-2 is not in fresh data (deleted remotely)

      // Clear remote and add only fresh data
      mockApiAdapter.clearRemote();
      mockApiAdapter.addRemoteModel(freshModel1);
      mockApiAdapter.addRemoteModel(freshModel3);

      // Step 3: Use truncateLocal()
      // remoteFirst pattern to refresh
      await repository.truncateLocal();

      final truncatedData = await repository.findAll(
        loadPolicy: DataLoadPolicy.localOnly,
      );

      expect(truncatedData.length, equals(0));

      // Step 4: Load fresh data from remote
      final freshData = await repository.findAll(
        loadPolicy: DataLoadPolicy.remoteFirst,
      );

      // Step 5: Verify fresh data is loaded correctly
      // should contain 'model-1', because we must recreate it in the local
      // storage
      // and 'model-3' because it is new
      // 'model-2' should not be present because it was deleted remotely
      expect(freshData.length, equals(2));

      // Find specific models
      final model4Fresh = freshData.firstWhere((m) => m.id == 'model-4');
      expect(model4Fresh.name, equals('Fresh Model 4'));
      expect(model4Fresh.value, equals(150));

      final model3Fresh = freshData.firstWhere((m) => m.id == 'model-3');
      expect(model3Fresh.name, equals('Fresh Model 3'));
      expect(model3Fresh.value, equals(300));

      // model-2 should not exist anymore
      final model2Fresh = freshData.where((m) => m.id == 'model-2').toList();
      expect(model2Fresh.length, equals(0));

      // Step 6: Verify local storage has been updated with fresh data
      final localDataAfterRefresh = await repository.fetchAllFromLocal();
      expect(localDataAfterRefresh.length, equals(3));

      final localModel1 = await repository.fetchFromLocal('model-1');
      expect(localModel1, isNotNull);
      expect(localModel1!.name, equals('Old Model 1')); // Recreated
      expect(localModel1.value, equals(100));
    });
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
