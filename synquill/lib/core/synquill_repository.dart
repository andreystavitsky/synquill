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

/// Base class for synchronized repositories.
///
/// This class provides the core functionality for repositories that
/// synchronize data between a local database and a remote API.
abstract class SynquillRepositoryBase<T extends SynquillDataModel<T>> {
  /// The database connection.
  final GeneratedDatabase db;

  /// The logger for this repository.
  late final Logger log;

  /// The queue manager for handling API operations.
  late final RequestQueueManager _queueManager;

  /// The stream controller for repository change events.
  final StreamController<RepositoryChange<T>> _changeController =
      StreamController<RepositoryChange<T>>.broadcast();

  /// Creates a new synchronized repository.
  SynquillRepositoryBase(this.db) {
    log = Logger('SyncedRepository<${T.toString()}>');
    try {
      _queueManager = SynquillStorage.queueManager;
    } catch (_) {
      // For tests or when SyncedStorage is not initialized
      _queueManager = RequestQueueManager();
    }
  }

  /// A stream of changes to this repository.
  Stream<RepositoryChange<T>> get changes => _changeController.stream;

  /// Gets the default save policy from global configuration.
  @protected
  DataSavePolicy get defaultSavePolicy {
    return SynquillStorage.config?.defaultSavePolicy ??
        DataSavePolicy.localFirst;
  }

  /// Gets the default load policy from global configuration.
  @protected
  DataLoadPolicy get defaultLoadPolicy {
    return SynquillStorage.config?.defaultLoadPolicy ??
        DataLoadPolicy.localThenRemote;
  }

  /// Gets the API adapter for this repository.
  /// This needs to be implemented by the concrete generated repository.
  @protected
  ApiAdapterBase<T> get apiAdapter =>
      throw UnimplementedError(
        'apiAdapter getter must be implemented by subclasses',
      );

  /// Finds an item by ID.
  ///
  /// Returns null if the item doesn\'t exist.
  ///
  /// [id] The unique identifier of the item to find.
  /// [loadPolicy] Controls whether to load from local storage, remote API,
  /// or both.
  /// [QueryParams] Additional query parameters for filtering, sorting,
  /// and pagination (applied to local queries).
  Future<T?> findOne(
    String id, {
    DataLoadPolicy? loadPolicy,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    loadPolicy ??= defaultLoadPolicy;
    queryParams ??= QueryParams.empty;
    log.info('Finding $T with ID $id using policy ${loadPolicy.name}');

    T? result;

    switch (loadPolicy) {
      case DataLoadPolicy.localOnly:
        log.info('Policy: localOnly. Getting $T from local database');
        result = await fetchFromLocal(id, queryParams: queryParams);
        break;
      case DataLoadPolicy.remoteFirst:
        log.info('Policy: remoteFirst. Fetching $T $id from remote API');
        try {
          final T? remoteItem = await fetchFromRemote(
            id,
            extra: extra,
            queryParams: queryParams,
            headers: headers,
          );
          if (remoteItem != null) {
            log.fine('Remote fetch for $id successful. Updating local copy.');
            await saveToLocal(remoteItem);
            result = remoteItem;
          } else {
            // fetchFromRemote returned null without ApiExceptionNotFound/NoContent.
            // This is an unexpected response. Fall back to local.
            log.warning(
              'Remote fetch for $T $id returned null unexpectedly. '
              'Falling back to local.',
            );
            result = await fetchFromLocal(id, queryParams: queryParams);
          }
        } on ApiExceptionGone catch (e, stackTrace) {
          log.fine(
            'No content for $id in remote API (410). Removing local copy.',
            e,
            stackTrace,
          );
          await removeFromLocalIfExists(id);
          result = null;
        } catch (e, stackTrace) {
          // Other ApiErrors or network issues.
          log.warning(
            'Failed to get $T $id from API, or API error. Falling back '
            'to local.',
            e,
            stackTrace,
          );
          result = await fetchFromLocal(id, queryParams: queryParams);
        }
        break;
      case DataLoadPolicy.localThenRemote:
        log.info(
          'Policy: localThenRemote. Getting $T $id from local database first.',
        );
        final T? localResult = await fetchFromLocal(
          id,
          queryParams: queryParams,
        );

        if (localResult != null) {
          log.fine(
            'Item $id found locally. Returning it and async refreshing '
            'from remote.',
          );
          result = localResult; // Return local data immediately

          // Asynchronously fetch from remote and update local cache
          // Ensure this block is async to use await inside
          () async {
            try {
              final remoteItem = await fetchFromRemote(
                id,
                extra: extra,
                queryParams: queryParams,
                headers: headers,
              );
              if (remoteItem != null) {
                log.fine(
                  'Async remote fetch for $id (localThenRemote) successful. '
                  'Updating local copy.',
                );
                try {
                  await saveToLocal(remoteItem);
                } catch (saveError, saveStackTrace) {
                  log.warning(
                    'Error saving remotely fetched item to local cache for '
                    '$id in localThenRemote',
                    saveError,
                    saveStackTrace,
                  );
                }
              } else {
                // Async fetchFromRemote returned null without specific error.
                // Log warning, local data preserved.
                log.warning(
                  'Async remote fetch for $id (localThenRemote) returned '
                  'null unexpectedly. Local data preserved.',
                );
              }
            } catch (fetchError, fetchStackTrace) {
              if (fetchError is ApiExceptionNotFound ||
                  fetchError is ApiExceptionGone) {
                log.fine(
                  'Async remote fetch for $id (localThenRemote) '
                  'confirmed not '
                  'found/no content. Removing local copy.',
                  fetchError,
                  fetchStackTrace,
                );
                try {
                  await removeFromLocalIfExists(id);
                } catch (removeError, removeStackTrace) {
                  log.warning(
                    'Error removing local $id after async not found/no '
                    'content in localThenRemote',
                    removeError,
                    removeStackTrace,
                  );
                }
              } else {
                log.warning(
                  'Error during async remote fetch for $id '
                  '(localThenRemote). '
                  'Local data preserved.',
                  fetchError,
                  fetchStackTrace,
                );
              }
            }
          }();
        } else {
          log.info(
            'Item $id not found locally. Fetching from remote API sync.',
          );
          try {
            final T? remoteItem = await fetchFromRemote(
              id,
              extra: extra,
              queryParams: queryParams,
              headers: headers,
            );
            if (remoteItem != null) {
              log.fine(
                'Remote fetch for $id successful after local miss. '
                'Saving local.',
              );
              await saveToLocal(remoteItem);
              result = remoteItem;
            } else {
              log.warning(
                'Remote fetch for $T $id after local miss returned null '
                'unexpectedly. Result is null.',
              );
              result = null;
            }
          } on ApiExceptionGone catch (e, stackTrace) {
            log.fine(
              'HTTP Gone status for $id in remote API (410) after local miss.',
              e,
              stackTrace,
            );
            result = null;
          } catch (e, stackTrace) {
            log.warning(
              'Failed to get $T $id from API after local miss, or API error. '
              'Result is null.',
              e,
              stackTrace,
            );
            result = null;
          }
        }
        break;
    }
    return result;
  }

  /// Watches a single item by its ID.
  ///
  /// Returns a stream that emits the item or null if not found.
  ///
  /// [id] The unique identifier of the item to watch.
  /// [loadPolicy] Controls whether to load from local storage, remote API,
  /// or both.
  /// [QueryParams] Additional query parameters for filtering
  /// (applied to local queries).
  Stream<T?> watchOne(
    String id, {
    DataLoadPolicy? loadPolicy,
    QueryParams? queryParams,
  }) {
    loadPolicy ??= defaultLoadPolicy;
    queryParams ??= QueryParams.empty;
    log.info('Finding $T with ID $id using policy ${loadPolicy.name}');

    if (loadPolicy == DataLoadPolicy.remoteFirst) {
      throw UnimplementedError(
        'watchOne() with remoteFirst policy is not implemented for $T',
      );
    } else {
      // Local first - just get from local DB
      log.info('Getting $T from local database');
      return watchFromLocal(id);
    }
  }

  /// Finds an item by ID.
  ///
  /// Throws [NotFoundException] if the item doesn't exist.
  ///
  /// [id] The unique identifier of the item to find.
  /// [loadPolicy] Controls whether to load from local storage, remote API,
  /// or both.
  /// [QueryParams] Additional query parameters for filtering, sorting,
  /// and pagination (applied to local queries).
  Future<T> findOneOrFail(
    String id, {
    DataLoadPolicy? loadPolicy,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    final result = await findOne(id, loadPolicy: loadPolicy);
    if (result == null) {
      throw NotFoundException('$T with ID $id not found');
    }
    return result;
  }

  /// Fetches an item from the remote API.
  ///
  /// This is a placeholder that should be overridden by concrete repository.
  /// [QueryParams] Additional query parameters for filtering
  /// (may be used for complex lookups).
  @protected
  Future<T?> fetchFromRemote(
    String id, {
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    log.warning('fetchFromRemote() not implemented for $T');
    return null;
  }

  /// Fetches an item from the local database.
  ///
  /// This is a placeholder that should be overridden by concrete repository.
  /// [QueryParams] Additional query parameters for filtering
  /// (applied to local queries).
  @protected
  Future<T?> fetchFromLocal(String id, {QueryParams? queryParams}) async {
    log.warning('fetchFromLocal() not implemented for $T');
    return null;
  }

  /// Watches a single item from the local database by its ID.
  ///
  /// This is a placeholder that should be overridden by concrete repository.
  /// [QueryParams] Additional query parameters for filtering
  /// (applied to local queries).
  @protected
  Stream<T?> watchFromLocal(String id, {QueryParams? queryParams}) {
    log.warning('watchFromLocal() not implemented for $T');
    return Stream<T?>.empty();
  }

  /// Saves an item to the local database.
  ///
  /// This is a placeholder that should be overridden by concrete repository.
  @protected
  Future<void> saveToLocal(T item) async {
    log.warning('saveToLocal() not implemented for $T');
  }

  /// Removes an item from the local database if it exists.
  ///
  /// This is a placeholder that should be overridden by concrete repository.
  @protected
  Future<void> removeFromLocalIfExists(String id) async {
    log.warning('removeFromLocalIfExists() not implemented for $T');
  }

  /// Truncates (clears) all local storage for this model type.
  ///
  /// This is a placeholder that should be overridden by concrete repository.
  /// Only affects local storage - does not trigger API synchronization.
  @protected
  Future<void> truncateLocalStorage() async {
    log.warning('truncateLocalStorage() not implemented for $T');
  }

  /// Truncates (clears) all local storage for this model type.
  ///
  /// This method deletes all records from the local table without triggering
  /// API synchronization. It's useful for "refreshing" local data by loading
  /// records from API after clearing the local cache.
  ///
  /// Note: This does not affect sync_queue_items - only the model table.
  Future<void> truncateLocal() async {
    log.info('Truncating all local storage for $T');
    try {
      await truncateLocalStorage();
      log.fine('Local storage truncated successfully for $T');
      _changeController.add(RepositoryChange.deleted('*'));
      // '*' indicates all items deleted
    } catch (e, stackTrace) {
      log.severe('Failed to truncate local storage for $T', e, stackTrace);
      _changeController.add(RepositoryChange.error(e, stackTrace));
      rethrow;
    }
  }

  /// Finds all items of this type.
  ///
  /// This may return cached data if the policy is [DataLoadPolicy.localOnly].
  ///
  /// [loadPolicy] Controls whether to load from local storage, remote API,
  /// or both.
  /// [queryParams] Query parameters for filtering, sorting, and pagination.
  Future<List<T>> findAll({
    DataLoadPolicy? loadPolicy,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    loadPolicy ??= defaultLoadPolicy;
    queryParams ??= QueryParams.empty;
    log.info(
      'Finding all $T using policy ${loadPolicy.name} and params: $queryParams',
    );

    List<T> results = [];

    switch (loadPolicy) {
      case DataLoadPolicy.localOnly:
        log.info('Policy: localOnly. Getting all $T from local database');
        results = await fetchAllFromLocal(queryParams: queryParams);
        break;
      case DataLoadPolicy.remoteFirst:
        log.info('Policy: remoteFirst. Fetching all $T from remote API');
        try {
          final List<T> remoteItems = await fetchAllFromRemote(
            queryParams: queryParams,
            extra: extra,
            headers: headers,
          );
          // Unlike findOne, an empty list from fetchAllFromRemote is
          // a valid response.
          // It means no items match the query on the remote.
          log.fine(
            'Remote fetch successful. Got ${remoteItems.length} items. '
            'Updating local cache.',
          );
          await updateLocalCache(remoteItems); // Handles empty list correctly
          // Fetch from local to get filtered results (excluding items with
          // pending sync operations)

          results = await fetchAllFromLocalWithoutPendingSyncOps(
            queryParams: queryParams,
          );
        } on ApiExceptionGone catch (e, stackTrace) {
          // 204 for a list endpoint implies no items match the query.
          log.fine(
            'No content for query in remote API (410). '
            'Clearing relevant local cache.',
            e,
            stackTrace,
          );
          await updateLocalCache([]);
          results = [];
        } catch (e, stackTrace) {
          log.warning(
            'Failed to get all $T from API, or API error. Falling back to '
            'local.',
            e,
            stackTrace,
          );
          results = await fetchAllFromLocal(queryParams: queryParams);
        }
        break;
      case DataLoadPolicy.localThenRemote:
        log.info(
          'Policy: localThenRemote. Getting all $T from local database first.',
        );
        try {
          results = await fetchAllFromLocal(queryParams: queryParams);
          log.fine(
            'Got ${results.length} items locally. Async refreshing from '
            'remote.',
          );
          fetchAllFromRemote(
                queryParams: queryParams,
                extra: extra,
                headers: headers,
              )
              .then((remoteItems) {
                log.fine(
                  'Async remote fetch for all $T (localThenRemote) '
                  'completed with '
                  '${remoteItems.length} items. Updating cache.',
                );
                updateLocalCache(remoteItems).catchError((
                  updateError,
                  updateStackTrace,
                ) {
                  log.warning(
                    'Error updating local cache for all $T in localThenRemote '
                    'async update',
                    updateError,
                    updateStackTrace,
                  );
                });
              })
              .catchError((fetchError, fetchStackTrace) {
                if (fetchError is ApiExceptionNotFound ||
                    fetchError is ApiExceptionGone) {
                  log.fine(
                    'Async remote fetch for all $T (localThenRemote) found no '
                    'items or no content. Clearing local cache.',
                    fetchError,
                    fetchStackTrace,
                  );
                  updateLocalCache([]).catchError((
                    updateError,
                    updateStackTrace,
                  ) {
                    log.warning(
                      'Error clearing local cache after async '
                      'not found/no content '
                      'for all $T in localThenRemote',
                      updateError,
                      updateStackTrace,
                    );
                  });
                } else {
                  log.warning(
                    'Error during async remote fetch for all $T '
                    '(localThenRemote). '
                    'Local data preserved.',
                    fetchError,
                    fetchStackTrace,
                  );
                }
              });
        } catch (localError, localStackTrace) {
          log.warning(
            'Failed to get all $T from local DB in localThenRemote. '
            'Fetching from remote API sync.',
            localError,
            localStackTrace,
          );
          try {
            final List<T> remoteItems = await fetchAllFromRemote(
              queryParams: queryParams,
              extra: extra,
              headers: headers,
            );
            log.fine(
              'Remote fetch successful after local error. Got '
              '${remoteItems.length} items. Updating local cache.',
            );
            await updateLocalCache(remoteItems);
            results = remoteItems;
          } on ApiExceptionGone catch (e, stackTrace) {
            log.fine(
              'No content for query (410) after local error.',
              e,
              stackTrace,
            );
            await updateLocalCache([]);
            results = [];
          } catch (remoteError, remoteStackTrace) {
            log.severe(
              'Failed to get all $T from API after local error in '
              'localThenRemote, or API error.',
              remoteError,
              remoteStackTrace,
            );
            _changeController.add(
              RepositoryChange.error(remoteError, remoteStackTrace),
            );
            results = [];
          }
        }
        break;
    }
    return results;
  }

  /// Watches all items in the local repository.
  ///
  /// Returns a stream that emits the list of all items whenever they change.
  ///
  /// [queryParams] Query parameters for filtering, sorting, and pagination.
  Stream<List<T>> watchAll({QueryParams? queryParams}) {
    queryParams ??= QueryParams.empty;
    log.info('Watching all $T');

    // Local first - just get from local DB
    log.info('Getting all $T from local database');
    return watchAllFromLocal(queryParams: queryParams);
  }

  /// Fetches all items from the remote API.
  ///
  /// This is a placeholder that should be overridden by concrete repository.
  /// [queryParams] Query parameters for filtering, sorting, and pagination.
  @protected
  Future<List<T>> fetchAllFromRemote({
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    log.warning('fetchAllFromRemote() not implemented for $T');
    return [];
  }

  /// Fetches all items from the local database.
  ///
  /// This is a placeholder that should be overridden by concrete repository.
  /// [queryParams] Query parameters for filtering, sorting, and pagination.
  @protected
  Future<List<T>> fetchAllFromLocal({QueryParams? queryParams}) async {
    log.warning('fetchAllFromLocal() not implemented for $T');
    return [];
  }

  /// Fetches all items from the local database, excluding those
  /// with pending sync operations.
  ///
  /// This is a placeholder that should be overridden by concrete repository.
  /// [queryParams] Query parameters for filtering, sorting, and pagination.
  @protected
  Future<List<T>> fetchAllFromLocalWithoutPendingSyncOps({
    QueryParams? queryParams,
  }) async {
    log.warning(
      'fetchAllFromLocalWithoutPendingSyncOps() not implemented for $T',
    );
    return [];
  }

  @protected
  /// Watches all items from the local database.
  ///
  /// This is a placeholder that should be overridden by concrete repository.
  /// [queryParams] Query parameters for filtering, sorting, and pagination.
  Stream<List<T>> watchAllFromLocal({QueryParams? queryParams}) {
    log.warning('watchAllFromLocal() not implemented for $T');
    return Stream<List<T>>.empty();
  }

  /// Updates the local cache with remote data.
  ///
  /// This is a placeholder that should be overridden by concrete repository.
  @protected
  Future<void> updateLocalCache(List<T> items) async {
    log.warning('updateLocalCache() not implemented for $T');
    for (final item in items) {
      await saveToLocal(item);
    }
  }

  /// Checks if an item with the given ID exists in the local database.
  /// This is a placeholder and should be overridden by concrete repositories.
  @protected
  Future<bool> isExistingItem(T item) async {
    // Default implementation, should be overridden.
    // For safety, assume item doesn't exist if not overridden,
    // to avoid accidental updates if create was intended.
    // However, a more robust approach is to require override or have a clear
    // contract on how newness is determined (e.g., model has an isNew flag).
    // For now, let's log and return false.
    log.warning(
      'isExistingItem() not implemented for $T with id ${item.id}, '
      'assuming false (new item).',
    );
    final existing = await fetchFromLocal(item.id, queryParams: null);
    return existing != null;
  }

  /// Saves an item.
  ///
  /// [item] The item to save.
  /// [savePolicy] Controls whether to save to local storage, remote API,
  /// or both.
  Future<T> save(
    T item, {
    DataSavePolicy? savePolicy,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    savePolicy ??= defaultSavePolicy;
    log.info('Saving $T with ID ${item.id} using policy ${savePolicy.name}');

    // Ensure the item has a repository reference.
    item.$setRepository(this);

    T resultItem;

    switch (savePolicy) {
      case DataSavePolicy.localFirst:
        log.info('Policy: localFirst. Saving $T to local database first.');

        // Determine if this is a create or update operation
        final isExisting = await isExistingItem(item);
        var operation =
            isExisting ? SyncOperation.update : SyncOperation.create;

        // Save to local database first
        await saveToLocal(item);
        _changeController.add(RepositoryChange.updated(item));
        log.fine(
          'Local save for ${item.id} successful. Creating sync queue entry.',
        );

        // Create sync queue entry for persistence and retry capability
        final idempotencyKey =
            '${item.id}-${operation.name}-'
            '${DateTime.now().millisecondsSinceEpoch}';
        int syncQueueId;

        final syncQueueDao = SyncQueueDao(SynquillStorage.database);

        try {
          // First check if there's already a pending CREATE task for this model
          // If so, update it with new payload regardless of current operation
          final existingCreateTaskId = await syncQueueDao.findPendingSyncTask(
            T.toString(),
            item.id,
            SyncOperation.create.name,
          );

          if (existingCreateTaskId != null) {
            // Update existing CREATE task with new payload
            await syncQueueDao.updateItem(
              id: existingCreateTaskId,
              payload: convert.jsonEncode(item.toJson()),
              idempotencyKey: idempotencyKey, // Update idempotency key too
              attemptCount: 0, // Reset attempt count for the new payload
              nextRetryAt: null, // Allow immediate retry
              lastError: null, // Clear any previous errors
              headers: headers != null ? convert.jsonEncode(headers) : null,
              extra: extra != null ? convert.jsonEncode(extra) : null,
            );
            syncQueueId = existingCreateTaskId;
            log.fine(
              'Updated existing CREATE sync queue entry $syncQueueId for '
              '${item.id} with new data',
            );
            // Keep it as CREATE operation for the sync task
            operation = SyncOperation.create;
          } else if (operation == SyncOperation.update) {
            // No pending CREATE, check for existing UPDATE task
            final existingUpdateTaskId = await syncQueueDao.findPendingSyncTask(
              T.toString(),
              item.id,
              operation.name,
            );

            if (existingUpdateTaskId != null) {
              // Update existing UPDATE task with new payload
              await syncQueueDao.updateItem(
                id: existingUpdateTaskId,
                payload: convert.jsonEncode(item.toJson()),
                idempotencyKey: idempotencyKey, // Update idempotency key too
                attemptCount: 0, // Reset attempt count for the new payload
                nextRetryAt: null, // Allow immediate retry
                lastError: null, // Clear any previous errors
                headers: headers != null ? convert.jsonEncode(headers) : null,
                extra: extra != null ? convert.jsonEncode(extra) : null,
              );
              syncQueueId = existingUpdateTaskId;
              log.fine(
                'Updated existing UPDATE sync queue entry $syncQueueId for '
                '${item.id} with new data',
              );
            } else {
              // No existing UPDATE task, create a new one
              syncQueueId = await syncQueueDao.insertItem(
                modelId: item.id,
                modelType: T.toString(),
                payload: convert.jsonEncode(item.toJson()),
                operation: operation.name,
                idempotencyKey: idempotencyKey,
                headers: headers != null ? convert.jsonEncode(headers) : null,
                extra: extra != null ? convert.jsonEncode(extra) : null,
              );
              log.fine('Created sync queue entry $syncQueueId for ${item.id}');
            }
          } else {
            // For CREATE operations, always create a new entry
            syncQueueId = await syncQueueDao.insertItem(
              modelId: item.id,
              modelType: T.toString(),
              payload: convert.jsonEncode(item.toJson()),
              operation: operation.name,
              idempotencyKey: idempotencyKey,
              headers: headers != null ? convert.jsonEncode(headers) : null,
              extra: extra != null ? convert.jsonEncode(extra) : null,
            );
            log.fine('Created sync queue entry $syncQueueId for ${item.id}');
          }

          // Now try immediate sync execution
          final syncTask = NetworkTask<void>(
            exec: () => _executeSyncOperation(operation, item, headers, extra),
            idempotencyKey: idempotencyKey,
            operation: operation,
            modelType: T.toString(),
            modelId: item.id,
            taskName: 'BackgroundSync-${T.toString()}-${item.id}',
          );

          await _queueManager.enqueueTask(
            syncTask,
            queueType: QueueType.background,
          );

          // If immediate sync succeeded, remove from sync queue
          await syncQueueDao.deleteTask(syncQueueId);
          log.fine(
            'Immediate sync succeeded, removed sync queue entry $syncQueueId',
          );
        } catch (e, stackTrace) {
          log.warning(
            'Immediate background sync failed for ${item.id}, '
            'task will be retried by RetryExecutor',
            e,
            stackTrace,
          );
          // Don't fail the save operation if immediate sync fails
          // The sync queue entry remains for retry by RetryExecutor
        }

        resultItem = item;
        break;

      case DataSavePolicy.remoteFirst:
        log.info('Policy: remoteFirst. Saving $T to remote API first.');
        try {
          T remoteItem;
          // Use the class's isExistingItem method
          final bool itemExists = await this.isExistingItem(item);

          if (itemExists) {
            log.fine('Item ${item.id} exists, calling adapter.updateOne()');
            final T? updatedItem = await apiAdapter.updateOne(
              item,
              extra: extra,
              headers: headers,
            );
            if (updatedItem == null) {
              // This case should ideally be handled based on API contract.
              // If null means not found or error, throw.
              // If null means no change or success with no content,
              // might be ok.
              // For now, assume it's an issue if we expected an item back.
              log.warning(
                'apiAdapter.updateOne for ${item.id} returned null. '
                'Using local item as fallback.',
              );
              remoteItem = item; // Fallback or decide error strategy
            } else {
              remoteItem = updatedItem;
            }
          } else {
            log.fine('Item ${item.id} is new, calling adapter.createOne()');
            final T? createdItem = await apiAdapter.createOne(
              item,
              extra: extra,
              headers: headers,
            );
            if (createdItem == null) {
              // Similar to update, null from create might be an issue or
              // intended.
              // Assuming an issue if no item is returned after creation.
              log.warning(
                'apiAdapter.createOne for ${item.id} returned null. '
                'Using local item as fallback.',
              );
              remoteItem = item; // Fallback or decide error strategy
            } else {
              remoteItem = createdItem;
            }
          }

          log.fine(
            'Remote save for ${item.id} successful. Updating local copy.',
          );
          // Ensure the remoteItem also has the repository set,
          // especially if it's a new instance from the adapter
          remoteItem.$setRepository(this);
          await saveToLocal(remoteItem);
          _changeController.add(RepositoryChange.updated(remoteItem));
          resultItem = remoteItem;
        } on OfflineException catch (e, stackTrace) {
          log.warning(
            'OfflineException during remoteFirst save for $T ${item.id}. '
            'Operation failed as per policy.',
            e,
            stackTrace,
          );
          _changeController.add(RepositoryChange.error(e, stackTrace));
          rethrow;
        } on ApiException catch (e, stackTrace) {
          log.severe(
            'ApiException during remoteFirst save for $T ${item.id}.',
            e,
            stackTrace,
          );
          _changeController.add(RepositoryChange.error(e, stackTrace));
          throw SynquillStorageException(
            'Failed to save $T ${item.id} with remoteFirst policy due to '
            'API error: $e',
            stackTrace,
          );
        } catch (e, stackTrace) {
          log.severe(
            'Unexpected error during remoteFirst save for $T ${item.id}.',
            e,
            stackTrace,
          );
          _changeController.add(RepositoryChange.error(e, stackTrace));
          throw SynquillStorageException(
            'Failed to save $T ${item.id} with remoteFirst policy: $e',
            stackTrace,
          );
        }
        break;
    }
    return resultItem;
  }

  /// Deletes an item by its ID.
  ///
  /// [id] The unique identifier of the item to delete.
  /// [savePolicy] Controls whether to delete from local storage, remote API,
  /// or both.
  Future<void> delete(
    String id, {
    DataSavePolicy? savePolicy,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    savePolicy ??= defaultSavePolicy;
    log.info('Deleting $T with ID $id using policy ${savePolicy.name}');

    // Handle cascade delete first
    await _handleCascadeDelete(
      id: id,
      savePolicy: savePolicy,
      extra: extra,
      headers: headers,
    );

    // Use smart delete logic to handle sync queue entries properly

    final itemToDelete = await fetchFromLocal(id);

    final payload =
        itemToDelete != null
            ? convert.jsonEncode(itemToDelete.toJson())
            : convert.jsonEncode({'id': id}); // Fallback with just ID

    switch (savePolicy) {
      case DataSavePolicy.localFirst:
        log.info('Policy: localFirst. Deleting $T from local database first.');

        await _handleSmartDelete(
          modelId: id,
          payload: payload,
          scheduleDelete: true,
          headers: headers,
          extra: extra,
        );

        await removeFromLocalIfExists(id);
        _changeController.add(RepositoryChange.deleted(id));
        log.fine('Local delete for $id successful.');

        return;
      case DataSavePolicy.remoteFirst:
        log.info('Policy: remoteFirst. Deleting $T from remote API first.');
        try {
          await apiAdapter.deleteOne(id, extra: extra, headers: headers);
          log.fine(
            'Remote delete for $id successful. Removing from local copy.',
          );

          await _handleSmartDelete(
            modelId: id,
            payload: payload,
            scheduleDelete: false,
            headers: headers,
            extra: extra,
          );
          await removeFromLocalIfExists(id);
          _changeController.add(RepositoryChange.deleted(id));
        } on OfflineException catch (e, stackTrace) {
          log.warning(
            'OfflineException during remoteFirst delete for $T $id. '
            'Operation failed as per policy.',
            e,
            stackTrace,
          );
          _changeController.add(RepositoryChange.error(e, stackTrace));
          rethrow;
        } on ApiExceptionGone catch (e, stackTrace) {
          // If remote says not found, it's good to ensure local is also gone.
          log.fine(
            'Item $id not found on remote during remoteFirst delete. '
            'Ensuring local removal.',
            e,
            stackTrace,
          );
          await _handleSmartDelete(
            modelId: id,
            payload: payload,
            scheduleDelete: false,
            headers: headers,
            extra: extra,
          );
          await removeFromLocalIfExists(id);
          _changeController.add(RepositoryChange.deleted(id));
          // Not rethrowing as the desired state (item gone) is achieved.
        } on ApiException catch (e, stackTrace) {
          log.severe(
            'ApiException during remoteFirst delete for $T $id.',
            e,
            stackTrace,
          );
          _changeController.add(RepositoryChange.error(e, stackTrace));
          throw SynquillStorageException(
            'Failed to delete $T $id with remoteFirst policy due to '
            'API error: $e',
            stackTrace,
          );
        } catch (e, stackTrace) {
          log.severe(
            'Unexpected error during remoteFirst delete for $T $id.',
            e,
            stackTrace,
          );
          _changeController.add(RepositoryChange.error(e, stackTrace));
          throw SynquillStorageException(
            'Failed to delete $T $id with remoteFirst policy: $e',
            stackTrace,
          );
        }
        return;
    }
  }

  /// Executes a sync operation for background queue processing.
  ///
  /// This method is called by NetworkTask to perform the actual API operation
  /// for background sync operations.
  Future<void> _executeSyncOperation(
    SyncOperation operation,
    T item,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  ) async {
    log.fine('Executing sync operation: ${operation.name} for ${item.id}');

    try {
      switch (operation) {
        case SyncOperation.create:
          await apiAdapter.createOne(item, extra: extra, headers: headers);
          break;
        case SyncOperation.update:
          await apiAdapter.updateOne(item, extra: extra, headers: headers);
          break;
        case SyncOperation.delete:
          await apiAdapter.deleteOne(item.id, extra: extra, headers: headers);
          break;
      }
      log.info('Sync operation ${operation.name} successful for ${item.id}');
    } catch (e, stackTrace) {
      log.warning(
        'Sync operation ${operation.name} failed for ${item.id}',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Closes the repository and its resources.
  Future<void> close() async {
    if (!_changeController.isClosed) {
      await _changeController.close();
    }
  }

  Future<void> _handleSmartDelete({
    required String modelId,
    required String payload,
    required bool scheduleDelete,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final syncQueueDao = SyncQueueDao(SynquillStorage.database);
    try {
      final deleteResult = await syncQueueDao.handleModelDeletion(
        modelType: T.toString(),
        modelId: modelId,
        payload: payload,
        idempotencyKey:
            '$modelId-delete-${DateTime.now().millisecondsSinceEpoch}',
        scheduleDelete: scheduleDelete,
        headers: headers != null ? convert.jsonEncode(headers) : null,
        extra: extra != null ? convert.jsonEncode(extra) : null,
      );

      log.fine(
        'Smart delete for $T $modelId completed with action: '
        '${deleteResult['action']}, '
        'deleted ${deleteResult['deleted_records']} '
        'records, created delete ID: ${deleteResult['created_delete_id']}',
      );
    } catch (e, stackTrace) {
      log.warning(
        'Failed to handle smart delete for $T $modelId, '
        'continuing with deletion',
        e,
        stackTrace,
      );
    }
  }

  /// Handles cascade delete for models with cascadeDelete = true relationships
  Future<void> _handleCascadeDelete({
    required String id,
    required DataSavePolicy savePolicy,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    try {
      // Use the generated ModelInfoRegistry to get cascade delete info
      final modelTypeName = T.toString();
      log.fine('Checking for cascade delete relations for $modelTypeName');

      // This will be available after code generation includes ModelInfoRegistry
      try {
        // Get cascade delete relations for this model type
        final cascadeRelations = _getCascadeDeleteRelations(modelTypeName);

        if (cascadeRelations.isEmpty) {
          log.fine('No cascade delete relations found for $modelTypeName');
          return;
        }

        log.info(
          'Found ${cascadeRelations.length} cascade delete relations '
          'for $modelTypeName',
        );

        // For each cascade delete relation, find and delete related items
        for (final relation in cascadeRelations) {
          await _deleteCascadeRelatedItems(
            parentId: id,
            relation: relation,
            savePolicy: savePolicy,
            extra: extra,
            headers: headers,
          );
        }
      } catch (e) {
        // ModelInfoRegistry might not be available yet during development
        log.fine(
          'ModelInfoRegistry not available, skipping cascade delete: $e',
        );
      }
    } catch (e, stackTrace) {
      log.warning(
        'Error during cascade delete for $T $id, continuing with main deletion',
        e,
        stackTrace,
      );
      // Don't rethrow - we don't want cascade delete issues to prevent
      // main deletion
    }
  }

  /// Get cascade delete relations for a model type
  /// This method uses the ModelInfoRegistryProvider to get cascade delete info
  List<CascadeDeleteRelation> _getCascadeDeleteRelations(String modelTypeName) {
    return ModelInfoRegistryProvider.getCascadeDeleteRelations(modelTypeName);
  }

  /// Delete related items for a cascade delete relation
  Future<void> _deleteCascadeRelatedItems({
    required String parentId,
    required CascadeDeleteRelation relation,
    required DataSavePolicy savePolicy,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    try {
      final targetType = relation.targetType;
      final mappedBy = relation.mappedBy;

      log.info('Cascade deleting $targetType items with $mappedBy = $parentId');

      // Get the repository for the target type
      final targetRepository = SynquillRepositoryProvider.getByTypeName(
        targetType,
      );
      if (targetRepository == null) {
        log.warning('No repository found for target type $targetType');
        return;
      }

      // Find all related items using the mappedBy field
      // Create a basic filter condition for the foreign key field
      final fieldSelector = FieldSelector<String>(mappedBy, String);
      final queryParams = QueryParams(
        filters: [fieldSelector.equals(parentId)],
      );

      final relatedItems = await targetRepository.findAll(
        loadPolicy: DataLoadPolicy.localOnly,
        queryParams: queryParams,
        extra: extra,
      );

      log.info(
        'Found ${relatedItems.length} related $targetType items to '
        'cascade delete',
      );

      // Delete each related item (this will recursively handle their
      // cascade deletes)
      for (final item in relatedItems) {
        await targetRepository.delete(
          item.id,
          savePolicy: savePolicy,
          extra: extra,
          headers: headers,
        );
      }

      log.info(
        'Successfully cascade deleted ${relatedItems.length} $targetType items',
      );
    } catch (e, stackTrace) {
      log.severe(
        'Failed to cascade delete related items for relation $relation',
        e,
        stackTrace,
      );
      // Don't rethrow - we want to continue with other cascade relations
    }
  }
}
