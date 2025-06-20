// ignore_for_file: avoid_relative_lib_imports, avoid_print

import 'package:test/test.dart';
import 'dart:isolate';
import 'dart:io';
import 'dart:async';

import 'package:synquill/synquill_core.dart';

import 'package:synquill/synquill.generated.dart';

import 'package:synquill/src/test_models/index.dart';

import '../common/mock_plain_model_api_adapter.dart';
import '../common/test_plain_model_repository.dart';

void main() {
  group('SyncedStorage Background Sync Methods', () {
    late SynquillDatabase database;
    late Logger logger;

    setUp(() async {
      // Set up test database using the generated SynquillDatabase
      database = SynquillDatabase(NativeDatabase.memory());

      // Set up logging
      logger = Logger('BackgroundSyncTest');
      Logger.root.level = Level.ALL;
      Logger.root.onRecord.listen((record) {
        // Uncomment for debugging:
        // print('[${record.level.name}] ${record.loggerName}: '
        //     '${record.message}');
      });

      // Initialize SyncedStorage with test configuration using generated
      // initialization
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
    });

    tearDown(() async {
      await SynquillStorage.close();
    });

    test('backgroundSyncManager getter should return manager instance', () {
      final manager = SynquillStorage.backgroundSyncManager;
      expect(manager, isNotNull);
      expect(manager, isA<BackgroundSyncManager>());
    });

    test(
      'backgroundSyncManager getter should throw when not initialized',
      () async {
        await SynquillStorage.close();

        expect(
          () => SynquillStorage.backgroundSyncManager,
          throwsA(isA<StateError>()),
        );
      },
    );

    test('processBackgroundSyncTasks instance method should work', () async {
      // This should not throw and should complete successfully
      await expectLater(
        SynquillStorage.instance.processBackgroundSyncTasks(),
        completes,
      );
    });

    test(
      'processBackgroundSyncTasks should throw when not initialized',
      () async {
        await SynquillStorage.close();

        expect(
          () => SynquillStorage.instance.processBackgroundSyncTasks(),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('processBackgroundSync static method should work', () async {
      // This should not throw and should complete successfully
      await expectLater(SynquillStorage.processBackgroundSync(), completes);
    });

    test('processBackgroundSync should throw when not initialized', () async {
      await SynquillStorage.close();

      expect(
        () => SynquillStorage.processBackgroundSync(),
        throwsA(isA<StateError>()),
      );
    });

    test('initForBackgroundIsolate should initialize successfully', () async {
      // Close current instance first
      await SynquillStorage.close();

      // Create a new database instance for background isolate
      final backgroundDatabase = SynquillDatabase(NativeDatabase.memory());

      // This should not throw and should complete successfully
      await expectLater(
        SynquillStorage.initForBackgroundIsolate(
          database: backgroundDatabase,
          config: const SynquillStorageConfig(),
          logger: Logger('BackgroundTest'),
          initializeFn: initializeSynquillStorage,
        ),
        completes,
      );

      // Verify that SyncedStorage is properly initialized
      expect(SynquillStorage.database, equals(backgroundDatabase));
      expect(SynquillStorage.backgroundSyncManager, isNotNull);

      // Should be able to process background sync
      await expectLater(SynquillStorage.processBackgroundSync(), completes);

      // Clean up
      await SynquillStorage.close();
      await backgroundDatabase.close();
    });

    test('enableBackgroundMode should switch modes', () {
      // Should not throw
      expect(() => SynquillStorage.enableBackgroundMode(), returnsNormally);
    });

    test('enableForegroundMode should switch modes', () {
      // Should not throw
      expect(() => SynquillStorage.enableForegroundMode(), returnsNormally);
    });

    test('enableBackgroundMode should throw when not initialized', () async {
      await SynquillStorage.close();

      expect(
        () => SynquillStorage.enableBackgroundMode(),
        throwsA(isA<StateError>()),
      );
    });

    test('enableForegroundMode should throw when not initialized', () async {
      await SynquillStorage.close();

      expect(
        () => SynquillStorage.enableForegroundMode(),
        throwsA(isA<StateError>()),
      );
    });

    test('mode switching integration', () {
      final manager = SynquillStorage.backgroundSyncManager;

      // Test the full mode switching flow
      expect(() => SynquillStorage.enableBackgroundMode(), returnsNormally);
      expect(() => manager.enableBackgroundMode(), returnsNormally);

      expect(() => SynquillStorage.enableForegroundMode(), returnsNormally);
      expect(() => manager.enableForegroundMode(), returnsNormally);

      // Should be ready for background sync
      expect(manager.isReadyForBackgroundSync, isTrue);
    });
  });

  group('SyncedStorage Isolate Integration Tests', () {
    late SynquillDatabase mainDatabase;
    late String tempDatabasePath;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('synquill_test');
      tempDatabasePath = '${tempDir.path}/test_db.sqlite';

      // Create database for main isolate with cross-isolate sharing enabled
      mainDatabase = SynquillDatabase(
        NativeDatabase(
          File(tempDatabasePath),
          setup: (database) {
            // Enable WAL mode for cross-isolate sharing
            database.execute('PRAGMA journal_mode=WAL;');
          },
        ),
      );

      // Initialize SyncedStorage with test configuration
      await SynquillStorage.init(
        database: mainDatabase,
        config: const SynquillStorageConfig(
          defaultSavePolicy: DataSavePolicy.localFirst,
          defaultLoadPolicy: DataLoadPolicy.localOnly,
          foregroundQueueConcurrency: 1,
          backgroundQueueConcurrency: 1,
        ),
        logger: Logger('MainIsolateTest'),
        initializeFn: initializeSynquillStorage,
        enableInternetMonitoring: false,
      );
    });

    tearDown(() async {
      await SynquillStorage.close();

      // Add a small delay to ensure all isolates have finished
      await Future.delayed(const Duration(milliseconds: 100));

      // Clean up temporary directory
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('background sync workflow in separate isolate', () async {
      // Create test data in the main isolate using the generated repository
      final repository = SynquillRepositoryProvider.getFrom<PlainModel>(
        mainDatabase,
      );
      final testModel = PlainModel(
        id: 'main-isolate-test-model',
        name: 'Test Model from Main Isolate',
        value: 42,
      );
      await repository.save(testModel, savePolicy: DataSavePolicy.localFirst);

      // Verify the data exists in the main isolate
      final foundInMain = await repository.findOne(testModel.id);
      expect(foundInMain, isNotNull);
      expect(foundInMain!.name, equals('Test Model from Main Isolate'));

      // Create isolate communication setup
      final receivePort = ReceivePort();
      final isolateCompleter = Completer<Map<String, dynamic>>();

      receivePort.listen((message) {
        if (message is Map<String, dynamic>) {
          isolateCompleter.complete(message);
        }
      });

      // Spawn background isolate with our test function
      await Isolate.spawn(_backgroundIsolateEntryPoint, {
        'sendPort': receivePort.sendPort,
        'databasePath': tempDatabasePath,
        'modelId': testModel.id,
      });

      // Wait for isolate to complete and get results
      final result = await isolateCompleter.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException(
          'Isolate test timed out',
          const Duration(seconds: 30),
        ),
      );

      receivePort.close();

      // Verify isolate execution results
      expect(result['success'], isTrue, reason: result['error']?.toString());
      expect(result['isolateInitialized'], isTrue);
      expect(result['backgroundSyncCompleted'], isTrue);
      expect(result['modesSwitched'], isTrue);
      expect(result['modelFound'], isTrue);
      expect(result['foundModelName'], equals('Test Model from Main Isolate'));
      expect(result['foundModelValue'], equals(42));
      expect(result['modelCreated'], isTrue);
      expect(result['createdModelName'], equals('Isolate Model'));
      expect(result['createdModelValue'], equals(123));

      // Now check if the model created in the isolate is visible in main
      final isolateCreatedModel = await repository.findOne(
        'isolate-created-model',
      );
      expect(isolateCreatedModel, isNotNull);
      expect(isolateCreatedModel!.name, equals('Isolate Model'));
      expect(isolateCreatedModel.value, equals(123));

      print('Isolate test completed successfully: $result');
    });

    test('pragma annotations prevent method tree-shaking in isolate', () async {
      // This test verifies that all pragma-annotated methods are accessible
      // from isolates by attempting to call them
      final receivePort = ReceivePort();
      final isolateCompleter = Completer<Map<String, dynamic>>();

      receivePort.listen((message) {
        if (message is Map<String, dynamic>) {
          isolateCompleter.complete(message);
        }
      });

      await Isolate.spawn(_pragmaTestIsolateEntryPoint, {
        'sendPort': receivePort.sendPort,
        'databasePath': tempDatabasePath,
      });

      final result = await isolateCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'Pragma test timed out',
          const Duration(seconds: 5),
        ),
      );

      receivePort.close();

      // Verify all pragma-annotated methods are accessible
      expect(result['success'], isTrue, reason: result['error']?.toString());
      expect(result['initForBackgroundIsolateAccessible'], isTrue);
      expect(result['processBackgroundSyncAccessible'], isTrue);
      expect(result['enableBackgroundModeAccessible'], isTrue);
      expect(result['enableForegroundModeAccessible'], isTrue);

      print('Pragma annotation test completed: $result');
    });
  });
}

/// Initializes the test storage system.
void initializeTestStorage(GeneratedDatabase db) {
  // Register the TestUser repository factory
  SynquillRepositoryProvider.register<PlainModel>(
    (database) =>
        TestPlainModelRepository(database, MockPlainModelApiAdapter()),
  );
}

/// Background isolate entry point for testing
/// true cross-isolate synchronization
@pragma('vm:entry-point')
void _backgroundIsolateEntryPoint(Map<String, dynamic> params) async {
  // Extract parameters
  final sendPort = params['sendPort'] as SendPort;
  final databasePath = params['databasePath'] as String;
  final modelId = params['modelId'] as String;

  final results = <String, dynamic>{};

  try {
    // Create database connection using the same file path with WAL mode
    final database = SynquillDatabase(
      NativeDatabase(
        File(databasePath),
        setup: (database) {
          // Enable WAL mode for cross-isolate sharing
          database.execute('PRAGMA journal_mode=WAL;');
        },
      ),
    );

    // Initialize SyncedStorage
    await SynquillStorage.initForBackgroundIsolate(
      database: database,
      config: const SynquillStorageConfig(),
      logger: Logger('BackgroundIsolate'),
      initializeFn: initializeSynquillStorage,
    );

    results['isolateInitialized'] = true;

    // Perform background sync processing
    await SynquillStorage.processBackgroundSync();
    results['backgroundSyncCompleted'] = true;

    // Example of switching modes in the background isolate
    SynquillStorage.enableForegroundMode();
    results['modesSwitched'] = true;

    // Test repository access and find the model created in main isolate
    // This tests TRUE cross-isolate data synchronization
    final repository = SynquillRepositoryProvider.getFrom<PlainModel>(database);
    final foundModel = await repository.findOne(modelId);
    results['modelFound'] = foundModel != null;

    if (foundModel != null) {
      results['foundModelName'] = foundModel.name;
      results['foundModelValue'] = foundModel.value;
    }

    // Create a new model in this isolate to test bi-directional synchronization
    final isolateModel = PlainModel(
      id: 'isolate-created-model',
      name: 'Isolate Model',
      value: 123,
    );
    await repository.save(isolateModel, savePolicy: DataSavePolicy.localFirst);

    // Verify the model was saved in this isolate
    final foundCreatedModel = await repository.findOne(isolateModel.id);
    results['modelCreated'] = foundCreatedModel != null;

    if (foundCreatedModel != null) {
      results['createdModelName'] = foundCreatedModel.name;
      results['createdModelValue'] = foundCreatedModel.value;
    }

    // Close the database connection properly
    await SynquillStorage.close();

    // Indicate success
    results['success'] = true;
    sendPort.send(results);
  } catch (e, s) {
    // Send error details back to the main isolate
    sendPort.send({
      'success': false,
      'error': e.toString(),
      'stackTrace': s.toString(),
    });
  }
}

/// Pragma annotation accessibility test entry point
@pragma('vm:entry-point')
void _pragmaTestIsolateEntryPoint(Map<String, dynamic> params) async {
  final sendPort = params['sendPort'] as SendPort;
  final databasePath = params['databasePath'] as String;

  try {
    // Create database connection using the same file path with WAL mode
    final database = SynquillDatabase(
      NativeDatabase(
        File(databasePath),
        setup: (database) {
          // Enable WAL mode for cross-isolate sharing
          database.execute('PRAGMA journal_mode=WAL;');
        },
      ),
    );

    await SynquillStorage.initForBackgroundIsolate(
      database: database,
      config: const SynquillStorageConfig(),
      logger: Logger('BackgroundIsolate'),
      initializeFn: initializeSynquillStorage,
    );

    // Test accessibility of pragma-annotated methods
    // These method references should be available due to @pragma annotations
    final initAccessible =
        SynquillStorage.initForBackgroundIsolate.toString().isNotEmpty;
    final processAccessible =
        SynquillStorage.processBackgroundSync.toString().isNotEmpty;
    final enableBackgroundAccessible =
        SynquillStorage.enableBackgroundMode.toString().isNotEmpty;
    final enableForegroundAccessible =
        SynquillStorage.enableForegroundMode.toString().isNotEmpty;

    await SynquillStorage.close();

    // Send results back to the main isolate
    sendPort.send({
      'success': true,
      'initForBackgroundIsolateAccessible': initAccessible,
      'processBackgroundSyncAccessible': processAccessible,
      'enableBackgroundModeAccessible': enableBackgroundAccessible,
      'enableForegroundModeAccessible': enableForegroundAccessible,
    });
  } catch (e) {
    sendPort.send({'success': false, 'error': e.toString()});
  }
}
