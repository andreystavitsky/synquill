import 'package:synquill/synquill_core.dart';
import 'package:test/test.dart';

// Simple test database that extends GeneratedDatabase
class _TestDatabase extends GeneratedDatabase {
  _TestDatabase(super.e);

  @override
  Iterable<TableInfo<Table, DataClass>> get allTables => [];

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      // Add required tables if needed for the test
    },
  );
}

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

// Mock repository for testing
class TestRepository extends SynquillRepositoryBase<TestModel> {
  TestRepository(super.db);

  // Implementation of findOne and findAll which delegate to overridden methods
  @override
  Future<TestModel?> findOne(
    String id, {
    DataLoadPolicy? loadPolicy,
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return await fetchFromLocal(id, queryParams: queryParams);
  }

  @override
  Future<List<TestModel>> findAll({
    DataLoadPolicy? loadPolicy,
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return await fetchAllFromLocal(queryParams: queryParams);
  }

  @override
  Stream<TestModel?> watchOne(
    String id, {
    DataLoadPolicy? loadPolicy,
    QueryParams? queryParams,
  }) {
    return watchFromLocal(id, queryParams: queryParams);
  }

  @override
  Stream<List<TestModel>> watchAll({QueryParams? queryParams}) {
    return watchAllFromLocal(queryParams: queryParams);
  }

  @override
  Future<TestModel> save(
    TestModel model, {
    DataSavePolicy? savePolicy,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    await saveToLocal(model);
    return model;
  }

  @override
  Future<void> delete(
    String id, {
    DataSavePolicy? savePolicy,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
    Set<String>? deletionContext,
  }) async {
    // Call the base class delete method which uses removeFromLocalIfExists
    await removeFromLocalIfExists(id);
  }

  @override
  Future<void> removeFromLocalIfExists(String id) async {
    // Mock implementation for testing
    // In a real repository, this would remove the item from local storage
  }

  @override
  Future<TestModel?> fetchFromLocal(
    String id, {
    QueryParams? queryParams,
  }) async {
    return TestModel(id: id, name: 'Test Name');
  }

  @override
  Future<List<TestModel>> fetchAllFromLocal({QueryParams? queryParams}) async {
    return [TestModel(id: '1', name: 'Test 1')];
  }

  @override
  Stream<TestModel?> watchFromLocal(String id, {QueryParams? queryParams}) {
    return Stream.value(TestModel(id: id, name: 'Test Name'));
  }

  @override
  Stream<List<TestModel>> watchAllFromLocal({QueryParams? queryParams}) {
    return Stream.value([TestModel(id: '1', name: 'Test 1')]);
  }

  @override
  Future<void> saveToLocal(
    TestModel item, {
    Map<String, dynamic>? extra,
  }) async {
    // Mock implementation
  }
}

void main() {
  // Disable database multiple instantiation warnings for testing
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('SyncedRepositoryProvider Default Database Support', () {
    late _TestDatabase testDb;

    setUp(() {
      // Reset state before each test
      SynquillRepositoryProvider.reset();
      DatabaseProvider.reset();

      // Create test database
      testDb = _TestDatabase(NativeDatabase.memory());

      // Register test repository
      SynquillRepositoryProvider.register<TestModel>(
        (db) => TestRepository(db),
      );
    });

    tearDown(() async {
      await testDb.close();
      SynquillRepositoryProvider.reset();
      DatabaseProvider.reset();
    });

    test('getDefault() should work after setting default database', () {
      // Set default database
      DatabaseProvider.setInstance(testDb);

      // Get repository using default database
      final repo = SynquillRepositoryProvider.get<TestModel>();

      expect(repo, isA<TestRepository>());
    });

    test('getDefault() should throw when no default database is set', () {
      // Don't set default database

      expect(
        () => SynquillRepositoryProvider.get<TestModel>(),
        throwsA(isA<StateError>()),
      );
    });

    test('tryGetDefault() should return repository when database is set', () {
      // Set default database
      DatabaseProvider.setInstance(testDb);

      // Get repository using default database
      final repo = SynquillRepositoryProvider.tryGet<TestModel>();

      expect(repo, isA<TestRepository>());
    });

    test(
      'tryGetDefault() should return null when no default database is set',
      () {
        // Don't set default database

        final repo = SynquillRepositoryProvider.tryGet<TestModel>();

        expect(repo, null);
      },
    );

    test('getDefault() should cache instances correctly', () {
      // Set default database
      DatabaseProvider.setInstance(testDb);

      // Get repository twice
      final repo1 = SynquillRepositoryProvider.get<TestModel>();
      final repo2 = SynquillRepositoryProvider.get<TestModel>();

      // Should be the same instance (cached)
      expect(identical(repo1, repo2), isTrue);
    });

    test('get() with explicit database should still work', () async {
      // Create another database
      final anotherDb = _TestDatabase(NativeDatabase.memory());

      try {
        // Set default database
        DatabaseProvider.setInstance(testDb);

        // Get repository with explicit database (should be different)
        final repoDefault = SynquillRepositoryProvider.get<TestModel>();
        final repoExplicit = SynquillRepositoryProvider.getFrom<TestModel>(
          anotherDb,
        );

        expect(repoDefault, isA<TestRepository>());
        expect(repoExplicit, isA<TestRepository>());
        expect(identical(repoDefault, repoExplicit), isFalse);
      } finally {
        await anotherDb.close();
      }
    });
  });

  group('SyncedRepositoryProvider Type Name Lookup', () {
    late _TestDatabase testDb;

    setUp(() {
      // Reset state before each test
      SynquillRepositoryProvider.reset();
      DatabaseProvider.reset();

      // Create test database
      testDb = _TestDatabase(NativeDatabase.memory());

      // Register test repository
      SynquillRepositoryProvider.register<TestModel>(
        (db) => TestRepository(db),
      );
    });

    tearDown(() async {
      await testDb.close();
      SynquillRepositoryProvider.reset();
      DatabaseProvider.reset();
    });

    test('getByTypeName() should work with default database', () {
      // Set default database
      DatabaseProvider.setInstance(testDb);

      // Get repository by type name
      final repo = SynquillRepositoryProvider.getByTypeName('TestModel');

      expect(repo, isA<TestRepository>());
    });

    test('getByTypeName() should return null for unknown types', () {
      // Set default database
      DatabaseProvider.setInstance(testDb);

      // Try to get repository for unknown type
      final repo = SynquillRepositoryProvider.getByTypeName('UnknownModel');

      expect(repo, isNull);
    });

    test('getByTypeName() should return null when no default database', () {
      // Don't set default database

      // Try to get repository by type name
      final repo = SynquillRepositoryProvider.getByTypeName('TestModel');

      expect(repo, isNull);
    });

    test('getByTypeNameFrom() should work with explicit database', () {
      // Get repository by type name with explicit database
      final repo = SynquillRepositoryProvider.getByTypeNameFrom(
        'TestModel',
        testDb,
      );

      expect(repo, isA<TestRepository>());
    });

    test('getByTypeNameFrom() should return null for unknown types', () {
      // Try to get repository for unknown type
      final repo = SynquillRepositoryProvider.getByTypeNameFrom(
        'UnknownModel',
        testDb,
      );

      expect(repo, isNull);
    });

    test('getByTypeName() should cache instances correctly', () {
      // Set default database
      DatabaseProvider.setInstance(testDb);

      // Get repository twice by type name
      final repo1 = SynquillRepositoryProvider.getByTypeName('TestModel');
      final repo2 = SynquillRepositoryProvider.getByTypeName('TestModel');

      // Should be the same instance (cached)
      expect(identical(repo1, repo2), isTrue);
    });
  });
}
