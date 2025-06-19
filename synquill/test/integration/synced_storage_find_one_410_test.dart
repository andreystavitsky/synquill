// ignore_for_file: avoid_relative_lib_imports, avoid_print

import 'package:test/test.dart';
import 'package:synquill/synquill.generated.dart';
import 'package:synquill/src/test_models/index.dart';

import '../common/mock_plain_model_api_adapter.dart';
import '../common/test_plain_model_repository.dart';

/// Integration test for findOne behavior when API returns 410 Gone error
void main() {
  group('SyncedStorage findOne API 410 Gone Integration Tests', () {
    late SynquillDatabase database;
    late MockPlainModelApiAdapter mockApiAdapter;
    late TestPlainModelRepository repository;
    late Logger logger;

    setUp(() async {
      // Set up test database using the generated SynquillDatabase
      database = SynquillDatabase(NativeDatabase.memory());

      // Set up logging
      logger = Logger('FindOne410Test');
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
          defaultLoadPolicy: DataLoadPolicy.localThenRemote,
          foregroundQueueConcurrency: 1,
          backgroundQueueConcurrency: 1,
        ),
        logger: logger,
        initializeFn: (db) {
          // Register the TestPlainModel repository factory
          // with our mock adapter
          SynquillRepositoryProvider.register<PlainModel>(
            (database) => TestPlainModelRepository(database, mockApiAdapter),
          );
        },
        enableInternetMonitoring: false, // Disable for testing
      );

      // Get repository instance
      repository = SynquillRepositoryProvider.getFrom<PlainModel>(database)
          as TestPlainModelRepository;
    });

    tearDown(() async {
      await SynquillStorage.close();
      mockApiAdapter.clearRemoteData();
      mockApiAdapter.clearOperationLog();
      mockApiAdapter.reset410Settings();
    });

    test(
      'findOne with remoteFirst policy should delete local model '
      'when API returns 410',
      () async {
        // Create test model
        final testModel = PlainModel(
          id: 'test-model-410',
          name: 'Test Model for 410',
          value: 42,
        );

        // First save the model locally
        await repository.save(
          testModel,
          savePolicy: DataSavePolicy.localFirst,
        );

        // Verify model exists locally
        final foundLocalModel = await repository.findOne(
          testModel.id,
          loadPolicy: DataLoadPolicy.localOnly,
        );
        expect(foundLocalModel, isNotNull);
        expect(foundLocalModel!.name, equals('Test Model for 410'));

        // Configure mock adapter to return 410 for this model
        mockApiAdapter.setFindOneToReturn410ForModel(testModel.id);

        // Now try to find the model with remoteFirst policy
        // This should trigger the API call, get 410, and delete the local model
        final foundModelAfter410 = await repository.findOne(
          testModel.id,
          loadPolicy: DataLoadPolicy.remoteFirst,
        );

        // Model should be null (deleted locally due to 410)
        expect(foundModelAfter410, isNull);

        // Verify the model was actually deleted from local database
        final localModelAfterDeletion = await repository.findOne(
          testModel.id,
          loadPolicy: DataLoadPolicy.localOnly,
        );
        expect(localModelAfterDeletion, isNull);

        // Verify API was called
        final operationLog = mockApiAdapter.getOperationLog();
        expect(
          operationLog,
          contains(
            predicate<Map<String, dynamic>>(
              (log) =>
                  log['operation'] == 'findOne' && log['id'] == testModel.id,
            ),
          ),
        );
      },
    );

    test(
      'findOne with remoteFirst policy should return null when API returns 410',
      () async {
        // Create test model
        final testModel = PlainModel(
          id: 'test-model-410-remote-only',
          name: 'Test Model for 410 Remote Only',
          value: 123,
        );

        // Save model locally first
        await repository.save(
          testModel,
          savePolicy: DataSavePolicy.localFirst,
        );

        // Configure mock adapter to return 410 for this model
        mockApiAdapter.setFindOneToReturn410ForModel(testModel.id);

        // Try to find the model with remoteFirst policy
        final foundModel = await repository.findOne(
          testModel.id,
          loadPolicy: DataLoadPolicy.remoteFirst,
        );

        // Should return null due to 410
        expect(foundModel, isNull);

        // Local model should still be deleted due to 410 handling
        final localModel = await repository.findOne(
          testModel.id,
          loadPolicy: DataLoadPolicy.localOnly,
        );
        expect(localModel, isNull);

        // Verify API was called
        final operationLog = mockApiAdapter.getOperationLog();
        expect(
          operationLog,
          contains(
            predicate<Map<String, dynamic>>(
              (log) =>
                  log['operation'] == 'findOne' && log['id'] == testModel.id,
            ),
          ),
        );
      },
    );

    test(
      'findOne with localThenRemote policy should trigger background '
      '410 handling when local model exists',
      () async {
        // Create test model
        final testModel = PlainModel(
          id: 'test-model-410-local-first',
          name: 'Test Model for 410 Local First',
          value: 456,
        );

        // Save model locally first so localThenRemote has something to return
        await repository.save(
          testModel,
          savePolicy: DataSavePolicy.localFirst,
        );

        // Verify model exists locally
        final localModel = await repository.findOne(
          testModel.id,
          loadPolicy: DataLoadPolicy.localOnly,
        );
        expect(localModel, isNotNull);
        expect(localModel!.name, equals('Test Model for 410 Local First'));

        // Configure mock adapter to return 410 for this model
        // in background refresh
        mockApiAdapter.setFindOneToReturn410ForModel(testModel.id);

        // Clear operation log to track only the upcoming operations
        mockApiAdapter.clearOperationLog();

        // Call findOne with localThenRemote policy
        // This should return local data immediately
        // and trigger background refresh
        final foundModel = await repository.findOne(
          testModel.id,
          loadPolicy: DataLoadPolicy.localThenRemote,
        );

        // Should return local model immediately (before background refresh)
        expect(foundModel, isNotNull);
        expect(foundModel!.name, equals('Test Model for 410 Local First'));

        // Wait for background refresh to complete
        await Future.delayed(const Duration(milliseconds: 500));

        // Verify the 410 background refresh triggered local deletion
        final modelAfterRefresh = await repository.findOne(
          testModel.id,
          loadPolicy: DataLoadPolicy.localOnly,
        );
        expect(modelAfterRefresh, isNull,
            reason: 'Model should be deleted locally after 410 response '
                'in background refresh');

        // Verify API was called in background
        final operationLog = mockApiAdapter.getOperationLog();
        expect(
          operationLog,
          contains(
            predicate<Map<String, dynamic>>(
              (log) =>
                  log['operation'] == 'findOne' && log['id'] == testModel.id,
            ),
          ),
          reason: 'Background refresh should have called API',
        );
      },
    );

    test(
      'findOne with localOnly policy should not be affected '
      'by 410 configuration',
      () async {
        // Create test model
        final testModel = PlainModel(
          id: 'test-model-410-local-only',
          name: 'Test Model for 410 Local Only',
          value: 789,
        );

        // Save model locally first
        await repository.save(
          testModel,
          savePolicy: DataSavePolicy.localFirst,
        );

        // Configure mock adapter to return 410 for this model
        mockApiAdapter.setFindOneToReturn410ForModel(testModel.id);

        // Try to find the model with localOnly policy
        final foundModel = await repository.findOne(
          testModel.id,
          loadPolicy: DataLoadPolicy.localOnly,
        );

        // Should find the model locally (API not called)
        expect(foundModel, isNotNull);
        expect(foundModel!.name, equals('Test Model for 410 Local Only'));

        // Verify API was NOT called
        final operationLog = mockApiAdapter.getOperationLog();
        expect(
          operationLog,
          isNot(
            contains(
              predicate<Map<String, dynamic>>(
                (log) =>
                    log['operation'] == 'findOne' && log['id'] == testModel.id,
              ),
            ),
          ),
        );
      },
    );

    test(
      'findOne with global 410 setting should affect all models',
      () async {
        // Create multiple test models
        final testModels = [
          PlainModel(
            id: 'test-model-global-410-1',
            name: 'Test Model Global 410 - 1',
            value: 100,
          ),
          PlainModel(
            id: 'test-model-global-410-2',
            name: 'Test Model Global 410 - 2',
            value: 200,
          ),
        ];

        // Save models locally
        for (final model in testModels) {
          await repository.save(
            model,
            savePolicy: DataSavePolicy.localFirst,
          );
        }

        // Configure mock adapter to return 410 for all models
        mockApiAdapter.setFindOneToReturn410();

        // Try to find each model with remoteFirst policy
        for (final model in testModels) {
          final foundModel = await repository.findOne(
            model.id,
            loadPolicy: DataLoadPolicy.remoteFirst,
          );

          // Should return null due to 410
          expect(foundModel, isNull);

          // Verify model was deleted locally
          final localModel = await repository.findOne(
            model.id,
            loadPolicy: DataLoadPolicy.localOnly,
          );
          expect(localModel, isNull);
        }

        // Verify API was called for all models
        final operationLog = mockApiAdapter.getOperationLog();
        for (final model in testModels) {
          expect(
            operationLog,
            contains(
              predicate<Map<String, dynamic>>(
                (log) => log['operation'] == 'findOne' && log['id'] == model.id,
              ),
            ),
          );
        }
      },
    );

    test(
      'findOne should handle API exception properly and log the error',
      () async {
        // Create test model
        final testModel = PlainModel(
          id: 'test-model-410-exception',
          name: 'Test Model for 410 Exception',
          value: 999,
        );

        // Save model locally first
        await repository.save(
          testModel,
          savePolicy: DataSavePolicy.localFirst,
        );

        // Configure mock adapter to return 410 for this model
        mockApiAdapter.setFindOneToReturn410ForModel(testModel.id);

        // Capture log messages
        final logMessages = <String>[];
        final subscription = Logger.root.onRecord.listen((record) {
          if (record.loggerName.contains('PlainModel') ||
              record.loggerName.contains('Repository') ||
              record.loggerName.contains('Sync')) {
            logMessages.add('${record.level.name}: ${record.message}');
          }
        });

        try {
          // Try to find the model with remoteFirst policy
          final foundModel = await repository.findOne(
            testModel.id,
            loadPolicy: DataLoadPolicy.remoteFirst,
          );

          // Should return null due to 410
          expect(foundModel, isNull);

          // Give some time for logging to complete
          await Future.delayed(const Duration(milliseconds: 50));

          // Check that appropriate logs were generated
          // (This may vary depending on the actual logging implementation)
          expect(logMessages, isNotEmpty);
        } finally {
          await subscription.cancel();
        }
      },
    );

    test(
      'multiple findOne calls with 410 should handle consistently',
      () async {
        // Create test model
        final testModel = PlainModel(
          id: 'test-model-410-multiple',
          name: 'Test Model for 410 Multiple',
          value: 555,
        );

        // Save model locally first
        await repository.save(
          testModel,
          savePolicy: DataSavePolicy.localFirst,
        );

        // Configure mock adapter to return 410 for this model
        mockApiAdapter.setFindOneToReturn410ForModel(testModel.id);

        // First call should trigger 410 and delete model
        final firstCall = await repository.findOne(
          testModel.id,
          loadPolicy: DataLoadPolicy.remoteFirst,
        );
        expect(firstCall, isNull);

        // Second call should also return null (no local model,
        // API still returns 410)
        final secondCall = await repository.findOne(
          testModel.id,
          loadPolicy: DataLoadPolicy.remoteFirst,
        );
        expect(secondCall, isNull);

        // Third call with localOnly should return null (model was deleted)
        final thirdCall = await repository.findOne(
          testModel.id,
          loadPolicy: DataLoadPolicy.localOnly,
        );
        expect(thirdCall, isNull);

        // Verify API was called multiple times
        final operationLog = mockApiAdapter.getOperationLog();
        final findOneCalls = operationLog
            .where(
              (log) =>
                  log['operation'] == 'findOne' && log['id'] == testModel.id,
            )
            .length;
        expect(findOneCalls, greaterThanOrEqualTo(2));
      },
    );
  });
}
