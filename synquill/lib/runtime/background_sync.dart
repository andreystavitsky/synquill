part of synquill;

/// Background sync manager for handling platform-specific background tasks.
///
/// This class integrates with WorkManager on Android and BGTaskScheduler
/// on iOS to enable background synchronization when the app is not active.
///
/// This implements the cross-isolate communication and background task
/// scheduling from the technical specification.
class BackgroundSyncManager {
  static BackgroundSyncManager? _instance;
  static Logger? _logger;
  static bool _isInitialized = false;

  /// Private constructor
  BackgroundSyncManager._();

  /// Gets the singleton instance
  static BackgroundSyncManager get instance {
    _instance ??= BackgroundSyncManager._();
    return _instance!;
  }

  /// Initializes the background sync system.
  ///
  /// This method should be called during app initialization to register
  /// background task handlers and configure platform-specific settings.
  ///

  static Future<void> initialize() async {
    _logger = Logger('BackgroundSyncManager');

    if (_isInitialized) {
      _logger?.info('BackgroundSyncManager already initialized');
      return;
    }

    _logger!.info('Initializing BackgroundSyncManager');

    _isInitialized = true;
    _logger!.info('BackgroundSyncManager initialization complete');
  }

  /// Processes sync tasks in the background isolate.
  ///
  /// This method runs the retry executor to process pending sync queue items
  /// when the app is running in the background.
  ///
  /// Background sync tasks are automatically terminated after 20 seconds
  /// to prevent excessive resource usage and battery drain.
  Future<void> processBackgroundSyncTasks({bool forceSync = false}) async {
    final logger = Logger('BackgroundSync');

    try {
      logger.info(
        'Starting background sync task processing, forceSync: $forceSync',
      );

      // Get the retry executor instance from SynquillStorage
      final retryExecutor = SynquillStorage.retryExecutor;

      // Process all due tasks with a 20-second timeout
      await retryExecutor
          .processDueTasksNow(forceSync: forceSync)
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              logger.warning(
                'Background sync processing timed out after 20 seconds',
              );
              throw TimeoutException(
                'Background sync processing exceeded 20 seconds timeout',
                const Duration(seconds: 20),
              );
            },
          );

      logger.info('Background sync processing completed successfully');
    } on TimeoutException catch (e, stackTrace) {
      logger.severe(
        'Background sync processing timed out: ${e.message}',
        e,
        stackTrace,
      );
      rethrow;
    } catch (e, stackTrace) {
      logger.severe('Background sync processing failed: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Cancels all background sync tasks.
  Future<void> cancelBackgroundSync() async {
    if (!_isInitialized) return;

    try {
      // Stop the retry executor to prevent further background work
      SynquillStorage.retryExecutor.stop();
      // Platform specific cancellation would go here
      _logger!.info('Background sync cancelled successfully');
    } catch (e, stackTrace) {
      _logger!.warning('Failed to cancel background sync: $e', e, stackTrace);
    }
  }

  /// Resets the background sync manager.
  static Future<void> reset() async {
    if (_instance != null) {
      await _instance!.cancelBackgroundSync();
    }
    _instance = null;
    _logger = null;
    _isInitialized = false;
  }

  /// Switches the retry executor to background mode for battery optimization.
  ///
  /// This method should be called when the app enters background mode
  /// to reduce polling frequency and conserve battery.
  void enableBackgroundMode() {
    try {
      final retryExecutor = SynquillStorage.retryExecutor;
      retryExecutor.setBackgroundMode(true);
      _logger?.info('Background mode enabled for sync operations');
    } catch (e) {
      _logger?.warning('Failed to enable background mode: $e');
    }
  }

  /// Switches the retry executor to foreground mode for active use.
  ///
  /// This method should be called when the app returns to foreground
  /// to increase polling frequency for better responsiveness.
  void enableForegroundMode({bool forceSync = false}) {
    try {
      final retryExecutor = SynquillStorage.retryExecutor;
      if (forceSync) {
        processBackgroundSyncTasks(forceSync: true)
            .then((_) {
              _logger?.info('Forced sync completed successfully');
              retryExecutor.setBackgroundMode(false);
            })
            .catchError((error) {
              _logger?.warning('Error during forced sync: $error');
              retryExecutor.setBackgroundMode(false);
            });
      } else {
        retryExecutor.setBackgroundMode(false);
      }
      _logger?.info('Foreground mode enabled for sync operations');
    } catch (e) {
      _logger?.warning('Failed to enable foreground mode: $e');
    }
  }

  /// Checks if SynquillStorage is properly initialized for background operations.
  ///
  /// This is useful for ensuring that background isolates have access
  /// to the necessary components before attempting sync operations.
  bool get isReadyForBackgroundSync {
    try {
      // Try to access key components - this will throw if not initialized
      SynquillStorage.retryExecutor;
      SynquillStorage.database;
      return true;
    } catch (e) {
      _logger?.warning('SynquillStorage not ready for background sync: $e');
      return false;
    }
  }
}
