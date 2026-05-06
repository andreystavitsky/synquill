// ignore_for_file: avoid_relative_lib_imports

import 'package:test/test.dart';
import 'package:synquill/synquill_core.dart';

import 'package:synquill/src/test_models/index.dart';
import 'package:synquill/synquill.generated.dart';

import '../common/mock_plain_model_api_adapter.dart';

/// Integration tests for fetchAllFromLocalWithoutPendingSyncOps.
///
/// Verifies that:
/// - Items with pending sync operations are excluded.
/// - Items with only 'dead' operations are included (dead = no longer pending).
/// - Fast path works when the sync queue is empty (0 extra queries).
/// - QueryParams (pagination) is applied at the SQL level, not post-filter.
void main() {
  group('fetchAllFromLocalWithoutPendingSyncOps Integration Tests', () {
    late SynquillDatabase database;
    late Logger logger;
    late MockPlainModelApiAdapter mockApiAdapter;
    late _TestRepo repo;

    setUp(() async {
      database = SynquillDatabase(NativeDatabase.memory());
      logger = Logger('FetchWithoutPendingTest');
      Logger.root.level = Level.ALL;

      DatabaseProvider.setInstance(database);
      mockApiAdapter = MockPlainModelApiAdapter();

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
        enableInternetMonitoring: false,
      );

      repo = _TestRepo(database, mockApiAdapter);
    });

    tearDown(() async {
      mockApiAdapter.clearRemote();
      mockApiAdapter.clearLog();
      await SynquillStorage.close();
      await database.close();
      SynquillRepositoryProvider.reset();
      DatabaseProvider.reset();
    });

    // -----------------------------------------------------------------------

    test('returns all items when sync queue is empty (fast path)', () async {
      // Arrange: 3 clean items, nothing in sync queue
      await repo.saveToLocal(PlainModel(id: 'a', name: 'Alpha', value: 1));
      await repo.saveToLocal(PlainModel(id: 'b', name: 'Beta', value: 2));
      await repo.saveToLocal(PlainModel(id: 'c', name: 'Gamma', value: 3));

      // Act
      final result = await repo.fetchAllFromLocalWithoutPendingSyncOps();

      // Assert: all 3 returned
      expect(result.length, equals(3));
      expect(result.map((m) => m.id).toSet(), equals({'a', 'b', 'c'}));
    });

    // -----------------------------------------------------------------------

    test('excludes items that have pending sync operations', () async {
      // Arrange: save 3 items locally
      await repo.saveToLocal(PlainModel(id: 'a', name: 'Alpha', value: 1));
      await repo.saveToLocal(PlainModel(id: 'b', name: 'Beta', value: 2));
      await repo.saveToLocal(PlainModel(id: 'c', name: 'Gamma', value: 3));

      // Add pending create ops for 'a' and 'c'
      final syncQueueDao = SyncQueueDao(database);
      await syncQueueDao.insertItem(
        modelId: 'a',
        modelType: 'PlainModel',
        payload: '{"id":"a","name":"Alpha","value":1}',
        operation: 'create',
        idempotencyKey: 'key-a',
      );
      await syncQueueDao.insertItem(
        modelId: 'c',
        modelType: 'PlainModel',
        payload: '{"id":"c","name":"Gamma","value":3}',
        operation: 'update',
        idempotencyKey: 'key-c',
      );

      // Act
      final result = await repo.fetchAllFromLocalWithoutPendingSyncOps();

      // Assert: only 'b' returned (no pending ops)
      expect(result.length, equals(1));
      expect(result.first.id, equals('b'));
    });

    // -----------------------------------------------------------------------

    test('includes items whose only sync ops are "dead"', () async {
      // Arrange: 2 items
      await repo.saveToLocal(PlainModel(id: 'a', name: 'Alpha', value: 1));
      await repo.saveToLocal(PlainModel(id: 'b', name: 'Beta', value: 2));

      // 'a' has a dead op (should NOT be excluded — dead = already processed)
      final syncQueueDao = SyncQueueDao(database);
      final taskId = await syncQueueDao.insertItem(
        modelId: 'a',
        modelType: 'PlainModel',
        payload: '{"id":"a","name":"Alpha","value":1}',
        operation: 'create',
        idempotencyKey: 'key-a-dead',
      );
      // Mark that task dead
      await syncQueueDao.markTaskAsDead(taskId, 'simulated permanent failure');

      // Act
      final result = await repo.fetchAllFromLocalWithoutPendingSyncOps();

      // Assert: both 'a' and 'b' are returned (dead ops don't block)
      expect(result.length, equals(2));
      expect(result.map((m) => m.id).toSet(), equals({'a', 'b'}));
    });

    // -----------------------------------------------------------------------

    test('pagination via queryParams is applied at SQL level (not post-filter)',
        () async {
      // Arrange: 5 items, 2 of them pending
      for (var i = 1; i <= 5; i++) {
        await repo.saveToLocal(
          PlainModel(id: 'item-$i', name: 'Item $i', value: i),
        );
      }

      final syncQueueDao = SyncQueueDao(database);
      // Mark item-1 and item-2 as pending
      await syncQueueDao.insertItem(
        modelId: 'item-1',
        modelType: 'PlainModel',
        payload: '{"id":"item-1"}',
        operation: 'create',
        idempotencyKey: 'key-1',
      );
      await syncQueueDao.insertItem(
        modelId: 'item-2',
        modelType: 'PlainModel',
        payload: '{"id":"item-2"}',
        operation: 'create',
        idempotencyKey: 'key-2',
      );
      // item-3, item-4, item-5 are clean

      // Act: request limit=2 sorted ascending by value
      const queryParams = QueryParams(
        sorts: [
          SortCondition(
            field: PlainModelFields.value,
            direction: SortDirection.ascending,
          ),
        ],
        pagination: PaginationParams(limit: 2, offset: 0),
      );

      final result = await repo.fetchAllFromLocalWithoutPendingSyncOps(
        queryParams: queryParams,
      );

      // Assert: pagination applied on the 3 clean items (item-3, 4, 5),
      // so limit=2 yields item-3 and item-4
      expect(result.length, equals(2));
      final ids = result.map((m) => m.id).toList();
      expect(ids, equals(['item-3', 'item-4']));
    });

    // -----------------------------------------------------------------------

    test('only excludes pending ops for this model type, not others', () async {
      // Arrange: 2 PlainModel items
      await repo.saveToLocal(PlainModel(id: 'a', name: 'Alpha', value: 1));
      await repo.saveToLocal(PlainModel(id: 'b', name: 'Beta', value: 2));

      // Add pending op for a DIFFERENT model type with id 'a'
      final syncQueueDao = SyncQueueDao(database);
      await syncQueueDao.insertItem(
        modelId: 'a',
        modelType: 'SomeOtherModel', // different model type
        payload: '{"id":"a"}',
        operation: 'create',
        idempotencyKey: 'key-other',
      );

      // Act
      final result = await repo.fetchAllFromLocalWithoutPendingSyncOps();

      // Assert: both returned because the pending op is for a different type
      expect(result.length, equals(2));
      expect(result.map((m) => m.id).toSet(), equals({'a', 'b'}));
    });
  });
}

class _TestRepo extends SynquillRepositoryBase<PlainModel>
    with RepositoryHelpersMixin<PlainModel> {
  final MockPlainModelApiAdapter _mockAdapter;
  late final PlainModelDao _dao;

  _TestRepo(super.db, this._mockAdapter) {
    _dao = PlainModelDao(db as SynquillDatabase);
  }

  @override
  ApiAdapterBase<PlainModel> get apiAdapter => _mockAdapter;

  @override
  DatabaseAccessor<GeneratedDatabase> get dao => _dao;

  @override
  bool get localOnly => false;

  @override
  Future<PlainModel?> fetchFromRemote(
    String id, {
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async =>
      _mockAdapter.findOne(id, queryParams: queryParams);

  @override
  Future<List<PlainModel>> fetchAllFromRemote({
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async =>
      _mockAdapter.findAll(queryParams: queryParams);
}
