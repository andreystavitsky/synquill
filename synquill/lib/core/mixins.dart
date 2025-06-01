part of synquill;

/// Base mixin for common DAO operations to reduce code duplication
mixin BaseDaoMixin<T> {
  /// Get model by ID as typed model object
  Future<T?> getByIdTyped(String id, {QueryParams? queryParams});

  /// Get all models as typed model objects
  Future<List<T>> getAllTyped({QueryParams? queryParams});

  /// Watch model by ID as typed stream
  Stream<T?> watchByIdTyped(String id, {QueryParams? queryParams});

  /// Watch all models as typed stream
  Stream<List<T>> watchAllTyped({QueryParams? queryParams});
}

/// Mixin that provides common repository operations to reduce code duplication
mixin RepositoryHelpersMixin<T extends SynquillDataModel<T>>
    on SynquillRepositoryBase<T> {
  /// The DAO instance for this repository - must be implemented
  /// by concrete classes
  DatabaseAccessor get dao;

  @override
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

  @override
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

  @override
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

  @override
  Stream<List<T>> watchAllFromLocal({QueryParams? queryParams}) {
    if (dao is BaseDaoMixin<T>) {
      return (dao as BaseDaoMixin<T>).watchAllTyped(queryParams: queryParams);
    }
    throw UnimplementedError(
      'DAO must implement BaseDaoMixin<${T.toString()}>',
    );
  }

  @override
  Future<void> saveToLocal(T item) async {
    // Use dynamic call since we don't have a common interface
    await (dao as dynamic).saveModel(item);
  }

  @override
  Future<void> removeFromLocalIfExists(String id) async {
    final existing = await fetchFromLocal(id, queryParams: null);
    if (existing != null) {
      await (dao as dynamic).deleteById(id);
    }
  }

  @override
  Future<void> truncateLocalStorage() async {
    // Use dynamic call to delete all records from the table
    await (dao as dynamic).deleteAll();
  }

  @override
  Future<bool> isExistingItem(T item) async {
    final existing = await fetchFromLocal(item.id, queryParams: null);
    return existing != null;
  }

  @override
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
            super.log.warning(
              'Warning: Failed to recreate model $modelId from sync queue: $e',
            );
          }
        }
      }
    }
  }
}
