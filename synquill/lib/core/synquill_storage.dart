part of synquill;

/// Base class for synced data storage configuration.
class SynquillStorageConfig {
  /// Optional Dio client for network requests.
  /// If null, an internal default client will be configured.
  final dynamic dio; // Using dynamic for now, will be Dio? later

  /// Whether to keep the connection alive. Defaults to true.
  final bool keepConnectionAlive;

  /// The concurrency level for the remoteFirst request queue. Defaults to 1.
  final int foregroundQueueConcurrency;

  /// The concurrency level for the localFirst request queue. Defaults to 2.
  final int backgroundQueueConcurrency;

  /// Default data save policy for all repositories.
  /// If null, defaults to [DataSavePolicy.localFirst].
  final DataSavePolicy? defaultSavePolicy;

  /// Default data load policy for all repositories.
  /// If null, defaults to [DataLoadPolicy.localThenRemote].
  final DataLoadPolicy? defaultLoadPolicy;

  /// Retry configuration

  /// Initial retry delay for failed sync operations.
  final Duration initialRetryDelay;

  /// Maximum retry delay for failed sync operations.
  final Duration maxRetryDelay;

  /// Backoff multiplier for exponential retry delays.
  final double backoffMultiplier;

  /// Jitter percentage (0.0 to 1.0) to add randomness to retry delays.
  final double jitterPercent;

  /// Maximum number of retry attempts before marking task as dead.
  final int maxRetryAttempts;

  /// Adaptive polling intervals

  /// Polling interval when app is in foreground.
  final Duration foregroundPollInterval;

  /// Polling interval when app is in background.
  final Duration backgroundPollInterval;

  /// Minimum retry delay to prevent excessive CPU usage.
  final Duration minRetryDelay;

  /// Whether to record HTTP request bodies in logs/debugging.
  ///  Defaults to false.
  final bool recordRequestBody;

  /// Whether to record HTTP response bodies in logs/debugging.
  ///  Defaults to false.
  final bool recordResponseBody;

  /// Whether to record HTTP request headers in logs/debugging.
  ///  Defaults to false.
  final bool recordRequestHeaders;

  /// Whether to record HTTP response headers in logs/debugging.
  ///  Defaults to false.
  final bool recordResponseHeaders;

  /// Queue capacity management timeouts

  /// Timeout for foreground queue when waiting for capacity.
  /// Defaults to 10 seconds for critical user operations.
  final Duration foregroundQueueCapacityTimeout;

  /// Timeout for load queue when waiting for capacity.
  /// Defaults to 5 seconds for UI-related operations.
  final Duration loadQueueCapacityTimeout;

  /// Timeout for background queue when waiting for capacity.
  /// Defaults to 2 seconds for background operations.
  final Duration backgroundQueueCapacityTimeout;

  /// Interval for checking queue capacity during wait.
  /// Defaults to 100 milliseconds.
  final Duration queueCapacityCheckInterval;

  /// Maximum queue capacity for foreground operations.
  /// Defaults to 50 to prevent memory issues.
  final int maxForegroundQueueCapacity;

  /// Maximum queue capacity for load operations.
  /// Defaults to 50 to prevent memory issues.
  final int maxLoadQueueCapacity;

  /// Maximum queue capacity for background operations.
  /// Defaults to 50 to prevent memory issues.
  final int maxBackgroundQueueCapacity;

  /// Maximum network timeout for HTTP requests.
  final dynamic maximumNetworkTimeout;

  /// Creates a new [SynquillStorageConfig].
  const SynquillStorageConfig({
    this.dio,
    this.keepConnectionAlive = true,
    this.foregroundQueueConcurrency = 1,
    this.backgroundQueueConcurrency = 2,
    this.defaultSavePolicy = DataSavePolicy.localFirst,
    this.defaultLoadPolicy = DataLoadPolicy.localThenRemote,
    this.initialRetryDelay = const Duration(seconds: 2),
    this.maxRetryDelay = const Duration(minutes: 5),
    this.backoffMultiplier = 2.0,
    this.jitterPercent = 0.2, // ±20% jitter
    this.maxRetryAttempts = 50,
    this.foregroundPollInterval = const Duration(seconds: 5),
    this.backgroundPollInterval = const Duration(minutes: 5),
    this.minRetryDelay = const Duration(seconds: 1),
    this.recordRequestBody = false,
    this.recordResponseBody = false,
    this.recordRequestHeaders = false,
    this.recordResponseHeaders = false,
    this.foregroundQueueCapacityTimeout = const Duration(seconds: 10),
    this.loadQueueCapacityTimeout = const Duration(seconds: 5),
    this.backgroundQueueCapacityTimeout = const Duration(seconds: 2),
    this.queueCapacityCheckInterval = const Duration(milliseconds: 100),
    this.maximumNetworkTimeout = const Duration(seconds: 20),
    this.maxForegroundQueueCapacity = 50,
    this.maxLoadQueueCapacity = 50,
    this.maxBackgroundQueueCapacity = 50,
  });
}

/// Main class for interacting with the synced data storage.
///
/// This class must be initialized before use by calling [SynquillStorage.init].
class SynquillStorage {
  static SynquillStorage? _instance;
  static SynquillStorageConfig? _config;
  static GeneratedDatabase? _database;
  static Logger? _logger;
  static StreamSubscription<bool>? _connectivitySubscription;
  static bool? _lastConnectivityStatus;
  static Future<bool> Function()? _connectivityChecker;
  static RequestQueueManager? _queueManager;
  static RetryExecutor? _retryExecutor;
  static DependencyResolver? _dependencyResolver;
  static BackgroundSyncManager? _backgroundSyncManager;
  static SyncQueueDao? _syncQueueDao;

  /// Default logger implementation that writes to developer.log.
  static Logger get _defaultLogger => Logger('SynquillStorage')
    ..onRecord.listen((record) {
      developer.log(
        record.message,
        time: DateTime.now(),
        name: record.loggerName,
        level: record.level.value,
        error: record.error,
        stackTrace: record.stackTrace,
      );
    });

  /// Private constructor.
  SynquillStorage._();

  /// Returns the singleton instance of [SynquillStorage].
  ///
  /// Throws [StateError] if [init] has not been called.
  static SynquillStorage get instance {
    if (_instance == null) {
      throw StateError(
        'SynquillStorage has not been initialized. '
        'Call SynquillStorage.init() first.',
      );
    }
    return _instance!;
  }

  /// Returns the global configuration.
  ///
  /// Returns null if [init] has not been called or no config was provided.
  static SynquillStorageConfig? get config => _config;

  /// Returns the global database instance.
  ///
  /// Throws [StateError] if [init] has not been called.
  static GeneratedDatabase get database {
    if (_database == null) {
      throw StateError(
        'SynquillStorage has not been initialized. '
        'Call SynquillStorage.init() first.',
      );
    }
    return _database!;
  }

  /// Returns the global logger instance.
  ///
  /// Throws [StateError] if [init] has not been called.
  static Logger get logger {
    if (_database == null) {
      throw StateError(
        'SynquillStorage has not been initialized. '
        'Call SynquillStorage.init() first.',
      );
    }
    return _logger!;
  }

  /// Returns the global queue manager instance.
  ///
  /// Throws [StateError] if [init] has not been called.
  static RequestQueueManager get queueManager {
    if (_queueManager == null) {
      throw StateError(
        'SynquillStorage has not been initialized. '
        'Call SynquillStorage.init() first.',
      );
    }
    return _queueManager!;
  }

  /// Returns the global retry executor instance.
  ///
  /// Throws [StateError] if [init] has not been called.
  static RetryExecutor get retryExecutor {
    if (_retryExecutor == null) {
      throw StateError(
        'SynquillStorage has not been initialized. '
        'Call SynquillStorage.init() first.',
      );
    }
    return _retryExecutor!;
  }

  /// Returns the global dependency resolver instance.
  ///
  /// Throws [StateError] if [init] has not been called.
  static DependencyResolver get dependencyResolver {
    if (_dependencyResolver == null) {
      throw StateError(
        'SynquillStorage has not been initialized. '
        'Call SynquillStorage.init() first.',
      );
    }
    return _dependencyResolver!;
  }

  /// Returns the global background sync manager instance.
  ///
  /// Throws [StateError] if [init] has not been called.
  static BackgroundSyncManager get backgroundSyncManager {
    if (_instance == null) {
      throw StateError(
        'SynquillStorage has not been initialized. '
        'Call SynquillStorage.init() first.',
      );
    }
    return _backgroundSyncManager!;
  }

  /// Returns the global sync queue DAO instance.
  ///
  /// Throws [StateError] if [init] has not been called.
  static SyncQueueDao get syncQueueDao {
    if (_syncQueueDao == null) {
      throw StateError(
        'SynquillStorage has not been initialized. '
        'Call SynquillStorage.init() first.',
      );
    }
    return _syncQueueDao!;
  }

  /// Checks if the device currently has an internet connection.
  ///
  /// Returns true if internet connection is available, false otherwise.
  ///
  /// Uses the connectivity checker function if provided, otherwise returns
  /// the last known status from the connectivity stream, or true if neither
  /// is available.
  ///
  /// If [init] has not been called, returns false.
  static Future<bool> get isConnected async {
    if (_instance == null) {
      return false;
    }

    // Use connectivity checker function if provided
    if (_connectivityChecker != null) {
      try {
        return await _connectivityChecker!();
      } catch (e) {
        _logger?.warning('Connectivity checker function failed: $e');
        // Fall back to last known status
      }
    }

    // Return last known status from stream, or true if no stream was provided
    return _lastConnectivityStatus ?? true;
  }

  /// Initializes the synced storage system.
  ///
  /// This method must be called once before any other operations.
  ///
  /// - [database]: The Drift database instance to use for local storage.
  /// - [config]: Optional configuration for the storage system.
  /// - [logger]: Optional custom logger implementation.
  /// - [initializeFn]: Optional function to call after database setup.
  ///   This should typically be the generated
  ///   `initializeSynquillStorage` function.
  /// - [connectivityStream]: Optional stream that emits connectivity status.
  ///   When provided, the system will listen to this stream and handle
  ///   connectivity changes automatically.
  /// - [connectivityChecker]: Optional function to check current connectivity.
  ///   Used by the [isConnected] getter when available.
  /// - [enableInternetMonitoring]: Whether to enable internet connection
  ///   monitoring. Defaults to true. Can be set to false for testing.
  static Future<void> init({
    required GeneratedDatabase database,
    SynquillStorageConfig? config,
    Logger? logger,
    void Function(GeneratedDatabase)? initializeFn,
    Stream<bool>? connectivityStream,
    Future<bool> Function()? connectivityChecker,
    bool enableInternetMonitoring = true,
  }) async {
    if (_instance != null) {
      _logger?.info('SynquillStorage already initialized');
      return;
    }

    // Create the instance and store config
    _createInstance(database, config ?? const SynquillStorageConfig(), logger);

    // Set up database provider for repository system
    _initializeDatabase(initializeFn);

    // Initialize request queue system
    _initializeCoreSystems();

    // Initialize background sync manager
    await _initializeBackgroundSync();

    // Setup connectivity monitoring
    _initializeConnectivity(
      connectivityStream,
      connectivityChecker,
      enableInternetMonitoring,
    );

    enableForegroundMode();

    _logger!.info('SynquillStorage initialization complete');
  }

  /// Completely obliterates all local storage data.
  ///
  /// This method is destructive and irreversible. It will:
  /// - Clear all request queues (foreground, load, background)
  /// - Remove all sync queue tasks and data
  /// - Clear all cached repository instances
  /// - Truncate all local database tables for all repositories
  /// - Reset background sync state and timers
  ///
  /// This is intended for scenarios like user logout, data reset,
  /// or when you need to completely start fresh with local storage.
  ///
  /// ⚠️ **WARNING**: This operation cannot be undone. All local data
  /// will be permanently lost.
  ///
  /// The method preserves the SynquillStorage initialization state,
  /// so the system remains functional after calling this method.
  ///
  /// Throws [StateError] if [SynquillStorage] has not been initialized.
  ///
  /// Example:
  /// ```dart
  /// // Complete data reset (e.g., user logout)
  /// await SynquillStorage.instance.obliterateLocalStorage();
  /// ```
  Future<void> obliterateLocalStorage() async {
    if (_instance == null) {
      throw StateError(
        'SynquillStorage has not been initialized. '
        'Call SynquillStorage.init() first.',
      );
    }

    _logger!.warning('Starting obliteration of all local storage data');

    try {
      // 1. Clear all request queues to prevent any pending operations
      _logger!.info('Clearing all request queues');
      try {
        await _queueManager?.clearQueuesOnDisconnect();
      } catch (e) {
        if (e is! QueueCancelledException) {
          _logger!.warning('Unexpected error while clearing queues: $e');
          rethrow;
        }
        // QueueCancelledException is expected during queue disposal
        _logger!.info('Request queues cleared (tasks cancelled)');
      }

      // 2. Reset background sync manager to stop any running sync operations
      _logger!.info('Resetting background sync manager');
      await BackgroundSyncManager.reset();

      // 3. Clear all sync queue data from the database
      _logger!.info('Clearing sync queue data');
      await _clearSyncQueueData();

      // 4. Truncate local storage in all registered repositories
      _logger!.info('Truncating local storage for all repositories');
      await _truncateAllRepositoryData();

      // 5. Clear all cached repository instances (but preserve registrations)
      _logger!.info('Clearing cached repository instances');
      SynquillRepositoryProvider.clearInstances();

      // 6. Re-initialize background sync manager to ensure clean state
      _logger!.info('Re-initializing background sync manager');
      await _initializeBackgroundSync();

      _logger!.warning('Local storage obliteration completed successfully');
    } catch (e, stackTrace) {
      _logger!.severe(
        'Error during local storage obliteration: $e',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Clears all sync queue data from the database.
  static Future<void> _clearSyncQueueData() async {
    try {
      // Get all sync tasks
      final allTasks = await _syncQueueDao!.getAllItems();

      // Delete each task
      for (final task in allTasks) {
        await _syncQueueDao!.deleteTask(task['id'] as int);
      }

      _logger!.info('Cleared ${allTasks.length} sync queue tasks');
    } catch (e) {
      _logger!.warning('Error clearing sync queue data: $e');
      // Continue execution - this is not critical enough to stop obliteration
    }
  }

  /// Truncates local storage data for all registered repositories.
  static Future<void> _truncateAllRepositoryData() async {
    try {
      // Get all registered repository type names using the public API
      final repositoryTypeNames =
          SynquillRepositoryProvider.getAllRegisteredTypeNames();

      _logger!.info(
        'Found ${repositoryTypeNames.length} registered repository types',
      );

      // Truncate local storage for each repository
      for (final typeName in repositoryTypeNames) {
        try {
          final repository = SynquillRepositoryProvider.getByTypeName(typeName);
          if (repository != null) {
            await repository.truncateLocalStorage();
            _logger!.fine('Truncated local storage for repository: $typeName');
          } else {
            _logger!.warning('Repository not found for type: $typeName');
          }
        } catch (e) {
          _logger!.warning('Error truncating storage for $typeName: $e');
          // Continue with other repositories even if one fails
        }
      }

      _logger!.info('Completed truncation for all repositories');
    } catch (e) {
      _logger!.warning('Error during repository data truncation: $e');
      // Continue execution - this is not critical enough to stop obliteration
    }
  }

  /// Resets the singleton instance and configuration.
  ///
  /// This method is primarily intended for testing purposes.
  /// After calling this method, [init] must be called again before using
  /// the storage system.
  static Future<void> reset() async {
    // Stop retry executor first to prevent new tasks
    _retryExecutor?.stop();

    // Reset background sync manager
    await BackgroundSyncManager.reset();

    // Cancel connectivity subscription before reset
    await _connectivitySubscription?.cancel();

    await _queueManager?.joinAll();

    await _queueManager?.dispose();

    await _database?.close();

    _instance = null;
    _config = null;
    _database = null;
    _logger = null;
    _connectivitySubscription = null;
    _lastConnectivityStatus = null;
    _connectivityChecker = null;
    _queueManager = null;
    _retryExecutor = null;
    _dependencyResolver = null;
    _backgroundSyncManager = null;
    _syncQueueDao = null;
    // Clear any cached repository instances
    SynquillRepositoryProvider.reset();
  }

  /// Closes the synced storage system and releases all resources.
  ///
  /// This method resets the singleton instance, closes the database,
  /// and cancels connectivity monitoring. After calling this method,
  /// [init] must be called again before using the storage system.
  static Future<void> close() async {
    await reset();
  }

  /// Sets the configuration for testing purposes without full initialization.
  ///
  /// This method is primarily intended for testing purposes.
  static void setConfigForTesting(SynquillStorageConfig config) {
    _config = config;
  }

  /// Handles connectivity changes to manage queue state.
  static void _handleConnectivityChange(
    bool? previousStatus,
    bool currentStatus,
  ) {
    // Handle transition to disconnected
    if (currentStatus == false && previousStatus == true) {
      _logger!.info('Connection lost - clearing request queues');
      _queueManager?.clearQueuesOnDisconnect();
    }

    // Handle transition to connected
    if (currentStatus == true && previousStatus == false) {
      _logger!.info('Connection restored - restoring queue processing');
      _queueManager?.restoreQueuesOnConnect();
    }
  }

  /// Retrieves a repository instance for the given model type.
  ///
  /// This method provides a convenient way to get repository instances
  /// using the global [SynquillRepositoryProvider]. The method returns the
  /// concrete repository type (e.g., UserRepository) rather than the base type.
  ///
  /// Type parameter [T] must extend [SynquillDataModel] and represents the
  /// model type for which to retrieve the repository.
  ///
  /// Throws [StateError] if [SynquillStorage] has not been initialized.
  /// Throws [Exception] if no factory is registered for the given model type.
  ///
  /// Example:
  /// ```dart
  /// // Get repository for a specific model type - returns UserRepository
  /// final userRepo = SynquillStorage.instance.getRepository<User>();
  /// final user = await userRepo.findOne('user_id');
  /// ```
  dynamic getRepository<T extends SynquillDataModel<T>>() {
    if (_instance == null) {
      throw StateError(
        'SynquillStorage has not been initialized. '
        'Call SynquillStorage.init() first.',
      );
    }

    return SynquillRepositoryProvider.get<T>();
  }

  /// Retrieves a repository instance by model type string name.
  ///
  /// This method allows lookup of repositories when only the string model type
  /// name is known (e.g., from sync queue operations or runtime lookups).
  ///
  /// - [modelTypeName]: The string name of the model type
  ///  (e.g., 'User', 'Todo')
  ///
  /// Returns the repository instance for the given model type, or null if no
  /// repository is registered for that type.
  ///
  /// Throws [StateError] if [SynquillStorage] has not been initialized.
  ///
  /// Example:
  /// ```dart
  /// // Get repository by string model name
  /// final userRepo = SynquillStorage.instance.getRepositoryByName('User');
  /// if (userRepo != null) {
  ///   // Use the repository
  /// }
  /// ```
  SynquillRepositoryBase<SynquillDataModel<dynamic>>? getRepositoryByName(
    String modelTypeName,
  ) {
    if (_instance == null) {
      throw StateError(
        'SynquillStorage has not been initialized. '
        'Call SynquillStorage.init() first.',
      );
    }

    return SynquillRepositoryProvider.getByTypeName(modelTypeName);
  }

  /// Triggers background sync tasks to be processed immediately.
  ///
  /// This method is used to manually trigger the processing of pending
  /// sync queue items, typically from a background task or isolate.
  ///
  /// It will process all due tasks in the sync queue using the retry executor.
  ///
  /// Throws [StateError] if [SynquillStorage] has not been initialized.
  ///
  /// Example:
  /// ```dart
  /// // Trigger background sync processing
  /// await SynquillStorage.instance.processBackgroundSyncTasks();
  /// ```
  Future<void> processBackgroundSyncTasks() async {
    if (_instance == null) {
      throw StateError(
        'SynquillStorage has not been initialized. '
        'Call SynquillStorage.init() first.',
      );
    }

    await _backgroundSyncManager!.processBackgroundSyncTasks();
  }

  /// Static method to trigger background sync tasks without an instance.
  ///
  /// This is useful for background isolates where you might not have
  /// easy access to the instance but need to trigger sync processing.
  ///
  /// Throws [StateError] if [SynquillStorage] has not been initialized.
  ///
  /// Example:
  /// ```dart
  /// // Trigger background sync from background isolate
  /// await SynquillStorage.processBackgroundSync();
  /// ```
  @pragma('vm:entry-point')
  static Future<void> processBackgroundSync() async {
    if (_instance == null) {
      throw StateError(
        'SynquillStorage has not been initialized. '
        'Call SynquillStorage.init() first.',
      );
    }

    await _instance!.processBackgroundSyncTasks();
  }

  /// Initializes SynquillStorage in a background isolate.
  ///
  ///
  /// This method is designed to be called from background isolates to set up
  /// the minimal SynquillStorage infrastructure needed for sync operations.
  ///
  /// It's a lightweight initialization that doesn't set up UI-related features
  /// like connectivity monitoring, but provides access to the database,
  /// retry executor, and sync queue operations.
  ///
  /// [database] The database instance to use in the background isolate.
  /// [config] Optional configuration for the storage system.
  /// [logger] Optional logger for background operations.
  /// [initializeFn] Optional initialization function for repository setup.
  ///
  /// Example usage in a background isolate:
  /// ```dart
  /// // In WorkManager or BGTaskScheduler callback
  /// await SynquillStorage.initForBackgroundIsolate(
  ///   database: myDatabase,
  ///   config: SynquillStorageConfig(),
  ///   initializeFn: initializeSynquillStorage,
  /// );
  ///
  /// // Now you can trigger sync
  /// await SynquillStorage.processBackgroundSync();
  /// ```
  @pragma('vm:entry-point')
  static Future<void> initForBackgroundIsolate({
    required GeneratedDatabase database,
    SynquillStorageConfig? config,
    Logger? logger,
    void Function(GeneratedDatabase)? initializeFn,
  }) async {
    // Initialize SynquillStorage without connectivity monitoring
    // for background use
    await init(
      database: database,
      config: config,
      logger: logger,
      initializeFn: initializeFn,
      enableInternetMonitoring: false,
    );

    final backgroundLogger = logger ?? Logger('BackgroundSyncIsolate');
    backgroundLogger.info('SynquillStorage initialized for background isolate');
  }

  /// Switches the retry executor to background mode for battery optimization.
  ///
  /// This method should be called when the app enters background mode
  /// to reduce polling frequency and conserve battery.
  ///
  /// Throws [StateError] if [SynquillStorage] has not been initialized.
  @pragma('vm:entry-point')
  static void enableBackgroundMode() {
    if (_instance == null) {
      throw StateError(
        'SynquillStorage has not been initialized. '
        'Call SynquillStorage.init() first.',
      );
    }

    _backgroundSyncManager!.enableBackgroundMode();
  }

  /// Switches the retry executor to foreground mode for active use.
  ///
  /// This method should be called when the app returns to foreground
  /// to increase polling frequency for better responsiveness.
  ///
  /// Throws [StateError] if [SynquillStorage] has not been initialized.
  @pragma('vm:entry-point')
  static void enableForegroundMode({bool forceSync = false}) {
    if (_instance == null) {
      throw StateError(
        'SynquillStorage has not been initialized. '
        'Call SynquillStorage.init() first.',
      );
    }
    _backgroundSyncManager!.enableForegroundMode(forceSync: forceSync);
  }

  /// Helper: create instance and set core properties.
  static void _createInstance(
    GeneratedDatabase database,
    SynquillStorageConfig config,
    Logger? logger,
  ) {
    _instance = SynquillStorage._();
    _config = config;
    _database = database;
    _logger = logger ?? _defaultLogger;
    _logger!.info('Database instance set');
  }

  /// Helper: initialize database and repository system.
  static void _initializeDatabase(
    void Function(GeneratedDatabase)? initializeFn,
  ) {
    DatabaseProvider.setInstance(_database!);
    if (initializeFn != null) {
      initializeFn(_database!);
      _logger!.info('Repository system initialized');
    }
  }

  /// Helper: initialize request queue, dependency resolver, and retry executor.
  static void _initializeCoreSystems() {
    _queueManager ??= RequestQueueManager(config: _config);
    _logger!.info('Request queue manager initialized');

    _dependencyResolver ??= DependencyResolver();
    _logger!.info('Dependency resolver initialized');

    _syncQueueDao ??= SyncQueueDao(_database!);
    _logger!.info('Sync queue DAO initialized');

    _retryExecutor ??= RetryExecutor(_database!, _queueManager!);
    _retryExecutor!.start();
    _logger!.info('Retry executor started');
  }

  /// Helper: initialize background sync manager.
  static Future<void> _initializeBackgroundSync() async {
    _backgroundSyncManager = BackgroundSyncManager.instance;
    await BackgroundSyncManager.initialize();
    _logger!.info('Background sync manager initialized');
  }

  /// Helper: setup connectivity monitoring based on provided parameters.
  static void _initializeConnectivity(
    Stream<bool>? connectivityStream,
    Future<bool> Function()? connectivityChecker,
    bool enableInternetMonitoring,
  ) {
    _connectivityChecker = connectivityChecker;
    if (enableInternetMonitoring && connectivityStream != null) {
      _connectivitySubscription = connectivityStream.listen(
        (isConnected) {
          final previousStatus = _lastConnectivityStatus;
          _lastConnectivityStatus = isConnected;
          _handleConnectivityChange(previousStatus, isConnected);
        },
        onError: (error) {
          _logger!.warning('Connectivity stream error: $error');
        },
      );
      _logger!.info('Connectivity monitoring enabled with stream');
    } else if (enableInternetMonitoring && connectivityChecker != null) {
      _logger!.info(
        'Connectivity monitoring enabled with checker function only',
      );
    } else {
      _logger!.info('Connectivity monitoring disabled');
    }
  }
}
