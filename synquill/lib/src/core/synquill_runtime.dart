part of 'synquill_storage.dart';

/// Owns the runtime services for a single initialized Synquill storage
/// lifetime.
class _SynquillRuntime {
  /// The Drift database used by this runtime.
  final GeneratedDatabase database;

  /// The runtime configuration.
  SynquillStorageConfig config;

  /// The runtime logger.
  final Logger logger;

  /// Repository factories and cached instances scoped to this runtime.
  final SynquillRepositoryRegistry repositoryRegistry;

  /// Connectivity subscription owned by this runtime.
  StreamSubscription<bool>? connectivitySubscription;

  /// Last status received from [connectivitySubscription].
  bool? lastConnectivityStatus;

  /// Optional active connectivity checker.
  Future<bool> Function()? connectivityChecker;

  /// Request queues owned by this runtime.
  RequestQueueManager? queueManager;

  /// Retry executor owned by this runtime.
  RetryExecutor? retryExecutor;

  /// Dependency resolver owned by this runtime.
  DependencyResolver? dependencyResolver;

  /// Background sync manager used by this runtime.
  BackgroundSyncManager? backgroundSyncManager;

  /// Sync queue DAO owned by this runtime.
  SyncQueueDao? syncQueueDao;

  bool _isClosed = false;

  /// Creates an uninitialized runtime state container.
  _SynquillRuntime({
    required this.database,
    required this.config,
    required this.logger,
    SynquillRepositoryRegistry? repositoryRegistry,
  }) : repositoryRegistry = repositoryRegistry ??
            SynquillRepositoryRegistry(
              logger: Logger('SynquillRepositoryProvider.runtime'),
            );

  /// Initializes the database, repositories, queues, background sync, and
  /// connectivity services owned by this runtime.
  Future<void> initialize({
    void Function(GeneratedDatabase)? initializeFn,
    Stream<bool>? connectivityStream,
    Future<bool> Function()? connectivityChecker,
    bool enableInternetMonitoring = true,
  }) async {
    SynquillRepositoryProvider.attachRuntimeRegistry(repositoryRegistry);

    _initializeDatabase(initializeFn);
    _initializeCoreSystems();
    await initializeBackgroundSync();
    _initializeConnectivity(
      connectivityStream,
      connectivityChecker,
      enableInternetMonitoring,
    );
    enableForegroundMode();

    logger.info('SynquillStorage initialization complete');
  }

  /// Checks if the device currently has an internet connection.
  Future<bool> get isConnected async {
    if (connectivityChecker != null) {
      try {
        return await connectivityChecker!();
      } catch (e) {
        logger.warning('Connectivity checker function failed: $e');
        // Fall back to last known status
      }
    }

    // Return last known status from stream, or true if no stream was provided
    return lastConnectivityStatus ?? true;
  }

  /// Retrieves a repository instance by model type string name.
  SynquillRepositoryBase<SynquillDataModel<dynamic>>? getRepositoryByName(
    String modelTypeName,
  ) {
    return repositoryRegistry.getByTypeName(modelTypeName);
  }

  /// Gets a strongly-typed repository for the specified model type.
  SynquillRepositoryBase<T> getRepository<T extends SynquillDataModel<T>>() {
    try {
      return repositoryRegistry.get<T>();
    } catch (e) {
      throw StateError(
        'No repository registered for type '
        '${T.toString()}. Make sure '
        'initializeSynquillStorage() was called.',
      );
    }
  }

  /// Processes queued background sync tasks.
  Future<void> processBackgroundSyncTasks({bool forceSync = false}) async {
    await backgroundSyncManager!.processBackgroundSyncTasks(
      forceSync: forceSync,
    );
  }

  /// Switches the retry executor to background mode.
  void enableBackgroundMode() {
    backgroundSyncManager!.enableBackgroundMode();
  }

  /// Switches the retry executor to foreground mode.
  void enableForegroundMode({bool forceSync = false}) {
    backgroundSyncManager!.enableForegroundMode(forceSync: forceSync);
  }

  /// Initializes or reinitializes the background sync manager.
  Future<void> initializeBackgroundSync() async {
    backgroundSyncManager = BackgroundSyncManager.instance;
    await BackgroundSyncManager.initialize();
    logger.info('Background sync manager initialized');
  }

  /// Closes all resources owned by this runtime.
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;

    try {
      await repositoryRegistry.disposeCachedRealtimeSubscriptions();

      // Stop retry executor first to prevent new tasks and wait for completion
      if (retryExecutor != null) {
        await retryExecutor!.stop();
      }

      // Reset background sync manager
      await BackgroundSyncManager.reset();

      // Cancel connectivity subscription before reset
      await connectivitySubscription?.cancel();

      await queueManager?.joinAll();

      await queueManager?.dispose();

      // Close database after all operations are complete
      logger.info('Closing database connection');
      await database.close();
    } finally {
      repositoryRegistry.reset();
      SynquillRepositoryProvider.detachRuntimeRegistry(repositoryRegistry);
      SynquillStorage._resetGlobalProviders();
    }
  }

  void _initializeDatabase(
    void Function(GeneratedDatabase)? initializeFn,
  ) {
    DatabaseProvider.setInstance(database);
    if (initializeFn != null) {
      initializeFn(database);
      logger.info('Repository system initialized');
    }
  }

  void _initializeCoreSystems() {
    queueManager ??= RequestQueueManager(config: config);
    logger.info('Request queue manager initialized');

    dependencyResolver ??= DependencyResolver();
    logger.info('Dependency resolver initialized');

    syncQueueDao ??= SyncQueueDao(database);
    logger.info('Sync queue DAO initialized');

    retryExecutor ??= RetryExecutor(database, queueManager!);
    retryExecutor!.start();
    logger.info('Retry executor started');
  }

  void _initializeConnectivity(
    Stream<bool>? connectivityStream,
    Future<bool> Function()? connectivityChecker,
    bool enableInternetMonitoring,
  ) {
    this.connectivityChecker = connectivityChecker;
    if (enableInternetMonitoring && connectivityStream != null) {
      connectivitySubscription = connectivityStream.listen(
        (isConnected) {
          final previousStatus = lastConnectivityStatus;
          lastConnectivityStatus = isConnected;
          _handleConnectivityChange(previousStatus, isConnected);
        },
        onError: (error) {
          logger.warning('Connectivity stream error: $error');
        },
      );
      logger.info('Connectivity monitoring enabled with stream');
    } else if (enableInternetMonitoring && connectivityChecker != null) {
      logger.info(
        'Connectivity monitoring enabled with checker function only',
      );
    } else {
      logger.info('Connectivity monitoring disabled');
    }
  }

  void _handleConnectivityChange(
    bool? previousStatus,
    bool currentStatus,
  ) {
    // Handle transition to disconnected
    if (currentStatus == false && previousStatus == true) {
      logger.info('Connection lost - clearing request queues');
      queueManager?.clearQueuesOnDisconnect();
    }

    // Handle transition to connected
    if (currentStatus == true && previousStatus == false) {
      logger.info('Connection restored - restoring queue processing');
      queueManager?.restoreQueuesOnConnect();
    }
  }
}
