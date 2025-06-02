part of synquill;

/// Mixin providing remote operations for repositories.
mixin RepositoryRemoteOperations<T extends SynquillDataModel<T>> {
  /// Fetches an item from the remote API.
  ///
  /// This is a placeholder that should be overridden by concrete repository.
  /// [QueryParams] Additional query parameters for filtering
  /// (may be used for complex lookups).
  @protected
  Future<T?> fetchFromRemote(
    String id, {
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    log.warning('fetchFromRemote() not implemented for $T');
    return null;
  }

  /// Fetches all items from the remote API.
  ///
  /// This is a placeholder that should be overridden by concrete repository.
  /// [queryParams] Query parameters for filtering, sorting, and pagination.
  @protected
  Future<List<T>> fetchAllFromRemote({
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    log.warning('fetchAllFromRemote() not implemented for $T');
    return [];
  }

  /// Logger for the repository - must be implemented by concrete classes
  Logger get log;
}
