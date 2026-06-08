// Tests for BackgroundSyncManager behaviour.
//
// BackgroundSyncManager delegates to SynquillStorage.retryExecutor, so these
// tests need a running SynquillStorage (integration tier).
//
// Focus: lifecycle (singleton, idempotent init, reset), mode switching,
// processBackgroundSyncTasks behaviour, cancelBackgroundSync, and
// isReadyForBackgroundSync.

import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:synquill/synquill.dart';
import 'package:synquill/synquill_drift.dart';

import '../common/test_models.dart';
import '../common/mock_test_user_api_adapter.dart';
import '../common/test_user_repository.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _testConfig = SynquillStorageConfig(
  defaultSavePolicy: DataSavePolicy.localFirst,
  defaultLoadPolicy: DataLoadPolicy.localOnly,
  foregroundQueueConcurrency: 1,
  backgroundQueueConcurrency: 1,
  foregroundPollInterval: Duration(milliseconds: 50),
  backgroundPollInterval: Duration(minutes: 1),
  foregroundQueueCapacityTimeout: Duration(milliseconds: 100),
  backgroundQueueCapacityTimeout: Duration(milliseconds: 100),
  loadQueueCapacityTimeout: Duration(milliseconds: 100),
);

Future<({TestDatabase database, MockApiAdapter adapter})> _initStorage() async {
  final db = TestDatabase(NativeDatabase.memory());
  final mockAdapter = MockApiAdapter();
  SynquillRepositoryProvider.register<TestUser>(
    (database) => TestUserRepository(database as TestDatabase, mockAdapter),
  );
  await SynquillStorage.init(
    database: db,
    config: _testConfig,
    enableInternetMonitoring: false,
  );
  return (database: db, adapter: mockAdapter);
}

Future<int> _insertCreateTask({
  required TestDatabase database,
  required MockApiAdapter adapter,
  required TestUser user,
}) async {
  TestUserRepository(database, adapter).addLocalUser(user);

  return SyncQueueDao(database).insertItem(
    modelId: user.id,
    modelType: 'TestUser',
    payload: jsonEncode(user.toJson()),
    operation: SyncOperation.create.name,
    idempotencyKey: 'background-sync-${user.id}',
  );
}

Future<void> _waitFor(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 2),
  Duration interval = const Duration(milliseconds: 25),
}) async {
  final deadline = DateTime.now().add(timeout);

  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) {
      return;
    }
    await Future.delayed(interval);
  }

  fail('Timed out waiting for condition after $timeout');
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late TestDatabase database;
  late MockApiAdapter mockAdapter;
  late bool warnAboutMultipleDatabases;

  setUpAll(() {
    warnAboutMultipleDatabases =
        driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        warnAboutMultipleDatabases;
  });

  setUp(() async {
    final fixture = await _initStorage();
    database = fixture.database;
    mockAdapter = fixture.adapter;
  });

  tearDown(() async {
    try {
      await SynquillStorage.close();
    } catch (_) {}
    try {
      await BackgroundSyncManager.reset();
    } catch (_) {}
    TestUserRepository.clearLocal();
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('BackgroundSyncManager – singleton lifecycle', () {
    test('instance always returns the same object', () {
      final a = BackgroundSyncManager.instance;
      final b = BackgroundSyncManager.instance;
      expect(identical(a, b), isTrue);
    });

    test('initialize() is idempotent — calling twice does not throw', () async {
      await expectLater(BackgroundSyncManager.initialize(), completes);
      await expectLater(BackgroundSyncManager.initialize(), completes);
    });

    test('reset() clears the singleton so the next instance is a new object',
        () async {
      final before = BackgroundSyncManager.instance;
      await BackgroundSyncManager.reset();

      // Re-init storage so retryExecutor is available again for tearDown.
      final fixture = await _initStorage();
      database = fixture.database;
      mockAdapter = fixture.adapter;

      final after = BackgroundSyncManager.instance;
      expect(identical(before, after), isFalse,
          reason: 'reset() should create a fresh instance');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Mode switching', () {
    test('background mode delays polling until foreground mode resumes it',
        () async {
      final manager = SynquillStorage.backgroundSyncManager;
      final syncQueueDao = SyncQueueDao(database);
      final user = TestUser(
        id: 'mode-switch-user',
        name: 'Mode Switch',
        email: 'mode-switch@example.test',
      );

      manager.enableBackgroundMode();
      final taskId = await _insertCreateTask(
        database: database,
        adapter: mockAdapter,
        user: user,
      );

      await Future.delayed(const Duration(milliseconds: 200));

      expect(mockAdapter.operationLog, isEmpty);
      expect(await syncQueueDao.getItemById(taskId), isNotNull);

      manager.enableForegroundMode();

      await _waitFor(
          () async => await syncQueueDao.getItemById(taskId) == null);
      expect(mockAdapter.operationLog, contains('createOne(${user.id})'));
    });

    test('enableForegroundMode(forceSync: true) drains pending queue task',
        () async {
      final manager = SynquillStorage.backgroundSyncManager;
      final syncQueueDao = SyncQueueDao(database);
      final user = TestUser(
        id: 'force-sync-user',
        name: 'Force Sync',
        email: 'force-sync@example.test',
      );

      manager.enableBackgroundMode();
      final taskId = await _insertCreateTask(
        database: database,
        adapter: mockAdapter,
        user: user,
      );

      manager.enableForegroundMode(forceSync: true);

      await _waitFor(
          () async => await syncQueueDao.getItemById(taskId) == null);
      expect(mockAdapter.operationLog, contains('createOne(${user.id})'));
    });

    test(
        'SynquillStorage.enableBackgroundMode '
        'and enableForegroundMode delegate to backgroundSyncManager', () async {
      final syncQueueDao = SyncQueueDao(database);
      final user = TestUser(
        id: 'storage-mode-user',
        name: 'Storage Mode',
        email: 'storage-mode@example.test',
      );

      SynquillStorage.enableBackgroundMode();
      final taskId = await _insertCreateTask(
        database: database,
        adapter: mockAdapter,
        user: user,
      );

      await Future.delayed(const Duration(milliseconds: 200));

      expect(mockAdapter.operationLog, isEmpty);
      expect(await syncQueueDao.getItemById(taskId), isNotNull);

      SynquillStorage.enableForegroundMode(forceSync: true);

      await _waitFor(
          () async => await syncQueueDao.getItemById(taskId) == null);
      expect(mockAdapter.operationLog, contains('createOne(${user.id})'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('processBackgroundSyncTasks', () {
    test('completes successfully when sync queue is empty', () async {
      final manager = SynquillStorage.backgroundSyncManager;
      await expectLater(manager.processBackgroundSyncTasks(), completes);
    });

    test('processes due sync queue items and removes successful tasks',
        () async {
      final manager = SynquillStorage.backgroundSyncManager;
      final syncQueueDao = SyncQueueDao(database);
      final user = TestUser(
        id: 'process-due-user',
        name: 'Process Due',
        email: 'process-due@example.test',
      );

      final taskId = await _insertCreateTask(
        database: database,
        adapter: mockAdapter,
        user: user,
      );

      await manager.processBackgroundSyncTasks(forceSync: true);

      expect(await syncQueueDao.getItemById(taskId), isNull);
      expect(mockAdapter.operationLog, contains('createOne(${user.id})'));
    });

    test('completes via SynquillStorage.instance method', () async {
      await expectLater(
        SynquillStorage.instance.processBackgroundSyncTasks(),
        completes,
      );
    });

    test('completes via static SynquillStorage.processBackgroundSync()',
        () async {
      await expectLater(SynquillStorage.processBackgroundSync(), completes);
    });

    test('throws when SynquillStorage is not initialized', () async {
      await SynquillStorage.close();

      expect(
        () => SynquillStorage.processBackgroundSync(),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('cancelBackgroundSync', () {
    test('stops retry polling and leaves persistent queue tasks untouched',
        () async {
      final manager = SynquillStorage.backgroundSyncManager;
      final syncQueueDao = SyncQueueDao(database);
      final user = TestUser(
        id: 'cancel-sync-user',
        name: 'Cancel Sync',
        email: 'cancel-sync@example.test',
      );

      await manager.cancelBackgroundSync();
      final taskId = await _insertCreateTask(
        database: database,
        adapter: mockAdapter,
        user: user,
      );

      await Future.delayed(const Duration(milliseconds: 200));

      expect(mockAdapter.operationLog, isEmpty);
      expect(await syncQueueDao.getItemById(taskId), isNotNull);
    });

    test('is a no-op when BackgroundSyncManager is not initialized', () async {
      await BackgroundSyncManager.reset();
      // Creating a fresh (un-initialized) instance.
      final freshManager = BackgroundSyncManager.instance;
      // cancelBackgroundSync checks _isInitialized and returns early.
      await expectLater(freshManager.cancelBackgroundSync(), completes);

      // Re-init for tearDown.
      final fixture = await _initStorage();
      database = fixture.database;
      mockAdapter = fixture.adapter;
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('isReadyForBackgroundSync', () {
    test('returns true when SynquillStorage is initialized', () {
      expect(SynquillStorage.backgroundSyncManager.isReadyForBackgroundSync,
          isTrue);
    });

    test('returns false when SynquillStorage is closed', () async {
      final manager = SynquillStorage.backgroundSyncManager;

      await SynquillStorage.close();

      expect(manager.isReadyForBackgroundSync, isFalse);
    });
  });
}
