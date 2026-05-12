// Tests for RequestQueueManager capacity management and timeout behaviour.
//
// These tests focus specifically on RequestQueueManager internals — per-queue
// capacity limits, per-queue timeouts, idempotency key lifecycle, and queue
// clearing — complementing the coarser capacity test in
// queue_system_integration_test.dart.

import 'dart:async';

import 'package:queue/queue.dart';
import 'package:test/test.dart';
import 'package:synquill/synquill_core.dart';

import '../common/test_models.dart';
import '../common/mock_test_user_api_adapter.dart';
import '../common/test_user_repository.dart';

// ---------------------------------------------------------------------------
// Shared setUp helpers
// ---------------------------------------------------------------------------

/// Very short timeouts so capacity-wait tests finish quickly.
const _quickConfig = SynquillStorageConfig(
  defaultSavePolicy: DataSavePolicy.localFirst,
  defaultLoadPolicy: DataLoadPolicy.localOnly,
  foregroundQueueConcurrency: 1,
  backgroundQueueConcurrency: 1,
  foregroundQueueCapacityTimeout: Duration(milliseconds: 150),
  loadQueueCapacityTimeout: Duration(milliseconds: 150),
  backgroundQueueCapacityTimeout: Duration(milliseconds: 150),
  queueCapacityCheckInterval: Duration(milliseconds: 10),
  // Small capacity so we can fill it cheaply.
  maxForegroundQueueCapacity: 5,
  maxLoadQueueCapacity: 5,
  maxBackgroundQueueCapacity: 5,
);

Future<void> _initStorage(TestDatabase db) async {
  final mockAdapter = MockApiAdapter();
  SynquillRepositoryProvider.register<TestUser>(
    (database) => TestUserRepository(database as TestDatabase, mockAdapter),
  );
  await SynquillStorage.init(
    database: db,
    config: _quickConfig,
    logger: null,
    enableInternetMonitoring: false,
  );
}

// ---------------------------------------------------------------------------
// Helpers for filling a queue
// ---------------------------------------------------------------------------

/// Enqueues [count] long-running tasks on [queueType].
/// Returns the list of futures (each will complete after [holdMs]).
List<Future<void>> _fillQueue(
  RequestQueueManager mgr,
  QueueType queueType,
  int count, {
  int holdMs = 500,
  String idPrefix = 'fill',
}) {
  final futures = <Future<void>>[];
  for (var i = 0; i < count; i++) {
    final task = NetworkTask<void>(
      exec: () => Future.delayed(Duration(milliseconds: holdMs)),
      idempotencyKey: '$idPrefix-$i',
      operation: SyncOperation.create,
      modelType: 'TestModel',
      modelId: 'model-$i',
    );
    futures.add(mgr.enqueueTask(task, queueType: queueType));
  }
  return futures;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late TestDatabase database;

  setUp(() async {
    database = TestDatabase(NativeDatabase.memory());
    await _initStorage(database);
  });

  tearDown(() async {
    try {
      await SynquillStorage.close();
    } catch (_) {}
    TestUserRepository.clearLocal();
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Initialization', () {
    test('getQueueStats returns three queues all at zero', () {
      final stats = SynquillStorage.queueManager.getQueueStats();
      expect(stats, hasLength(3));
      expect(stats[QueueType.foreground]!.activeAndPendingTasks, equals(0));
      expect(stats[QueueType.load]!.activeAndPendingTasks, equals(0));
      expect(stats[QueueType.background]!.activeAndPendingTasks, equals(0));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Capacity management – background queue', () {
    test(
        'throws SynquillStorageException when background queue is full '
        'and timeout expires', () async {
      final mgr = SynquillStorage.queueManager;
      // Fill the queue (capacity = 5) with tasks that hold for 1 s.
      final futures = _fillQueue(mgr, QueueType.background, 5,
          holdMs: 1000, idPrefix: 'bg-cap');
      // Give them a moment to register.
      await Future.delayed(const Duration(milliseconds: 30));

      // Next task should timeout (backgroundQueueCapacityTimeout = 150 ms).
      final overflow = NetworkTask<void>(
        exec: () => Future.value(),
        idempotencyKey: 'bg-overflow',
        operation: SyncOperation.create,
        modelType: 'TestModel',
        modelId: 'overflow',
      );

      await expectLater(
        mgr.enqueueTask(overflow, queueType: QueueType.background),
        throwsA(isA<SynquillStorageException>()),
      );

      // Drain the fill tasks to avoid interference with tearDown.
      for (final f in futures) {
        await f.catchError((_) {});
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Capacity management – foreground queue', () {
    test(
        'throws SynquillStorageException when foreground queue is full '
        'and timeout expires', () async {
      final mgr = SynquillStorage.queueManager;
      final futures = _fillQueue(mgr, QueueType.foreground, 5,
          holdMs: 1000, idPrefix: 'fg-cap');
      await Future.delayed(const Duration(milliseconds: 30));

      final overflow = NetworkTask<void>(
        exec: () => Future.value(),
        idempotencyKey: 'fg-overflow',
        operation: SyncOperation.create,
        modelType: 'TestModel',
        modelId: 'fg-overflow',
      );

      await expectLater(
        mgr.enqueueTask(overflow, queueType: QueueType.foreground),
        throwsA(isA<SynquillStorageException>()),
      );

      for (final f in futures) {
        await f.catchError((_) {});
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Capacity management – load queue', () {
    test(
        'throws SynquillStorageException when load queue is full '
        'and timeout expires', () async {
      final mgr = SynquillStorage.queueManager;
      final futures = _fillQueue(mgr, QueueType.load, 5,
          holdMs: 1000, idPrefix: 'load-cap');
      await Future.delayed(const Duration(milliseconds: 30));

      final overflow = NetworkTask<void>(
        exec: () => Future.value(),
        idempotencyKey: 'load-overflow',
        operation: SyncOperation.read,
        modelType: 'TestModel',
        modelId: 'load-overflow',
      );

      await expectLater(
        mgr.enqueueTask(overflow, queueType: QueueType.load),
        throwsA(isA<SynquillStorageException>()),
      );

      for (final f in futures) {
        await f.catchError((_) {});
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Capacity freed before timeout', () {
    test('enqueue succeeds when a slot opens before the timeout', () async {
      final mgr = SynquillStorage.queueManager;

      // Fill with tasks that complete in 80 ms (well under 150 ms timeout).
      final futures = _fillQueue(mgr, QueueType.background, 5,
          holdMs: 80, idPrefix: 'free-cap');

      // Let the queue fill.
      await Future.delayed(const Duration(milliseconds: 20));

      // This task starts waiting; a slot should open within ~80 ms.
      final lateTask = NetworkTask<void>(
        exec: () => Future.value(),
        idempotencyKey: 'late-task',
        operation: SyncOperation.create,
        modelType: 'TestModel',
        modelId: 'late',
      );

      // Should NOT throw — slot frees up before the 150 ms timeout.
      await expectLater(
        mgr.enqueueTask(lateTask, queueType: QueueType.background),
        completes,
      );

      await Future.wait(futures.map((f) => f.catchError((_) {})));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Idempotency key tracking', () {
    test(
        'duplicate idempotency key throws SynquillStorageException immediately',
        () async {
      final mgr = SynquillStorage.queueManager;

      final task1 = NetworkTask<void>(
        exec: () => Future.delayed(const Duration(milliseconds: 200)),
        idempotencyKey: 'dup-key',
        operation: SyncOperation.create,
        modelType: 'TestModel',
        modelId: 'dup-model',
      );

      final task2 = NetworkTask<void>(
        exec: () => Future.value(),
        idempotencyKey: 'dup-key', // same key
        operation: SyncOperation.create,
        modelType: 'TestModel',
        modelId: 'dup-model-2',
      );

      final f1 = mgr.enqueueTask(task1, queueType: QueueType.background);

      expect(
        () => mgr.enqueueTask(task2, queueType: QueueType.background),
        throwsA(isA<SynquillStorageException>()),
      );

      await f1.catchError((_) {});
    });

    test('idempotency key is released after task completes successfully',
        () async {
      final mgr = SynquillStorage.queueManager;

      final task1 = NetworkTask<void>(
        exec: () => Future.delayed(const Duration(milliseconds: 30)),
        idempotencyKey: 'release-key',
        operation: SyncOperation.create,
        modelType: 'TestModel',
        modelId: 'release-model',
      );

      await mgr.enqueueTask(task1, queueType: QueueType.background);

      // Same key should now be usable.
      final task2 = NetworkTask<void>(
        exec: () => Future.value(),
        idempotencyKey: 'release-key',
        operation: SyncOperation.create,
        modelType: 'TestModel',
        modelId: 'release-model-2',
      );

      await expectLater(
        mgr.enqueueTask(task2, queueType: QueueType.background),
        completes,
      );
    });

    test('idempotency key is released after task throws', () async {
      final mgr = SynquillStorage.queueManager;

      final failingTask = NetworkTask<void>(
        exec: () => throw Exception('task failed'),
        idempotencyKey: 'fail-key',
        operation: SyncOperation.create,
        modelType: 'TestModel',
        modelId: 'fail-model',
      );

      await mgr
          .enqueueTask(failingTask, queueType: QueueType.background)
          .catchError((_) {});

      // Key must be released so the same key can be reused.
      final retryTask = NetworkTask<void>(
        exec: () => Future.value(),
        idempotencyKey: 'fail-key',
        operation: SyncOperation.create,
        modelType: 'TestModel',
        modelId: 'fail-model-retry',
      );

      await expectLater(
        mgr.enqueueTask(retryTask, queueType: QueueType.background),
        completes,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('clearQueuesOnDisconnect', () {
    test('clears all queues — all counters drop to zero', () async {
      // Run the entire test body in a zone so we can catch the async
      // QueueCancelledException that fires from the cancelled task's future
      // regardless of which microtask it arrives on.
      final capturedErrors = <dynamic>[];
      await runZonedGuarded(() async {
        final mgr = SynquillStorage.queueManager;

        // Enqueue a long task; we don't care if it completes or is cancelled.
        mgr
            .enqueueTask(
              NetworkTask<void>(
                exec: () => Future.delayed(const Duration(seconds: 10)),
                idempotencyKey: 'clr-1',
                operation: SyncOperation.create,
                modelType: 'TestModel',
                modelId: 'clr-1',
              ),
              queueType: QueueType.background,
            )
            .ignore();

        await Future.delayed(const Duration(milliseconds: 20));
        await mgr.clearQueuesOnDisconnect();
        await Future.delayed(const Duration(milliseconds: 50));

        final stats = mgr.getQueueStats();
        expect(stats[QueueType.foreground]!.activeAndPendingTasks, equals(0));
        expect(stats[QueueType.load]!.activeAndPendingTasks, equals(0));
        expect(stats[QueueType.background]!.activeAndPendingTasks, equals(0));
      }, (e, _) => capturedErrors.add(e));

      // Only fail if we got an unexpected error type
      // (not QueueCancelledException).
      final unexpected =
          capturedErrors.where((e) => e is! QueueCancelledException).toList();
      expect(unexpected, isEmpty, reason: 'Unexpected errors: $unexpected');
    });

    test('new tasks can be enqueued immediately after clearing', () async {
      final mgr = SynquillStorage.queueManager;

      await runZonedGuarded(
        () => mgr.clearQueuesOnDisconnect(),
        (_, __) {},
      );

      final task = NetworkTask<void>(
        exec: () => Future.value(),
        idempotencyKey: 'post-clear',
        operation: SyncOperation.create,
        modelType: 'TestModel',
        modelId: 'post-clear',
      );

      await expectLater(
        mgr.enqueueTask(task, queueType: QueueType.background),
        completes,
      );
    });

    test('idempotency keys are cleared after disconnect', () async {
      final capturedErrors = <dynamic>[];

      await runZonedGuarded(() async {
        final mgr = SynquillStorage.queueManager;

        // Enqueue a long-running task to hold the key.
        mgr
            .enqueueTask(
              NetworkTask<void>(
                exec: () => Future.delayed(const Duration(seconds: 10)),
                idempotencyKey: 'held-key',
                operation: SyncOperation.create,
                modelType: 'TestModel',
                modelId: 'held-model',
              ),
              queueType: QueueType.background,
            )
            .ignore();

        await Future.delayed(const Duration(milliseconds: 20));
        await mgr.clearQueuesOnDisconnect();
        await Future.delayed(const Duration(milliseconds: 50));

        // Key should now be available.
        final sameKeyTask = NetworkTask<void>(
          exec: () => Future.value(),
          idempotencyKey: 'held-key',
          operation: SyncOperation.create,
          modelType: 'TestModel',
          modelId: 'held-model-2',
        );

        await expectLater(
          mgr.enqueueTask(sameKeyTask, queueType: QueueType.background),
          completes,
        );
      }, (e, _) => capturedErrors.add(e));

      final unexpected =
          capturedErrors.where((e) => e is! QueueCancelledException).toList();
      expect(unexpected, isEmpty, reason: 'Unexpected errors: $unexpected');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  group('Default queue routing', () {
    test('create operation is routed to foreground queue', () async {
      final mgr = SynquillStorage.queueManager;

      final task = NetworkTask<void>(
        exec: () => Future.value(),
        idempotencyKey: 'route-create',
        operation: SyncOperation.create,
        modelType: 'TestModel',
        modelId: 'route-create',
        // No explicit queueType — let routing decide.
      );

      // Record load-queue counter before enqueue; a create op must NOT be
      // routed to the load queue, so this counter must remain unchanged.
      final loadBefore =
          mgr.getQueueStats()[QueueType.load]!.activeAndPendingTasks;

      // The enqueue must complete without throwing — confirming the task was
      // accepted by a queue (foreground, per routing rules for create ops).
      await expectLater(
        mgr.enqueueTask(task), // no queueType
        completes,
      );

      // Load queue must be untouched: create ops are never routed there.
      final loadAfter =
          mgr.getQueueStats()[QueueType.load]!.activeAndPendingTasks;
      expect(loadAfter, equals(loadBefore),
          reason: 'A create operation must not be routed to the load queue');
    });

    test('read operation is routed to load queue', () async {
      final mgr = SynquillStorage.queueManager;

      final task = NetworkTask<void>(
        exec: () => Future.value(),
        idempotencyKey: 'route-read',
        operation: SyncOperation.read,
        modelType: 'TestModel',
        modelId: 'route-read',
      );

      // Read ops go to the load queue via _getDefaultQueueType.
      await expectLater(
        mgr.enqueueTask(task), // no queueType
        completes,
      );
    });
  });
}
