part of synquill;

/// Mixin providing save operations for repositories.
mixin RepositorySaveOperations<T extends SynquillDataModel<T>>
    on RepositoryLocalOperations<T>, RepositoryRemoteOperations<T> {
  /// Gets the default save policy from global configuration.
  @protected
  DataSavePolicy get defaultSavePolicy;

  /// Gets the API adapter for this repository.
  @protected
  ApiAdapterBase<T> get apiAdapter;

  /// The queue manager for handling API operations.
  RequestQueueManager get queueManager;

  /// The stream controller for repository change events.
  StreamController<RepositoryChange<T>> get changeController;

  /// Saves an item.
  ///
  /// [item] The item to save.
  /// [savePolicy] Controls whether to save to local storage, remote API,
  /// or both.
  /// [updateTimestamps] Whether to automatically update createdAt/updatedAt
  /// timestamps. Defaults to true. Set to false if you want to manually
  /// control timestamp values.
  Future<T> save(
    T item, {
    DataSavePolicy? savePolicy,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
    bool updateTimestamps = true,
  }) async {
    savePolicy ??= defaultSavePolicy;
    log.info('Saving $T with ID ${item.id} using policy ${savePolicy.name}');

    // Ensure the item has a repository reference.
    item.$setRepository(this as SynquillRepositoryBase<T>);

    // Determine if this is a create or update operation before modifying
    final isExisting = await isExistingItem(item);

    // Automatically update timestamps when saving (if enabled)
    if (updateTimestamps) {
      final now = DateTime.now();
      if (!isExisting && item.createdAt == null) {
        // For new items, set createdAt if not already set
        item.createdAt = now;
      }
      // Always update updatedAt when saving (for both new and existing items)
      item.updatedAt = now;
    }

    T resultItem;

    switch (savePolicy) {
      case DataSavePolicy.localFirst:
        log.info('Policy: localFirst. Saving $T to local database first.');

        // Use the existing check result
        var operation =
            isExisting ? SyncOperation.update : SyncOperation.create;

        // Save to local database first
        await saveToLocal(item);
        changeController.add(isExisting
            ? RepositoryChange.updated(item)
            : RepositoryChange.created(item));
        log.fine(
          'Local save for ${item.id} successful.',
        );

        // Check if this is a local-only repository
        bool isLocalOnly = false;
        try {
          // Try to access the apiAdapter - if it throws UnsupportedError,
          // this is a local-only repository
          apiAdapter;
        } on UnsupportedError {
          isLocalOnly = true;
          log.fine(
            'Repository for $T is local-only, skipping sync queue operations.',
          );
        }

        if (isLocalOnly) {
          // For local-only repositories, just return the item without sync
          resultItem = item;
          break;
        }

        log.fine(
          'Creating sync queue entry for ${item.id}.',
        );

        // Create sync queue entry for persistence and retry capability
        final idempotencyKey = '${item.id}-${operation.name}-${cuid()}';
        int syncQueueId;

        final syncQueueDao = SyncQueueDao(SynquillStorage.database);

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

        // Try immediate sync in background (fire-and-forget)
        // If it fails, the task remains in sync queue for RetryExecutor
        final syncTask = NetworkTask<void>(
          exec: () => _executeSyncOperation(operation, item, headers, extra),
          idempotencyKey: idempotencyKey,
          operation: operation,
          modelType: T.toString(),
          modelId: item.id,
          taskName: 'ImmediateSync-${T.toString()}-${item.id}',
        );

        // Use fire-and-forget approach - don't block localFirst saves
        _tryImmediateSyncInBackground(syncTask, syncQueueId);

        resultItem = item;
        break;

      case DataSavePolicy.remoteFirst:
        log.info('Policy: remoteFirst. Saving $T to remote API first.');
        try {
          // Create a NetworkTask for remoteFirst save operation
          final operation =
              isExisting ? SyncOperation.update : SyncOperation.create;
          final idempotencyKey =
              '${item.id}-remoteFirst-${operation.name}-${cuid()}';

          final remoteFirstTask = NetworkTask<T>(
            exec: () async {
              T remoteItem;

              if (isExisting) {
                log.fine('Item ${item.id} exists, calling adapter.updateOne()');
                final T? updatedItem = await apiAdapter.updateOne(
                  item,
                  extra: extra,
                  headers: headers,
                );
                if (updatedItem == null) {
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
              remoteItem.$setRepository(this as SynquillRepositoryBase<T>);
              await saveToLocal(remoteItem);
              changeController.add(RepositoryChange.updated(remoteItem));

              return remoteItem;
            },
            idempotencyKey: idempotencyKey,
            operation: operation,
            modelType: T.toString(),
            modelId: item.id,
            taskName: 'RemoteFirstSave-${T.toString()}-${item.id}',
          );

          // Execute through foreground queue for remoteFirst operations
          resultItem = await queueManager.enqueueTask(
            remoteFirstTask,
            queueType: QueueType.foreground,
          );
        } on OfflineException catch (e, stackTrace) {
          log.warning(
            'OfflineException during remoteFirst save for $T ${item.id}. '
            'Operation failed as per policy.',
            e,
            stackTrace,
          );
          changeController.add(RepositoryChange.error(e, stackTrace));
          rethrow;
        } on ApiException catch (e, stackTrace) {
          log.severe(
            'ApiException during remoteFirst save for $T ${item.id}.',
            e,
            stackTrace,
          );
          changeController.add(RepositoryChange.error(e, stackTrace));
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
          changeController.add(RepositoryChange.error(e, stackTrace));
          throw SynquillStorageException(
            'Failed to save $T ${item.id} with remoteFirst policy: $e',
            stackTrace,
          );
        }
        break;
    }
    return resultItem;
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
        case SyncOperation.read:
          throw StateError(
            'Read operations should not be processed as sync operations',
          );
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

  /// Tries immediate sync in background without blocking localFirst saves.
  ///
  /// This is a fire-and-forget operation that attempts to sync immediately
  /// but doesn't block the save operation if it fails or times out.
  void _tryImmediateSyncInBackground(
    NetworkTask<void> syncTask,
    int syncQueueId,
  ) {
    final syncQueueDao = SyncQueueDao(SynquillStorage.database);

    // Fire-and-forget: don't await, don't block
    unawaited(
      queueManager
          .enqueueTask(syncTask, queueType: QueueType.background)
          .then((_) async {
        // Success: remove from sync queue
        await syncQueueDao.deleteTask(syncQueueId);
        log.fine(
          'Background immediate sync succeeded, '
          'removed sync queue entry $syncQueueId',
        );
      }).catchError((e) {
        // Failure: log and leave in sync queue for RetryExecutor
        log.fine(
          'Background immediate sync failed for ${syncTask.modelId}, '
          'task will be retried by RetryExecutor: $e',
        );
      }),
    );
  }
}
