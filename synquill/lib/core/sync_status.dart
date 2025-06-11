part of synquill;

/// Enum representing the synchronization status of a record
enum SyncStatus {
  /// The record is pending synchronization to the remote server
  pending,

  /// The record has been successfully synchronized
  synced,

  /// The record failed to synchronize
  dead,
}

/// Drift type converter for SyncStatus enum
///
/// Converts between database String representation and SyncStatus enum
class SyncStatusConverter extends TypeConverter<SyncStatus?, String?> {
  const SyncStatusConverter();

  @override
  SyncStatus? fromSql(String? fromDb) {
    if (fromDb == null) return null;
    return SyncStatus.values.firstWhere(
      (status) => status.name == fromDb,
      orElse: () => SyncStatus.pending,
    );
  }

  @override
  String? toSql(SyncStatus? value) {
    return value?.name;
  }
}

/// Holds detailed synchronization information for a model instance.
///
/// This class contains information about the sync queue status for a specific
/// model, including error details and retry scheduling.
class SyncDetails {
  /// The last error message from a failed sync attempt.
  final String? lastError;

  /// The timestamp when the next retry attempt should occur.
  final DateTime? nextRetryAt;

  /// The number of sync attempts that have been made.
  final int attemptCount;

  /// The current status of the sync operation.
  final SyncStatus status;

  /// The operation type that is pending (create, update, delete).
  final String? operation;

  /// Creates a new [SyncDetails] instance.
  const SyncDetails({
    this.lastError,
    this.nextRetryAt,
    this.attemptCount = 0,
    this.status = SyncStatus.synced,
    this.operation,
  });

  /// Creates a [SyncDetails] instance representing a synced state.
  const SyncDetails.synced()
      : lastError = null,
        nextRetryAt = null,
        attemptCount = 0,
        status = SyncStatus.synced,
        operation = null;

  /// Creates a [SyncDetails] instance from a sync queue task map.
  factory SyncDetails.fromSyncQueueTask(Map<String, dynamic> task) {
    SyncStatus status;
    final statusStr = task['status'] as String?;

    if (statusStr == 'dead') {
      status = SyncStatus.dead;
    } else {
      status = SyncStatus.pending;
    }

    return SyncDetails(
      lastError: task['last_error'] as String?,
      nextRetryAt: task['next_retry_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(task['next_retry_at'] as int)
          : null,
      attemptCount: task['attempt_count'] as int? ?? 0,
      status: status,
      operation: task['op'] as String?,
    );
  }

  /// Whether the model has a pending sync operation.
  bool get hasPendingSync => status == SyncStatus.pending;

  /// Whether the model failed to sync and is marked as dead.
  bool get isDead => status == SyncStatus.dead;

  /// Whether the model is fully synchronized.
  bool get isSynced => status == SyncStatus.synced;

  @override
  String toString() {
    return 'SyncDetails(status: $status, lastError: $lastError, '
        'nextRetryAt: $nextRetryAt, attemptCount: $attemptCount, '
        'operation: $operation)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SyncDetails &&
        other.lastError == lastError &&
        other.nextRetryAt == nextRetryAt &&
        other.attemptCount == attemptCount &&
        other.status == status &&
        other.operation == operation;
  }

  @override
  int get hashCode {
    return Object.hash(
      lastError,
      nextRetryAt,
      attemptCount,
      status,
      operation,
    );
  }
}
