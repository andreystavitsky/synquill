import 'dart:async';
import 'package:dio/dio.dart';
import 'package:queue/queue.dart';

import 'package:synquill/src/core/repository_mixins/repository_types.dart';

/// Represents a network operation task that can be executed
/// by the RequestQueue.
///
/// Each NetworkTask encapsulates an API operation with its execution logic,
/// completion handling, and idempotency key for safe retries.
///
class NetworkTask<T> {
  /// The execution function that performs the actual network operation.
  final Future<T> Function() exec;

  /// Completer that will be completed when the task finishes or fails.
  final Completer<T> completer;

  /// Unique idempotency key to prevent duplicate execution.
  /// Format: "cuid-attempt" for retry safety.
  final String idempotencyKey;

  /// Optional task name for logging purposes.
  final String? taskName;

  /// The type of sync operation this task represents.
  final SyncOperation operation;

  /// The model type being operated on.
  final String modelType;

  /// The model ID being operated on.
  final String modelId;

  /// Creates a new NetworkTask.
  ///
  /// [exec] The function that executes the network operation.
  /// [idempotencyKey] Unique key for idempotency (format: "cuid-attempt").
  /// [operation] The type of sync operation.
  /// [modelType] The type of model being operated on.
  /// [modelId] The ID of the model being operated on.
  /// [taskName] Optional descriptive name for logging.
  NetworkTask({
    required this.exec,
    required this.idempotencyKey,
    required this.operation,
    required this.modelType,
    required this.modelId,
    this.taskName,
  }) : completer = Completer<T>();

  final NetworkTaskCancellationContext _cancellationContext =
      NetworkTaskCancellationContext();
  final Completer<void> _executionSettled = Completer<void>();

  /// Internal flag tracking whether this task was explicitly cancelled.
  bool _wasCancelled = false;
  bool _executionStarted = false;

  /// Returns the future that completes when this task finishes.
  Future<T> get future => completer.future;

  /// Completes when [exec] settles, or before it starts if the task is
  /// cancelled while still queued.
  Future<void> get executionSettled => _executionSettled.future;

  /// Whether [exec] has started running.
  bool get executionStarted => _executionStarted;

  /// Whether there is no longer an in-flight execution for this task.
  bool get isExecutionSettled => _executionSettled.isCompleted;

  /// Returns true only if [cancel] was explicitly called on this task.
  /// A successfully completed or failed task returns false.
  bool get isCancelled => _wasCancelled;

  /// Cancels this task with a QueueCancelledException.
  void cancel() {
    _wasCancelled = true;
    _cancellationContext.cancel();
    if (!completer.isCompleted) {
      // Cancellation may arrive while execute() is still waiting on transport.
      // Attach a handler before completing with an error so the deliberate
      // cancellation is not reported as an unhandled async error in that gap.
      unawaited(completer.future.then<void>((_) {}, onError: (_) {}));
      completer.completeError(QueueCancelledException());
    }
    if (!_executionStarted) {
      _settleExecution();
    }
  }

  /// Executes the task and completes the completer.
  Future<void> execute() async {
    _executionStarted = true;
    try {
      // Wrap exec() in Future.sync() to handle both sync and async exceptions
      final result = await NetworkTaskCancellationContext._run(
        _cancellationContext,
        () => Future.sync(exec),
      );
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    } catch (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    } finally {
      _settleExecution();
    }
  }

  void _settleExecution() {
    if (!_executionSettled.isCompleted) {
      _executionSettled.complete();
    }
  }

  /// Returns a string representation for logging.
  @override
  String toString() {
    final name = taskName ?? '${operation.name}($modelType:$modelId)';
    return 'NetworkTask($name, key: $idempotencyKey)';
  }
}

/// Cancellation state available while a [NetworkTask] is executing.
///
/// Built-in Dio-backed adapters consume [current] to attach a cancel token
/// without widening the public CRUD adapter method signatures.
class NetworkTaskCancellationContext {
  static final Object _zoneKey = Object();

  /// Dio token for the task currently running in this context.
  final CancelToken cancelToken = CancelToken();

  /// The active task cancellation context, if code runs inside a task [exec].
  static NetworkTaskCancellationContext? get current =>
      Zone.current[_zoneKey] as NetworkTaskCancellationContext?;

  /// Cancels the Dio token associated with the running task.
  void cancel() {
    if (!cancelToken.isCancelled) {
      cancelToken.cancel('NetworkTask cancelled');
    }
  }

  static Future<R> _run<R>(
    NetworkTaskCancellationContext context,
    Future<R> Function() body,
  ) {
    return runZoned(body, zoneValues: {_zoneKey: context});
  }
}
