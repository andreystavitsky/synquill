part of synquill;

/// Service for resolving ID conflicts during server ID negotiation.
///
/// This service handles complex scenarios that arise when server-assigned IDs
/// conflict with existing local data or when multiple concurrent operations
/// attempt to modify the same resources.
class IdConflictResolver {
  /// The database instance.
  final GeneratedDatabase _db;

  /// Logger instance for this service
  static Logger get _log {
    try {
      return SynquillStorage.logger;
    } catch (_) {
      return Logger('IdConflictResolver');
    }
  }

  /// Maximum number of retry attempts for ID conflict resolution
  static const int maxRetryAttempts = 3;

  /// Timeout duration for ID conflict resolution operations
  static const Duration conflictResolutionTimeout = Duration(seconds: 30);

  /// Creates a new [IdConflictResolver] instance.
  IdConflictResolver(this._db);

  /// Resolves ID conflicts that may occur during server ID negotiation.
  ///
  /// This method handles several scenarios:
  /// 1. Proposed server ID already exists locally
  /// 2. Concurrent ID replacement operations
  /// 3. Foreign key constraint violations
  /// 4. Network timeouts during negotiation
  ///
  /// Returns the final ID that should be used for the model.
  Future<String> resolveIdConflict({
    required String temporaryId,
    required String proposedServerId,
    required String modelType,
    int retryCount = 0,
  }) async {
    _log.info(
      'Resolving ID conflict: $temporaryId -> $proposedServerId '
      '(attempt ${retryCount + 1}/$maxRetryAttempts)',
    );

    try {
      // 1. Check if proposed server ID already exists locally
      if (await _idExistsLocally(proposedServerId, modelType)) {
        return await _handleIdCollision(
          temporaryId,
          proposedServerId,
          modelType,
          retryCount,
        );
      }

      // 2. Check for concurrent operations on the same temporary ID
      if (await _hasConcurrentOperations(temporaryId, modelType)) {
        _log.warning(
          'Concurrent operations detected for $temporaryId, waiting...',
        );
        await Future.delayed(const Duration(milliseconds: 100));

        // Retry after delay
        if (retryCount < maxRetryAttempts) {
          return await resolveIdConflict(
            temporaryId: temporaryId,
            proposedServerId: proposedServerId,
            modelType: modelType,
            retryCount: retryCount + 1,
          );
        } else {
          throw IdConflictException(
            'Too many concurrent operations for $temporaryId',
            temporaryId: temporaryId,
            proposedServerId: proposedServerId,
            modelType: modelType,
          );
        }
      }

      // 3. Validate foreign key integrity before accepting server ID
      await _validateForeignKeyIntegrity(
        temporaryId,
        proposedServerId,
        modelType,
      );

      // 4. Check for deadlock potential
      if (await _hasDeadlockPotential(
          temporaryId, proposedServerId, modelType)) {
        _log.warning(
          'Deadlock potential detected, using alternative strategy',
        );
        return await _resolveWithAlternativeStrategy(
          temporaryId,
          proposedServerId,
          modelType,
          retryCount,
        );
      }

      // 5. If all checks pass, return the proposed server ID
      _log.info('ID conflict resolved: using server ID $proposedServerId');
      return proposedServerId;
    } catch (e, stackTrace) {
      _log.severe(
        'Error resolving ID conflict for $temporaryId -> $proposedServerId',
        e,
        stackTrace,
      );

      if (retryCount < maxRetryAttempts) {
        _log.info('Retrying ID conflict resolution...');
        await Future.delayed(Duration(seconds: 1 << retryCount));
        return await resolveIdConflict(
          temporaryId: temporaryId,
          proposedServerId: proposedServerId,
          modelType: modelType,
          retryCount: retryCount + 1,
        );
      }

      rethrow;
    }
  }

  /// Checks if the proposed server ID already exists locally.
  Future<bool> _idExistsLocally(String serverId, String modelType) async {
    try {
      final tableName = PluralizationUtils.toSnakeCase(
        PluralizationUtils.toCamelCasePlural(modelType),
      );

      final result = await _db.customSelect(
        'SELECT COUNT(*) as count FROM $tableName WHERE id = ?',
        variables: [Variable.withString(serverId)],
      ).getSingleOrNull();

      final count = result?.data['count'] as int? ?? 0;
      return count > 0;
    } catch (e) {
      _log.warning('Error checking if ID exists locally: $e');
      // If we can't check, assume it doesn't exist to avoid blocking
      return false;
    }
  }

  /// Handles ID collision scenarios.
  Future<String> _handleIdCollision(
    String temporaryId,
    String proposedServerId,
    String modelType,
    int retryCount,
  ) async {
    _log.warning(
      'ID collision detected: $proposedServerId already exists locally',
    );

    // Strategy 1: Check if the existing record is actually the same
    // as our temporary record
    if (await _isSameRecord(temporaryId, proposedServerId, modelType)) {
      _log.info(
        'Collision resolved: existing record $proposedServerId is the same '
        'as temporary $temporaryId',
      );

      // Clean up the temporary record
      await _cleanupTemporaryRecord(temporaryId, modelType);
      return proposedServerId;
    }

    // Strategy 2: Check if the existing record has a temporary status
    // (i.e., it might be from another concurrent operation)
    if (await _isTemporaryRecord(proposedServerId, modelType)) {
      _log.info(
        'Collision with temporary record $proposedServerId, '
        'waiting for resolution...',
      );

      // Wait and retry - the other operation might complete first
      await Future.delayed(Duration(seconds: 1 << retryCount));
      if (retryCount < maxRetryAttempts) {
        return await resolveIdConflict(
          temporaryId: temporaryId,
          proposedServerId: proposedServerId,
          modelType: modelType,
          retryCount: retryCount + 1,
        );
      }
    }

    // Strategy 3: Check if we can merge the records
    final mergeResult = await _attemptRecordMerge(
      temporaryId,
      proposedServerId,
      modelType,
    );

    if (mergeResult != null) {
      _log.info(
        'Collision resolved through record merge: using ID $mergeResult',
      );
      return mergeResult;
    }

    // Strategy 4: Use alternative ID strategy
    // (keep temporary, mark as conflict)
    _log.warning(
      'Cannot resolve collision for $proposedServerId, '
      'keeping temporary ID $temporaryId',
    );

    // Mark as conflicted for later resolution
    await _markAsConflicted(temporaryId, proposedServerId, modelType);

    throw IdConflictException(
      'Server ID $proposedServerId conflicts with existing local record. '
      'Kept temporary ID $temporaryId for manual resolution.',
      temporaryId: temporaryId,
      proposedServerId: proposedServerId,
      modelType: modelType,
    );
  }

  /// Checks if there are concurrent operations on the same temporary ID.
  Future<bool> _hasConcurrentOperations(
    String temporaryId,
    String modelType,
  ) async {
    try {
      final syncQueueDao = SyncQueueDao(_db);
      final pendingTasks = await syncQueueDao.getTasksForModelId(
        modelType,
        temporaryId,
      );

      // Check for multiple pending ID negotiation tasks
      final idNegotiationTasks = pendingTasks
          .where(
            (task) =>
                task['id_negotiation_status'] ==
                IdNegotiationStatus.pending.name,
          )
          .toList();

      return idNegotiationTasks.length > 1;
    } catch (e) {
      _log.warning('Error checking concurrent operations: $e');
      return false;
    }
  }

  /// Validates foreign key integrity before ID replacement.
  Future<void> _validateForeignKeyIntegrity(
    String temporaryId,
    String proposedServerId,
    String modelType,
  ) async {
    try {
      // Get all foreign key relations that reference this model type
      final foreignKeyRelations =
          ModelInfoRegistryProvider.getForeignKeyRelations(modelType);

      if (foreignKeyRelations.isEmpty) {
        _log.fine('No foreign key relations to validate for $modelType');
        return;
      }

      _log.fine(
        'Validating foreign key integrity for ${foreignKeyRelations.length} '
        'relations before ID replacement',
      );

      // Check each relation for potential conflicts
      for (final relation in foreignKeyRelations) {
        await _validateSingleForeignKeyRelation(
          relation,
          temporaryId,
          proposedServerId,
        );
      }

      _log.fine('Foreign key integrity validation completed successfully');
    } catch (e, stackTrace) {
      _log.severe(
        'Foreign key integrity validation failed for '
        '$temporaryId -> $proposedServerId',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Validates a single foreign key relation.
  Future<void> _validateSingleForeignKeyRelation(
    ForeignKeyRelation relation,
    String temporaryId,
    String proposedServerId,
  ) async {
    final sourceTable = relation.sourceTable;
    final foreignKeyField = relation.fieldName;

    try {
      // Check if the proposed server ID would create conflicts
      final relationColumnName =
          PluralizationUtils.toSnakeCase(foreignKeyField);

      final conflictCount = await _db.customSelect(
        '''
        SELECT COUNT(*) as count FROM $sourceTable 
        WHERE $relationColumnName = ?
        ''',
        variables: [Variable.withString(proposedServerId)],
      ).getSingleOrNull();

      final count = conflictCount?.data['count'] as int? ?? 0;
      if (count > 0) {
        _log.warning(
          'Foreign key conflict detected: $sourceTable.$relationColumnName '
          'already has references to $proposedServerId',
        );

        // This might be legitimate if records were created with the server ID
        // We'll log it but not fail the validation
      }
    } catch (e) {
      _log.warning(
        'Failed to validate foreign key relation '
        '$sourceTable.$foreignKeyField: $e',
      );
      // Continue with other relations even if one fails
    }
  }

  /// Checks for potential deadlock scenarios.
  Future<bool> _hasDeadlockPotential(
    String temporaryId,
    String proposedServerId,
    String modelType,
  ) async {
    try {
      // Check if there are circular dependency chains that could cause deadlock
      final cascadeRelations =
          ModelInfoRegistryProvider.getCascadeDeleteRelations(modelType);

      if (cascadeRelations.isEmpty) {
        return false;
      }

      // Simple heuristic: check if there are pending operations
      // on related models
      // that might interfere with this ID replacement
      for (final relation in cascadeRelations) {
        final relatedTasks = await SyncQueueDao(_db).getItemsByModelType(
          relation.targetType,
        );

        final pendingRelatedTasks = relatedTasks
            .where(
              (task) => task['status'] == 'pending',
            )
            .toList();

        if (pendingRelatedTasks.length > 5) {
          _log.warning(
            'High number of pending tasks for related model '
            '${relation.targetType}, potential deadlock risk',
          );
          return true;
        }
      }

      return false;
    } catch (e) {
      _log.warning('Error checking deadlock potential: $e');
      return false;
    }
  }

  /// Resolves conflicts using an alternative strategy.
  Future<String> _resolveWithAlternativeStrategy(
    String temporaryId,
    String proposedServerId,
    String modelType,
    int retryCount,
  ) async {
    _log.info(
      'Using alternative resolution strategy for '
      '$temporaryId -> $proposedServerId',
    );

    // Strategy: Defer the ID replacement and let other operations
    // complete first
    await Future.delayed(Duration(seconds: 2 << retryCount));

    // Check if the conflict situation has improved
    final hasDeadlock = await _hasDeadlockPotential(
      temporaryId,
      proposedServerId,
      modelType,
    );
    if (!hasDeadlock) {
      return proposedServerId;
    }

    // If still problematic, generate a unique alternative ID
    // Note: This is a fallback strategy and may require server API changes
    throw IdConflictException(
      'Cannot resolve deadlock potential for ID replacement',
      temporaryId: temporaryId,
      proposedServerId: proposedServerId,
      modelType: modelType,
    );
  }

  /// Checks if two records represent the same entity.
  Future<bool> _isSameRecord(
    String temporaryId,
    String existingId,
    String modelType,
  ) async {
    try {
      final tableName = PluralizationUtils.toSnakeCase(
        PluralizationUtils.toCamelCasePlural(modelType),
      );

      final tempRecord = await _db.customSelect(
        'SELECT * FROM $tableName WHERE id = ?',
        variables: [Variable.withString(temporaryId)],
      ).getSingleOrNull();

      final existingRecord = await _db.customSelect(
        'SELECT * FROM $tableName WHERE id = ?',
        variables: [Variable.withString(existingId)],
      ).getSingleOrNull();

      if (tempRecord == null || existingRecord == null) {
        return false;
      }

      // Compare non-ID fields to see if they represent the same entity
      final tempData = Map<String, dynamic>.from(tempRecord.data);
      final existingData = Map<String, dynamic>.from(existingRecord.data);

      // Remove ID and timestamp fields for comparison
      tempData.remove('id');
      tempData.remove('created_at');
      tempData.remove('updated_at');
      tempData.remove('sync_status');

      existingData.remove('id');
      existingData.remove('created_at');
      existingData.remove('updated_at');
      existingData.remove('sync_status');

      // Deep comparison of remaining fields
      return _deepEquals(tempData, existingData);
    } catch (e) {
      _log.warning('Error comparing records: $e');
      return false;
    }
  }

  /// Performs deep equality comparison of two maps.
  bool _deepEquals(Map<String, dynamic> map1, Map<String, dynamic> map2) {
    if (map1.length != map2.length) return false;

    for (final key in map1.keys) {
      if (!map2.containsKey(key)) return false;

      final value1 = map1[key];
      final value2 = map2[key];

      if (value1 != value2) {
        // Handle special cases like null vs empty string
        if ((value1 == null && value2 == '') ||
            (value1 == '' && value2 == null)) {
          continue;
        }
        return false;
      }
    }

    return true;
  }

  /// Cleans up a temporary record after successful collision resolution.
  Future<void> _cleanupTemporaryRecord(
    String temporaryId,
    String modelType,
  ) async {
    try {
      final tableName = PluralizationUtils.toSnakeCase(
        PluralizationUtils.toCamelCasePlural(modelType),
      );

      await _db.customUpdate(
        'DELETE FROM $tableName WHERE id = ?',
        variables: [Variable.withString(temporaryId)],
      );

      _log.fine('Cleaned up temporary record $temporaryId from $tableName');
    } catch (e) {
      _log.warning('Failed to cleanup temporary record $temporaryId: $e');
      // Non-critical error, continue operation
    }
  }

  /// Checks if a record is marked as temporary (from concurrent operations).
  Future<bool> _isTemporaryRecord(String recordId, String modelType) async {
    try {
      final syncQueueDao = SyncQueueDao(_db);
      final pendingTasks = await syncQueueDao.getTasksForModelId(
        modelType,
        recordId,
      );

      // Check if there are any pending ID negotiation tasks for this ID
      final hasTemporaryStatus = pendingTasks.any(
        (task) =>
            task['id_negotiation_status'] == IdNegotiationStatus.pending.name ||
            task['temporary_client_id'] == recordId,
      );

      return hasTemporaryStatus;
    } catch (e) {
      _log.warning('Error checking temporary record status: $e');
      return false;
    }
  }

  /// Attempts to merge two records that have the same server ID.
  Future<String?> _attemptRecordMerge(
    String temporaryId,
    String existingId,
    String modelType,
  ) async {
    try {
      _log.fine('Attempting record merge: $temporaryId -> $existingId');

      // Get both records for comparison
      final tableName = PluralizationUtils.toSnakeCasePlural(modelType);

      final tempRecord = await _db.customSelect(
        'SELECT * FROM $tableName WHERE id = ?',
        variables: [Variable.withString(temporaryId)],
      ).getSingleOrNull();

      final existingRecord = await _db.customSelect(
        'SELECT * FROM $tableName WHERE id = ?',
        variables: [Variable.withString(existingId)],
      ).getSingleOrNull();

      if (tempRecord == null || existingRecord == null) {
        _log.warning(
          'Cannot merge records: one or both records not found '
          '(temp: $temporaryId, existing: $existingId)',
        );
        return null;
      }

      _log.fine('Found both records for merge comparison');

      // Check if records can be merged (similar created_at, same key fields)
      final tempData = tempRecord.data;
      final existingData = existingRecord.data;

      _log.fine(
        'Temp record: name="${tempData['name']}", '
        'desc="${tempData['description']}"',
      );
      _log.fine(
        'Existing record: name="${existingData['name']}", '
        'desc="${existingData['description']}"',
      );

      // Parse created_at from whatever form it's in (DateTime, int, String)
      DateTime? tempCreatedAt;
      DateTime? existingCreatedAt;

      // Handle temporary record created_at
      if (tempData['created_at'] is DateTime) {
        tempCreatedAt = tempData['created_at'] as DateTime;
      } else if (tempData['created_at'] is int) {
        final timestamp = tempData['created_at'] as int;
        tempCreatedAt = DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else if (tempData['created_at'] is String) {
        try {
          tempCreatedAt = DateTime.parse(tempData['created_at'] as String);
        } catch (_) {
          tempCreatedAt = null;
        }
      }

      // Handle existing record created_at
      if (existingData['created_at'] is DateTime) {
        existingCreatedAt = existingData['created_at'] as DateTime;
      } else if (existingData['created_at'] is int) {
        final timestamp = existingData['created_at'] as int;
        existingCreatedAt = DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else if (existingData['created_at'] is String) {
        try {
          existingCreatedAt = DateTime.parse(
            existingData['created_at'] as String,
          );
        } catch (_) {
          existingCreatedAt = null;
        }
      }

      if (tempCreatedAt != null && existingCreatedAt != null) {
        _log.fine(
          'Comparing timestamps for merge: temp=$tempCreatedAt, '
          'existing=$existingCreatedAt',
        );

        if (tempCreatedAt.isAfter(existingCreatedAt)) {
          _log.fine(
            'Temporary record is newer, merging into existing record',
          );

          // Update existing record with temporary record's data
          await _mergeRecordData(
            tableName,
            existingId,
            tempData,
            existingData,
          );

          // Clean up temporary record
          await _cleanupTemporaryRecord(temporaryId, modelType);

          _log.fine(
            'Successfully merged records, using existing ID: $existingId',
          );
          return existingId;
        } else {
          _log.fine(
            'Records $temporaryId and $existingId cannot be merged: '
            'temporary created_at is not after existing created_at',
          );
        }
      } else {
        _log.warning(
          'Cannot compare timestamps for merge: '
          'temp=$tempCreatedAt, existing=$existingCreatedAt',
        );
      }

      return null;
    } catch (e) {
      _log.warning('Error attempting record merge: $e');
      return null;
    }
  }

  /// Merges data from temporary record into existing record.
  Future<void> _mergeRecordData(
    String tableName,
    String targetId,
    Map<String, dynamic> tempData,
    Map<String, dynamic> existingData,
  ) async {
    try {
      // Build update query for non-null fields from temporary record
      final updateFields = <String>[];
      final updateValues = <Variable>[];

      for (final entry in tempData.entries) {
        final key = entry.key;
        final value = entry.value;

        // Skip ID and system fields
        if (key == 'id' || key == 'created_at' || key == 'sync_status') {
          continue;
        }

        // Only update if temporary has non-null value and it's different
        if (value != null && value != existingData[key]) {
          updateFields.add('$key = ?');
          updateValues.add(Variable.withString(value.toString()));
        }
      }

      if (updateFields.isNotEmpty) {
        // Update updated_at timestamp
        updateFields.add('updated_at = ?');
        updateValues.add(Variable.withDateTime(DateTime.now().toUtc()));

        // Add WHERE clause
        updateValues.add(Variable.withString(targetId));

        await _db.customUpdate(
          'UPDATE $tableName SET ${updateFields.join(', ')} WHERE id = ?',
          variables: updateValues,
        );

        _log.info('Merged temporary data into existing record $targetId');
      }
    } catch (e) {
      _log.warning('Error merging record data: $e');
      rethrow;
    }
  }

  /// Marks a record as conflicted for later manual resolution.
  Future<void> _markAsConflicted(
    String temporaryId,
    String proposedServerId,
    String modelType,
  ) async {
    try {
      // Update sync queue to mark conflict
      final syncQueueDao = SyncQueueDao(_db);
      final pendingTasks = await syncQueueDao.getTasksForModelId(
        modelType,
        temporaryId,
      );

      for (final task in pendingTasks) {
        final taskId = task['id'] as int;
        await syncQueueDao.updateItem(
          id: taskId,
          idNegotiationStatus: IdNegotiationStatus.conflict.name,
          lastError: 'ID conflict: server assigned $proposedServerId '
              'but it already exists locally',
        );
      }

      _log.warning(
        'Marked $temporaryId as conflicted due to server ID collision '
        'with $proposedServerId',
      );
    } catch (e) {
      _log.warning('Error marking record as conflicted: $e');
      // Non-critical error, continue operation
    }
  }
}

/// Exception thrown when ID conflicts cannot be resolved.
class IdConflictException implements Exception {
  /// The error message.
  final String message;

  /// The temporary client ID that caused the conflict.
  final String temporaryId;

  /// The proposed server ID that conflicts.
  final String proposedServerId;

  /// The model type involved in the conflict.
  final String modelType;

  /// Creates a new [IdConflictException].
  const IdConflictException(
    this.message, {
    required this.temporaryId,
    required this.proposedServerId,
    required this.modelType,
  });

  @override
  String toString() {
    return 'IdConflictException: $message '
        '(temporary: $temporaryId, proposed: $proposedServerId, '
        'model: $modelType)';
  }
}
