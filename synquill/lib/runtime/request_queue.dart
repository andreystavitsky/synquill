part of synquill;

/// Queue types for different API operations.
enum QueueType {
  /// Foreground queue for remoteFirst write operations
  /// (parallel: 1, delay: 50ms).
  foreground,

  /// Load queue for remoteFirst load operations
  /// (parallel: 2, delay: 50ms).
  load,

  /// Background queue for localFirst sync operations
  /// (parallel: 1, delay: 100ms).
  background,
}

/// Manages multiple request queues for different types of API operations.
///
/// This class provides three independent queues with different concurrency
/// and delay settings optimized for different use cases:
/// - foregroundQueue: For remoteFirst save operations
/// - loadQueue: For remoteFirst load operations
/// - backgroundQueue: For localFirst sync operations
///
/// Features:
/// - Capacity limits (50 tasks max per queue)
/// - Duplicate detection via idempotency keys
/// - Connectivity-responsive queue clearing/restoration
///
/// This implements N-01 from the technical specification.
class RequestQueueManager {
  final Map<QueueType, RequestQueue> _queues = {};
  final Map<QueueType, Set<String>> _activeIdempotencyKeys = {};
  late final Logger _log;

  /// Maximum number of tasks per queue to prevent memory issues
  static const int maxQueueCapacity = 50;

  /// Creates a new RequestQueueManager with configured queues.
  RequestQueueManager() {
    _log = Logger('RequestQueueManager');

    // Initialize the three queues with specific configurations
    _queues[QueueType.foreground] = RequestQueue(
      parallelism: 1,
      delay: const Duration(milliseconds: 50),
      name: 'ForegroundQueue',
    );

    _queues[QueueType.load] = RequestQueue(
      parallelism: 2,
      delay: const Duration(milliseconds: 50),
      name: 'LoadQueue',
    );

    _queues[QueueType.background] = RequestQueue(
      parallelism: 1,
      delay: const Duration(milliseconds: 100),
      name: 'BackgroundQueue',
    );

    // Initialize idempotency key tracking
    for (final queueType in QueueType.values) {
      _activeIdempotencyKeys[queueType] = <String>{};
    }

    _log.info('RequestQueueManager initialized with 3 queues');
  }

  /// Enqueues a NetworkTask to the appropriate queue.
  ///
  /// [task] The NetworkTask to enqueue.
  /// [queueType] The type of queue to use. If not specified,
  /// defaults based on operation.
  ///
  /// Returns the task result or throws an exception if:
  /// - Queue is at capacity (50 tasks)
  /// - Task is a duplicate (same idempotency key)
  /// - Device is offline for remoteFirst operations
  Future<T> enqueueTask<T>(NetworkTask<T> task, {QueueType? queueType}) async {
    queueType ??= _getDefaultQueueType(task);
    final queue = _queues[queueType]!;
    final idempotencyKeys = _activeIdempotencyKeys[queueType]!;

    // Check capacity limit
    if (queue.activeAndPendingTasks >= maxQueueCapacity) {
      final message =
          'Queue ${queueType.name} is at capacity ($maxQueueCapacity tasks)';
      _log.warning(message);
      throw SynquillStorageException(message);
    }

    // Check for duplicate idempotency key
    if (idempotencyKeys.contains(task.idempotencyKey)) {
      final message =
          'Duplicate task with idempotency key: ${task.idempotencyKey}';
      _log.fine(message);
      throw SynquillStorageException(message);
    }

    // For remoteFirst operations, check connectivity
    if (_isRemoteFirstOperation(queueType) &&
        !await SynquillStorage.isConnected) {
      const message = 'Cannot perform remoteFirst operation while offline';
      _log.warning(message);
      throw SynquillStorageException(message);
    }

    _log.fine('Enqueueing ${task} to ${queueType.name} queue');

    // Track idempotency key
    idempotencyKeys.add(task.idempotencyKey);

    try {
      final result = await queue.addTask<T>(() async {
        // Execute the task and return its future result directly
        // The task.execute() will handle exceptions internally
        // and complete the completer
        await task.execute();
        return task.future;
      }, taskName: task.toString());

      return result;
    } finally {
      // Remove idempotency key when task completes (success or failure)
      idempotencyKeys.remove(task.idempotencyKey);
    }
  }

  /// Determines the default queue type for a NetworkTask.
  QueueType _getDefaultQueueType(NetworkTask task) {
    // Background sync operations go to background queue
    // Immediate operations go to foreground or load queue based on operation
    switch (task.operation) {
      case SyncOperation.create:
      case SyncOperation.update:
      case SyncOperation.delete:
        // These could be foreground or background depending on context
        // For now, default to foreground
        return QueueType.foreground;
    }
  }

  /// Checks if the queue type represents a remoteFirst operation.
  bool _isRemoteFirstOperation(QueueType queueType) {
    return queueType == QueueType.foreground || queueType == QueueType.load;
  }

  /// Gets statistics for all queues.
  Map<QueueType, QueueStats> getQueueStats() {
    return _queues.map(
      (type, queue) => MapEntry(
        type,
        QueueStats(
          activeAndPendingTasks: queue.activeAndPendingTasks,
          pendingTasks: queue.pendingTasks,
        ),
      ),
    );
  }

  /// Clears all queues when connectivity is lost.
  ///
  /// This is the preferred approach since the Queue package doesn't support
  /// pause/resume operations. Tasks remain in the sync_queue database
  /// and will be restored when connectivity returns.
  Future<void> clearQueuesOnDisconnect() async {
    _log.info('Clearing all request queues due to connectivity loss');

    // Clear idempotency key tracking
    for (final keys in _activeIdempotencyKeys.values) {
      keys.clear();
    }

    // Dispose and recreate queues
    // Handle QueueCancelledException from disposing queues
    await Future.wait(
      _queues.values.map((queue) async {
        try {
          await queue.dispose();
        } catch (e) {
          if (e is! QueueCancelledException) {
            // Only log non-cancellation exceptions as these are expected
            _log.warning('Error disposing queue: $e');
          }
          // QueueCancelledException is expected when cancelling queues
        }
      }),
    );

    // Recreate fresh queues
    _queues[QueueType.foreground] = RequestQueue(
      parallelism: 1,
      delay: const Duration(milliseconds: 50),
      name: 'ForegroundQueue',
    );

    _queues[QueueType.load] = RequestQueue(
      parallelism: 2,
      delay: const Duration(milliseconds: 50),
      name: 'LoadQueue',
    );

    _queues[QueueType.background] = RequestQueue(
      parallelism: 1,
      delay: const Duration(milliseconds: 100),
      name: 'BackgroundQueue',
    );

    _log.info('All queues cleared and recreated');
  }

  /// Restores queue processing when connectivity returns.
  ///
  /// This triggers the RetryExecutor to immediately process due tasks
  /// and fill queues based on priority: foreground → load → background.
  Future<void> restoreQueuesOnConnect() async {
    _log.info('Restoring queue processing due to connectivity return');

    try {
      // Trigger immediate processing of due tasks
      await SynquillStorage.retryExecutor.processDueTasksNow();
      _log.info('Queue restoration completed');
    } catch (e, stackTrace) {
      _log.severe('Error during queue restoration', e, stackTrace);
    }
  }

  /// Waits for all queues to complete their current tasks.
  Future<void> joinAll() async {
    _log.info('Waiting for all queues to complete');
    await Future.wait(_queues.values.map((queue) => queue.join()));
    _log.info('All queues completed');
  }

  /// Disposes all queues.
  Future<void> dispose() async {
    _log.info('Disposing RequestQueueManager');
    await Future.wait(_queues.values.map((queue) => queue.dispose()));
    _queues.clear();
    _log.info('RequestQueueManager disposed');
  }
}

/// Statistics for a request queue.
class QueueStats {
  /// The total number of tasks that are currently active or pending
  final int activeAndPendingTasks;

  /// The number of tasks that are pending execution
  final int pendingTasks;

  /// Creates a new QueueStats instance
  const QueueStats({
    required this.activeAndPendingTasks,
    required this.pendingTasks,
  });

  @override
  String toString() =>
      'QueueStats(active+pending: $activeAndPendingTasks, '
      'pending: $pendingTasks)';
}

/// A queue for managing sequential execution of network operations.
///
/// This class wraps the `package:queue` to provide a configurable concurrency
/// for tasks. It ensures that network requests can be processed in a controlled
/// manner, respecting order and concurrency limits.
///
/// This implements N-01 from the technical specification.
class RequestQueue {
  final Queue _queue;
  final Logger _log;

  /// Creates a new [RequestQueue].
  ///
  /// [parallelism] specifies the maximum number of concurrent operations.
  /// Defaults to 1, ensuring sequential execution.
  /// [name] is an optional name for the logger associated with this queue.
  RequestQueue({int parallelism = 1, String? name, Duration? delay})
    : _queue = Queue(parallel: parallelism, delay: delay),
      _log =
          (() {
            try {
              return SynquillStorage.logger;
            } catch (_) {
              return Logger(name ?? 'RequestQueue');
            }
          })();

  /// Adds a new asynchronous [operation] to the queue.
  ///
  /// The [operation] will be executed when its turn comes according to the
  /// queue's concurrency settings.
  ///
  /// Returns a [Future] that completes with the result of the [operation].
  /// If the [operation] throws an error, the returned [Future] will also
  /// complete with that error.
  ///
  /// [taskName] is an optional descriptive name for the task, used for logging.
  Future<T> addTask<T>(
    Future<T> Function() operation, {
    String? taskName,
  }) async {
    final description = taskName ?? 'Unnamed Task';
    _log.fine('Adding task "$description" to the queue.');
    try {
      // Ensure the operation is properly cast for the queue.
      final result = await _queue.add<T>(operation);

      _log.finer('Task "$description" completed successfully.');
      return result;
    } catch (e, s) {
      _log.warning('Task "$description" failed.', e, s);
      rethrow;
    }
  }

  /// Returns the number of tasks currently active or waiting in the queue.
  /// Note: The `queue` package (as of 3.4.0) primarily
  /// exposes `remainingItemCount`
  /// which includes both active and pending. A direct `activeTasks`
  /// count isn't readily available.
  int get activeAndPendingTasks => _queue.remainingItemCount;

  /// Returns the number of tasks waiting in the queue.
  /// This is equivalent to `activeAndPendingTasks` as `queue` package doesn't
  /// differentiate between active and pending in its public API for counts.
  int get pendingTasks => _queue.remainingItemCount;

  /// Disposes of the queue.
  ///
  /// This will prevent new tasks from being added and cancel all pending tasks.
  /// It's recommended to call [join] (or `await queue.onComplete`) before
  /// disposing if you need to ensure all tasks complete.
  Future<void> dispose() async {
    _log.info('Disposing RequestQueue (remaining: $activeAndPendingTasks)...');
    try {
      // The `dispose` method in `package:queue` closes the `remainingItems`
      // stream controller and cancels pending tasks with
      // QueueCancelledException.
      _queue.dispose();
      _log.info('RequestQueue disposed.');
    } catch (e) {
      if (e is! QueueCancelledException) {
        _log.warning('Error disposing RequestQueue: $e');
        rethrow;
      }
      // QueueCancelledException is expected when cancelling pending tasks
      _log.info('RequestQueue disposed (pending tasks cancelled).');
    }
  }

  /// Waits for all currently enqueued tasks to complete.
  Future<void> join() async {
    _log.fine(
      'Waiting for all tasks to complete (join). '
      'Remaining: $activeAndPendingTasks',
    );
    await _queue.onComplete;
    _log.fine('All tasks completed (join).');
  }
}
