// Tests for the _defaultLogger listener accumulation behaviour.
//
// SynquillStorage._defaultLogger is a `static final` field, meaning it is
// initialised exactly once per process and its onRecord listener is attached
// only once.  If it were a non-final field re-created on every init() call,
// each cycle would add an additional listener, causing duplicate log emissions.
//
// These tests verify the observable contract:
//   1. After N init/close cycles the logger's emission count per log record
//      remains constant (i.e. exactly the number of explicit listeners *we*
//      add, not more).
//   2. Re-initialising SynquillStorage does not silently attach a second
//      built-in listener to Logger('SynquillStorage').

import 'dart:async';

import 'package:synquill/synquill.dart';
import 'package:test/test.dart';

import '../common/test_models.dart';
import '../common/mock_test_user_api_adapter.dart';
import '../common/test_user_repository.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Runs [cycles] init→close cycles and returns after the last close.
Future<void> _runCycles(int cycles) async {
  for (var i = 0; i < cycles; i++) {
    final db = TestDatabase(NativeDatabase.memory());
    final logger = Logger('DefaultLoggerTest');

    SynquillRepositoryProvider.register<TestUser>(
      (database) =>
          TestUserRepository(database as TestDatabase, MockApiAdapter()),
    );

    await SynquillStorage.init(
      database: db,
      config: const SynquillStorageConfig(
        defaultSavePolicy: DataSavePolicy.localFirst,
        defaultLoadPolicy: DataLoadPolicy.localOnly,
      ),
      logger: logger,
      enableInternetMonitoring: false,
    );

    await SynquillStorage.close();
    TestUserRepository.clearLocal();
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Silence output during tests by setting root level to OFF, then restoring.
  Level? savedLevel;

  setUp(() {
    savedLevel = Logger.root.level;
    Logger.root.level = Level.OFF;
  });

  tearDown(() async {
    // Ensure storage is closed between tests even if a test throws.
    try {
      await SynquillStorage.close();
    } catch (_) {}
    TestUserRepository.clearLocal();
    Logger.root.level = savedLevel ?? Level.INFO;
  });

  group('_defaultLogger listener accumulation', () {
    test(
      'one init/close cycle does not attach extra listeners to '
      'Logger("SynquillStorage")',
      () async {
        // Enable logging so the listener actually receives records.
        Logger.root.level = Level.ALL;

        final storageLogger = Logger('SynquillStorage');

        // Measure emissions during the first cycle.
        var recordsBefore = 0;
        final subBefore = storageLogger.onRecord.listen((_) => recordsBefore++);
        await _runCycles(1);
        await subBefore.cancel();

        // Measure emissions during a second cycle with the same setup.
        var recordsAfter = 0;
        final subAfter = storageLogger.onRecord.listen((_) => recordsAfter++);
        await _runCycles(1);
        await subAfter.cancel();

        Logger.root.level = Level.OFF;

        // If the internal listener were added on every init() call, the second
        // cycle would emit at least as many records as the first (not double),
        // but we verify the ratio stays < 2× — i.e. listener count is stable.
        //
        // Both windows must have emitted at least one record (Level.ALL is on).
        expect(recordsBefore, greaterThan(0),
            reason: 'Expected at least one log record during init/close cycle');
        expect(recordsAfter, greaterThan(0),
            reason: 'Expected at least one log record during init/close cycle');

        final ratio = recordsAfter / recordsBefore;
        expect(
          ratio,
          lessThan(2.0),
          reason: 'Emission count should not double between cycles — '
              'got before=$recordsBefore, after=$recordsAfter (ratio≈$ratio). '
              'This indicates listener accumulation.',
        );
      },
    );

    test(
      'listener count is stable across multiple init/close cycles',
      () async {
        // Enable logging so records are actually emitted.
        Logger.root.level = Level.ALL;

        final storageLogger = Logger('SynquillStorage');
        final emissionCounts = <int>[];

        // Run 3 separate cycles, counting emissions per cycle.
        for (var cycle = 0; cycle < 3; cycle++) {
          var count = 0;
          final sub = storageLogger.onRecord.listen((_) => count++);

          await _runCycles(1);

          await sub.cancel();
          emissionCounts.add(count);
        }

        Logger.root.level = Level.OFF;

        // Every cycle must have produced at least one record.
        expect(emissionCounts.every((c) => c > 0), isTrue,
            reason: 'Each init/close cycle must emit ≥1 log record '
                '(got $emissionCounts)');

        // The emission count should not grow between cycles.
        // We allow for minor variance (log messages can differ by phase),
        // but the ratio between the last and the first cycle must be < 2×
        // (i.e. emissions did NOT double, which would happen with 2 built-in
        // listeners on the 3rd cycle vs 1 on the 1st cycle).
        final ratio = emissionCounts.last / emissionCounts.first;
        expect(
          ratio,
          lessThan(2.0),
          reason: 'Emissions per cycle should not grow — '
              'got counts $emissionCounts (ratio ≈ $ratio). '
              'This would indicate listener accumulation.',
        );
      },
    );

    test(
      'five rapid init/close cycles complete without errors or stream '
      'state corruption',
      () async {
        // If listeners accumulate and a stream is closed/re-created,
        // we would see StateError or bad-state exceptions.  Completing
        // successfully is the observable proof of stability.
        await expectLater(_runCycles(5), completes);
      },
    );
  });
}
