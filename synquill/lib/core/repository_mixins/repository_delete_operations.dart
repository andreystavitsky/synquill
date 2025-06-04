part of synquill;

/// Mixin providing delete and cascade delete operations for repositories.
///
/// This mixin contains all deletion-related functionality including:
/// - Single item deletion with different policies
/// - Cascade delete support for related models
/// - Smart delete queue management
/// - Local storage removal methods
mixin RepositoryDeleteOperations<T extends SynquillDataModel<T>> {
  /// The logger instance for this repository.
  ///
  /// Used for logging all repository operations, errors, and debug
  /// information. This logger should be used for all actions, errors,
  /// and debug output related to repository lifecycle and sync.
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

  /// Abstract methods that must be implemented by the using class
  /// Removes an item from local storage if it exists.
  ///
  /// [id] The unique identifier of the item to remove.
  Future<void> removeFromLocalIfExists(String id);

  /// Saves an item to local storage.
  ///
  /// [item] The item to save.
  /// [extra] Optional extra data to associate with the save operation.
  Future<void> saveToLocal(T item, {Map<String, dynamic>? extra});

  /// Fetches an item from local storage by its ID.
  ///
  /// [id] The unique identifier of the item to fetch.
  /// [queryParams] Optional query parameters for the fetch operation.
  /// Returns the item if found, or null otherwise.
  Future<T?> fetchFromLocal(String id, {QueryParams? queryParams});

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

    final itemToDelete = await fetchFromLocal(id, queryParams: null);

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
        changeController.add(RepositoryChange.deleted(id));
        log.fine('Local delete for $id successful.');

        return;
      case DataSavePolicy.remoteFirst:
        log.info('Policy: remoteFirst. Deleting $T from remote API first.');
        try {
          // Create a NetworkTask for remoteFirst delete operation
          // and route through foreground queue for immediate execution
          final remoteFirstDeleteTask = NetworkTask<void>(
            exec:
                () => apiAdapter.deleteOne(id, extra: extra, headers: headers),
            idempotencyKey:
                '$id-remoteFirst-delete-'
                '${DateTime.now().millisecondsSinceEpoch}',
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
