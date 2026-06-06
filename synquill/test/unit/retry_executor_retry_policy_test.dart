import 'dart:convert';

import 'package:synquill/synquill_core.dart';
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

    test('marks payload without id dead without incrementing attempts',
        () async {
      await initStorage();

      final taskId = await insertTask(
        modelType: 'TestUser',
        modelId: 'missing-id',
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
