part of synquill;

/// Enum representing the synchronization status of a record
enum SyncStatus {
  /// The record is pending synchronization to the remote server
  pending,

  /// The record is currently being synchronized
  syncing,

  /// The record has been successfully synchronized
  synced,

  /// The record failed to synchronize
  failed,
}

/// Extension providing JSON serialization utilities for [SyncStatus].
extension SyncStatusExtension on SyncStatus {
  /// Convert the enum to a string representation
  String toJson() => name;

  /// Create SyncStatus from string representation
  static SyncStatus fromJson(String value) {
    return SyncStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => SyncStatus.pending,
    );
  }
}
