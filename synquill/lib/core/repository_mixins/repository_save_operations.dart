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
    // Check if this repository supports server ID negotiation and if the item
    // needs it. We check if 'this' is a RepositoryServerIdMixin

    if (this is RepositoryServerIdMixin<T>) {
      final idMixin = this as RepositoryServerIdMixin<T>;

      // For models that use server-generated IDs, check if this is a new model
      // that needs to be marked as temporary
      if (idMixin.modelUsesServerGeneratedId(item)) {
        final isExisting = await isExistingItem(item);

        if (!isExisting && !idMixin.hasTemporaryId(item)) {
          // This is a new model with a client-generated ID that should be
          // temporary

          idMixin.markAsTemporary(item, item.id);
        }

        if (idMixin.hasTemporaryId(item)) {
          return await _handleServerIdNegotiation(
            item,
            savePolicy: savePolicy,
            extra: extra,
            headers: headers,
            updateTimestamps: updateTimestamps,
          );
        }
      }
    }

    // Standard save flow for client-generated IDs
    return await _handleStandardSave(
      item,
      savePolicy: savePolicy,
      extra: extra,
      headers: headers,
      updateTimestamps: updateTimestamps,
    );
  }

  /// Handles save operations for models with server-generated IDs.
  /// This method implements the ID negotiation process.
  Future<T> _handleServerIdNegotiation(
    T item, {
    DataSavePolicy? savePolicy,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
    bool updateTimestamps = true,
  }) async {
    savePolicy ??= defaultSavePolicy;
    log.info(
      'Handling server ID negotiation for $T with temporary ID ${item.id} '
      'using policy ${savePolicy.name}',
    );

    // No need to set repository reference since we use service-based approach

    switch (savePolicy) {
      case DataSavePolicy.localFirst:
        return await _handleLocalFirstWithIdNegotiation(
          item,
          extra: extra,
          headers: headers,
          updateTimestamps: updateTimestamps,
        );

      case DataSavePolicy.remoteFirst:
        return await _handleRemoteFirstWithIdNegotiation(
          item,
          extra: extra,
          headers: headers,
          updateTimestamps: updateTimestamps,
        );
    }
  }

  /// Standard save flow for client-generated IDs (original implementation).
  Future<T> _handleStandardSave(
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

  // ===== ID NEGOTIATION METHODS =====

  /// Handles local-first save with ID negotiation.
  Future<T> _handleLocalFirstWithIdNegotiation(
    T item, {
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
    bool updateTimestamps = true,
  }) async {
    log.info('LocalFirst with ID negotiation for ${item.id}');

    // Set timestamps if needed
    if (updateTimestamps) {
      final now = DateTime.now();
      if (item.createdAt == null) {
        item.createdAt = now;
      }
      item.updatedAt = now;
    }

    // Save locally with temporary ID
    await saveToLocal(item);
    changeController.add(RepositoryChange.created(item));
    log.fine('Local save with temporary ID ${item.id} successful');

    // Check if this is a local-only repository
    bool isLocalOnly = false;
    try {
      apiAdapter;
    } on UnsupportedError {
      isLocalOnly = true;
      log.fine('Repository is local-only, skipping ID negotiation');
    }

    if (isLocalOnly) {
      return item;
    }

    // Create sync queue entry with ID negotiation tracking
    final syncQueueDao = SyncQueueDao(SynquillStorage.database);
    final idempotencyKey = '${item.id}-create-${cuid()}';

    // Check if there's already a pending negotiation for this model
    final existingTaskId =
        await syncQueueDao.findPendingSyncTaskWithNegotiation(
      T.toString(),
      item.id,
      SyncOperation.create.name,
    );

    int syncQueueId;
    if (existingTaskId != null) {
      // Update existing task with new payload
      await syncQueueDao.updateItem(
        id: existingTaskId,
        payload: convert.jsonEncode(item.toJson()),
        idempotencyKey: idempotencyKey,
        attemptCount: 0, // Reset attempt count for the new payload
        nextRetryAt: null, // Allow immediate retry
        lastError: null, // Clear any previous errors
        headers: headers != null ? convert.jsonEncode(headers) : null,
        extra: extra != null ? convert.jsonEncode(extra) : null,
      );
      syncQueueId = existingTaskId;
      log.fine('Updated existing ID negotiation task $syncQueueId for '
          '${item.id}');
    } else {
      // Create new sync queue entry
      syncQueueId = await syncQueueDao.insertItemWithIdNegotiation(
        modelId: item.id,
        modelType: T.toString(),
        payload: convert.jsonEncode(item.toJson()),
        operation: SyncOperation.create.name,
        temporaryClientId: item.id, // Store the temporary ID
        idNegotiationStatus: 'pending', // Mark as pending negotiation
        idempotencyKey: idempotencyKey,
        headers: headers != null ? convert.jsonEncode(headers) : null,
        extra: extra != null ? convert.jsonEncode(extra) : null,
      );
      log.fine('Created sync queue entry $syncQueueId with ID negotiation');
    }

    // Try immediate sync in background for ID negotiation
    final syncTask = NetworkTask<void>(
      exec: () => _executeIdNegotiationSync(item, headers, extra, syncQueueId),
      idempotencyKey: idempotencyKey,
      operation: SyncOperation.create,
      modelType: T.toString(),
      modelId: item.id,
      taskName: 'IdNegotiation-${T.toString()}-${item.id}',
    );

    _tryImmediateSyncInBackground(syncTask, syncQueueId);

    return item;
  }

  /// Handles remote-first save with ID negotiation.
  Future<T> _handleRemoteFirstWithIdNegotiation(
    T item, {
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
    bool updateTimestamps = true,
  }) async {
    log.info('RemoteFirst with ID negotiation for ${item.id}');

    // Set timestamps if needed
    if (updateTimestamps) {
      final now = DateTime.now();
      if (item.createdAt == null) {
        item.createdAt = now;
      }
      item.updatedAt = now;
    }

    try {
      // Create on server first to get permanent ID
      final serverItem = await apiAdapter.createOne(
        item,
        headers: headers,
        extra: extra,
      );

      if (serverItem == null) {
        throw Exception('Server returned null for create operation');
      }

      // If server returned a different ID, replace it everywhere
      if (serverItem.id != item.id) {
        final updatedItem = await _replaceIdEverywhere(item, serverItem.id);

        // Save to local with permanent ID
        await saveToLocal(updatedItem);
        changeController.add(RepositoryChange.created(updatedItem));

        // Emit ID change event
        changeController.add(
          RepositoryChange.idChanged(updatedItem, item.id, serverItem.id),
        );

        log.info('ID negotiation complete: ${item.id} -> ${serverItem.id}');
        return updatedItem;
      } else {
        // Server used the same ID, just save locally
        await saveToLocal(serverItem);
        changeController.add(RepositoryChange.created(serverItem));
        return serverItem;
      }
    } catch (e, stack) {
      log.severe('Remote-first ID negotiation failed for ${item.id}', e, stack);

      // Fall back to local-first approach
      log.info('Falling back to local-first approach');
      return await _handleLocalFirstWithIdNegotiation(
        item,
        extra: extra,
        headers: headers,
        updateTimestamps: false, // Already set timestamps
      );
    }
  }

  /// Executes ID negotiation sync operation.
  Future<void> _executeIdNegotiationSync(
    T item,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
    int syncQueueId,
  ) async {
    final syncQueueDao = SyncQueueDao(SynquillStorage.database);
    final conflictResolver = IdConflictResolver(SynquillStorage.database);

    try {
      log.fine('Executing ID negotiation sync for ${item.id}');

      // 1. Check for concurrent operations on the same model
      if (await _hasConcurrentIdNegotiation(item.id, syncQueueId)) {
        log.warning(
          'Concurrent ID negotiation detected for ${item.id}, aborting',
        );
        await syncQueueDao.updateItem(
          id: syncQueueId,
          idNegotiationStatus: 'failed',
          lastError: 'Concurrent ID negotiation detected',
        );
        return;
      }

      // 2. Mark negotiation as in progress to prevent concurrent modifications
      await syncQueueDao.updateItem(
        id: syncQueueId,
        idNegotiationStatus: 'in_progress',
      );

      // 3. Execute server create operation with timeout
      final serverItem = await _executeCreateWithTimeout(
        item,
        headers,
        extra,
      );

      if (serverItem == null) {
        throw Exception('Server returned null for create operation');
      }

      // 4. If server assigned a different ID, handle ID replacement with
      // conflict resolution
      if (serverItem.id != item.id) {
        log.info(
          'Server assigned different ID: ${item.id} -> ${serverItem.id}',
        );

        // Check for potential ID collision before proceeding
        if (await _wouldCauseConstraintViolation(serverItem.id)) {
          log.warning(
            'Server ID ${serverItem.id} would cause constraint violation',
          );

          // Resolve conflict using conflict resolver
          final resolvedId = await conflictResolver.resolveIdConflict(
            temporaryId: item.id,
            proposedServerId: serverItem.id,
            modelType: T.toString(),
          );

          // Check if conflict was resolved through merge
          if (resolvedId == serverItem.id) {
            // This means the conflict was resolved through merge
            // The temporary record was cleaned up by the resolver
            // We just need to mark the sync as complete
            log.info(
              'ID conflict resolved through merge: ${item.id} -> $resolvedId',
            );

            // Check if temp record still exists (might have been cleaned up)
            final tempStillExists = await _validateModelExists(item.id);
            if (!tempStillExists) {
              // Record was merged and cleaned up, just mark sync complete
              await syncQueueDao.deleteTask(syncQueueId);
              log.info('Sync marked complete after successful merge');
              return;
            }
          }

          // If we reach here, either:
          // 1. Conflict was resolved but temp record still exists
          // 2. Resolved ID is different (fallback scenario)
          // Proceed with atomic replacement
          final finalId = resolvedId;

          // 5. Perform atomic ID replacement within transaction
          await _performAtomicIdReplacement(
            syncQueueId: syncQueueId,
            oldId: item.id,
            newId: finalId,
            updatedItem: finalId == serverItem.id ? serverItem : item,
          );

          log.info('ID negotiation successful: ${item.id} -> $finalId');
        } else {
          // No conflict, proceed with direct replacement
          await _performAtomicIdReplacement(
            syncQueueId: syncQueueId,
            oldId: item.id,
            newId: serverItem.id,
            updatedItem: serverItem,
          );

          log.info(
            'ID negotiation successful: ${item.id} -> ${serverItem.id}',
          );
        }
      } else {
        // Server used the same ID, just mark as complete
        log.fine('Server used same ID: ${item.id}');
        await syncQueueDao.updateItem(
          id: syncQueueId,
          idNegotiationStatus: 'complete',
        );
      }

      // 6. Mark sync as successful by removing from queue
      await syncQueueDao.deleteTask(syncQueueId);
    } catch (e, stack) {
      log.severe('ID negotiation sync failed for ${item.id}', e, stack);

      // Enhanced error handling with retry logic
      await _handleIdNegotiationFailure(syncQueueId, item.id, e);

      rethrow;
    }
  }

  /// Checks if there are concurrent ID negotiations for the same model.
  Future<bool> _hasConcurrentIdNegotiation(
    String modelId,
    int currentSyncQueueId,
  ) async {
    try {
      final syncQueueDao = SyncQueueDao(SynquillStorage.database);
      final pendingTasks = await syncQueueDao.getTasksForModelId(
        T.toString(),
        modelId,
      );

      // Check for other pending ID negotiation tasks for the same model
      final concurrentTasks = pendingTasks
          .where((task) =>
              task['id'] != currentSyncQueueId &&
              task['id_negotiation_status'] == 'pending' &&
              task['status'] == 'pending')
          .toList();

      return concurrentTasks.isNotEmpty;
    } catch (e) {
      log.warning('Error checking concurrent ID negotiations: $e');
      return false;
    }
  }

  /// Executes the create operation with timeout protection.
  Future<T?> _executeCreateWithTimeout(
    T item,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  ) async {
    const timeoutDuration = Duration(seconds: 30);

    try {
      return await apiAdapter
          .createOne(
        item,
        headers: headers,
        extra: extra,
      )
          .timeout(
        timeoutDuration,
        onTimeout: () {
          throw TimeoutException(
            'Create operation timed out after '
            '${timeoutDuration.inSeconds} seconds',
            timeoutDuration,
          );
        },
      );
    } catch (e) {
      log.warning('Create operation failed or timed out: $e');
      rethrow;
    }
  }

  /// Performs atomic ID replacement within a database transaction.
  Future<void> _performAtomicIdReplacement({
    required int syncQueueId,
    required String oldId,
    required String newId,
    required T updatedItem,
  }) async {
    final syncQueueDao = SyncQueueDao(SynquillStorage.database);

    await SynquillStorage.database.transaction(() async {
      try {
        // 1. Validate that the old ID still exists before replacement
        if (!await _validateModelExists(oldId)) {
          throw StateError('Model with ID $oldId no longer exists');
        }

        // 2. Check for constraint violations before proceeding
        if (await _wouldCauseConstraintViolation(newId)) {
          throw StateError(
            'ID replacement would cause constraint violation for ID $newId',
          );
        }

        // 3. Validate foreign key integrity before replacement
        await _validateForeignKeyIntegrityBeforeReplacement(
          oldId,
          newId,
          T.toString(),
        );

        // 4. Replace ID in model table, sync queue, and relationships
        await syncQueueDao.replaceIdEverywhere(
          taskId: syncQueueId,
          oldId: oldId,
          newId: newId,
          modelType: T.toString(),
        );

        // 5. Validate foreign key integrity after replacement
        await _validateForeignKeyIntegrityAfterReplacement(
          oldId,
          newId,
          T.toString(),
        );

        // 6. Create updated model instance and emit change event
        final updatedModelWithNewId =
            await _replaceIdEverywhere(updatedItem, newId);
        changeController.add(
          RepositoryChange.idChanged(updatedModelWithNewId, oldId, newId),
        );

        log.fine('Atomic ID replacement completed successfully');
      } catch (e, stackTrace) {
        log.severe(
          'Atomic ID replacement failed, transaction will rollback',
          e,
          stackTrace,
        );
        rethrow;
      }
    });
  }

  /// Validates that a model with the given ID exists in the database.
  Future<bool> _validateModelExists(String modelId) async {
    try {
      // Cast to query operations to access findOne
      if (this is RepositoryQueryOperations<T>) {
        final queryOps = this as RepositoryQueryOperations<T>;
        final existingModel = await queryOps.findOne(modelId);
        return existingModel != null;
      }
      return false;
    } catch (e) {
      log.warning('Error validating model existence for $modelId: $e');
      return false;
    }
  }

  /// Checks if using the new ID would cause a constraint violation.
  Future<bool> _wouldCauseConstraintViolation(String newId) async {
    try {
      // Cast to query operations to access findOne
      if (this is RepositoryQueryOperations<T>) {
        final queryOps = this as RepositoryQueryOperations<T>;
        final existingModel = await queryOps.findOne(newId);
        return existingModel != null;
      }
      return false;
    } catch (e) {
      log.warning('Error checking constraint violation for $newId: $e');
      return false;
    }
  }

  /// Validates foreign key integrity before ID replacement.
  Future<void> _validateForeignKeyIntegrityBeforeReplacement(
    String oldId,
    String newId,
    String modelType,
  ) async {
    try {
      // Get all foreign key relations that reference this model type
      final foreignKeyRelations =
          ModelInfoRegistryProvider.getForeignKeyRelations(modelType);

      if (foreignKeyRelations.isEmpty) {
        log.fine('No foreign key relations to validate for $modelType');
        return;
      }

      log.fine(
        'Validating foreign key integrity before ID replacement for '
        '${foreignKeyRelations.length} relations',
      );

      // Check each relation for potential conflicts with the new ID
      for (final relation in foreignKeyRelations) {
        await _validateSingleForeignKeyBeforeReplacement(
          relation,
          oldId,
          newId,
        );
      }

      log.fine(
        'Foreign key integrity validation before replacement completed',
      );
    } catch (e, stackTrace) {
      log.severe(
        'Foreign key integrity validation failed before replacement '
        'for $oldId -> $newId',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Validates a single foreign key relation before ID replacement.
  Future<void> _validateSingleForeignKeyBeforeReplacement(
    ForeignKeyRelation relation,
    String oldId,
    String newId,
  ) async {
    final sourceTable = relation.sourceTable;
    final foreignKeyField = relation.fieldName;

    try {
      final relationColumnName =
          PluralizationUtils.toSnakeCase(foreignKeyField);

      // Check if there are existing references to the new ID
      final existingReferences = await SynquillStorage.database.customSelect(
        '''
        SELECT COUNT(*) as count FROM $sourceTable 
        WHERE $relationColumnName = ?
        ''',
        variables: [Variable.withString(newId)],
      ).getSingleOrNull();

      final count = existingReferences?.data['count'] as int? ?? 0;
      if (count > 0) {
        log.warning(
          'Existing foreign key references found for new ID $newId '
          'in $sourceTable.$relationColumnName (count: $count)',
        );

        // This might be legitimate if the server ID already has references
        // We'll log it but not fail the validation unless it causes issues
      }

      // Check if the old ID has references that need to be updated
      final oldReferences = await SynquillStorage.database.customSelect(
        '''
        SELECT COUNT(*) as count FROM $sourceTable 
        WHERE $relationColumnName = ?
        ''',
        variables: [Variable.withString(oldId)],
      ).getSingleOrNull();

      final oldCount = oldReferences?.data['count'] as int? ?? 0;
      if (oldCount > 0) {
        log.info(
          'Found $oldCount foreign key references to update from $oldId '
          'to $newId in $sourceTable.$relationColumnName',
        );
      }
    } catch (e) {
      log.warning(
        'Failed to validate foreign key relation before replacement '
        '$sourceTable.$foreignKeyField: $e',
      );
      // Continue with other relations even if one fails
    }
  }

  /// Validates foreign key integrity after ID replacement.
  Future<void> _validateForeignKeyIntegrityAfterReplacement(
    String oldId,
    String newId,
    String modelType,
  ) async {
    try {
      // Get all foreign key relations that reference this model type
      final foreignKeyRelations =
          ModelInfoRegistryProvider.getForeignKeyRelations(modelType);

      if (foreignKeyRelations.isEmpty) {
        return;
      }

      log.fine(
        'Validating foreign key integrity after ID replacement for '
        '${foreignKeyRelations.length} relations',
      );

      // Check each relation to ensure references were properly updated
      for (final relation in foreignKeyRelations) {
        await _validateSingleForeignKeyAfterReplacement(
          relation,
          oldId,
          newId,
        );
      }

      log.fine(
        'Foreign key integrity validation after replacement completed',
      );
    } catch (e, stackTrace) {
      log.severe(
        'Foreign key integrity validation failed after replacement '
        'for $oldId -> $newId',
        e,
        stackTrace,
      );

      // Don't rethrow here - the ID replacement already happened
      // Log the issue for monitoring but don't roll back the transaction
    }
  }

  /// Validates a single foreign key relation after ID replacement.
  Future<void> _validateSingleForeignKeyAfterReplacement(
    ForeignKeyRelation relation,
    String oldId,
    String newId,
  ) async {
    final sourceTable = relation.sourceTable;
    final foreignKeyField = relation.fieldName;

    try {
      final relationColumnName =
          PluralizationUtils.toSnakeCase(foreignKeyField);

      // Check if any references to the old ID still exist
      final remainingOldReferences =
          await SynquillStorage.database.customSelect(
        '''
        SELECT COUNT(*) as count FROM $sourceTable 
        WHERE $relationColumnName = ?
        ''',
        variables: [Variable.withString(oldId)],
      ).getSingleOrNull();

      final oldCount = remainingOldReferences?.data['count'] as int? ?? 0;
      if (oldCount > 0) {
        log.warning(
          'Foreign key integrity issue: $oldCount references to old ID '
          '$oldId still exist in $sourceTable.$relationColumnName '
          'after replacement with $newId',
        );
      }

      // Check if references to the new ID exist (should be > 0 if updated)
      final newReferences = await SynquillStorage.database.customSelect(
        '''
        SELECT COUNT(*) as count FROM $sourceTable 
        WHERE $relationColumnName = ?
        ''',
        variables: [Variable.withString(newId)],
      ).getSingleOrNull();

      final newCount = newReferences?.data['count'] as int? ?? 0;
      log.fine(
        'Foreign key validation: $newCount references to new ID $newId '
        'found in $sourceTable.$relationColumnName',
      );
    } catch (e) {
      log.warning(
        'Failed to validate foreign key relation after replacement '
        '$sourceTable.$foreignKeyField: $e',
      );
    }
  }

  /// Handles ID negotiation failures with enhanced error handling and
  /// retry logic.
  Future<void> _handleIdNegotiationFailure(
    int syncQueueId,
    String modelId,
    Object error,
  ) async {
    final syncQueueDao = SyncQueueDao(SynquillStorage.database);

    try {
      // Get current sync queue item to check retry count
      final queueItem = await syncQueueDao.getItemById(syncQueueId);
      if (queueItem == null) {
        log.warning(
          'Sync queue item $syncQueueId not found during error handling',
        );
        return;
      }

      final currentAttemptCount = queueItem['attempt_count'] as int? ?? 0;
      const maxRetryAttempts = 3;

      if (currentAttemptCount < maxRetryAttempts && _isRetryableError(error)) {
        // Schedule retry with exponential backoff
        final nextRetryAt = DateTime.now().add(
          Duration(seconds: math.pow(2, currentAttemptCount).toInt() * 60),
        );

        await syncQueueDao.updateTaskRetry(
          syncQueueId,
          nextRetryAt,
          currentAttemptCount + 1,
          error.toString(),
        );

        log.info(
          'Scheduled retry for ID negotiation of $modelId '
          '(attempt ${currentAttemptCount + 1}/$maxRetryAttempts) '
          'at $nextRetryAt',
        );
      } else {
        // Mark as permanently failed
        await syncQueueDao.markIdNegotiationAsFailed(
          taskId: syncQueueId,
          error: 'Max retry attempts exceeded: ${error.toString()}',
        );

        log.severe(
          'ID negotiation permanently failed for $modelId after '
          '$maxRetryAttempts attempts',
        );
      }
    } catch (e, stackTrace) {
      log.severe(
        'Error handling ID negotiation failure for $modelId',
        e,
        stackTrace,
      );
    }
  }

  /// Determines if an error is retryable.
  bool _isRetryableError(Object error) {
    if (error is TimeoutException) return true;
    if (error is DioException) {
      // Retry on network errors, server errors, but not client errors
      final type = error.type;
      return type == DioExceptionType.connectionTimeout ||
          type == DioExceptionType.receiveTimeout ||
          type == DioExceptionType.sendTimeout ||
          type == DioExceptionType.connectionError ||
          (error.response?.statusCode != null &&
              error.response!.statusCode! >= 500);
    }
    // Don't retry conflict errors
    if (error is IdConflictException) return false;

    // Default to retryable for unknown errors
    return true;
  }

  /// Replaces an item's ID everywhere it's referenced.
  /// This method uses the repository's ID negotiation service.
  Future<T> _replaceIdEverywhere(T item, String newId) async {
    if (this is RepositoryServerIdMixin<T>) {
      final idMixin = this as RepositoryServerIdMixin<T>;
      return idMixin.replaceIdEverywhere(item, newId);
    } else {
      // For models without server ID support, throw an error
      throw UnsupportedError(
        'ID replacement is not supported for models that do not use '
        'server-generated IDs. Model: ${item.runtimeType}',
      );
    }
  }
}
