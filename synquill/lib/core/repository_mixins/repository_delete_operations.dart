part of synquill;

/// Mixin providing delete and cascade delete operations for repositories.
///
/// This mixin contains all deletion-related functionality including:
/// - Single item deletion with different policies
/// - Cascade delete support for related models
/// - Smart delete queue management
/// - Local storage removal methods
mixin RepositoryDeleteOperations<T extends SynquillDataModel<T>>
    on RepositoryLocalOperations<T> {
  /// The logger instance for this repository.
  ///
  /// Used for logging all repository operations, errors, and debug
  /// information. This logger should be used for all actions, errors,
  /// and debug output related to repository lifecycle and sync.
  @override
  Logger get log;

  /// The stream controller for repository change events.
  ///
  /// Notifies listeners about changes to the repository, such as item
  /// deletions, insertions, or errors. This enables reactive updates
  /// in the UI or other system components when repository state changes.
  StreamController<RepositoryChange<T>> get changeController;

  /// The API adapter used for remote operations.
  ///
  /// Handles communication with the remote REST API for CRUD operations
  /// on the model type [T]. This adapter abstracts network calls and
  /// error handling for remote data sync.
  ApiAdapterBase<T> get apiAdapter;

  /// The request queue manager for handling queued operations.
  ///
  /// Manages the local queue of pending operations (such as deletes)
  /// to be synchronized with the remote API when online. Ensures
  /// reliable sync and conflict resolution in offline/online scenarios.
  RequestQueueManager get queueManager;

  /// The default save policy for this repository.
  ///
  /// Determines the default strategy for saving and deleting data
  /// (e.g., local-first or remote-first) when not explicitly specified.
  /// This policy guides how data is prioritized between local and remote.
  DataSavePolicy get defaultSavePolicy;

  /// Deletes an item by its ID.
  ///
  /// [id] The unique identifier of the item to delete.
  /// [savePolicy] Controls whether to delete from local storage, remote API,
  /// or both.
  /// [deletionContext] Internal parameter for cycle detection in cascade
  /// deletes. Should not be used by external callers.
  Future<void> delete(
    String id, {
    DataSavePolicy? savePolicy,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
    Set<String>? deletionContext,
  }) async {
    // Use provided deletion context or create empty set for new operations
    final effectiveDeletionContext = deletionContext ?? <String>{};

    // Delegate to private method with deletion context
    await _deleteWithContext(
      id,
      savePolicy: savePolicy,
      deletionContext: effectiveDeletionContext,
      extra: extra,
      headers: headers,
    );
  }

  /// Private method that handles deletion with cycle detection context.
  ///
  /// [id] The unique identifier of the item to delete.
  /// [savePolicy] Controls whether to delete from local storage, remote API,
  /// or both.
  /// [deletionContext] Set of IDs currently being deleted to prevent cycles.
  Future<void> _deleteWithContext(
    String id, {
    DataSavePolicy? savePolicy,
    required Set<String> deletionContext,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    savePolicy ??= defaultSavePolicy;
    log.fine('Current deletion context: $deletionContext');
    log.fine('Using policy: ${savePolicy.name}');

    // Check for cycles - if this item is already being deleted, skip it
    if (deletionContext.contains(id)) {
      log.warning(
        'Cycle detected: $T with ID $id is already being deleted, '
        'skipping to prevent infinite recursion',
      );
      return;
    }

    // Add current ID to deletion context to track it
    final updatedContext = {...deletionContext, id};
    log.fine('Updated deletion context: $updatedContext');

    // Handle cascade delete first with updated context
    await _handleCascadeDelete(
      id: id,
      savePolicy: savePolicy,
      deletionContext: updatedContext,
      extra: extra,
      headers: headers,
    );

    log.fine('_handleCascadeDelete completed for ${T.toString()} $id');

    // Use smart delete logic to handle sync queue entries properly
    log.info('About to fetch item from local for ${T.toString()} $id');

    final itemToDelete = await fetchFromLocal(id, queryParams: null);

    // Check if this is a local-only repository
    bool isLocalOnly = false;
    try {
      // Try to access the apiAdapter - if it throws UnsupportedError,
      // this is a local-only repository
      apiAdapter;
    } on UnsupportedError {
      isLocalOnly = true;
      log.fine(
        'Repository for $T is local-only, skipping sync operations for delete.',
      );
    }

    String payload;
    if (isLocalOnly) {
      // For local-only repositories, we don't need JSON payload
      payload = convert.jsonEncode({'id': id});
    } else {
      // For sync-enabled repositories, try to get full payload
      payload = itemToDelete != null
          ? convert.jsonEncode(itemToDelete.toJson())
          : convert.jsonEncode({'id': id}); // Fallback with just ID
    }

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
        changeController.add(RepositoryChange.deleted(id));
        log.fine('Local delete for $id successful.');

        return;
      case DataSavePolicy.remoteFirst:
        log.info('Policy: remoteFirst. Deleting $T from remote API first.');
        try {
          // Create a NetworkTask for remoteFirst delete operation
          // and route through foreground queue for immediate execution
          final remoteFirstDeleteTask = NetworkTask<void>(
            exec: () =>
                apiAdapter.deleteOne(id, extra: extra, headers: headers),
            idempotencyKey: '$id-remoteFirst-delete-'
                '${cuid()}',
            operation: SyncOperation.delete,
            modelType: T.toString(),
            modelId: id,
            taskName: 'remoteFirst_delete_$T',
          );

          // Execute via foreground queue
          await queueManager.enqueueTask(
            remoteFirstDeleteTask,
            queueType: QueueType.foreground,
          );

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
          changeController.add(RepositoryChange.deleted(id));
        } on OfflineException catch (e, stackTrace) {
          log.warning(
            'OfflineException during remoteFirst delete for $T $id. '
            'Operation failed as per policy.',
            e,
            stackTrace,
          );
          changeController.add(RepositoryChange.error(e, stackTrace));
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
          changeController.add(RepositoryChange.deleted(id));
          // Not rethrowing as the desired state (item gone) is achieved.
        } on ApiException catch (e, stackTrace) {
          log.severe(
            'ApiException during remoteFirst delete for $T $id.',
            e,
            stackTrace,
          );
          changeController.add(RepositoryChange.error(e, stackTrace));
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
          changeController.add(RepositoryChange.error(e, stackTrace));
          throw SynquillStorageException(
            'Failed to delete $T $id with remoteFirst policy: $e',
            stackTrace,
          );
        }
        return;
    }
  }

  /// Smart delete handler that manages sync queue operations for deletions.
  ///
  /// This method handles the complex logic of managing sync queue entries
  /// when a model is deleted, ensuring proper queue state management.
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
        idempotencyKey: '$modelId-delete-${cuid()}',
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
    required Set<String> deletionContext,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    log.info('===== _handleCascadeDelete START for ${T.toString()} $id =====');
    log.info('Deletion context in cascade delete: $deletionContext');
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
            deletionContext: deletionContext,
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
    required Set<String> deletionContext,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    log.info(
      '===== _deleteCascadeRelatedItems START for $parentId → '
      '${relation.targetType} =====',
    );
    log.info('Deletion context in cascade related items: $deletionContext');
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

      // Delete each related item with cycle detection
      for (final item in relatedItems) {
        log.info('Processing cascade delete for ${item.id}');
        // Check for cycles before processing each item
        if (deletionContext.contains(item.id)) {
          log.warning(
            'Cycle detected: $targetType with ID ${item.id} is already '
            'being deleted, skipping to prevent infinite recursion',
          );
          continue; // Skip this item to prevent cycle
        }

        log.info('About to delete ${item.id} via targetRepository.delete');
        // Pass deletion context to prevent cycles across repositories
        await targetRepository.delete(
          item.id,
          savePolicy: savePolicy,
          extra: extra,
          headers: headers,
          deletionContext: deletionContext,
        );
        log.info('Completed delete for ${item.id}');
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

  /// Handles cascade delete operations when a parent model is gone (HTTP 410).
  ///
  /// This method is specifically designed for scenarios where the server
  /// reports that a parent model is gone (HTTP 410 Gone). It performs:
  /// 1. Local cascade delete to clean up child relationships
  /// 2. Remote cleanup attempts for children using remoteFirst policy
  /// 3. Proper sync queue management (doesn't schedule parent delete)
  ///
  /// The API is expected to handle delete attempts on already-deleted children
  /// gracefully by returning HTTP 204 (No Content). The existing delete()
  /// method already handles HTTP 410 responses appropriately.
  ///
  /// Unlike regular delete operations, this assumes the parent is already
  /// gone from the server and focuses on cleaning up children that might
  /// be orphaned.
  ///
  /// [id] The ID of the parent model that is gone
  /// [extra] Optional extra data for delete operations
  /// [headers] Optional headers for API requests
  Future<void> handleCascadeDeleteAfterGone(
    String id, {
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    log.info(
      'Handling cascade delete after parent $T $id reported as gone (410)',
    );

    try {
      // Use remoteFirst policy for children to ensure API cleanup
      // API will return 204 for already-deleted children, or 410 if gone
      // Both cases are handled appropriately by the delete() method
      await _handleCascadeDelete(
        id: id,
        savePolicy: DataSavePolicy.remoteFirst,
        deletionContext: {id}, // Parent is already being handled
        extra: extra,
        headers: headers,
      );

      // Remove the parent from local storage and clean up sync queue
      await _handleSmartDelete(
        modelId: id,
        payload: convert.jsonEncode({'id': id}),
        scheduleDelete: false, // Don't schedule delete - it's already gone
        headers: headers,
        extra: extra,
      );

      await removeFromLocalIfExists(id);
      changeController.add(RepositoryChange.deleted(id));

      log.fine('Cascade delete after gone completed for $T $id');
    } catch (e, stackTrace) {
      log.warning(
        'Error during cascade delete after gone for $T $id',
        e,
        stackTrace,
      );
      // Still try to remove the local copy even if cascade delete fails
      await removeFromLocalIfExists(id);
      changeController.add(RepositoryChange.deleted(id));
    }
  }

  /// Truncates (clears) all local storage for this model type.
  ///
  /// This method deletes all records from the local table without triggering
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
