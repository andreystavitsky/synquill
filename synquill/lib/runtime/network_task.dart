part of synquill;

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

  /// Returns the future that completes when this task finishes.
  Future<T> get future => completer.future;

  /// Executes the task and completes the completer.
  Future<void> execute() async {
    try {
      // Wrap exec() in Future.sync() to handle both sync and async exceptions
      final result = await Future.sync(() => exec());
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    } catch (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
  }

  /// Returns a string representation for logging.
  @override
  String toString() {
    final name = taskName ?? '${operation.name}($modelType:$modelId)';
    return 'NetworkTask($name, key: $idempotencyKey)';
  }
}
