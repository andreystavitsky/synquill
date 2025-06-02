part of synquill;

/// Mixin providing query operations for repositories.
mixin RepositoryQueryOperations<T extends SynquillDataModel<T>>
    on RepositoryLocalOperations<T>, RepositoryRemoteOperations<T> {
  /// Gets the default load policy from global configuration.
  @protected
  DataLoadPolicy get defaultLoadPolicy;

  /// The stream controller for repository change events.
  StreamController<RepositoryChange<T>> get changeController;

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
          'Policy: localThenRemote. Getting $T from local database first.',
        );
        try {
          result = await fetchFromLocal(id, queryParams: queryParams);
          log.fine(
            'Got local result for $id: '
            '${result != null ? "found" : "not found"}. '
            'Async refreshing from remote.',
          );
          // Async remote refresh without blocking
          unawaited(
            fetchFromRemote(
                  id,
                  extra: extra,
                  queryParams: queryParams,
                  headers: headers,
                )
                .then((remoteItem) {
                  if (remoteItem != null) {
                    log.fine(
                      'Async remote fetch for $id (localThenRemote) successful.'
                      ' Updating local copy.',
                    );
                    saveToLocal(remoteItem).catchError((
                      saveError,
                      saveStackTrace,
                    ) {
                      log.warning(
                        'Error saving async fetched item for $T $id in '
                        'localThenRemote',
                        saveError,
                        saveStackTrace,
                      );
                    });
                  } else {
                    log.fine(
                      'Async remote fetch for $id (localThenRemote) '
                      'returned null.',
                    );
                  }
                })
                .catchError((fetchError, fetchStackTrace) {
                  if (fetchError is ApiExceptionGone) {
                    log.fine(
                      'Async remote fetch for $id (localThenRemote) '
                      'found no content. Removing local copy.',
                      fetchError,
                      fetchStackTrace,
                    );
                    removeFromLocalIfExists(id).catchError((
                      removeError,
                      removeStackTrace,
                    ) {
                      log.warning(
                        'Error removing local copy for $T $id after async '
                        'not found/no content',
                        removeError,
                        removeStackTrace,
                      );
                    });
                  } else {
                    log.fine(
                      'Async remote fetch for $id (localThenRemote) failed, '
                      'keeping local result',
                      fetchError,
                      fetchStackTrace,
                    );
                  }
                }),
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
            // Don't remove from local if local access failed
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
        // Trigger async fetch to ensure local is up to date
        unawaited(
          findOne(
            id,
            loadPolicy: loadPolicy,
            queryParams: queryParams,
          ).catchError((e, stackTrace) {
            log.warning(
              'Error during async refresh for watch $T $id',
              e,
              stackTrace,
            );
            return null; // Return null on error
          }),
        );
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
          unawaited(
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
                      'Error updating local cache for all $T '
                      'in localThenRemote async update',
                      updateError,
                      updateStackTrace,
                    );
                  });
                })
                .catchError((fetchError, fetchStackTrace) {
                  if (fetchError is ApiExceptionNotFound ||
                      fetchError is ApiExceptionGone) {
                    log.fine(
                      'Async remote fetch for all $T (localThenRemote) found '
                      'no items or no content. Clearing local cache.',
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
                    log.fine(
                      'Async remote fetch for all $T (localThenRemote) failed, '
                      'keeping local results',
                      fetchError,
                      fetchStackTrace,
                    );
                  }
                }),
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
}
