import 'package:test/test.dart';
import 'package:synquill/synquill_core.dart';
import '../common/test_models.dart';
import '../common/test_user_repository.dart';
import '../common/mock_test_user_api_adapter.dart';

void main() {
  group('RetryExecutor Disposal Race Condition Fix', () {
    late TestDatabase database;
    late MockApiAdapter mockAdapter;

    setUp(() async {
      database = TestDatabase(NativeDatabase.memory());
      mockAdapter = MockApiAdapter();
      TestUserRepository.clearLocal();

      SynquillRepositoryProvider.register<TestUser>(
        (db) => TestUserRepository(db as TestDatabase, mockAdapter),
      );
    });

    tearDown(() async {
      try {
        await SynquillStorage.close();
      } catch (e) {
        // Ignore errors during teardown
      }
    });

    test(
      'should gracefully handle disposal during ongoing operations',
      () async {
        // Initialize SynquillStorage
        await SynquillStorage.init(
          database: database,
          config: const SynquillStorageConfig(
            foregroundPollInterval: Duration(milliseconds: 100),
            backgroundPollInterval: Duration(milliseconds: 200),
          ),
        );

        // Trigger multiple simultaneous operations
        final futures = <Future<void>>[];

        // Start multiple operations in parallel
        for (int i = 0; i < 5; i++) {
          futures.add(
            SynquillStorage.retryExecutor.processDueTasksNow(forceSync: true),
          );
        }

        // Wait a bit to let operations start
        await Future.delayed(const Duration(milliseconds: 50));

        // Trigger disposal while operations are ongoing
        final resetFuture = SynquillStorage.close();

        // Wait for everything to complete without errors
        await Future.wait([
          ...futures,
          resetFuture,
        ]);

        // Verify no exceptions were thrown and disposal completed cleanly
        expect(() => SynquillStorage.instance, throwsStateError);
      },
    );

    test(
      'should handle rapid start/stop cycles without race conditions',
      () async {
        for (int cycle = 0; cycle < 3; cycle++) {
          await SynquillStorage.init(
            database: database,
            config: const SynquillStorageConfig(
              foregroundPollInterval: Duration(milliseconds: 50),
            ),
          );

          // Start some operations
          final operation = SynquillStorage.retryExecutor.processDueTasksNow();

          // Immediately reset
          await SynquillStorage.close();

          // Wait for the operation to complete (should not error)
          try {
            await operation;
          } catch (e) {
            // Acceptable errors during shutdown
            expect(
              e.toString().contains('Channel was closed') ||
                  e.toString().contains('QueueCancelledException'),
              isTrue,
              reason: 'Unexpected error during shutdown: $e',
            );
          }

          expect(() => SynquillStorage.instance, throwsStateError);
        }
      },
    );
  });
}
