part of synquill;

/// Base class for synchronized repositories.
///
/// This class provides the core functionality for repositories that
/// synchronize data between a local database and a remote API.
abstract class SynquillRepositoryBase<T extends SynquillDataModel<T>>
    with
        RepositoryLocalOperations<T>,
        RepositoryRemoteOperations<T>,
        RepositoryQueryOperations<T>,
        RepositorySaveOperations<T>,
        RepositoryDeleteOperations<T>,
        RepositorySyncOperations<T> {
  /// The database connection.
  final GeneratedDatabase db;

  /// The logger for this repository.
  late final Logger log;

  /// The queue manager for handling API operations.
  late final RequestQueueManager _queueManager;

  /// The stream controller for repository change events.
  final StreamController<RepositoryChange<T>> _changeController =
      StreamController<RepositoryChange<T>>.broadcast();

  /// Creates a new synchronized repository.
  SynquillRepositoryBase(this.db) {
    log = Logger('SyncedRepository<${T.toString()}>');
    try {
      _queueManager = SynquillStorage.queueManager;
    } catch (_) {
      // For tests or when SyncedStorage is not initialized
      _queueManager = RequestQueueManager(config: SynquillStorage.config);
    }
  }

  /// A stream of changes to this repository.
  Stream<RepositoryChange<T>> get changes => _changeController.stream;

  /// Gets the stream controller for emitting change events.
  /// This is used by the mixins to emit change events.
  @protected
  StreamController<RepositoryChange<T>> get changeController =>
      _changeController;

  /// Gets the queue manager for this repository.
  /// This is used by the mixins for sync operations.
  @protected
  RequestQueueManager get queueManager => _queueManager;

  /// Gets the default save policy from global configuration.
  @protected
  DataSavePolicy get defaultSavePolicy {
    return SynquillStorage.config?.defaultSavePolicy ??
        DataSavePolicy.localFirst;
  }

  /// Gets the default load policy from global configuration.
  @protected
  DataLoadPolicy get defaultLoadPolicy {
    return SynquillStorage.config?.defaultLoadPolicy ??
        DataLoadPolicy.localThenRemote;
  }

  /// Gets the API adapter for this repository.
  /// This needs to be implemented by the concrete generated repository.
  @protected
  ApiAdapterBase<T> get apiAdapter =>
      throw UnimplementedError(
        'apiAdapter getter must be implemented by subclasses',
      );

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
    final result = await findOne(
      id,
      loadPolicy: loadPolicy,
      queryParams: queryParams,
      extra: extra,
      headers: headers,
    );
    if (result == null) {
      throw NotFoundException('$T with ID $id not found');
    }
    return result;
  }

  /// Disposes of resources used by this repository.
  void dispose() {
    _changeController.close();
  }
}
