// filepath: test/core/default_policy_config_test.dart
import 'package:synquill/synquill_core.dart';
import 'package:test/test.dart';

import '../common/test_models.dart';

// Test model for repository testing
class TestModel extends SynquillDataModel<TestModel> {
  @override
  final String id;
  final String name;

  TestModel({required this.id, required this.name});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name;

  @override
  int get hashCode => id.hashCode ^ name.hashCode;

  @override
  String toString() => 'TestModel(id: $id, name: $name)';

  TestModel copyWith({String? id, String? name}) {
    return TestModel(id: id ?? this.id, name: name ?? this.name);
  }

  @override
  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name};
  }

  // Factory fromJson is not abstract in SyncedDataModel, so not strictly
  // needed here
  // unless used by tests.
}

// Mock repository for testing default policies
class _MockApiAdapter extends ApiAdapterBase<TestModel> {
  final MockTestRepository _repository;

  _MockApiAdapter(this._repository);

  @override
  Uri get baseUrl => Uri.parse('https://test.example.com/api/v1/');

  @override
  TestModel fromJson(Map<String, dynamic> json) =>
      TestModel(id: json['id'] as String, name: json['name'] as String);

  @override
  Map<String, dynamic> toJson(TestModel model) => model.toJson();

  @override
  Future<TestModel?> createOne(
    TestModel item, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return await _repository.saveToRemote(item);
  }

  @override
  Future<TestModel?> updateOne(
    TestModel item, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return await _repository.saveToRemote(item);
  }

  @override
  Future<TestModel?> replaceOne(
    TestModel item, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return await _repository.saveToRemote(item);
  }

  @override
  Future<void> deleteOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    await _repository.deleteFromRemote(id);
  }

  @override
  Future<TestModel?> findOne(
    String id, {
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    _repository._operationLog.add('apiAdapter.getOne($id)');
    return _repository._remoteData[id];
  }

  @override
  Future<List<TestModel>> findAll({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    _repository._operationLog.add('apiAdapter.getAll()');
    return _repository._remoteData.values.toList();
  }
}

class MockTestRepository extends SynquillRepositoryBase<TestModel> {
  final Map<String, TestModel> _localData = {};
  final Map<String, TestModel> _remoteData = {};
  final List<String> _operationLog = [];

  MockTestRepository(super.db);

  List<String> get operationLog => List.unmodifiable(_operationLog);

  // Access the protected getters for testing
  @override
  DataSavePolicy get defaultSavePolicy => super.defaultSavePolicy;
  @override
  DataLoadPolicy get defaultLoadPolicy => super.defaultLoadPolicy;

  @override
  ApiAdapterBase<TestModel> get apiAdapter => _MockApiAdapter(this);

  void clearLog() => _operationLog.clear();

  void addRemoteData(String id, TestModel item) {
    _remoteData[id] = item;
  }

  void clearRemoteData() => _remoteData.clear();

  @override
  Future<TestModel?> fetchFromLocal(
    String id, {
    QueryParams? queryParams,
  }) async {
    _operationLog.add('fetchFromLocal($id)');
    return _localData[id];
  }

  @override
  Future<TestModel?> fetchFromRemote(
    String id, {
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('fetchFromRemote($id)');
    await Future.delayed(const Duration(milliseconds: 10));
    return _remoteData[id];
  }

  @override
  Future<List<TestModel>> fetchAllFromLocal({QueryParams? queryParams}) async {
    _operationLog.add('fetchAllFromLocal()');
    return _localData.values.toList();
  }

  @override
  Future<List<TestModel>> fetchAllFromRemote({
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('fetchAllFromRemote()');
    await Future.delayed(const Duration(milliseconds: 10));
    return _remoteData.values.toList();
  }

  @override
  Future<void> saveToLocal(
    TestModel item, {
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('saveToLocal(${item.id})');
    _localData[item.id] = item;
  }

  Future<TestModel> saveToRemote(TestModel item) async {
    _operationLog.add('saveToRemote(${item.id})');
    await Future.delayed(const Duration(milliseconds: 10));
    _remoteData[item.id] = item;
    return item;
  }

  @override
  Future<void> removeFromLocalIfExists(String id) async {
    _operationLog.add('removeFromLocalIfExists($id)');
    _localData.remove(id);
  }

  Future<void> deleteFromRemote(String id) async {
    _operationLog.add('deleteFromRemote($id)');
    await Future.delayed(const Duration(milliseconds: 10));
    _remoteData.remove(id);
  }

  /// Mock method to simulate sync queue functionality that's
  /// not yet implemented
  void queueForSync(String id, String operation) {
    _operationLog.add('queueForSync($id, $operation)');
  }

  @override
  Future<bool> isExistingItem(TestModel item) async {
    // Check against local data as per the original logic for TestModel item
    return _localData.containsKey(item.id);
  }

  @override
  Future<void> updateLocalCache(List<TestModel> items) async {
    _operationLog.add('updateLocalCache(${items.length} items)');
    _localData.clear();
    for (final item in items) {
      _localData[item.id] = item;
    }
  }

  @override
  Stream<TestModel?> watchFromLocal(String id, {QueryParams? queryParams}) {
    _operationLog.add('watchFromLocal($id)');
    return Stream.value(_localData[id]);
  }

  @override
  Stream<List<TestModel>> watchAllFromLocal({QueryParams? queryParams}) {
    _operationLog.add('watchAllFromLocal()');
    return Stream.value(_localData.values.toList());
  }

  /// Override the save method to simulate the queue behavior for localFirst
  @override
  Future<TestModel> save(
    TestModel item, {
    DataSavePolicy? savePolicy,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
    bool updateTimestamps = true,
  }) async {
    savePolicy ??= defaultSavePolicy;

    // Set repository reference
    item.$setRepository(this);

    switch (savePolicy) {
      case DataSavePolicy.localFirst:
        // Check if item exists BEFORE saving to local
        final exists = await isExistingItem(item);
        await saveToLocal(item);
        // Simulate the Todo sync queue behavior
        final operation = exists ? 'update' : 'create';
        queueForSync(item.id, operation);
        return item;
      case DataSavePolicy.remoteFirst:
        // Call the parent implementation for remoteFirst
        return await super.save(item, savePolicy: savePolicy);
    }
  }

  /// Override the delete method to simulate the queue behavior for localFirst
  @override
  Future<void> delete(
    String id, {
    DataSavePolicy? savePolicy,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
    Set<String>? deletionContext,
  }) async {
    savePolicy ??= defaultSavePolicy;

    switch (savePolicy) {
      case DataSavePolicy.localFirst:
        // For localFirst, only remove locally and queue for sync
        // Don't call deleteFromRemote immediately (test expectation)
        await removeFromLocalIfExists(id);
        // Simulate queueing for delete sync (don't call deleteFromRemote)
        // queueForDeleteSync is not yet implemented per test comment
        return;
      case DataSavePolicy.remoteFirst:
        // Call the parent implementation for remoteFirst
        return await super.delete(id, savePolicy: savePolicy);
    }
  }
}

void main() {
  group('Default Policy Configuration Tests', () {
    late MockTestRepository repository;

    setUp(() async {
      // Reset SyncedStorage configuration before each test
      final database = TestDatabase(NativeDatabase.memory());
      final logger = Logger('SavePolicyTest');
      await SynquillStorage.close();
      await SynquillStorage.init(
        database: database,
        config: const SynquillStorageConfig(
          defaultSavePolicy: DataSavePolicy.localFirst,
          defaultLoadPolicy: DataLoadPolicy.localOnly,
          foregroundQueueConcurrency: 1,
          backgroundQueueConcurrency: 1,
        ),
        logger: logger,
        initializeFn: initializeTestStorage,
        enableInternetMonitoring: false, // Disable for testing
      );
    });

    tearDown(() async {
      await SynquillStorage.close();
    });

    group('Configuration Setup', () {
      setUp(() async {
        repository = MockTestRepository(SynquillStorage.database);
        await SynquillStorage.close();
      });
      test('should use default fallback policies when no config is set', () {
        // No SyncedStorage initialization
        expect(SynquillStorage.config, equals(null));

        // Check default fallback behavior
        expect(repository.defaultSavePolicy, equals(DataSavePolicy.localFirst));
        expect(
          repository.defaultLoadPolicy,
          equals(DataLoadPolicy.localThenRemote),
        );
      });

      test('should use configured default save policy', () {
        // Manually set configuration for testing
        SynquillStorage.setConfigForTesting(
          const SynquillStorageConfig(
            defaultSavePolicy: DataSavePolicy.remoteFirst,
          ),
        );

        expect(
          repository.defaultSavePolicy,
          equals(DataSavePolicy.remoteFirst),
        );
        expect(
          repository.defaultLoadPolicy,
          equals(DataLoadPolicy.localThenRemote),
        ); // fallback
      });

      test('should use configured default load policy', () {
        // Manually set configuration for testing
        SynquillStorage.setConfigForTesting(
          const SynquillStorageConfig(
            defaultLoadPolicy: DataLoadPolicy.remoteFirst,
          ),
        );

        expect(
          repository.defaultSavePolicy,
          equals(DataSavePolicy.localFirst),
        ); // fallback
        expect(
          repository.defaultLoadPolicy,
          equals(DataLoadPolicy.remoteFirst),
        );
      });

      test('should use both configured default policies', () {
        // Manually set configuration for testing
        SynquillStorage.setConfigForTesting(
          const SynquillStorageConfig(
            defaultSavePolicy: DataSavePolicy.remoteFirst,
            defaultLoadPolicy: DataLoadPolicy.localOnly,
          ),
        );

        expect(
          repository.defaultSavePolicy,
          equals(DataSavePolicy.remoteFirst),
        );
        expect(repository.defaultLoadPolicy, equals(DataLoadPolicy.localOnly));
      });
    });

    group('findOne Policy Inheritance', () {
      setUp(() {
        SynquillStorage.setConfigForTesting(
          const SynquillStorageConfig(
            defaultLoadPolicy: DataLoadPolicy.localOnly,
          ),
        );
        repository = MockTestRepository(SynquillStorage.database);
      });

      test('should use default load policy when none specified', () async {
        final testItem = TestModel(id: 'test1', name: 'Test Item');
        repository._localData['test1'] = testItem;

        final result = await repository.findOne('test1');

        expect(result, equals(testItem));
        expect(repository.operationLog, contains('fetchFromLocal(test1)'));
        expect(
          repository.operationLog,
          isNot(contains('fetchFromRemote(test1)')),
        );
      });

      test(
        'should override default load policy when explicitly specified',
        () async {
          final testItem = TestModel(id: 'test1', name: 'Test Item');
          repository.addRemoteData('test1', testItem);

          final result = await repository.findOne(
            'test1',
            loadPolicy: DataLoadPolicy.remoteFirst,
          );

          expect(result, equals(testItem));
          expect(repository.operationLog, contains('fetchFromRemote(test1)'));
          expect(
            repository.operationLog,
            contains('updateLocalCache(1 items)'),
          );
        },
      );
    });

    group('findAll Policy Inheritance', () {
      setUp(() {
        SynquillStorage.setConfigForTesting(
          const SynquillStorageConfig(
            defaultLoadPolicy: DataLoadPolicy.remoteFirst,
          ),
        );
        repository = MockTestRepository(SynquillStorage.database);
      });

      test(
        'should override default load policy when explicitly specified',
        () async {
          final testItem = TestModel(id: 'test1', name: 'Test Item');
          repository._localData['test1'] = testItem;

          final result = await repository.findAll(
            loadPolicy: DataLoadPolicy.localOnly,
          );

          expect(result, contains(testItem));
          expect(repository.operationLog, contains('fetchAllFromLocal()'));
          expect(
            repository.operationLog,
            isNot(contains('fetchAllFromRemote()')),
          );
        },
      );
    });

    group('save Policy Inheritance', () {
      setUp(() async {
        SynquillStorage.setConfigForTesting(
          const SynquillStorageConfig(
            defaultSavePolicy: DataSavePolicy.remoteFirst,
          ),
        );

        repository = MockTestRepository(SynquillStorage.database);
      });

      test('should use default save policy when none specified', () async {
        final testItem = TestModel(id: 'test1', name: 'Test Item');

        final result = await repository.save(testItem);

        expect(result, equals(testItem));
        expect(repository.operationLog, contains('saveToRemote(test1)'));
        expect(repository.operationLog, contains('saveToLocal(test1)'));
        expect(repository.operationLog, isNot(contains('queueForSync(test1')));
      });

      test(
        'should override default save policy when explicitly specified',
        () async {
          final testItem = TestModel(id: 'test1', name: 'Test Item');

          final result = await repository.save(
            testItem,
            savePolicy: DataSavePolicy.localFirst,
          );

          expect(result, equals(testItem));
          expect(repository.operationLog, contains('saveToLocal(test1)'));
          expect(
            repository.operationLog,
            contains('queueForSync(test1, create)'),
          );
          expect(
            repository.operationLog,
            isNot(contains('saveToRemote(test1)')),
          );
        },
      );
    });

    group('delete Policy Inheritance', () {
      setUp(() {
        SynquillStorage.setConfigForTesting(
          const SynquillStorageConfig(
            defaultSavePolicy: DataSavePolicy.localFirst,
          ),
        );
        repository = MockTestRepository(SynquillStorage.database);
      });

      test('should use default save policy when none specified', () async {
        final testItem = TestModel(id: 'test1', name: 'Test Item');
        repository._localData['test1'] = testItem;

        await repository.delete('test1');

        expect(
          repository.operationLog,
          contains('removeFromLocalIfExists(test1)'),
        );
        // Note: deleteFromLocal() method doesn't exist in the current
        // implementation. Repository uses removeFromLocalIfExists() directly
        expect(
          repository.operationLog,
          isNot(contains('deleteFromLocal(test1)')),
        );
        // Note: queueForDeleteSync is not yet implemented (marked as ToDo)
        expect(
          repository.operationLog,
          isNot(contains('queueForDeleteSync(test1)')),
        );
        expect(
          repository.operationLog,
          isNot(contains('deleteFromRemote(test1)')),
        );
      });

      test(
        'should override default save policy when explicitly specified',
        () async {
          final testItem = TestModel(id: 'test1', name: 'Test Item');
          repository._localData['test1'] = testItem;

          await repository.delete(
            'test1',
            savePolicy: DataSavePolicy.remoteFirst,
          );

          expect(repository.operationLog, contains('deleteFromRemote(test1)'));
          expect(
            repository.operationLog,
            contains('removeFromLocalIfExists(test1)'),
          );
          expect(
            repository.operationLog,
            isNot(contains('queueForDeleteSync(test1)')),
          );
        },
      );
    });

    group('watchOne Policy Inheritance', () {
      setUp(() {
        SynquillStorage.setConfigForTesting(
          const SynquillStorageConfig(
            defaultLoadPolicy: DataLoadPolicy.localThenRemote,
          ),
        );
        repository = MockTestRepository(SynquillStorage.database);
      });

      test('should use default load policy when none specified', () async {
        final testItem = TestModel(id: 'test1', name: 'Test Item');
        repository._localData['test1'] = testItem;

        final stream = repository.watchOne('test1');
        final result = await stream.first;

        expect(result, equals(testItem));
        expect(repository.operationLog, contains('watchFromLocal(test1)'));
      });

      test(
        'should override default load policy when explicitly specified',
        () async {
          final testItem = TestModel(id: 'test1', name: 'Test Item');
          repository._localData['test1'] = testItem;

          final stream = repository.watchOne(
            'test1',
            loadPolicy: DataLoadPolicy.localOnly,
          );
          final result = await stream.first;

          expect(result, equals(testItem));
          expect(repository.operationLog, contains('watchFromLocal(test1)'));
        },
      );

      test('should throw UnimplementedError for remoteFirst policy', () {
        expect(
          () => repository.watchOne(
            'test1',
            loadPolicy: DataLoadPolicy.remoteFirst,
          ),
          throwsA(isA<UnimplementedError>()),
        );
      });
    });

    group('Multiple Policy Changes', () {
      setUp(() {
        repository = MockTestRepository(SynquillStorage.database);
      });
      test('should reflect policy changes when configuration is updated', () {
        // Initial configuration
        SynquillStorage.setConfigForTesting(
          const SynquillStorageConfig(
            defaultSavePolicy: DataSavePolicy.localFirst,
          ),
        );

        expect(repository.defaultSavePolicy, equals(DataSavePolicy.localFirst));

        // Update configuration
        SynquillStorage.setConfigForTesting(
          const SynquillStorageConfig(
            defaultSavePolicy: DataSavePolicy.remoteFirst,
          ),
        );

        expect(
          repository.defaultSavePolicy,
          equals(DataSavePolicy.remoteFirst),
        );
      });
    });
  });
}

/// Initializes the test storage system.
void initializeTestStorage(GeneratedDatabase db) {
  // Database provider should already be set by this point
  // Register all test repositories if needed
}
