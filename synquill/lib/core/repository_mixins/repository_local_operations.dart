part of synquill;

/// Mixin providing abstract local storage operations for repositories.
mixin RepositoryLocalOperations<T extends SynquillDataModel<T>> {
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
  Future<void> saveToLocal(T item, {Map<String, dynamic>? extra}) async {
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

  /// Watches all items from the local database.
  ///
  /// This is a placeholder that should be overridden by concrete repository.
  /// [queryParams] Query parameters for filtering, sorting, and pagination.
  @protected
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

  /// Logger for the repository - must be implemented by concrete classes
  Logger get log;
}
