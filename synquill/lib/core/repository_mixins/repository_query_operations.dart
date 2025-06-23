part of synquill;

/// Mixin providing query operations for repositories.
mixin RepositoryQueryOperations<T extends SynquillDataModel<T>>
    on
        RepositoryLocalOperations<T>,
        RepositoryRemoteOperations<T>,
        RepositoryDeleteOperations<T> {
  /// Gets the default load policy from global configuration.
  @protected
  DataLoadPolicy get defaultLoadPolicy;

  /// The stream controller for repository change events.
  @override
  StreamController<RepositoryChange<T>> get changeController;

  /// The request queue manager for handling queued operations.
  @override
  RequestQueueManager get queueManager;

  /// Finds an item by ID.
  ///
  /// Returns null if the item doesn't exist.
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
          // Create a NetworkTask for remoteFirst query operation
          // and route through foreground queue for immediate execution
          final remoteFirstFetchTask = NetworkTask<T?>(
            exec: () => fetchFromRemote(
              id,
              extra: extra,
              queryParams: queryParams,
              headers: headers,
            ),
            idempotencyKey: '$id-remoteFirst-fetch-${cuid()}',
            operation: SyncOperation.read,
            modelType: T.toString(),
            modelId: id,
            taskName: 'remoteFirst_fetch_$T',
          );

          // Execute via foreground queue
          final T? remoteItem = await queueManager.enqueueTask(
            remoteFirstFetchTask,
            queueType: QueueType.foreground,
          );

          if (remoteItem != null) {
            log.fine('Remote fetch for $id successful. Updating local copy.');
            await saveToLocal(remoteItem);
            result = remoteItem;
          } else {
            // fetchFromRemote returned null without
            // ApiExceptionNotFound/NoContent.
            // This is an unexpected response. Fall back to local.
            log.warning(
              'Remote fetch for $T $id returned null unexpectedly. '
              'Falling back to local.',
            );
            result = await fetchFromLocal(id, queryParams: queryParams);
          }
        } on ApiExceptionGone catch (e, stackTrace) {
          log.fine(
            'No content for $id in remote API (410). Triggering cascade '
            'delete and removing local copy.',
            e,
            stackTrace,
          );
          await handleCascadeDeleteAfterGone(
            id,
            extra: extra,
            headers: headers,
          );
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
          'Policy: localThenRemote. Getting $T from local database first.',
        );
        try {
          result = await fetchFromLocal(id, queryParams: queryParams);
          log.fine(
            'Got local result for $id: '
            '${result != null ? "found" : "not found"}. '
            'Async refreshing from remote.',
          );
          // Async remote refresh using load queue instead of unawaited
          _enqueueRemoteFetchTask(
            id,
            queryParams: queryParams,
            extra: extra,
            headers: headers,
          );
        } catch (localError, localStackTrace) {
          log.warning(
            'Failed to get $T $id from local database, trying remote',
            localError,
            localStackTrace,
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
                'Remote fetch for $id successful after local failure. '
                'Updating local copy.',
              );
              await saveToLocal(remoteItem);
              result = remoteItem;
            } else {
              log.warning(
                'Remote fetch for $T $id also returned null after local '
                'failure.',
              );
              result = null;
            }
          } on ApiExceptionGone catch (e, stackTrace) {
            log.fine(
              'No content for $id in remote API (410) after local failure.',
              e,
              stackTrace,
            );
            // Item is gone from server - trigger cascade delete
            await handleCascadeDeleteAfterGone(
              id,
              extra: extra,
              headers: headers,
            );
            result = null;
          } catch (remoteError, remoteStackTrace) {
            log.warning(
              'Both local and remote fetch failed for $T $id',
              remoteError,
              remoteStackTrace,
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
    log.info('Watching $T with ID $id using policy ${loadPolicy.name}');

    // For watch operations, only use local database
    // Load policy affects the initial fetch, but watch always monitors local
    switch (loadPolicy) {
      case DataLoadPolicy.localOnly:
        log.info('Policy: localOnly. Watching $T from local database');
        return watchFromLocal(id, queryParams: queryParams);
      case DataLoadPolicy.remoteFirst:
        throw UnimplementedError(
          'Remote first policy is not supported for watchOne. '
          'Use localThenRemote or localOnly instead.',
        );
      case DataLoadPolicy.localThenRemote:
        log.info(
          'Policy: ${loadPolicy.name}. Async refresh then watch from local',
        );
        // Trigger async fetch to ensure local is up to date using load queue
        _enqueueRemoteFetchTask(id, queryParams: queryParams);
        // Return local watch stream
        return watchFromLocal(id, queryParams: queryParams);
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
          // Create a NetworkTask for remoteFirst findAll operation
          // and route through foreground queue for immediate execution
          final remoteFirstFetchAllTask = NetworkTask<List<T>>(
            exec: () => fetchAllFromRemote(
              queryParams: queryParams,
              extra: extra,
              headers: headers,
            ),
            idempotencyKey: 'all-remoteFirst-fetch-'
                '${cuid()}',
            operation: SyncOperation.read,
            modelType: T.toString(),
            modelId: 'all',
            taskName: 'remoteFirst_fetchAll_$T',
          );

          // Execute via foreground queue
          final List<T> remoteItems = await queueManager.enqueueTask(
            remoteFirstFetchAllTask,
            queueType: QueueType.foreground,
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
          // Async remote refresh using load queue instead of unawaited
          _enqueueRemoteFetchAllTask(
            queryParams: queryParams,
            extra: extra,
            headers: headers,
          );
        } catch (localError, localStackTrace) {
          log.warning(
            'Failed to get all $T from local database, trying remote',
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
              'Remote fetch successful after local failure. '
              'Got ${remoteItems.length} items. Updating local cache.',
            );
            await updateLocalCache(remoteItems);
            results = remoteItems;
          } on ApiExceptionGone catch (e, stackTrace) {
            log.fine(
              'No content for query in remote API (410) after local failure.',
              e,
              stackTrace,
            );
            results = [];
          } catch (remoteError, remoteStackTrace) {
            log.warning(
              'Both local and remote fetch failed for all $T',
              remoteError,
              remoteStackTrace,
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
      changeController.add(RepositoryChange.deleted('*'));
      // '*' indicates all items deleted
    } catch (e, stackTrace) {
      log.severe('Failed to truncate local storage for $T', e, stackTrace);
      changeController.add(RepositoryChange.error(e, stackTrace));
      rethrow;
    }
  }

  /// Enqueues a remote fetch task for localThenRemote operations.
  ///
  /// This method uses the load queue (QueueType.load) to perform async
  /// remote fetching for localThenRemote operations, as intended by the
  /// queue architecture.
  void _enqueueRemoteFetchTask(
    String id, {
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) {
    final task = NetworkTask<void>(
      exec: () async {
        try {
          final remoteItem = await fetchFromRemote(
            id,
            extra: extra,
            queryParams: queryParams,
            headers: headers,
          );

          if (remoteItem != null) {
            log.fine(
              'Async remote fetch for $id (localThenRemote) successful.'
              ' Updating local copy.',
            );
            await saveToLocal(remoteItem);
          } else {
            log.fine(
              'Async remote fetch for $id (localThenRemote) '
              'returned null.',
            );
          }
        } on ApiExceptionGone catch (fetchError, fetchStackTrace) {
          log.fine(
            'Async remote fetch for $id (localThenRemote) '
            'found no content. Triggering cascade delete and '
            'removing local copy.',
            fetchError,
            fetchStackTrace,
          );
          await handleCascadeDeleteAfterGone(
            id,
            extra: extra,
            headers: headers,
          );
        } catch (fetchError, fetchStackTrace) {
          log.fine(
            'Async remote fetch for $id (localThenRemote) failed, '
            'keeping local result',
            fetchError,
            fetchStackTrace,
          );
        }
      },
      idempotencyKey: 'load-$id-${cuid()}',
      operation: SyncOperation.read,
      modelType: T.toString(),
      modelId: id,
      taskName: 'LoadRefresh-${T.toString()}-$id',
    );

    // Use unawaited to avoid blocking, but enqueue to load queue
    unawaited(
      queueManager.enqueueTask(task, queueType: QueueType.load).catchError((
        e,
        stackTrace,
      ) {
        log.warning(
          'Failed to enqueue remote fetch task for $T $id',
          e,
          stackTrace,
        );
      }),
    );
  }

  /// Enqueues a remote fetch all task for localThenRemote operations.
  ///
  /// This method uses the load queue (QueueType.load) to perform async
  /// remote fetching for localThenRemote operations.
  void _enqueueRemoteFetchAllTask({
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) {
    final task = NetworkTask<void>(
      exec: () async {
        try {
          final remoteItems = await fetchAllFromRemote(
            queryParams: queryParams,
            extra: extra,
            headers: headers,
          );

          log.fine(
            'Async remote fetch for all $T (localThenRemote) '
            'completed with ${remoteItems.length} items. Updating cache.',
          );
          await updateLocalCache(remoteItems);
        } on ApiExceptionNotFound catch (fetchError, fetchStackTrace) {
          log.fine(
            'Async remote fetch for all $T (localThenRemote) found '
            'no items or no content. Clearing local cache.',
            fetchError,
            fetchStackTrace,
          );
          await updateLocalCache([]);
        } on ApiExceptionGone catch (fetchError, fetchStackTrace) {
          log.fine(
            'Async remote fetch for all $T (localThenRemote) found '
            'no items or no content. Clearing local cache.',
            fetchError,
            fetchStackTrace,
          );
          await updateLocalCache([]);
        } catch (fetchError, fetchStackTrace) {
          log.fine(
            'Async remote fetch for all $T (localThenRemote) failed, '
            'keeping local results',
            fetchError,
            fetchStackTrace,
          );
        }
      },
      idempotencyKey: 'load-all-${T.toString()}-${cuid()}',
      operation: SyncOperation.read,
      modelType: T.toString(),
      modelId: 'all',
      taskName: 'LoadRefreshAll-${T.toString()}',
    );

    // Use unawaited to avoid blocking, but enqueue to load queue
    unawaited(
      queueManager.enqueueTask(task, queueType: QueueType.load).catchError((
        e,
        stackTrace,
      ) {
        log.warning(
          'Failed to enqueue remote fetch all task for $T',
          e,
          stackTrace,
        );
      }),
    );
  }
}
