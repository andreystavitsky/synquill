import 'package:test/test.dart';
import 'package:synquill/synquill.dart';

import '../common/test_models.dart';

void main() {
  group('Repository Access Tests', () {
    late TestDatabase database;

    setUp(() async {
      // Create an in-memory database for testing
      database = TestDatabase(NativeDatabase.memory());

      // Register test repository factory

      SynquillRepositoryProvider.register<TestUser>(
        (db) => TestUserRepository(db as TestDatabase),
      );

      // Initialize SynquillStorage with test configuration

      try {
        await SynquillStorage.init(
          database: database,
          config: const SynquillStorageConfig(
            defaultSavePolicy: DataSavePolicy.localFirst,
            defaultLoadPolicy: DataLoadPolicy.localOnly,
          ),
          logger: Logger('RepositoryAccessTest'),
          enableInternetMonitoring: false, // Disable for testing
        );
      } catch (e) {
        rethrow;
      }
    });

    tearDown(() async {
      await SynquillStorage.reset();
    });

    test('getRepository<T>() returns correct repository type', () {
      // Test the simplified getRepository method that only requires
      // the model type
      final userRepo = SynquillStorage.instance.getRepository<TestUser>();

      expect(userRepo, isA<TestUserRepository>());
    });

    test('repository instances are singletons', () {
      // Verify repository singleton behavior
      final userRepo1 = SynquillStorage.instance.getRepository<TestUser>();

      final userRepo2 = SynquillStorage.instance.getRepository<TestUser>();

      expect(identical(userRepo1, userRepo2), isTrue);
    });
  });
}

/// Simple test repository implementation for the simplified access pattern test
class TestUserRepository extends SynquillRepositoryBase<TestUser> {
  TestUserRepository(super.db);

  @override
  Future<TestUser?> findOne(
    String id, {
    DataLoadPolicy? loadPolicy,
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return TestUser(id: id, name: 'Test User', email: 'test@example.com');
  }

  @override
  Future<List<TestUser>> findAll({
    DataLoadPolicy? loadPolicy,
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return [TestUser(id: '1', name: 'Test User', email: 'test@example.com')];
  }

  @override
  Stream<TestUser?> watchOne(
    String id, {
    DataLoadPolicy? loadPolicy,
    QueryParams? queryParams,
  }) {
    return Stream.value(
      TestUser(id: id, name: 'Test User', email: 'test@example.com'),
    );
  }

  @override
  Stream<List<TestUser>> watchAll({QueryParams? queryParams}) {
    return Stream.value([
      TestUser(id: '1', name: 'Test User', email: 'test@example.com'),
    ]);
  }

  @override
  Future<TestUser> save(
    TestUser model, {
    Object? savePolicy,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
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
  }) async {
    // No-op for testing
  }
}
