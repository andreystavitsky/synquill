import 'dart:async';

import 'package:synquill/synquill_core.dart';
import 'package:test/test.dart';

import '../common/test_models.dart';

void main() {
  group('Repository realtime operations', () {
    late TestDatabase database;
    late _RealtimeAdapter adapter;
    late _RealtimeRepository repository;

    setUp(() async {
      database = TestDatabase(NativeDatabase.memory());
      SynquillStorage.setConfigForTesting(
        const SynquillStorageConfig(
          initialRetryDelay: Duration(milliseconds: 1),
          maxRetryDelay: Duration(milliseconds: 2),
          minRetryDelay: Duration(milliseconds: 1),
          jitterPercent: 0,
        ),
      );
      await SynquillStorage.init(
        database: database,
        config: SynquillStorage.config,
        enableInternetMonitoring: false,
      );
      adapter = _RealtimeAdapter();
      repository = _RealtimeRepository(database, adapter);
    });

    tearDown(() async {
      await repository.disposeRealtimeSubscriptions();
      await SynquillStorage.close();
    });

    test('watchRemote false keeps local watch behavior', () async {
      repository.addLocal(TestUser(
        id: '1',
        name: 'Local',
        email: 'local@example.com',
      ));

      final values = <List<TestUser>>[];
      final subscription = repository.watchAll().listen(values.add);
      await pumpEventQueue();

      expect(values.single.map((user) => user.name), ['Local']);
      expect(adapter.subscribeCallCount, 0);

      await subscription.cancel();
    });

    test('watchRemote true requires a realtime adapter', () {
      final unsupported = _LocalOnlyRepository(database);

      expect(
        () => unsupported.watchAll(watchRemote: true),
        throwsA(isA<SynquillStorageException>()),
      );
    });

    test('created, updated, and upserted events update local watchers',
        () async {
      final values = <List<TestUser>>[];
      final subscription = repository
          .watchAll(watchRemote: true)
          .listen((items) => values.add(List<TestUser>.from(items)));
      await pumpEventQueue();

      adapter.emit(RealtimeEvent(
        type: RealtimeEventType.created,
        id: '1',
        item: TestUser(id: '1', name: 'Created', email: 'a@example.com'),
      ));
      await pumpEventQueue();

      adapter.emit(RealtimeEvent(
        type: RealtimeEventType.updated,
        id: '1',
        item: TestUser(id: '1', name: 'Updated', email: 'b@example.com'),
      ));
      await pumpEventQueue();

      adapter.emit(RealtimeEvent(
        type: RealtimeEventType.upserted,
        id: '2',
        item: TestUser(id: '2', name: 'Upserted', email: 'c@example.com'),
      ));
      await pumpEventQueue();

      expect(values.last.map((user) => user.name).toSet(), {
        'Updated',
        'Upserted',
      });

      await subscription.cancel();
    });

    test('deleted events remove local cache entries', () async {
      await repository.saveToLocal(TestUser(
        id: '1',
        name: 'Cached',
        email: 'cached@example.com',
      ));

      final values = <List<TestUser>>[];
      final subscription = repository
          .watchAll(watchRemote: true)
          .listen((items) => values.add(List<TestUser>.from(items)));
      await pumpEventQueue();

      adapter.emit(const RealtimeEvent(
        type: RealtimeEventType.deleted,
        id: '1',
      ));
      await pumpEventQueue();

      expect(repository.localById('1'), isNull);
      expect(values.last, isEmpty);

      await subscription.cancel();
    });

    test('pending sync task blocks incoming realtime event', () async {
      await repository.saveToLocal(TestUser(
        id: '1',
        name: 'Pending local',
        email: 'local@example.com',
      ));
      await SyncQueueDao(database).insertItem(
        modelId: '1',
        modelType: 'TestUser',
        payload:
            '{"id":"1","name":"Pending local","email":"local@example.com"}',
        operation: 'update',
        idempotencyKey: 'pending-1',
      );

      final values = <List<TestUser>>[];
      final subscription = repository
          .watchAll(watchRemote: true)
          .listen((items) => values.add(List<TestUser>.from(items)));
      await pumpEventQueue();

      adapter.emit(RealtimeEvent(
        type: RealtimeEventType.updated,
        id: '1',
        item: TestUser(id: '1', name: 'Remote', email: 'remote@example.com'),
      ));
      await pumpEventQueue();

      expect(repository.localById('1')!.name, 'Pending local');
      expect(values.last.single.name, 'Pending local');

      await subscription.cancel();
    });

    test('identical remote watches share one subscription', () async {
      final first = repository.watchAll(
        watchRemote: true,
        headers: {'Authorization': 'Bearer token'},
      ).listen((_) {});
      final second = repository.watchAll(
        watchRemote: true,
        headers: {'Authorization': 'Bearer token'},
      ).listen((_) {});
      await pumpEventQueue();

      expect(adapter.subscribeCallCount, 1);

      await first.cancel();
      expect(adapter.cancelCount, 0);

      await second.cancel();
      expect(adapter.cancelCount, 1);
    });

    test('headers and extra use canonical sorted signatures for dedupe',
        () async {
      final first = repository.watchAll(
        watchRemote: true,
        headers: {'b': '2', 'a': '1'},
        extra: {
          'nested': {'z': 2, 'a': 1},
        },
      ).listen((_) {});
      final second = repository.watchAll(
        watchRemote: true,
        headers: {'a': '1', 'b': '2'},
        extra: {
          'nested': {'a': 1, 'z': 2},
        },
      ).listen((_) {});
      await pumpEventQueue();

      expect(adapter.subscribeCallCount, 1);

      await first.cancel();
      await second.cancel();
    });

    test('different query params create distinct subscriptions', () async {
      final active = QueryParams(
        filters: [TestUserFields.name.equals('active')],
      );
      final archived = QueryParams(
        filters: [TestUserFields.name.equals('archived')],
      );

      final first = repository
          .watchAll(watchRemote: true, queryParams: active)
          .listen((_) {});
      final second = repository
          .watchAll(watchRemote: true, queryParams: archived)
          .listen((_) {});
      await pumpEventQueue();

      expect(adapter.subscribeCallCount, 2);

      await first.cancel();
      await second.cancel();
    });

    test('retriable transport error restarts without closing local stream',
        () async {
      adapter.failNextSubscriptions = 1;

      final errors = <Object>[];
      final changes = <RepositoryChange<TestUser>>[];
      final changeSubscription = repository.changes.listen(changes.add);
      final watchSubscription = repository
          .watchAll(
            watchRemote: true,
            retryOnFail: true,
          )
          .listen((_) {}, onError: errors.add);

      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(adapter.subscribeCallCount, greaterThanOrEqualTo(2));
      expect(errors, isEmpty);
      expect(changes.where((change) => change.isRealtimeError), isNotEmpty);
      expect(
        changes.where((change) => change.isRetriable == true),
        isNotEmpty,
      );

      await watchSubscription.cancel();
      await changeSubscription.cancel();
    });

    test('fatal transport error emits non-retriable change without retry',
        () async {
      adapter
        ..failNextSubscriptions = 1
        ..failNextError = ApiException('subscription denied', statusCode: 403);

      final changes = <RepositoryChange<TestUser>>[];
      final changeSubscription = repository.changes.listen(changes.add);
      final watchSubscription = repository
          .watchAll(
            watchRemote: true,
            retryOnFail: true,
          )
          .listen((_) {});

      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(adapter.subscribeCallCount, 1);
      expect(changes.where((change) => change.isRealtimeError), isNotEmpty);
      expect(
        changes.where((change) => change.isRetriable == false),
        isNotEmpty,
      );

      await watchSubscription.cancel();
      await changeSubscription.cancel();
    });

    test('watchRemote is orthogonal to localThenRemote initial refresh',
        () async {
      adapter.remote['1'] = TestUser(
        id: '1',
        name: 'Remote snapshot',
        email: 'remote@example.com',
      );

      final subscription = repository
          .watchOne(
            '1',
            loadPolicy: DataLoadPolicy.localThenRemote,
            watchRemote: true,
          )
          .listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(adapter.findOneCallCount, 1);
      expect(adapter.subscribeCallCount, 1);

      await subscription.cancel();
    });

    test('repository realtime dispose cancels active subscriptions', () async {
      final subscription =
          repository.watchAll(watchRemote: true).listen((_) {});
      await pumpEventQueue();

      await repository.disposeRealtimeSubscriptions();

      expect(adapter.cancelCount, 1);

      await subscription.cancel();
    });

    test('storage close cancels cached repository subscriptions', () async {
      final registeredAdapter = _RealtimeAdapter();
      SynquillRepositoryProvider.register<TestUser>(
        (db) => _RealtimeRepository(db, registeredAdapter),
      );
      final cachedRepository =
          SynquillRepositoryProvider.getFrom<TestUser>(database);
      final subscription =
          cachedRepository.watchAll(watchRemote: true).listen((_) {});
      await pumpEventQueue();

      await SynquillStorage.close();

      expect(registeredAdapter.cancelCount, 1);

      await subscription.cancel();
    });

    test('obliterateLocalStorage cancels cached repository subscriptions',
        () async {
      final registeredAdapter = _RealtimeAdapter();
      SynquillRepositoryProvider.register<TestUser>(
        (db) => _RealtimeRepository(db, registeredAdapter),
      );
      final cachedRepository =
          SynquillRepositoryProvider.getFrom<TestUser>(database);
      final subscription =
          cachedRepository.watchAll(watchRemote: true).listen((_) {});
      await pumpEventQueue();

      await SynquillStorage.instance.obliterateLocalStorage();

      expect(registeredAdapter.cancelCount, 1);

      await subscription.cancel();
    });

    test(
        'deduplicates active subscriptions for identical query parameters '
        'and maps with different key orderings', () async {
      final subscription1 = repository.watchAll(
        watchRemote: true,
        extra: {
          'nested': {'b': 2, 'a': 1},
          'c': 3,
        },
      ).listen((_) {});
      await pumpEventQueue();

      final subscription2 = repository.watchAll(
        watchRemote: true,
        extra: {
          'c': 3,
          'nested': {'a': 1, 'b': 2},
        },
      ).listen((_) {});
      await pumpEventQueue();

      // Should only establish one remote subscription because keys are
      // canonicalized identically.
      expect(adapter.subscribeCallCount, 1);

      await subscription1.cancel();
      await subscription2.cancel();
    });

    test(
        'created and updated events execute inside db transactions, while '
        'deleted events execute outside', () async {
      final trackingDb = TransactionTrackingDatabase(NativeDatabase.memory());
      // Re-initialize SynquillStorage with tracking database
      await SynquillStorage.close();
      await SynquillStorage.init(
        database: trackingDb,
        config: SynquillStorage.config,
        enableInternetMonitoring: false,
      );

      final trackingRepository = _RealtimeRepository(trackingDb, adapter);
      final subscription = trackingRepository
          .watchAll(watchRemote: true)
          .listen((_) {});
      await pumpEventQueue();

      // Reset transaction counter
      trackingDb.transactionCallCount = 0;

      // 1. Emit a created event (should use transaction)
      adapter.emit(RealtimeEvent(
        type: RealtimeEventType.created,
        id: '20',
        item: TestUser(id: '20', name: 'User 20', email: 'user20@example.com'),
      ));
      await pumpEventQueue();

      expect(trackingDb.transactionCallCount, 1);

      // 2. Emit a deleted event (should NOT use transaction)
      adapter.emit(const RealtimeEvent(
        type: RealtimeEventType.deleted,
        id: '20',
      ));
      await pumpEventQueue();

      // Transaction count should still be 1 (meaning delete executed outside)
      expect(trackingDb.transactionCallCount, 1);

      await subscription.cancel();
    });
  });
}

class TransactionTrackingDatabase extends TestDatabase {
  TransactionTrackingDatabase(super.e);

  int transactionCallCount = 0;

  @override
  Future<T> transaction<T>(Future<T> Function() action,
      {bool requireNew = false}) {
    transactionCallCount++;
    return super.transaction(action, requireNew: requireNew);
  }
}

class TestUserFields {
  static const name = FieldSelector<String>('name', String);
}

class _RealtimeAdapter extends ApiAdapterBase<TestUser>
    implements RealtimeApiAdapter<TestUser> {
  final remote = <String, TestUser>{};
  final _controllers = <StreamController<RealtimeEvent<TestUser>>>[];
  int subscribeCallCount = 0;
  int cancelCount = 0;
  int findOneCallCount = 0;
  int failNextSubscriptions = 0;
  Object? failNextError;

  @override
  Uri get baseUrl => Uri.parse('https://example.com');

  @override
  TestUser fromJson(Map<String, dynamic> json) {
    return TestUser(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson(TestUser model) => model.toJson();

  @override
  Stream<RealtimeEvent<TestUser>> subscribeEvents({
    String? id,
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) {
    subscribeCallCount++;
    if (failNextSubscriptions > 0) {
      failNextSubscriptions--;
      return Stream<RealtimeEvent<TestUser>>.error(
        failNextError ?? NetworkException('temporary disconnect'),
      );
    }

    final controller = StreamController<RealtimeEvent<TestUser>>(
      onCancel: () {
        cancelCount++;
      },
    );
    _controllers.add(controller);
    return controller.stream;
  }

  void emit(RealtimeEvent<TestUser> event) {
    for (final controller in List.of(_controllers)) {
      if (!controller.isClosed) {
        controller.add(event);
      }
    }
  }

  @override
  Future<TestUser?> findOne(
    String id, {
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    findOneCallCount++;
    return remote[id];
  }

  @override
  Future<List<TestUser>> findAll({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    return remote.values.toList();
  }

  @override
  Future<TestUser?> createOne(
    TestUser model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    remote[model.id] = model;
    return model;
  }

  @override
  Future<TestUser?> updateOne(
    TestUser model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    remote[model.id] = model;
    return model;
  }

  @override
  Future<TestUser?> replaceOne(
    TestUser model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    remote[model.id] = model;
    return model;
  }

  @override
  Future<void> deleteOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    remote.remove(id);
  }
}

class _PlainAdapter extends ApiAdapterBase<TestUser> {
  @override
  Uri get baseUrl => Uri.parse('https://example.com');

  @override
  TestUser fromJson(Map<String, dynamic> json) {
    return TestUser(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson(TestUser model) => model.toJson();

  @override
  Future<TestUser?> findOne(
    String id, {
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    return null;
  }

  @override
  Future<List<TestUser>> findAll({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    return [];
  }

  @override
  Future<TestUser?> createOne(
    TestUser model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return model;
  }

  @override
  Future<TestUser?> updateOne(
    TestUser model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return model;
  }

  @override
  Future<TestUser?> replaceOne(
    TestUser model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return model;
  }

  @override
  Future<void> deleteOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {}
}

class _RealtimeRepository extends SynquillRepositoryBase<TestUser> {
  _RealtimeRepository(super.db, this._adapter);

  final ApiAdapterBase<TestUser> _adapter;
  final _local = <String, TestUser>{};
  final _oneWatchers = <String, StreamController<TestUser?>>{};
  final _allWatcher = StreamController<List<TestUser>>.broadcast();

  @override
  ApiAdapterBase<TestUser> get apiAdapter => _adapter;

  @override
  bool get localOnly => false;

  TestUser? localById(String id) => _local[id];

  void addLocal(TestUser user) {
    _local[user.id] = user;
  }

  @override
  Future<TestUser?> fetchFromLocal(
    String id, {
    QueryParams? queryParams,
  }) async {
    return _local[id];
  }

  @override
  Future<List<TestUser>> fetchAllFromLocal({QueryParams? queryParams}) async {
    return _local.values.toList();
  }

  @override
  Future<TestUser?> fetchFromRemote(
    String id, {
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) {
    return apiAdapter.findOne(
      id,
      queryParams: queryParams,
      extra: extra,
      headers: headers,
    );
  }

  @override
  Future<List<TestUser>> fetchAllFromRemote({
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) {
    return apiAdapter.findAll(
      queryParams: queryParams,
      extra: extra,
      headers: headers,
    );
  }

  @override
  Stream<TestUser?> watchFromLocal(
    String id, {
    QueryParams? queryParams,
  }) async* {
    final controller = _oneWatchers.putIfAbsent(
      id,
      () => StreamController<TestUser?>.broadcast(),
    );
    yield _local[id];
    yield* controller.stream;
  }

  @override
  Stream<List<TestUser>> watchAllFromLocal({QueryParams? queryParams}) async* {
    yield _local.values.toList();
    yield* _allWatcher.stream;
  }

  @override
  Future<void> saveToLocal(TestUser item, {Map<String, dynamic>? extra}) async {
    _local[item.id] = item;
    _oneWatchers[item.id]?.add(item);
    _allWatcher.add(_local.values.toList());
  }

  @override
  Future<void> removeFromLocalIfExists(String id) async {
    _local.remove(id);
    _oneWatchers[id]?.add(null);
    _allWatcher.add(_local.values.toList());
  }

  @override
  Future<void> applyRealtimeDelete(
    String id, {
    RealtimeEvent<TestUser>? event,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    await removeFromLocalIfExists(id);
    changeController.add(RepositoryChange.deleted(id));
  }
}

class _LocalOnlyRepository extends _RealtimeRepository {
  _LocalOnlyRepository(TestDatabase db) : super(db, _PlainAdapter());
}
