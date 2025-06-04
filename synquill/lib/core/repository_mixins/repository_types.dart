part of synquill;

/// Represents a change to a repository.
/// This is used for notifying listeners about changes to the data.
enum RepositoryChangeType {
  /// An item was added to the repository
  created,

  /// An item was updated in the repository
  updated,

  /// An item was deleted from the repository
  deleted,

  /// An error occurred while trying to make a change
  error,
}

/// Represents an operation to be performed on a sync queue.
enum SyncOperation {
  /// Create a new item
  create,

  /// Update an existing item
  update,

  /// Delete an item
  delete,

  /// Read/fetch an item (for immediate operations only, not queued)
  read,
}

/// A change in a repository.
/// This is emitted through the repository's change stream.
class RepositoryChange<T> {
  /// The type of change that occurred
  final RepositoryChangeType type;

  /// The item that was changed, if applicable
  final T? item;

  /// The ID of the item that was changed, if applicable
  final String? id;

  /// An error that occurred, if applicable
  final Object? error;

  /// The stack trace for the error, if applicable
  final StackTrace? stackTrace;

  /// Creates a new repository change event.
  const RepositoryChange({
    required this.type,
    this.item,
    this.id,
    this.error,
    this.stackTrace,
  });

  /// Creates a new repository change event for a created item.
  factory RepositoryChange.created(T item) =>
      RepositoryChange(type: RepositoryChangeType.created, item: item);

  /// Creates a new repository change event for an updated item.
  factory RepositoryChange.updated(T item) =>
      RepositoryChange(type: RepositoryChangeType.updated, item: item);

  /// Creates a new repository change event for a deleted item.
  factory RepositoryChange.deleted(String id, [T? item]) =>
      RepositoryChange(type: RepositoryChangeType.deleted, id: id, item: item);

  /// Creates a new repository change event for an error.
  factory RepositoryChange.error(Object error, [StackTrace? stackTrace]) =>
      RepositoryChange(
        type: RepositoryChangeType.error,
        error: error,
        stackTrace: stackTrace,
      );
}
