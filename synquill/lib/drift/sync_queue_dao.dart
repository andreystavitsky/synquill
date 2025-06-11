part of synquill;

/// Data Access Object for managing sync queue items.
///
/// This DAO provides methods for querying and manipulating sync queue items
/// in the database. It works with any database that includes the
/// [SyncQueueItems] table.
///
/// Note: This is a base implementation that works without generated files.
/// Client applications may extend this with more specific generated methods.
class SyncQueueDao {
  /// The database instance.
  final GeneratedDatabase _db;

  /// Cache for table name to table mapping for performance optimization.
  /// Maps table name (e.g., 'users') to the corresponding Drift table.
  final Map<String, TableInfo<Table, dynamic>> _tableCache = {};

  /// Whether the table cache has been initialized.
  bool _cacheInitialized = false;

  /// Logger instance for this DAO
  static Logger get _log {
    try {
      return SynquillStorage.logger;
    } catch (_) {
      return Logger('SyncQueueDao');
    }
  }

  /// Creates a new [SyncQueueDao] instance.
  SyncQueueDao(this._db);

  /// Initializes the table cache by mapping table names to their tables.
  ///
  /// This method builds a cache of table names to Drift table instances
  /// for efficient table lookups during sync status updates.
  void _initializeTableCache() {
    if (_cacheInitialized) return;

    try {
      _tableCache.clear();

      for (final table in _db.allTables) {
        final tableName = table.actualTableName;

        // Skip sync_queue_items table as it's not a model table
        if (tableName == 'sync_queue_items') continue;

        // Cache table directly by its name
        _tableCache[tableName] = table;
      }

      _cacheInitialized = true;
      _log.fine(
        'Table cache initialized with ${_tableCache.length} model tables',
      );
    } catch (e, stack) {
      _log.warning('Failed to initialize table cache', e, stack);
      // Don't prevent DAO from working if cache initialization fails
    }
  }

  /// Gets a cached table for the given table name.
  ///
  /// Returns null if the table is not found or not cached.
  TableInfo<Table, dynamic>? _getCachedTable(String tableName) {
    if (!_cacheInitialized) {
      _initializeTableCache();
    }
    return _tableCache[tableName];
  }

  /// Retrieves all items from the sync queue.
  /// Returns raw data as `Map<String, dynamic>` since generated types
  /// are not available in the library.
  Future<List<Map<String, dynamic>>> getAllItems() async {
    final results = await _db
        .customSelect(
          'SELECT * FROM sync_queue_items ORDER BY created_at ASC',
        )
        .get();
    return results.map((row) => row.data).toList();
  }

  /// Gets items by model type.
  Future<List<Map<String, dynamic>>> getItemsByModelType(
    String modelType,
  ) async {
    final results = await _db.customSelect(
      'SELECT * FROM sync_queue_items WHERE model_type = ?',
      variables: [Variable.withString(modelType)],
    ).get();
    return results.map((row) => row.data).toList();
  }

  /// Retrieves all sync queue items that are due for processing.
  ///
  /// An item is considered due if its `next_retry_at` is null or in the past,
  /// and it has not been marked as dead.
  /// Items are ordered by their `created_at` timestamp.
  Future<List<Map<String, dynamic>>> getDueTasks() async {
    final results = await _db.customSelect(
      'SELECT * FROM sync_queue_items WHERE (next_retry_at IS NULL OR '
      'next_retry_at <= ?) AND status != ? ORDER BY created_at ASC',
      variables: [
        Variable.withDateTime(DateTime.now()),
        Variable.withString(
          'dead',
        ), // Assuming 'dead' is the status for dead tasks
      ],
    ).get();
    return results.map((row) => row.data).toList();
  }

  /// Retrieves a specific sync queue item by its [id].
  /// Returns `null` if no item with the given [id] is found.
  Future<Map<String, dynamic>?> getItemById(int id) async {
    final results = await _db.customSelect(
      'SELECT * FROM sync_queue_items WHERE id = ?',
      variables: [Variable.withInt(id)],
    ).get();
    return results.isNotEmpty ? results.first.data : null;
  }

  /// Inserts a new item into the sync queue.
  /// Returns the `id` of the newly inserted item.
  Future<int> insertItem({
    required String modelType,
    required String modelId,
    required String payload, // Should be JSON string
    required String operation, // 'create', 'update', 'delete'
    int attemptCount = 0,
    String? lastError,
    DateTime? nextRetryAt,
    String? idempotencyKey,
    String status = 'pending',
    String? headers, // JSON string of headers
    String? extra, // JSON string of extra parameters
  }) async {
    final itemId = await _db.customInsert(
      'INSERT INTO sync_queue_items '
      '(model_type, model_id, payload, op, attempt_count, last_error, '
      'next_retry_at, idempotency_key, status, created_at, headers, extra) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      variables: [
        Variable.withString(modelType),
        Variable.withString(modelId),
        Variable.withString(payload),
        Variable.withString(operation),
        Variable.withInt(attemptCount),
        lastError != null
            ? Variable.withString(lastError)
            : const Variable(null),
        nextRetryAt != null
            ? Variable.withDateTime(nextRetryAt)
            : const Variable(null),
        idempotencyKey != null
            ? Variable.withString(idempotencyKey)
            : const Variable(null),
        Variable.withString(status), // Added status variable
        Variable.withDateTime(DateTime.now().toUtc()), // Added created_at
        headers != null ? Variable.withString(headers) : const Variable(null),
        extra != null ? Variable.withString(extra) : const Variable(null),
      ],
    );

    // Update the model's syncStatus to reflect the new sync queue entry
    await updateModelSyncStatus(modelType, modelId, status);

    return itemId;
  }

  /// Updates an existing item in the sync queue.
  /// Returns the number of rows affected (usually 1 if successful).
  ///
  /// Note: This method only updates the sync queue item. To update the
  /// model's syncStatus, use specific methods like markTaskAsDead() or
  /// updateTaskRetry().
  Future<int> updateItem({
    required int id,
    String? modelType,
    String? payload,
    String? operation,
    int? attemptCount,
    String? lastError,
    DateTime? nextRetryAt,
    String? idempotencyKey,
    String? status, // Added status
    String? headers, // JSON string of headers
    String? extra, // JSON string of extra parameters
  }) async {
    final updates = <String>[];
    final variables = <Variable>[];

    if (modelType != null) {
      updates.add('model_type = ?');
      variables.add(Variable.withString(modelType));
    }
    if (payload != null) {
      updates.add('payload = ?');
      variables.add(Variable.withString(payload));
    }
    if (operation != null) {
      updates.add('op = ?');
      variables.add(Variable.withString(operation));
    }
    if (attemptCount != null) {
      updates.add('attempt_count = ?');
      variables.add(Variable.withInt(attemptCount));
    }
    if (lastError != null) {
      updates.add('last_error = ?');
      variables.add(Variable.withString(lastError));
    } else {
      // Allow explicitly setting lastError to null
      updates.add('last_error = ?');
      variables.add(const Variable(null));
    }
    if (nextRetryAt != null) {
      updates.add('next_retry_at = ?');
      variables.add(Variable.withDateTime(nextRetryAt));
    }
    if (idempotencyKey != null) {
      updates.add('idempotency_key = ?');
      variables.add(Variable.withString(idempotencyKey));
    }
    if (status != null) {
      updates.add('status = ?');
      variables.add(Variable.withString(status));
    }
    if (headers != null) {
      updates.add('headers = ?');
      variables.add(Variable.withString(headers));
    }
    if (extra != null) {
      updates.add('extra = ?');
      variables.add(Variable.withString(extra));
    }

    if (updates.isEmpty) {
      return 0; // No updates to perform
    }

    variables.add(Variable.withInt(id)); // For the WHERE clause

    final result = await _db.customUpdate(
      'UPDATE sync_queue_items SET ${updates.join(', ')} WHERE id = ?',
      variables: variables,
    );

    return result;
  }

  /// Deletes a specific sync queue item by its [id].
  /// Returns the number of rows affected (usually 1 if successful).
  Future<int> deleteTask(int id) async {
    // Get task info before deletion to update model's syncStatus
    final task = await getItemById(id);

    final result = await _db.customUpdate(
      'DELETE FROM sync_queue_items WHERE id = ?',
      variables: [Variable.withInt(id)],
    );

    // Update the model's syncStatus after deletion
    // Since we deleted the only task for this model, status becomes 'synced'
    if (task != null && result > 0) {
      final modelType = task['model_type'] as String;
      final modelId = task['model_id'] as String;
      await updateModelSyncStatus(modelType, modelId, 'synced');
    }

    return result;
  }

  /// Marks a task as 'dead' and records the final error.
  /// This prevents the task from being retried indefinitely.
  Future<int> markTaskAsDead(int id, String error) async {
    // Get task info to update model's syncStatus
    final task = await getItemById(id);

    final result = await updateItem(
      id: id,
      status: 'dead',
      lastError: error,
      // nextRetryAt could be set to null or a far future date if desired
    );

    // Update the model's syncStatus to 'dead'
    if (task != null && result > 0) {
      final modelType = task['model_type'] as String;
      final modelId = task['model_id'] as String;
      await updateModelSyncStatus(modelType, modelId, 'dead');
    }

    return result;
  }

  /// Updates a task's retry information.
  Future<int> updateTaskRetry(
    int id,
    DateTime nextRetryAt,
    int attemptCount,
    String lastError,
  ) async {
    // Get task info to update model's syncStatus
    final task = await getItemById(id);

    final result = await updateItem(
      id: id,
      nextRetryAt: nextRetryAt,
      attemptCount: attemptCount,
      lastError: lastError,
      status: 'pending', // Ensure status is pending for retry
    );

    // Update the model's syncStatus to 'pending'
    if (task != null && result > 0) {
      final modelType = task['model_type'] as String;
      final modelId = task['model_id'] as String;
      await updateModelSyncStatus(modelType, modelId, 'pending');
    }

    return result;
  }

  /// Finds sync queue tasks for a specific model type and model ID.
  ///
  /// This is useful to check if there are pending sync operations
  /// for a specific item (e.g., before deleting it locally).
  Future<List<Map<String, dynamic>>> getTasksForModelId(
    String modelType,
    String modelId,
  ) async {
    final results = await _db.customSelect(
      'SELECT * FROM sync_queue_items WHERE model_type = ? AND '
      'model_id = ? AND status != ?',
      variables: [
        Variable.withString(modelType),
        Variable.withString(modelId),
        Variable.withString('dead'),
      ],
    ).get();
    return results.map((row) => row.data).toList();
  }

  /// Deletes all pending sync tasks for a specific model type and model ID.
  ///
  /// This is useful when an item is deleted locally - we should cancel
  /// any pending CREATE/UPDATE operations for that item.
  /// Returns the number of tasks deleted.
  Future<int> deleteTasksForModelId(String modelType, String modelId) async {
    final result = await _db.customUpdate(
      'DELETE FROM sync_queue_items WHERE model_type = ? AND '
      'model_id = ? AND status != ?',
      variables: [
        Variable.withString(modelType),
        Variable.withString(modelId),
        Variable.withString('dead'),
      ],
    );

    // Update model's syncStatus after deletion
    // Since we deleted all non-dead tasks, status is either 'synced' or 'dead'
    if (result > 0) {
      // Check if there are any dead tasks left
      final deadTasks = await _db.customSelect(
        'SELECT COUNT(*) as count FROM sync_queue_items '
        'WHERE model_type = ? AND model_id = ? AND status = ?',
        variables: [
          Variable.withString(modelType),
          Variable.withString(modelId),
          Variable.withString('dead'),
        ],
      ).get();

      final hasDeadTasks = (deadTasks.first.data['count'] as int) > 0;
      final syncStatus = hasDeadTasks ? 'dead' : 'synced';
      await updateModelSyncStatus(modelType, modelId, syncStatus);
    }

    return result;
  }

  /// Deletes specific types of operations for a model ID.
  ///
  /// This allows more granular control - for example, deleting only
  /// CREATE and UPDATE operations but keeping DELETE operations.
  Future<int> deleteTasksForModelIdAndOperations(
    String modelType,
    String modelId,
    List<String> operations,
  ) async {
    if (operations.isEmpty) return 0;

    final placeholders = operations.map((_) => '?').join(', ');
    final variables = [
      Variable.withString(modelType),
      Variable.withString(modelId),
      Variable.withString('dead'),
      ...operations.map((op) => Variable.withString(op)),
    ];

    final result = await _db.customUpdate(
      'DELETE FROM sync_queue_items '
      'WHERE model_type = ? AND model_id = ? AND status != ? AND '
      'op IN ($placeholders)',
      variables: variables,
    );

    // Update model's syncStatus after deletion
    // Since there's only one task per model, if we deleted it,
    // status becomes 'synced'
    if (result > 0) {
      await updateModelSyncStatus(modelType, modelId, 'synced');
    }

    return result;
  }

  /// Find the latest pending sync queue item for a specific model operation.
  ///
  /// This is useful when we want to update an existing sync queue item
  /// instead of creating a new one, for example when the same item is
  /// updated multiple times while offline.
  /// Returns the queue item ID if found, null otherwise.
  Future<int?> findPendingSyncTask(
    String modelType,
    String modelId,
    String operation,
  ) async {
    final results = await _db.customSelect(
      'SELECT id FROM sync_queue_items WHERE model_type = ? AND '
      'model_id = ? AND op = ? AND status != ? '
      'ORDER BY created_at DESC LIMIT 1',
      variables: [
        Variable.withString(modelType),
        Variable.withString(modelId),
        Variable.withString(operation),
        Variable.withString('dead'),
      ],
    ).get();

    return results.isNotEmpty ? results.first.data['id'] as int : null;
  }

  /// Checks if a specific operation exists for a model in the sync queue.
  ///
  /// Returns true if there's a pending operation of the specified type
  /// for the given model.
  Future<bool> hasOperationForModel(
    String modelType,
    String modelId,
    String operation,
  ) async {
    final results = await _db.customSelect(
      'SELECT 1 FROM sync_queue_items WHERE model_type = ? AND '
      'model_id = ? AND op = ? AND status != ? LIMIT 1',
      variables: [
        Variable.withString(modelType),
        Variable.withString(modelId),
        Variable.withString(operation),
        Variable.withString('dead'),
      ],
    ).get();

    return results.isNotEmpty;
  }

  /// Smart delete logic for handling model deletion based on sync queue state.
  ///
  /// Logic:
  /// - If CREATE exists: just delete the CREATE record
  ///   (model never existed in API)
  /// - If UPDATE exists: delete UPDATE and create DELETE (model exists in API)
  /// - If DELETE already exists: do nothing
  /// - Otherwise: create DELETE (model exists in API)
  ///
  /// Returns a map with information about what action was taken:
  /// - 'action':
  /// 'removed_create' |
  /// 'replaced_update_with_delete' |
  /// 'created_delete' |
  /// 'delete_already_exists'
  /// - 'deleted_records': number of records deleted
  /// - 'created_delete_id': ID of newly created delete record (if any)
  Future<Map<String, dynamic>> handleModelDeletion({
    required String modelType,
    required String modelId,
    required String payload,
    String? idempotencyKey,
    bool scheduleDelete = false,
    String? headers,
    String? extra,
  }) async {
    // Check what operations exist for this model
    final existingTasks = await getTasksForModelId(modelType, modelId);

    bool hasCreate = false;
    bool hasUpdate = false;
    bool hasDelete = false;

    for (final task in existingTasks) {
      final operation = task['op'] as String;
      switch (operation) {
        case 'create':
          hasCreate = true;
          break;
        case 'update':
          hasUpdate = true;
          break;
        case 'delete':
          hasDelete = true;
          break;
      }
    }

    if (hasDelete) {
      // DELETE already exists, do nothing
      return {
        'action': 'delete_already_exists',
        'deleted_records': 0,
        'created_delete_id': null,
      };
    }

    if (hasCreate) {
      // Model never existed in API, just remove CREATE
      final deletedCount = await deleteTasksForModelIdAndOperations(
        modelType,
        modelId,
        ['create', 'update'], // Remove both CREATE and any UPDATE
      );
      return {
        'action': 'removed_create',
        'deleted_records': deletedCount,
        'created_delete_id': null,
      };
    }

    if (hasUpdate) {
      // Model exists in API with pending updates, replace with DELETE
      final deletedCount = await deleteTasksForModelIdAndOperations(
        modelType,
        modelId,
        ['update'],
      );

      if (scheduleDelete) {
        // Create DELETE operation
        final deleteId = await insertItem(
          modelType: modelType,
          modelId: modelId,
          payload: payload,
          operation: 'delete',
          idempotencyKey: idempotencyKey,
          headers: headers,
          extra: extra,
        );

        return {
          'action': 'replaced_update_with_delete',
          'deleted_records': deletedCount,
          'created_delete_id': deleteId,
        };
      }

      return {
        'action': 'cleared_update',
        'deleted_records': deletedCount,
        'created_delete_id': null,
      };
    }

    if (scheduleDelete) {
      // No pending operations, model exists in API, create DELETE
      final deleteId = await insertItem(
        modelType: modelType,
        modelId: modelId,
        payload: payload,
        operation: 'delete',
        idempotencyKey: idempotencyKey,
        headers: headers,
        extra: extra,
      );

      return {
        'action': 'created_delete',
        'deleted_records': 0,
        'created_delete_id': deleteId,
      };
    }

    return {
      'action': 'cleared_no_operations',
      'deleted_records': 0,
      'created_delete_id': null,
    };
  }

  /// Converts model type to table name using naming convention.
  ///
  /// Converts CamelCase model names to snake_case table names with plural form.
  /// Example: User -> users, TodoItem -> todo_items, Category -> categories
  String modelTypeToTableName(String modelType) {
    // Use proper pluralization first
    final pluralSnakeCase = PluralizationUtils.toSnakeCasePlural(modelType);

    // Remove leading underscore if present
    return pluralSnakeCase.startsWith('_')
        ? pluralSnakeCase.substring(1)
        : pluralSnakeCase;
  }

  /// Updates the syncStatus field in the model table.
  ///
  /// This method directly updates the model's syncStatus field in its table
  /// with the provided status value and manually notifies Drift about the
  /// table changes to trigger reactive streams.
  ///
  /// [modelType] The type of the model (e.g., 'User', 'Post')
  /// [modelId] The ID of the model instance
  /// [syncStatus] The sync status to set ('pending', 'synced', 'dead')
  Future<void> updateModelSyncStatus(
    String modelType,
    String modelId,
    String syncStatus,
  ) async {
    // Convert model type to table name and use cached table lookup
    final tableName = modelTypeToTableName(modelType);
    try {
      // Use cached table lookup for better performance
      final modelTable = _getCachedTable(tableName);

      // Use cached table for reactive updates
      await _db.customUpdate(
        'UPDATE $tableName SET sync_status = ? WHERE id = ?',
        variables: [
          Variable.withString(syncStatus),
          Variable.withString(modelId),
        ],
        updates: modelTable != null ? {modelTable} : null,
        updateKind: modelTable != null ? UpdateKind.update : null,
      );

      if (modelTable == null) {
        // Fallback: update without reactive notifications
        // This happens in tests or when tables are not properly registered
        _log.fine(
          'Table $tableName not found in cache, using fallback update for '
          '$modelType with ID $modelId',
        );
      }
    } catch (e, stack) {
      _log.severe(
        'Failed to update syncStatus for $modelType with ID $modelId '
        'to $syncStatus',
        e,
        stack,
      );
    }
  }
}
