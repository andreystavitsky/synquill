import 'dart:async';

import 'package:synquill/synquill_core.dart';

import 'package:test/test.dart';

// Mock model for testing
class TestModel extends SynquillDataModel<TestModel> {
  @override
  final String id;
  final String name;

  TestModel({required this.id, required this.name});

  @override
  TestModel fromJson(Map<String, dynamic> json) =>
      TestModel(id: json['id'], name: json['name']);

  @override
  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  @override
  String toString() => 'TestModel(id: $id, name: $name)';
}

// Simple test database
class _TestDatabase extends GeneratedDatabase {
  _TestDatabase(super.e);

  @override
  Iterable<TableInfo<Table, DataClass>> get allTables => [];

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      // Not needed for this test
    },
  );
}

// Special repository implementation that uses controllable streams for testing
class TestReactiveRepository extends SynquillRepositoryBase<TestModel> {
  final StreamController<TestModel?> _singleController;
  final StreamController<List<TestModel>> _listController;

  TestReactiveRepository(
    super.db,
    this._singleController,
    this._listController,
  );

  @override
  Future<TestModel?> findOne(
    String id, {
    DataLoadPolicy? loadPolicy,
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return TestModel(id: id, name: 'Test');
  }

  @override
  Future<List<TestModel>> findAll({
    DataLoadPolicy? loadPolicy,
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return [TestModel(id: '1', name: 'Test')];
  }

  @override
  Stream<TestModel?> watchOne(
    String id, {
    DataLoadPolicy? loadPolicy,
    QueryParams? queryParams,
  }) {
    return _singleController.stream;
  }

  @override
  Stream<List<TestModel>> watchAll({QueryParams? queryParams}) {
    return _listController.stream;
  }

  @override
  Future<TestModel> save(
    TestModel model, {
    DataSavePolicy? savePolicy,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
    bool updateTimestamps = true,
  }) async {
    return model;
  }

  @override
  Future<void> delete(
    String id, {
    Object? savePolicy,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
    Set<String>? deletionContext,
  }) async {}

  // Override protected methods
  @override
  Future<TestModel?> fetchFromLocal(
    String id, {
    QueryParams? queryParams,
  }) async {
    return TestModel(id: id, name: 'Test');
  }

  @override
  Future<List<TestModel>> fetchAllFromLocal({QueryParams? queryParams}) async {
    return [TestModel(id: '1', name: 'Test')];
  }

  @override
  Stream<TestModel?> watchFromLocal(String id, {QueryParams? queryParams}) =>
      _singleController.stream;

  @override
  Stream<List<TestModel>> watchAllFromLocal({QueryParams? queryParams}) =>
      _listController.stream;

  @override
  Future<void> saveToLocal(
    TestModel item, {
    Map<String, dynamic>? extra,
  }) async {}

  // Methods for test control
  void emitSingleItem(TestModel? model) {
    _singleController.add(model);
  }

  void emitModelList(List<TestModel> models) {
    _listController.add(models);
  }
}

void main() {
  group('SyncedRepository Reactive Data Tests', () {
    late _TestDatabase db;
    late StreamController<TestModel?> singleController;
    late StreamController<List<TestModel>> listController;
    late TestReactiveRepository repository;

    setUp(() {
      // Create in-memory database for testing
      db = _TestDatabase(NativeDatabase.memory());

      // Create broadcast controllers for testing streams
      singleController = StreamController<TestModel?>.broadcast();
      listController = StreamController<List<TestModel>>.broadcast();

      // Create repository with controlled streams
      repository = TestReactiveRepository(db, singleController, listController);
    });

    tearDown(() async {
      await singleController.close();
      await listController.close();
      await db.close();
    });

    test('watchOne() should emit updated values when model changes', () async {
      const String testId = 'test-123';

      // Collect emitted values into a list
      final emittedValues = <TestModel?>[];
      final subscription = repository
          .watchOne(testId)
          .listen(emittedValues.add);

      // Emit initial value
      repository.emitSingleItem(TestModel(id: testId, name: 'Initial'));

      // Wait for stream events to be processed
      await Future.delayed(Duration.zero);

      // Emit updated value
      repository.emitSingleItem(TestModel(id: testId, name: 'Updated'));

      // Wait for stream events to be processed
      await Future.delayed(Duration.zero);

      // Clean up
      await subscription.cancel();

      // Verify both values were emitted in the correct order
      expect(emittedValues, hasLength(2));
      expect(emittedValues[0]?.name, equals('Initial'));
      expect(emittedValues[1]?.name, equals('Updated'));
    });

    test(
      'watchAll() should emit updated collections when models change',
      () async {
        // Collect emitted collections into a list
        final emittedCollections = <List<TestModel>>[];
        final subscription = repository.watchAll().listen(
          emittedCollections.add,
        );

        // Emit initial collection
        repository.emitModelList([
          TestModel(id: '1', name: 'First'),
          TestModel(id: '2', name: 'Second'),
        ]);

        // Wait for stream events to be processed
        await Future.delayed(Duration.zero);

        // Emit updated collection with a new item
        repository.emitModelList([
          TestModel(id: '1', name: 'First'),
          TestModel(id: '2', name: 'Second'),
          TestModel(id: '3', name: 'Third'),
        ]);

        // Wait for stream events to be processed
        await Future.delayed(Duration.zero);

        // Clean up
        await subscription.cancel();

        // Verify both collections were emitted in the correct order
        expect(emittedCollections, hasLength(2));
        expect(emittedCollections[0], hasLength(2));
        expect(emittedCollections[1], hasLength(3));
        expect(emittedCollections[1][2].name, equals('Third'));
      },
    );

    test('repository changes should update all watchers', () async {
      // This test verifies that multiple watchers receive the same updates
      const String testId = 'test-123';

      // Set up two watchers for the same item
      final watcher1Values = <TestModel?>[];
      final watcher2Values = <TestModel?>[];

      final subscription1 = repository
          .watchOne(testId)
          .listen(watcher1Values.add);
      final subscription2 = repository
          .watchOne(testId)
          .listen(watcher2Values.add);

      // Emit a sequence of updates
      repository.emitSingleItem(TestModel(id: testId, name: 'First Update'));
      await Future.delayed(Duration.zero);

      repository.emitSingleItem(TestModel(id: testId, name: 'Second Update'));
      await Future.delayed(Duration.zero);

      repository.emitSingleItem(null); // Test null emission (item deleted)
      await Future.delayed(Duration.zero);

      // Clean up
      await subscription1.cancel();
      await subscription2.cancel();

      // Both watchers should have received the same updates
      expect(watcher1Values, hasLength(3));
      expect(watcher2Values, hasLength(3));

      // Verify the values match in both watchers
      for (var i = 0; i < watcher1Values.length; i++) {
        expect(watcher1Values[i]?.name, equals(watcher2Values[i]?.name));
      }

      // Verify the specific values
      expect(watcher1Values[0]?.name, equals('First Update'));
      expect(watcher1Values[1]?.name, equals('Second Update'));
      expect(watcher1Values[2], null);
    });
  });
}
