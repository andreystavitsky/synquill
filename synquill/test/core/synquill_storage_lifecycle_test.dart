import 'dart:async';

import 'package:synquill/synquill.dart';
import 'package:test/test.dart';

import '../common/mock_test_user_api_adapter.dart';
import '../common/test_models.dart';
import '../common/test_user_repository.dart';

void main() {
  group('SynquillStorage lifecycle', () {
    tearDown(() async {
      await SynquillStorage.close();
    });

    test(
      'rolls back partial state when initialization fails',
      () async {
        final failedDatabase = TestDatabase(NativeDatabase.memory());
        final initFailure = StateError('generated initialization failed');

        await expectLater(
          SynquillStorage.init(
            database: failedDatabase,
            logger: Logger('SynquillStorageLifecycleTest'),
            initializeFn: (_) => throw initFailure,
            enableInternetMonitoring: false,
          ),
          throwsA(same(initFailure)),
        );

        expect(
          () => SynquillStorage.instance,
          throwsA(isA<StateError>()),
        );
        expect(
          () => SynquillStorage.database,
          throwsA(isA<StateError>()),
        );
        expect(
          () => SynquillStorage.queueManager,
          throwsA(isA<StateError>()),
        );
        expect(
          () => SynquillStorage.retryExecutor,
          throwsA(isA<StateError>()),
        );
        expect(
          () => SynquillStorage.backgroundSyncManager,
          throwsA(isA<StateError>()),
        );

        await failedDatabase.close();

        final recoveredDatabase = TestDatabase(NativeDatabase.memory());

        await SynquillStorage.init(
          database: recoveredDatabase,
          logger: Logger('SynquillStorageLifecycleTestRecovered'),
          enableInternetMonitoring: false,
        );

        expect(identical(SynquillStorage.database, recoveredDatabase), isTrue);
        expect(() => SynquillStorage.queueManager, returnsNormally);
      },
    );

    test(
      'cleans owned resources when a late initialization step fails',
      () async {
        final database = TestDatabase(NativeDatabase.memory());
        final initFailure = StateError('connectivity listener failed');

        await expectLater(
          SynquillStorage.init(
            database: database,
            logger: Logger('SynquillStorageLifecycleTest'),
            connectivityStream: _ThrowingListenStream(initFailure),
          ),
          throwsA(same(initFailure)),
        );

        expect(
          () => SynquillStorage.instance,
          throwsA(isA<StateError>()),
        );
        await expectLater(
          database.customSelect('select 1').get(),
          throwsA(anything),
        );
      },
    );

    test(
      'failed late initialization clears runtime repository registry',
      () async {
        final database = TestDatabase(NativeDatabase.memory());
        final initFailure = StateError('connectivity listener failed');

        await expectLater(
          SynquillStorage.init(
            database: database,
            logger: Logger('SynquillStorageLifecycleTest'),
            initializeFn: (_) {
              SynquillRepositoryProvider.register<TestUser>(
                (db) => TestUserRepository(
                  db as TestDatabase,
                  MockApiAdapter(),
                ),
              );
            },
            connectivityStream: _ThrowingListenStream(initFailure),
          ),
          throwsA(same(initFailure)),
        );

        expect(SynquillRepositoryProvider.getAllRegisteredTypeNames(), isEmpty);
        expect(
          () => DatabaseProvider.instance,
          throwsA(isA<StateError>()),
        );
        await expectLater(
          database.customSelect('select 1').get(),
          throwsA(anything),
        );
      },
    );

    test('runtime-backed getters expose initialized services', () async {
      final database = TestDatabase(NativeDatabase.memory());
      const config = SynquillStorageConfig(
        defaultSavePolicy: DataSavePolicy.remoteFirst,
      );
      final logger = Logger('SynquillStorageLifecycleRuntimeGetters');

      await SynquillStorage.init(
        database: database,
        config: config,
        logger: logger,
        initializeFn: (_) {
          SynquillRepositoryProvider.register<TestUser>(
            (db) => TestUserRepository(db as TestDatabase, MockApiAdapter()),
          );
        },
        enableInternetMonitoring: false,
      );

      expect(identical(SynquillStorage.database, database), isTrue);
      expect(identical(SynquillStorage.config, config), isTrue);
      expect(identical(SynquillStorage.logger, logger), isTrue);
      expect(SynquillStorage.queueManager, isNotNull);
      expect(SynquillStorage.retryExecutor, isNotNull);
      expect(SynquillStorage.backgroundSyncManager, isNotNull);
      expect(SynquillStorage.syncQueueDao, isNotNull);
      expect(SynquillStorage.dependencyResolver, isNotNull);
    });

    test('close clears global providers and generated metadata', () async {
      final database = TestDatabase(NativeDatabase.memory());

      DependencyResolver.registerDependency('Project', 'User');
      ModelInfoRegistryProvider.registerIdJsonKey('ServerUser', 'server_id');

      await SynquillStorage.init(
        database: database,
        logger: Logger('SynquillStorageLifecycleTest'),
        initializeFn: (_) {
          SynquillRepositoryProvider.register<TestUser>(
            (db) => TestUserRepository(db as TestDatabase, MockApiAdapter()),
          );
        },
        enableInternetMonitoring: false,
      );

      expect(identical(DatabaseProvider.instance, database), isTrue);
      expect(
        SynquillRepositoryProvider.getAllRegisteredTypeNames(),
        contains('TestUser'),
      );
      expect(DependencyResolver.hasDependencies('Project'), isTrue);
      expect(
        ModelInfoRegistryProvider.getIdJsonKey('ServerUser'),
        equals('server_id'),
      );

      await SynquillStorage.close();

      expect(
        () => DatabaseProvider.instance,
        throwsA(isA<StateError>()),
      );
      expect(SynquillRepositoryProvider.getAllRegisteredTypeNames(), isEmpty);
      expect(DependencyResolver.hasDependencies('Project'), isFalse);
      expect(
        ModelInfoRegistryProvider.getIdJsonKey('ServerUser'),
        equals('id'),
      );
    });

    test('repository registrations are scoped to initialized runtime',
        () async {
      final firstDatabase = TestDatabase(NativeDatabase.memory());

      await SynquillStorage.init(
        database: firstDatabase,
        logger: Logger('SynquillStorageLifecycleTestFirst'),
        initializeFn: (_) {
          SynquillRepositoryProvider.register<TestUser>(
            (db) => _TaggedTestUserRepository(
              db as TestDatabase,
              MockApiAdapter(),
              'first',
            ),
          );
        },
        enableInternetMonitoring: false,
      );

      final firstRepository = SynquillStorage.instance.getRepository<TestUser>()
          as _TaggedTestUserRepository;
      expect(firstRepository.tag, equals('first'));
      expect(
        SynquillRepositoryProvider.getAllRegisteredTypeNames(),
        equals(['TestUser']),
      );

      await SynquillStorage.close();

      expect(SynquillRepositoryProvider.getAllRegisteredTypeNames(), isEmpty);

      final secondDatabase = TestDatabase(NativeDatabase.memory());

      await SynquillStorage.init(
        database: secondDatabase,
        logger: Logger('SynquillStorageLifecycleTestSecond'),
        initializeFn: (_) {
          SynquillRepositoryProvider.register<TestUser>(
            (db) => _TaggedTestUserRepository(
              db as TestDatabase,
              MockApiAdapter(),
              'second',
            ),
          );
        },
        enableInternetMonitoring: false,
      );

      final secondRepository = SynquillStorage.instance
          .getRepository<TestUser>() as _TaggedTestUserRepository;
      expect(secondRepository.tag, equals('second'));
      expect(identical(firstRepository, secondRepository), isFalse);
    });

    test('close is idempotent after successful and failed initialization',
        () async {
      await SynquillStorage.close();
      await SynquillStorage.close();

      final failedDatabase = TestDatabase(NativeDatabase.memory());

      await expectLater(
        SynquillStorage.init(
          database: failedDatabase,
          logger: Logger('SynquillStorageLifecycleFailedClose'),
          initializeFn: (_) => throw StateError('init failed'),
          enableInternetMonitoring: false,
        ),
        throwsA(isA<StateError>()),
      );

      await SynquillStorage.close();

      final database = TestDatabase(NativeDatabase.memory());
      await SynquillStorage.init(
        database: database,
        logger: Logger('SynquillStorageLifecycleSuccessfulClose'),
        enableInternetMonitoring: false,
      );

      await SynquillStorage.close();
      await SynquillStorage.close();

      expect(
        () => SynquillStorage.instance,
        throwsA(isA<StateError>()),
      );
    });

    test('uninitialized accessors throw the standard StateError', () {
      final accessors = <String, Object? Function()>{
        'instance': () => SynquillStorage.instance,
        'database': () => SynquillStorage.database,
        'logger': () => SynquillStorage.logger,
        'queueManager': () => SynquillStorage.queueManager,
        'retryExecutor': () => SynquillStorage.retryExecutor,
        'dependencyResolver': () => SynquillStorage.dependencyResolver,
        'backgroundSyncManager': () => SynquillStorage.backgroundSyncManager,
        'syncQueueDao': () => SynquillStorage.syncQueueDao,
        'enableBackgroundMode': () => SynquillStorage.enableBackgroundMode(),
        'enableForegroundMode': () => SynquillStorage.enableForegroundMode(),
      };

      for (final MapEntry(:key, :value) in accessors.entries) {
        expect(
          value,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              '$key message',
              equals(
                'SynquillStorage has not been initialized. '
                'Call SynquillStorage.init() first.',
              ),
            ),
          ),
        );
      }
    });

    test('isConnected returns false before initialization', () async {
      expect(await SynquillStorage.isConnected, isFalse);
    });

    test('setConfigForTesting remains available without runtime', () async {
      const config = SynquillStorageConfig(
        defaultSavePolicy: DataSavePolicy.remoteFirst,
      );

      SynquillStorage.setConfigForTesting(config);

      expect(identical(SynquillStorage.config, config), isTrue);

      await SynquillStorage.close();

      expect(SynquillStorage.config, isNull);
    });
  });
}

class _TaggedTestUserRepository extends TestUserRepository {
  final String tag;

  _TaggedTestUserRepository(super.db, super.mockAdapter, this.tag);
}

class _ThrowingListenStream extends Stream<bool> {
  final Object error;

  _ThrowingListenStream(this.error);

  @override
  StreamSubscription<bool> listen(
    void Function(bool event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    throw error;
  }
}
