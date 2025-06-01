part of synquill;

/// Manages retry logic for sync queue operations with exponential backoff.
///
/// The RetryExecutor polls the sync_queue table for due tasks and manages
/// retry scheduling with exponential backoff and jitter.
///
/// This implements the background sync component from the technical
/// specification.
class RetryExecutor {
  final GeneratedDatabase _db;
  final RequestQueueManager _queueManager;
  late final SyncQueueDao _syncQueueDao;
  late final Logger _log;

  Timer? _pollTimer;
  bool _isRunning = false;
  bool _isBackgroundMode = false;

  /// Cached regex for network error detection (performance optimization)
  static final RegExp _httpServerErrorPattern = RegExp(r'5\d\d');

  /// Network error keywords for faster lookup
  static const Set<String> _networkErrorKeywords = {
    'timeout',
    'connection',
    'network',
    'socket',
    'refused',
    'unreachable',
    'dns',
    'resolve',
  };

  /// Creates a new RetryExecutor.
  ///
  /// [db] The database instance for accessing sync queue.
  /// [queueManager] The queue manager for enqueueing retry tasks.
  RetryExecutor(this._db, this._queueManager) {
    _syncQueueDao = SyncQueueDao(_db);
    _log = Logger('RetryExecutor');
  }

  /// Starts the retry executor polling.
  ///
  /// [backgroundMode] If true, uses longer polling intervals
  /// to conserve battery.
  void start({bool backgroundMode = false}) {
    if (_isRunning) {
      _log.warning('RetryExecutor is already running');
      return;
    }

    _isRunning = true;
    _isBackgroundMode = backgroundMode;
    final config = SynquillStorage.config!;
    final pollInterval =
        backgroundMode
            ? config.backgroundPollInterval
            : config.foregroundPollInterval;

    final mode = backgroundMode ? 'background' : 'foreground';
    _log.info(
      'Starting RetryExecutor in $mode mode '
      'with ${pollInterval.inSeconds}s poll interval',
    );

    // Process immediately on start
    _processDueTasks();

    // Set up periodic polling with adaptive interval
    _pollTimer = Timer.periodic(pollInterval, (_) => _processDueTasks());
  }

  /// Switches between foreground and background polling modes.
  void setBackgroundMode(bool backgroundMode) {
    if (_isBackgroundMode == backgroundMode) return;

    _log.info(
      'Switching to ${backgroundMode ? 'background' : 'foreground'} mode',
    );

    _isBackgroundMode = backgroundMode;

    // Restart with new polling interval if running
    if (_isRunning) {
      _restartWithNewInterval();
    }
  }

  /// Restarts the polling timer with the current background mode interval.
  void _restartWithNewInterval() {
    _pollTimer?.cancel();

    final config = SynquillStorage.config!;
    final pollInterval =
        _isBackgroundMode
            ? config.backgroundPollInterval
            : config.foregroundPollInterval;

    _pollTimer = Timer.periodic(pollInterval, (_) => _processDueTasks());
  }

  /// Stops the retry executor.
  void stop() {
    if (!_isRunning) return;

    _isRunning = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _log.info('RetryExecutor stopped');
  }

  /// Processes all tasks that are due for retry.
  Future<void> _processDueTasks({bool forceSync = false}) async {
    if (!_isRunning) return;

    try {
      // Check connectivity before processing any tasks
      // Skip processing if offline (unless forceSync is specifically 
      // requesting offline processing)
      final isConnected = await SynquillStorage.isConnected;
      if (!isConnected && !forceSync) {
        _log.fine('Device is offline, skipping sync queue processing');
        return;
      }

      final dueTasks = await _fetchDueTasks(forceSync);

      if (dueTasks.isEmpty) {
        _log.fine('No due tasks found in sync queue');
        return;
      }

      _log.info('Found ${dueTasks.length} due tasks in sync queue');

      final prioritizedTasks = _prioritizeAndOrderTasks(dueTasks);
      await _processTaskList(prioritizedTasks);
    } catch (e, stackTrace) {
      _log.severe('Error processing due tasks', e, stackTrace);
    }
  }

  /// Fetches due tasks based on force sync mode and connectivity.
  Future<List<Map<String, dynamic>>> _fetchDueTasks(bool forceSync) async {
    if (forceSync) {
      final isConnected = await SynquillStorage.isConnected;
      if (isConnected) {
        // When forceSync is true and connectivity is available,
        // process ALL pending tasks immediately, ignoring retry delays
        _log.info(
          'Force sync enabled with connectivity - processing all pending tasks',
        );
        final allTasks = await _syncQueueDao.getAllItems();

        // Filter out only pending and processing tasks (not dead ones)
        return allTasks.where((task) {
          final status = task['status'] as String? ?? 'pending';
          return status != 'dead';
        }).toList();
      } else {
        // Force sync requested but no connectivity - return empty list
        _log.info(
          'Force sync requested but device is offline - no tasks to process',
        );
        return [];
      }
    } else {
      // Normal operation - only get due tasks
      // (connectivity was already checked in _processDueTasks)
      _log.fine('Polling sync queue for due tasks');
      return await _syncQueueDao.getDueTasks();
    }
  }

  /// Prioritizes tasks by network errors and applies dependency ordering.
  List<Map<String, dynamic>> _prioritizeAndOrderTasks(
    List<Map<String, dynamic>> dueTasks,
  ) {
    // Separate network error tasks for immediate retry
    final networkErrorTasks =
        dueTasks.where((task) => _hasNetworkError(task)).toList();

    final otherTasks =
        dueTasks.where((task) => !_hasNetworkError(task)).toList();

    // Apply dependency ordering to both groups using DependencyResolver
    final orderedNetworkErrorTasks =
        DependencyResolver.sortTasksByDependencyOrder(networkErrorTasks);
    final orderedOtherTasks = DependencyResolver.sortTasksByDependencyOrder(
      otherTasks,
    );

    _logPrioritizationInfo(networkErrorTasks.length, otherTasks.length);

    // Process network error tasks first (with dependency ordering), then others
    return [...orderedNetworkErrorTasks, ...orderedOtherTasks];
  }

  /// Checks if a task has a network-related error.
  bool _hasNetworkError(Map<String, dynamic> task) {
    final lastError = task['last_error'] as String?;
    return lastError != null && _isNetworkError(lastError);
  }

  /// Logs prioritization information for debugging.
  void _logPrioritizationInfo(int networkErrorCount, int otherTasksCount) {
    if (networkErrorCount > 0) {
      _log.info(
        'Processing $networkErrorCount network error tasks '
        'with dependency ordering',
      );
    }
    if (otherTasksCount > 0) {
      _log.info(
        'Processing $otherTasksCount other tasks '
        'with dependency ordering',
      );
    }
  }

  /// Processes a list of prioritized tasks sequentially.
  Future<void> _processTaskList(List<Map<String, dynamic>> tasks) async {
    for (final taskData in tasks) {
      // Double-check connectivity before processing each task
      // This prevents processing if connection is lost during task list 
      // execution
      final isConnected = await SynquillStorage.isConnected;
      if (!isConnected) {
        _log.info(
          'Lost connectivity during task processing - stopping task execution',
        );
        break;
      }
      
      await _processQueueTask(taskData);
    }
  }

  /// Processes a single sync queue task.
  Future<void> _processQueueTask(Map<String, dynamic> taskData) async {
    final taskId = taskData['id'] as int;
    final modelType = taskData['model_type'] as String;
    final operation = taskData['op'] as String;
    final attemptCount = taskData['attempt_count'] as int;
    final idempotencyKey = taskData['idempotency_key'] as String?;

    _log.fine('Processing sync queue task $taskId: $operation $modelType');

    try {
      // Mark as processing
      await _syncQueueDao.updateItem(id: taskId, status: 'processing');

      // Create NetworkTask for this sync operation
      final networkTask = await _createNetworkTaskFromQueue(
        taskData,
        idempotencyKey ?? '${cuid()}-$attemptCount',
      );

      // Determine which queue to use based on operation
      final queueType = _getQueueTypeForOperation(operation);

      // Enqueue the network task
      await _queueManager.enqueueTask(networkTask, queueType: queueType);

      // Wait for task completion
      try {
        await networkTask.future;

        // Success - delete from sync queue
        await _syncQueueDao.deleteTask(taskId);
        _log.info('Successfully synced task $taskId: $operation $modelType');
      } catch (networkError, networkStackTrace) {
        // Check if model no longer exists locally
        if (networkError is ModelNoLongerExistsException) {
          // Model was deleted locally - remove task from sync queue
          await _syncQueueDao.deleteTask(taskId);
          _log.info(
            'Deleted sync queue task $taskId: model no longer exists locally',
          );
        } else if (networkError is DoubleFallbackException) {
          // Double 404 failure - task was already updated to remain due
          // No additional retry scheduling needed
          _log.info(
            'Handling DoubleFallbackException for task $taskId, '
            'task should remain available for manual retry',
          );
        } else {
          // Network operation failed - schedule retry
          await _scheduleRetry(taskId, attemptCount, networkError.toString());
          _log.warning(
            'Network operation failed for task $taskId, scheduled retry',
            networkError,
            networkStackTrace,
          );
        }
      }
    } catch (e, stackTrace) {
      if (e is DoubleFallbackException) {
        // Double 404 failure - task was already updated to remain due
        // No additional retry scheduling needed
        _log.info(
          'Double fallback failure for task $taskId, '
          'task remains available for manual retry',
        );
      } else {
        _log.severe('Error processing sync queue task $taskId', e, stackTrace);
        // Mark task as failed for retry
        await _scheduleRetry(taskId, attemptCount, e.toString());
      }
    }
  }

  /// Creates a NetworkTask from sync queue data.
  Future<NetworkTask> _createNetworkTaskFromQueue(
    Map<String, dynamic> taskData,
    String idempotencyKey,
  ) async {
    final modelType = taskData['model_type'] as String;
    final payload = taskData['payload'] as String;
    final operation = taskData['op'] as String;
    final taskId = taskData['id'] as int;

    // Parse optional JSON fields
    final headers = _parseJsonField<Map<String, String>>(
      taskData['headers'] as String?,
      'headers',
      (decoded) => (decoded as Map<String, dynamic>).cast<String, String>(),
    );

    final extra = _parseJsonField<Map<String, dynamic>>(
      taskData['extra'] as String?,
      'extra',
      (decoded) => decoded as Map<String, dynamic>,
    );

    // Parse the sync operation
    final syncOp = _parseSyncOperation(operation);

    // Parse model data from payload
    final modelData = _parseModelData(payload);
    final modelId = _extractModelId(modelData);

    return NetworkTask<void>(
      exec:
          () => _executeApiOperation(
            syncOp,
            modelType,
            modelData,
            headers,
            extra,
            taskId,
          ),
      idempotencyKey: idempotencyKey,
      operation: syncOp,
      modelType: modelType,
      modelId: modelId,
      taskName: 'SyncQueue-$taskId-${syncOp.name}',
    );
  }

  /// Generic helper for parsing JSON fields with error handling.
  T? _parseJsonField<T>(
    String? jsonString,
    String fieldName,
    T Function(dynamic) converter,
  ) {
    if (jsonString == null) return null;

    try {
      final decoded = convert.jsonDecode(jsonString);
      return converter(decoded);
    } catch (e) {
      _log.warning('Failed to parse $fieldName from sync queue: $e');
      return null;
    }
  }

  /// Parses sync operation from string with validation.
  SyncOperation _parseSyncOperation(String operation) {
    try {
      return SyncOperation.values.firstWhere((op) => op.name == operation);
    } catch (e) {
      throw ArgumentError('Unknown sync operation: $operation');
    }
  }

  /// Parses model data from JSON payload.
  Map<String, dynamic> _parseModelData(String payload) {
    try {
      return convert.jsonDecode(payload) as Map<String, dynamic>;
    } catch (e) {
      throw SynquillStorageException('Failed to parse task payload: $e');
    }
  }

  /// Extracts model ID from model data.
  String _extractModelId(Map<String, dynamic> modelData) {
    final modelId = modelData['id'] as String?;
    if (modelId == null) {
      throw SynquillStorageException('Model data missing ID');
    }
    return modelId;
  }

  /// Executes the actual API operation for a sync task.
  Future<void> _executeApiOperation(
    SyncOperation operation,
    String modelType,
    Map<String, dynamic> modelData,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
    int taskId,
  ) async {
    _log.info('Executing API operation: ${operation.name} for $modelType');

    try {
      final repository = _getRepository(modelType);
      await _performSyncOperation(
        operation,
        repository,
        modelData,
        headers,
        extra,
        taskId,
      );

      _log.info(
        'API operation ${operation.name} completed successfully for $modelType',
      );
    } catch (e, stackTrace) {
      _log.severe(
        'API operation ${operation.name} failed for $modelType: $e',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Gets repository for the specified model type.
  SynquillRepositoryBase<SynquillDataModel<dynamic>> _getRepository(
    String modelType,
  ) {
    final db = DatabaseProvider.instance;
    final repository = SynquillRepositoryProvider.getByTypeNameFrom(
      modelType,
      db,
    );

    if (repository == null) {
      throw SynquillStorageException(
        'No registered repository found for model type: $modelType',
      );
    }

    _log.fine('Found repository for $modelType: ${repository.runtimeType}');
    return repository;
  }

  /// Performs the sync operation based on the operation type.
  Future<void> _performSyncOperation(
    SyncOperation operation,
    SynquillRepositoryBase<SynquillDataModel<dynamic>> repository,
    Map<String, dynamic> modelData,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
    int taskId,
  ) async {
    switch (operation) {
      case SyncOperation.create:
        await _performCreateOperation(repository, modelData, headers, extra);
        break;

      case SyncOperation.update:
        await _performUpdateOperation(
          repository,
          modelData,
          headers,
          extra,
          taskId,
        );
        break;

      case SyncOperation.delete:
        await _performDeleteOperation(repository, modelData, headers, extra);
        break;
    }
  }

  /// Performs create operation with local existence check.
  Future<void> _performCreateOperation(
    SynquillRepositoryBase<SynquillDataModel<dynamic>> repository,
    Map<String, dynamic> modelData,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  ) async {
    // For create operations, check if model still exists locally
    final modelId = modelData['id'] as String;
    final existingModel = await repository.fetchFromLocal(modelId);

    if (existingModel == null) {
      _log.warning(
        'Model ${repository.runtimeType} $modelId no longer exists locally, '
        'skipping create sync operation',
      );

      // Throw a specific exception to indicate we should remove
      // this task from sync queue without retrying
      throw ModelNoLongerExistsException(
        'Model ${repository.runtimeType} $modelId was deleted locally '
        'before sync could complete',
      );
    }

    final modelObject = repository.apiAdapter.fromJson(modelData);
    await repository.apiAdapter.createOne(
      modelObject,
      headers: headers,
      extra: extra,
    );
  }

  /// Performs update operation with fallback to create on 404.
  Future<void> _performUpdateOperation(
    SynquillRepositoryBase<SynquillDataModel<dynamic>> repository,
    Map<String, dynamic> modelData,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
    int taskId,
  ) async {
    // For update operations, check if model still exists locally
    final modelId = modelData['id'] as String;
    final existingModel = await repository.fetchFromLocal(modelId);

    if (existingModel == null) {
      _log.warning(
        'Model ${repository.runtimeType} $modelId no longer exists locally, '
        'skipping update sync operation',
      );

      // Throw a specific exception to indicate we should remove
      // this task from sync queue without retrying
      throw ModelNoLongerExistsException(
        'Model ${repository.runtimeType} $modelId was deleted locally '
        'before sync could complete',
      );
    }

    try {
      final modelObject = repository.apiAdapter.fromJson(modelData);
      await repository.apiAdapter.updateOne(
        modelObject,
        headers: headers,
        extra: extra,
      );
    } on ApiExceptionNotFound catch (originalError) {
      await _handleUpdateNotFoundFallback(
        repository,
        modelData,
        headers,
        extra,
        taskId,
        originalError,
      );
    }
  }

  /// Handles update operation fallback when model is not found (404).
  Future<void> _handleUpdateNotFoundFallback(
    SynquillRepositoryBase<SynquillDataModel<dynamic>> repository,
    Map<String, dynamic> modelData,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
    int taskId,
    ApiExceptionNotFound originalError,
  ) async {
    final modelId = modelData['id'] as String;

    _log.info(
      'Update operation for ${repository.runtimeType} $modelId failed '
      'with 404, attempting create fallback',
    );

    try {
      final modelObject = repository.apiAdapter.fromJson(modelData);
      await repository.apiAdapter.createOne(
        modelObject,
        headers: headers,
        extra: extra,
      );

      // Update the sync queue entry to reflect the operation change
      await _syncQueueDao.updateItem(
        id: taskId,
        operation: 'create',
        lastError: null, // Clear any previous error
      );

      _log.info(
        'Successfully created ${repository.runtimeType} $modelId '
        'after update fallback',
      );
    } on ApiExceptionNotFound catch (createError) {
      await _handleDoubleFallbackFailure(
        taskId,
        originalError,
        createError,
        modelId,
      );
    }
  }

  /// Handles the case when both update and create operations fail with 404.
  Future<void> _handleDoubleFallbackFailure(
    int taskId,
    ApiExceptionNotFound originalError,
    ApiExceptionNotFound createError,
    String modelId,
  ) async {
    _log.severe(
      'Both update and create operations for model $modelId '
      'failed with 404. This indicates an API or URL '
      'configuration issue. Original update error: $originalError, '
      'Create error: $createError',
    );

    // For double-404 failures, update the task but don't schedule
    // exponential backoff since this is likely a configuration issue
    // that needs immediate attention
    await _syncQueueDao.updateItem(
      id: taskId,
      operation: 'update',
      nextRetryAt: null, // Keep immediately due for retry
      lastError:
          'Fallback failed: Both update and create '
          'returned 404. Update error: ${originalError.message}, '
          'Create error: ${createError.message}',
    );

    // Throw a special exception to avoid normal exponential backoff retry logic
    throw DoubleFallbackException(
      'Both update and create operations failed with 404 for model $modelId',
      originalError: originalError,
      createError: createError,
    );
  }

  /// Performs delete operation.
  Future<void> _performDeleteOperation(
    SynquillRepositoryBase<SynquillDataModel<dynamic>> repository,
    Map<String, dynamic> modelData,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  ) async {
    // For delete operations, we just need the ID
    // No need to check local existence - deletion should proceed
    final id = modelData['id'] as String;
    await repository.apiAdapter.deleteOne(id, headers: headers, extra: extra);
  }

  /// Determines which queue to use for a sync operation.
  QueueType _getQueueTypeForOperation(String operation) {
    // Background sync operations always use backgroundQueue
    return QueueType.background;
  }

  /// Schedules a retry for a failed task with exponential backoff.
  ///
  /// If the task has exceeded the maximum retry attempts, it will be marked
  /// as dead and removed from the sync queue.
  Future<void> _scheduleRetry(
    int taskId,
    int currentAttempt,
    String error,
  ) async {
    final nextAttempt = currentAttempt + 1;
    final config = SynquillStorage.config!;

    // Check if task has exceeded maximum retry attempts
    if (nextAttempt > config.maxRetryAttempts) {
      _log.warning(
        'Task $taskId has exceeded maximum retry attempts '
        '(${config.maxRetryAttempts}). Marking as dead',
      );

      // Mark task as dead and remove from sync queue
      await _markTaskAsDead(taskId, error);
      return;
    }

    final retryDelay = _calculateRetryDelay(nextAttempt);
    final nextRetryAt = DateTime.now().add(retryDelay);

    await _syncQueueDao.updateTaskRetry(
      taskId,
      nextRetryAt,
      nextAttempt,
      error,
    );

    _log.info(
      'Scheduled retry $nextAttempt/${config.maxRetryAttempts} for task $taskId '
      'at $nextRetryAt (delay: ${retryDelay.inSeconds}s)',
    );
  }

  /// Marks a task as dead and removes it from the sync queue.
  ///
  /// Dead tasks are those that have exceeded the maximum retry attempts
  /// and should no longer be processed.
  Future<void> _markTaskAsDead(int taskId, String lastError) async {
    try {
      // Log the dead task for debugging
      _log.severe('Marking task $taskId as dead. Last error: $lastError');

      // Remove the task from sync queue
      await _syncQueueDao.markTaskAsDead(taskId, lastError);

      _log.info('Dead task $taskId marked successfully');
    } catch (e, stackTrace) {
      _log.severe('Failed to mark task $taskId as dead', e, stackTrace);
    }
  }

  /// Calculates retry delay with exponential backoff and jitter.
  Duration _calculateRetryDelay(int attemptNumber) {
    final config = SynquillStorage.config!;

    // Calculate base delay: 2s, 4s, 8s, 16s, etc., up to max
    final baseDelayMs =
        (config.initialRetryDelay.inMilliseconds *
                math.pow(config.backoffMultiplier, attemptNumber - 1))
            .toInt();

    final cappedDelayMs = math.min(
      baseDelayMs,
      config.maxRetryDelay.inMilliseconds,
    );

    // Add jitter (±20%) for better distribution
    final jitterMs = (cappedDelayMs * config.jitterPercent).toInt();
    final random = math.Random();
    final randomOffset = random.nextInt(jitterMs * 2) - jitterMs;

    final finalDelayMs = math.max(
      config.minRetryDelay.inMilliseconds,
      cappedDelayMs + randomOffset,
    );

    return Duration(milliseconds: finalDelayMs);
  }

  /// Manually triggers processing of due tasks.
  ///
  /// This method is used for:
  /// - Testing purposes
  /// - Connectivity restoration (immediate processing)
  /// - External triggers from background tasks
  Future<void> processDueTasksNow({bool forceSync = false}) async {
    _log.info('Processing due tasks immediately (triggered externally)');
    await _processDueTasks(forceSync: forceSync);
  }

  /// Checks if an error is network-related and should trigger immediate retry.
  ///
  /// Network errors include:
  /// - HTTP 5xx status codes
  /// - Connection timeouts
  /// - Network connectivity issues
  bool _isNetworkError(String errorMessage) {
    // Check for HTTP 5xx status codes using cached regex
    if (_httpServerErrorPattern.hasMatch(errorMessage)) return true;

    // Check for common network error keywords using Set.contains
    // for O(1) lookup performance
    final lowerError = errorMessage.toLowerCase();
    return _networkErrorKeywords.any((keyword) => lowerError.contains(keyword));
  }
}
