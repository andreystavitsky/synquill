import 'dart:async';

import 'package:synquill/synquill.dart';
import 'package:test/test.dart';

import '../common/test_models.dart';

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

    test('close clears global providers and generated metadata', () async {
      final database = TestDatabase(NativeDatabase.memory());

      SynquillRepositoryProvider.register<TestUser>(
        (_) => throw StateError('stale repository factory was used'),
      );
      DependencyResolver.registerDependency('Project', 'User');
      ModelInfoRegistryProvider.registerIdJsonKey('ServerUser', 'server_id');

      await SynquillStorage.init(
        database: database,
        logger: Logger('SynquillStorageLifecycleTest'),
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
  });
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
