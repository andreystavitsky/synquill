part of synquill;

/// Base mixin for common DAO operations to reduce code duplication
mixin BaseDaoMixin<T> {
  /// Retrieves a model by its unique identifier as a typed model object.
  ///
  /// [id] The unique identifier of the model to fetch.
  /// [queryParams] Optional query parameters for filtering or
  /// customizing the fetch.
  /// Returns the model if found, or null otherwise.
  Future<T?> getByIdTyped(String id, {QueryParams? queryParams});

  /// Retrieves all models as typed model objects.
  ///
  /// [queryParams] Optional query parameters for filtering, sorting,
  /// or pagination.
  /// Returns a list of all models matching the query.
  Future<List<T>> getAllTyped({QueryParams? queryParams});

  /// Watches a model by its unique identifier as a typed stream.
  ///
  /// [id] The unique identifier of the model to watch.
  /// [queryParams] Optional query parameters for filtering or
  /// customizing the stream.
  /// Returns a stream that emits the model when it changes.
  Stream<T?> watchByIdTyped(String id, {QueryParams? queryParams});

  /// Watches all models as a typed stream.
  ///
  /// [queryParams] Optional query parameters for filtering, sorting,
  /// or pagination.
  /// Returns a stream that emits the list of models when any change occurs.
  Stream<List<T>> watchAllTyped({QueryParams? queryParams});
}

/// Mixin that provides common repository operations to reduce code duplication
mixin RepositoryHelpersMixin<T extends SynquillDataModel<T>> {
  /// The DAO instance for this repository.
  ///
  /// Provides access to database operations for the model type [T].
  /// Must be implemented by concrete repository classes to enable
  /// local storage and query operations.
  DatabaseAccessor get dao;

  /// The logger instance for this repository.
  ///
  /// Used for logging repository operations, errors, and debug
  /// information. Should be used for all actions and error reporting
  /// related to repository logic.
  Logger get log;

  /// The generated database instance for this repository.
  ///
  /// Provides access to the underlying Drift database for advanced
  /// queries and sync queue management.
  GeneratedDatabase get db;

  /// The API adapter for this repository.
  ///
  /// Handles communication with the remote REST API for CRUD operations
  /// and model serialization/deserialization for type [T].
  ApiAdapterBase<T> get apiAdapter;

  /// Fetches a model from local storage by its unique identifier.
  ///
  /// [id] The unique identifier of the model to fetch.
  /// [queryParams] Optional query parameters for filtering or
  /// customizing the fetch.
  /// Returns the model if found, or throws an error
  /// if the DAO is not implemented.
  Future<T?> fetchFromLocal(String id, {QueryParams? queryParams}) async {
    if (dao is BaseDaoMixin<T>) {
      return await (dao as BaseDaoMixin<T>).getByIdTyped(
        id,
        queryParams: queryParams,
      );
    }
    throw UnimplementedError(
      'DAO must implement BaseDaoMixin<${T.toString()}>',
    );
  }

  /// Fetches all models from local storage.
  ///
  /// [queryParams] Optional query parameters for filtering, sorting,
  /// or pagination.
  /// Returns a list of all models matching the query, or throws an error
  /// if the DAO is not implemented.
  Future<List<T>> fetchAllFromLocal({QueryParams? queryParams}) async {
    if (dao is BaseDaoMixin<T>) {
      return await (dao as BaseDaoMixin<T>).getAllTyped(
        queryParams: queryParams,
      );
    }
    throw UnimplementedError(
      'DAO must implement BaseDaoMixin<${T.toString()}>',
    );
  }

  /// Fetches all items from local storage, excluding items with pending
  /// sync operations.
  ///
  /// This method is used when we want to get local data but filter out
  /// items that have local changes that haven't been synced to remote yet.
  /// [queryParams] Query parameters for filtering, sorting, and pagination.
  Future<List<T>> fetchAllFromLocalWithoutPendingSyncOps({
    QueryParams? queryParams,
  }) async {
    final allItems = await fetchAllFromLocal(queryParams: queryParams);
    final syncQueueDao = SyncQueueDao(db);
    final filteredItems = <T>[];

    for (final item in allItems) {
      final pendingTasks = await syncQueueDao.getTasksForModelId(
        T.toString(),
        item.id,
      );

      // Include only items without pending sync operations
      if (pendingTasks.isEmpty) {
        filteredItems.add(item);
      }
    }

    return filteredItems;
  }

  /// Watches a model from local storage by its unique identifier.
  ///
  /// [id] The unique identifier of the model to watch.
  /// [queryParams] Optional query parameters for filtering or
  /// customizing the stream.
  /// Returns a stream that emits the model when it changes, or throws
  /// an error if the DAO is not implemented.
  Stream<T?> watchFromLocal(String id, {QueryParams? queryParams}) {
    if (dao is BaseDaoMixin<T>) {
      return (dao as BaseDaoMixin<T>).watchByIdTyped(
        id,
        queryParams: queryParams,
      );
    }
    throw UnimplementedError(
      'DAO must implement BaseDaoMixin<${T.toString()}>',
    );
  }

  /// Watches all models from local storage as a stream.
  ///
  /// [queryParams] Optional query parameters for filtering, sorting,
  /// or pagination.
  /// Returns a stream that emits the list of models when any change occurs,
  /// or throws an error if the DAO is not implemented.
  Stream<List<T>> watchAllFromLocal({QueryParams? queryParams}) {
    if (dao is BaseDaoMixin<T>) {
      return (dao as BaseDaoMixin<T>).watchAllTyped(queryParams: queryParams);
    }
    throw UnimplementedError(
      'DAO must implement BaseDaoMixin<${T.toString()}>',
    );
  }

  /// Saves a model to local storage.
  ///
  /// [item] The model to save.
  /// [extra] Optional extra data to associate with the save operation.
  Future<void> saveToLocal(T item, {Map<String, dynamic>? extra}) async {
    // Use dynamic call since we don't have a common interface
    await (dao as dynamic).saveModel(item);
  }

  /// Removes a model from local storage if it exists.
  ///
  /// [id] The unique identifier of the model to remove.
  Future<void> removeFromLocalIfExists(String id) async {
    final existing = await fetchFromLocal(id, queryParams: null);
    if (existing != null) {
      await (dao as dynamic).deleteById(id);
    }
  }

  /// Truncates all data in local storage.
  ///
  /// Deletes all records from the table associated with the model type [T]
  /// without firing a remote sync operations.
  Future<void> truncateLocalStorage() async {
    // Use dynamic call to delete all records from the table
    await (dao as dynamic).deleteAll();
  }

  /// Checks if a model exists in local storage.
  ///
  /// [item] The model to check for existence.
  /// Returns true if the model exists, false otherwise.
  Future<bool> isExistingItem(T item) async {
    final existing = await fetchFromLocal(item.id, queryParams: null);
    return existing != null;
  }

  /// Updates the local cache with a list of models.
  ///
  /// [items] The list of models to update the cache with.
  /// This method skips updating models that have pending sync operations
  /// to avoid overwriting local changes.
  Future<void> updateLocalCache(List<T> items) async {
    final syncQueueDao = SyncQueueDao(db);

    for (final item in items) {
      final pendingTasks = await syncQueueDao.getTasksForModelId(
        T.toString(),
        item.id,
      );

      // Skip updating local cache for items that have ANY pending sync
      // operations (create, update, or delete). This prevents overwriting
      // local changes that haven't been synced yet.
      if (pendingTasks.isNotEmpty) {
        continue;
      }

      // No pending operations, safe to update local cache with remote data
      await saveToLocal(item);
    }

    // After processing remote items, check for pending CREATE/UPDATE operations
    // in sync queue and recreate those models from their stored payload.
    // This is important for data refresh workflows where local storage is
    // truncated but we need to restore models with pending operations.
    final allPendingTasks = await syncQueueDao.getItemsByModelType(
      T.toString(),
    );

    for (final task in allPendingTasks) {
      final operation = task['op'] as String;
      final modelId = task['model_id'] as String;

      // Only recreate for CREATE and UPDATE operations
      if (operation == 'create' || operation == 'update') {
        // Check if model already exists in local storage
        final existing = await fetchFromLocal(modelId);
        if (existing == null) {
          // Model doesn't exist locally, recreate from sync queue payload
          try {
            final payload = task['payload'] as String;
            final modelData =
                convert.jsonDecode(payload) as Map<String, dynamic>;

            // Create model instance from JSON data
            // We need to use the API adapter's fromJson method to properly
            // reconstruct the model
            final recreatedModel = apiAdapter.fromJson(modelData);
            await saveToLocal(recreatedModel);
          } catch (e) {
            // Log error but don't fail the entire operation
            log.warning(
              'Warning: Failed to recreate model $modelId from sync queue: $e',
            );
          }
        }
      }
    }
  }
}
