part of synquill;

/// Mixin providing sync operations and queue management for repositories.
///
/// This mixin contains background sync functionality including:
/// - Sync queue operations and task management
/// - Background processing coordination
/// - Network task execution and retry handling
/// - Queue state management for different save policies
mixin RepositorySyncOperations<T extends SynquillDataModel<T>> {
  /// The logger instance for this repository.
  ///
  /// Used for logging all repository operations, errors, and debug
  /// information. This logger should be used for all actions, errors,
  /// and debug output related to repository lifecycle and sync.
  Logger get log;

  /// The API adapter used for remote operations.
  ///
  /// Handles communication with the remote REST API for CRUD operations
  /// on the model type [T]. This adapter abstracts network calls and
  /// error handling for remote data sync.
  ApiAdapterBase<T> get apiAdapter;

  /// The request queue manager for handling queued operations.
  ///
  /// Manages the local queue of pending operations (such as sync tasks)
  /// to be synchronized with the remote API when online. Ensures
  /// reliable sync and conflict resolution in offline/online scenarios.
  RequestQueueManager get queueManager;

  /// Executes a sync operation for background queue processing.
  ///
  /// This method is called by NetworkTask to perform the actual API operation
  /// for background sync operations.
  ///
  /// [operation] The type of sync operation to execute
  /// (create, update, delete).
  /// [item] The model instance to sync.
  /// [headers] Optional headers to include in the API request.
  /// [extra] Optional extra data to include in the API request.
  Future<void> executeSyncOperation(
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
        // Read operations are intentionally not processed as sync operations.
        // Reads do not modify data, do not require offline persistence, and
        // should be handled directly via API or load queue. This avoids
        // unnecessary complexity and ensures only mutating operations are
        // tracked for sync/retry.
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

  /// Creates and enqueues a NetworkTask for immediate sync execution.
  ///
  /// This method is used by save operations to perform immediate background
  /// sync while also maintaining the sync queue entry for retry capability.
  ///
  /// [operation] The type of sync operation to enqueue
  /// (create, update, delete).
  /// [item] The model instance to sync.
  /// [idempotencyKey] A unique key to ensure idempotent task execution.
  /// [headers] Optional headers to include in the API request.
  /// [extra] Optional extra data to include in the API request.
  Future<void> enqueueImmediateSyncTask(
    SyncOperation operation,
    T item,
    String idempotencyKey,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  ) async {
    final syncTask = NetworkTask<void>(
      exec: () => executeSyncOperation(operation, item, headers, extra),
      idempotencyKey: idempotencyKey,
      operation: operation,
      modelType: T.toString(),
      modelId: item.id,
      taskName: 'BackgroundSync-${T.toString()}-${item.id}',
    );

    await queueManager.enqueueTask(syncTask, queueType: QueueType.background);
  }

  /// Manages sync queue entries for save operations.
  ///
  /// This method handles the complex logic of:
  /// - Checking for existing sync queue entries
  /// - Updating or creating entries as needed
  /// - Managing operation precedence (CREATE vs UPDATE)
  /// - Triggering immediate sync execution
  ///
  /// [item] The model instance to sync.
  /// [operation] The type of sync operation to manage (create, update).
  /// [idempotencyKey] A unique key to ensure idempotent task execution.
  /// [headers] Optional headers to include in the API request.
  /// [extra] Optional extra data to include in the API request.
  /// Returns the sync queue entry ID for tracking purposes.
  Future<int> manageSyncQueueForSave(
    T item,
    SyncOperation operation,
    String idempotencyKey,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  ) async {
    final syncQueueDao = SyncQueueDao(SynquillStorage.database);
    int syncQueueId;

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

    return syncQueueId;
  }

  /// Attempts immediate sync execution and removes queue entry on success.
  ///
  /// This method tries to perform the sync operation immediately, and if
  /// successful, removes the sync queue entry. If it fails, the entry
  /// remains for retry by the RetryExecutor.
  Future<void> tryImmediateSyncAndCleanup(
    SyncOperation operation,
    T item,
    String idempotencyKey,
    int syncQueueId,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  ) async {
    final syncQueueDao = SyncQueueDao(SynquillStorage.database);

    try {
      await enqueueImmediateSyncTask(
        operation,
        item,
        idempotencyKey,
        headers,
        extra,
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
  }

  /// Processes background sync operations for localFirst saves.
  ///
  /// This method coordinates the full background sync workflow:
  /// 1. Creates or updates sync queue entries
  /// 2. Attempts immediate sync execution
  /// 3. Manages queue cleanup on success
  ///
  /// This ensures proper background sync behavior while maintaining
  /// local-first semantics.
  Future<void> processBackgroundSync(
    T item,
    SyncOperation operation,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  ) async {
    // Create idempotency key for this operation
    final idempotencyKey =
        '${item.id}-${operation.name}-'
        '${cuid()}';

    try {
      // Manage sync queue entry (create/update as needed)
      final syncQueueId = await manageSyncQueueForSave(
        item,
        operation,
        idempotencyKey,
        headers,
        extra,
      );

      // Try immediate sync execution
      await tryImmediateSyncAndCleanup(
        operation,
        item,
        idempotencyKey,
        syncQueueId,
        headers,
        extra,
      );
    } catch (e, stackTrace) {
      log.warning(
        'Error during background sync processing for ${item.id}',
        e,
        stackTrace,
      );
      // Don't rethrow - background sync failures shouldn't break saves
    }
  }

  /// Checks if the repository has access to required sync components.
  ///
  /// This method validates that the repository can access the queue manager
  /// and sync queue DAO needed for background sync operations.
  bool get canPerformBackgroundSync {
    try {
      // Try to access key sync components to ensure they work
      queueManager;
      SynquillStorage.database;
      return true;
    } catch (e) {
      log.fine('Background sync components not available: $e');
      return false;
    }
  }

  /// Gets queue statistics for monitoring sync operations.
  ///
  /// Returns a map of queue types to their current statistics,
  /// useful for debugging and monitoring sync performance.
  Map<QueueType, QueueStats> getSyncQueueStats() {
    try {
      return queueManager.getQueueStats();
    } catch (e) {
      log.warning('Failed to get sync queue stats: $e');
      return {};
    }
  }

  /// Triggers immediate processing of pending sync tasks.
  ///
  /// This method can be used to manually trigger sync operations,
  /// useful for testing or when connectivity is restored.
  Future<void> processPendingSyncTasks({bool forceSync = false}) async {
    try {
      final retryExecutor = SynquillStorage.retryExecutor;
      await retryExecutor.processDueTasksNow(forceSync: forceSync);
      log.info('Pending sync tasks processed successfully');
    } catch (e, stackTrace) {
      log.warning('Failed to process pending sync tasks', e, stackTrace);
      rethrow;
    }
  }
}
