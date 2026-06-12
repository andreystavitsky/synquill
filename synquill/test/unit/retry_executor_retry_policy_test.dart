import 'dart:convert';

import 'package:queue/queue.dart';
import 'package:synquill/synquill.dart';
import 'package:test/test.dart';

import '../common/mock_test_user_api_adapter.dart';
import '../common/test_models.dart';
import '../common/test_user_repository.dart';

void main() {
  group('RetryExecutor retry policy', () {
    late TestDatabase database;
    late ThrowingMockApiAdapter mockAdapter;
    late SyncQueueDao syncQueueDao;
    late TestUserRepository repository;

    Future<void> initStorage({bool registerRepository = true}) async {
      SynquillRepositoryProvider.reset();
      DatabaseProvider.reset();
      TestUserRepository.clearLocal();

      database = TestDatabase(NativeDatabase.memory());
      mockAdapter = ThrowingMockApiAdapter();

      if (registerRepository) {
        SynquillRepositoryProvider.register<TestUser>(
          (db) => TestUserRepository(db as TestDatabase, mockAdapter),
        );
      }

      await SynquillStorage.init(
        database: database,
        config: const SynquillStorageConfig(
          foregroundPollInterval: Duration(minutes: 1),
          backgroundPollInterval: Duration(minutes: 1),
          initialRetryDelay: Duration(milliseconds: 5),
          minRetryDelay: Duration(milliseconds: 1),
          maxRetryAttempts: 3,
          jitterPercent: 0,
        ),
        enableInternetMonitoring: false,
        connectivityChecker: () async => true,
      );

      syncQueueDao = SyncQueueDao(database);
      if (registerRepository) {
        repository = TestUserRepository(database, mockAdapter);
      }
    }

    Future<int> insertTask({
      required String modelType,
      required String modelId,
      required String operation,
      required String payload,
    }) {
      return syncQueueDao.insertItem(
        modelType: modelType,
        modelId: modelId,
        operation: operation,
        payload: payload,
        idempotencyKey: '$modelId-$operation-test',
      );
    }

    Future<Map<String, dynamic>?> processAndFetch(int taskId) async {
      await SynquillStorage.retryExecutor.processDueTasksNow(forceSync: true);
      return syncQueueDao.getItemById(taskId);
    }

    Future<void> expectCreateErrorMarksDead(
      Object error,
      String modelId,
    ) async {
      await initStorage();
      final user = TestUser(
        id: modelId,
        name: 'Terminal User',
        email: '$modelId@example.test',
      );
      repository.addLocalUser(user);
      mockAdapter.createError = error;

      final taskId = await insertTask(
        modelType: 'TestUser',
        modelId: user.id,
        operation: SyncOperation.create.name,
        payload: jsonEncode(user.toJson()),
      );

      final task = await processAndFetch(taskId);

      expect(task, isNotNull);
      expect(task!['status'], SyncStatus.dead.name);
      expect(task['attempt_count'], 0);
      expect(task['last_error'], contains(error.toString()));
      await SynquillStorage.close();
    }

    tearDown(() async {
      try {
        await SynquillStorage.close();
      } catch (_) {
        // Ignore cleanup errors from tests that close storage themselves.
      }
      TestUserRepository.clearLocal();
      SynquillRepositoryProvider.reset();
      DatabaseProvider.reset();
    });

    test('marks task without payload or queue id dead without incrementing',
        () async {
      await initStorage();

      final taskId = await insertTask(
        modelType: 'TestUser',
        modelId: '',
        operation: SyncOperation.delete.name,
        payload: '{}',
      );

      final task = await processAndFetch(taskId);

      expect(task, isNotNull);
      expect(task!['status'], SyncStatus.dead.name);
      expect(task['attempt_count'], 0);
      expect(task['next_retry_at'], isNull);
      expect(task['last_error'], contains('missing ID'));
    });

    test('marks invalid JSON payload dead without incrementing attempts',
        () async {
      await initStorage();

      final taskId = await insertTask(
        modelType: 'TestUser',
        modelId: 'invalid-json',
        operation: SyncOperation.delete.name,
        payload: '{',
      );

      final task = await processAndFetch(taskId);

      expect(task, isNotNull);
      expect(task!['status'], SyncStatus.dead.name);
      expect(task['attempt_count'], 0);
      expect(task['next_retry_at'], isNull);
      expect(task['last_error'], contains('Failed to parse task payload'));
    });

    test('marks missing repository configuration dead', () async {
      await initStorage(registerRepository: false);

      final taskId = await insertTask(
        modelType: 'MissingUser',
        modelId: 'missing-repository',
        operation: SyncOperation.create.name,
        payload: jsonEncode({
          'id': 'missing-repository',
          'name': 'Missing',
          'email': 'missing@example.test',
        }),
      );

      final task = await processAndFetch(taskId);

      expect(task, isNotNull);
      expect(task!['status'], SyncStatus.dead.name);
      expect(task['attempt_count'], 0);
      expect(task['last_error'], contains('No registered repository'));
    });

    test('schedules retry for transient network errors', () async {
      await initStorage();
      final user = TestUser(
        id: 'network-retry',
        name: 'Network Retry',
        email: 'network@example.test',
      );
      repository.addLocalUser(user);
      mockAdapter.setNetworkError(true);

      final taskId = await insertTask(
        modelType: 'TestUser',
        modelId: user.id,
        operation: SyncOperation.create.name,
        payload: jsonEncode(user.toJson()),
      );

      final task = await processAndFetch(taskId);

      expect(task, isNotNull);
      expect(task!['status'], SyncStatus.pending.name);
      expect(task['attempt_count'], 1);
      expect(task['next_retry_at'], isNotNull);
      expect(task['last_error'], contains('DioException'));
    });

    test('schedules retry for queue cancellation lifecycle errors', () async {
      await initStorage();
      final user = TestUser(
        id: 'queue-cancel-retry',
        name: 'Queue Cancel Retry',
        email: 'queue-cancel@example.test',
      );
      repository.addLocalUser(user);
      mockAdapter.createError = QueueCancelledException();

      final taskId = await insertTask(
        modelType: 'TestUser',
        modelId: user.id,
        operation: SyncOperation.create.name,
        payload: jsonEncode(user.toJson()),
      );

      final task = await processAndFetch(taskId);

      expect(task, isNotNull);
      expect(task!['status'], SyncStatus.pending.name);
      expect(task['attempt_count'], 1);
      expect(task['next_retry_at'], isNotNull);
      expect(task['last_error'], contains('QueueCancelledException'));
    });

    test('discards delete tasks when remote resource is already gone',
        () async {
      for (final error in [
        ApiExceptionNotFound('/users/already-gone'),
        ApiExceptionGone('/users/already-gone'),
      ]) {
        await initStorage();
        mockAdapter.deleteError = error;

        final taskId = await insertTask(
          modelType: 'TestUser',
          modelId: 'already-gone-${error.runtimeType}',
          operation: SyncOperation.delete.name,
          payload: jsonEncode({'id': 'already-gone-${error.runtimeType}'}),
        );

        final task = await processAndFetch(taskId);

        expect(task, isNull);
        await SynquillStorage.close();
      }
    });

    test('marks validation, auth, and conflict failures dead', () async {
      await expectCreateErrorMarksDead(
        ValidationException('invalid data'),
        'validation-dead',
      );
      await expectCreateErrorMarksDead(
        AuthenticationException('missing auth'),
        'authentication-dead',
      );
      await expectCreateErrorMarksDead(
        AuthorizationException('forbidden'),
        'authorization-dead',
      );
      await expectCreateErrorMarksDead(
        ConflictException('conflict'),
        'conflict-dead',
      );
    });

    test('marks server failures retryable', () async {
      await initStorage();
      final user = TestUser(
        id: 'server-retry',
        name: 'Server Retry',
        email: 'server@example.test',
      );
      repository.addLocalUser(user);
      mockAdapter.createError = ServerException('server down');

      final taskId = await insertTask(
        modelType: 'TestUser',
        modelId: user.id,
        operation: SyncOperation.create.name,
        payload: jsonEncode(user.toJson()),
      );

      final task = await processAndFetch(taskId);

      expect(task, isNotNull);
      expect(task!['status'], SyncStatus.pending.name);
      expect(task['attempt_count'], 1);
      expect(task['next_retry_at'], isNotNull);
    });

    test('resolves retry task id from registered custom JSON key', () async {
      SynquillRepositoryProvider.reset();
      DatabaseProvider.reset();
      TestPlaceRepository.clearLocal();

      database = TestDatabase(NativeDatabase.memory());
      final placeAdapter = TestPlaceApiAdapter();

      SynquillRepositoryProvider.register<TestPlace>(
        (db) => TestPlaceRepository(db as TestDatabase, placeAdapter),
      );
      ModelInfoRegistryProvider.registerIdJsonKey('TestPlace', 'placeId');

      await SynquillStorage.init(
        database: database,
        config: const SynquillStorageConfig(
          foregroundPollInterval: Duration(minutes: 1),
          backgroundPollInterval: Duration(minutes: 1),
          initialRetryDelay: Duration(milliseconds: 5),
          minRetryDelay: Duration(milliseconds: 1),
          maxRetryAttempts: 3,
          jitterPercent: 0,
        ),
        enableInternetMonitoring: false,
        connectivityChecker: () async => true,
      );

      syncQueueDao = SyncQueueDao(database);
      final placeRepository = TestPlaceRepository(database, placeAdapter);
      placeRepository.addLocalPlace(
        TestPlace(id: 'place-1', title: 'Favorite'),
      );

      final createTaskId = await insertTask(
        modelType: 'TestPlace',
        modelId: 'place-1',
        operation: SyncOperation.create.name,
        payload: jsonEncode({'placeId': 'place-1', 'title': 'Favorite'}),
      );
      final updateTaskId = await insertTask(
        modelType: 'TestPlace',
        modelId: 'place-1',
        operation: SyncOperation.update.name,
        payload: jsonEncode({'placeId': 'place-1', 'title': 'Favorite'}),
      );
      final deleteTaskId = await insertTask(
        modelType: 'TestPlace',
        modelId: 'place-1',
        operation: SyncOperation.delete.name,
        payload: jsonEncode({'placeId': 'place-1', 'title': 'Favorite'}),
      );

      await SynquillStorage.retryExecutor.processDueTasksNow(forceSync: true);

      expect(await syncQueueDao.getItemById(createTaskId), isNull);
      expect(await syncQueueDao.getItemById(updateTaskId), isNull);
      expect(await syncQueueDao.getItemById(deleteTaskId), isNull);
      expect(placeAdapter.createdIds, ['place-1']);
      expect(placeAdapter.updatedIds, ['place-1']);
      expect(placeAdapter.deletedIds, ['place-1']);
      expect(placeAdapter.lastPayloadHadCanonicalId, isFalse);
    });

    test('prefers registered custom JSON key over payload id', () async {
      SynquillRepositoryProvider.reset();
      DatabaseProvider.reset();
      TestPlaceRepository.clearLocal();

      database = TestDatabase(NativeDatabase.memory());
      final placeAdapter = TestPlaceApiAdapter();

      SynquillRepositoryProvider.register<TestPlace>(
        (db) => TestPlaceRepository(db as TestDatabase, placeAdapter),
      );
      ModelInfoRegistryProvider.registerIdJsonKey('TestPlace', 'placeId');

      await SynquillStorage.init(
        database: database,
        config: const SynquillStorageConfig(
          foregroundPollInterval: Duration(minutes: 1),
          backgroundPollInterval: Duration(minutes: 1),
          initialRetryDelay: Duration(milliseconds: 5),
          minRetryDelay: Duration(milliseconds: 1),
          maxRetryAttempts: 3,
          jitterPercent: 0,
        ),
        enableInternetMonitoring: false,
        connectivityChecker: () async => true,
      );

      syncQueueDao = SyncQueueDao(database);
      final placeRepository = TestPlaceRepository(database, placeAdapter);
      placeRepository.addLocalPlace(
        TestPlace(id: 'place-1', title: 'Favorite'),
      );

      final taskId = await insertTask(
        modelType: 'TestPlace',
        modelId: 'place-1',
        operation: SyncOperation.update.name,
        payload: jsonEncode({
          'id': 'wrong-id',
          'placeId': 'place-1',
          'title': 'Favorite',
        }),
      );

      final task = await processAndFetch(taskId);

      expect(task, isNull);
      expect(placeAdapter.updatedIds, ['place-1']);
    });

    test('falls back to sync queue model_id when payload omits identity',
        () async {
      await initStorage();

      final taskId = await insertTask(
        modelType: 'TestUser',
        modelId: 'queue-only-delete-id',
        operation: SyncOperation.delete.name,
        payload: jsonEncode({'name': 'No ID Payload'}),
      );

      final task = await processAndFetch(taskId);

      expect(task, isNull);
      expect(mockAdapter.operationLog,
          contains('deleteOne(queue-only-delete-id)'));
    });
  });
}

class ThrowingMockApiAdapter extends MockApiAdapter {
  Object? createError;
  Object? updateError;
  Object? deleteError;

  @override
  Future<TestUser?> createOne(
    TestUser model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final error = createError;
    if (error != null) {
      throw error;
    }
    return super.createOne(model, headers: headers, extra: extra);
  }

  @override
  Future<TestUser?> updateOne(
    TestUser model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final error = updateError;
    if (error != null) {
      throw error;
    }
    return super.updateOne(model, headers: headers, extra: extra);
  }

  @override
  Future<void> deleteOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final error = deleteError;
    if (error != null) {
      throw error;
    }
    return super.deleteOne(id, headers: headers, extra: extra);
  }
}

class TestPlace extends SynquillDataModel<TestPlace> {
  @override
  final String id;
  final String title;

  TestPlace({required this.id, required this.title});

  @override
  TestPlace fromJson(Map<String, dynamic> json) {
    return TestPlace(
      id: json['placeId'] as String,
      title: json['title'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {'placeId': id, 'title': title};
  }
}

class TestPlaceRepository extends SynquillRepositoryBase<TestPlace> {
  final TestPlaceApiAdapter _apiAdapter;
  static final Map<String, TestPlace> _localData = {};

  TestPlaceRepository(super.db, this._apiAdapter);

  static void clearLocal() {
    _localData.clear();
  }

  void addLocalPlace(TestPlace place) {
    _localData[place.id] = place;
  }

  @override
  ApiAdapterBase<TestPlace> get apiAdapter => _apiAdapter;

  @override
  bool get localOnly => false;

  @override
  Future<TestPlace?> fetchFromLocal(
    String id, {
    QueryParams? queryParams,
  }) async {
    return _localData[id];
  }

  @override
  Future<List<TestPlace>> fetchAllFromLocal({QueryParams? queryParams}) async {
    return _localData.values.toList();
  }

  @override
  Future<TestPlace?> fetchFromRemote(
    String id, {
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    return _apiAdapter.findOne(
      id,
      queryParams: queryParams,
      headers: headers,
      extra: extra,
    );
  }

  @override
  Future<List<TestPlace>> fetchAllFromRemote({
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    return _apiAdapter.findAll(
      queryParams: queryParams,
      headers: headers,
      extra: extra,
    );
  }

  @override
  Future<void> removeFromLocalIfExists(String id) async {
    _localData.remove(id);
  }

  @override
  Future<void> saveToLocal(
    TestPlace item, {
    Map<String, dynamic>? extra,
  }) async {
    _localData[item.id] = item;
  }

  @override
  Stream<TestPlace?> watchFromLocal(String id, {QueryParams? queryParams}) {
    return Stream.value(_localData[id]);
  }

  @override
  Stream<List<TestPlace>> watchAllFromLocal({QueryParams? queryParams}) {
    return Stream.value(_localData.values.toList());
  }
}

class TestPlaceApiAdapter extends ApiAdapterBase<TestPlace> {
  final List<String> createdIds = [];
  final List<String> updatedIds = [];
  final List<String> deletedIds = [];
  bool lastPayloadHadCanonicalId = false;

  @override
  Uri get baseUrl => Uri.parse('https://test.example.com/api/v1/');

  @override
  String get type => 'place';

  @override
  String get pluralType => 'places';

  @override
  TestPlace fromJson(Map<String, dynamic> json) {
    lastPayloadHadCanonicalId = json.containsKey('id');
    return TestPlace(
      id: json['placeId'] as String,
      title: json['title'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson(TestPlace model) => model.toJson();

  @override
  Future<TestPlace?> findOne(
    String id, {
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    return null;
  }

  @override
  Future<List<TestPlace>> findAll({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    return const [];
  }

  @override
  Future<TestPlace?> createOne(
    TestPlace model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    createdIds.add(model.id);
    return model;
  }

  @override
  Future<TestPlace?> updateOne(
    TestPlace model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    updatedIds.add(model.id);
    return model;
  }

  @override
  Future<TestPlace?> replaceOne(
    TestPlace model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    updatedIds.add(model.id);
    return model;
  }

  @override
  Future<void> deleteOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    deletedIds.add(id);
  }
}
