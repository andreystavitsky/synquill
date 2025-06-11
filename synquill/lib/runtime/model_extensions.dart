part of synquill;

/// Runtime extensions for [SynquillDataModel] instances.
///
/// These extensions provide instance-level methods that delegate to the
/// repository associated with the model instance. The repository instance
/// is injected by the code generation process.
///
/// This implements RC-03 from the technical specification.
extension SynquillDataModelExtensions<T extends SynquillDataModel<T>>
    on SynquillDataModel<T> {
  /// Logger for the model extensions.
  static Logger get _log => Logger('SynquillDataModelExtensions');

  /// Saves this model instance using the associated repository.
  ///
  /// [savePolicy] determines whether to save to local storage first
  /// ([DataSavePolicy.localFirst]) or to the remote API first
  /// ([DataSavePolicy.remoteFirst]).
  /// [updateTimestamps] Whether to automatically update createdAt/updatedAt
  /// timestamps. Defaults to true. Set to false if you want to manually
  /// control timestamp values.
  ///
  /// Returns the saved instance, which may be updated with data from the
  /// remote API (such as server-generated timestamps).
  ///
  /// Throws [StateError] if no repository is associated with this model
  /// instance.
  ///
  /// Example:
  /// ```dart
  /// final user = User(id: generateCuid(), name: 'John Doe');
  /// final savedUser = await user.save();
  /// ```
  ///
  /// Example with custom timestamp:
  /// ```dart
  /// final user = User(id: generateCuid(), name: 'John Doe');
  /// user.updatedAt = DateTime.parse('2024-12-25T10:00:00Z');
  /// final savedUser = await user.save(updateTimestamps: false);
  /// ```
  Future<T> save({
    DataSavePolicy savePolicy = DataSavePolicy.localFirst,
    Map<String, dynamic>? extra,
    bool updateTimestamps = true,
  }) async {
    _log.fine('save() called on ${T.toString()} instance with ID $id');

    try {
      // Get the database instance (this should be set up by initialization)
      final database = DatabaseProvider.instance;

      // Get repository using RepositoryProvider
      final repository = SynquillRepositoryProvider.getFrom<T>(database);

      // Cast this to T since we know it's a SynquillDataModel<T>
      final result = await repository.save(
        this as T,
        savePolicy: savePolicy,
        extra: extra,
        updateTimestamps: updateTimestamps,
      );

      _log.fine('Successfully saved ${T.toString()} with ID $id');
      return result;
    } catch (e, stackTrace) {
      _log.severe('Failed to save ${T.toString()} with ID $id', e, stackTrace);
      rethrow;
    }
  }

  /// Deletes this model instance using the associated repository.
  ///
  /// [savePolicy] determines whether to delete from local storage first
  /// ([DataSavePolicy.localFirst]) or from the remote API first
  /// ([DataSavePolicy.remoteFirst]).
  ///
  /// Throws [StateError] if no repository is associated with this model
  /// instance.
  ///
  /// Example:
  /// ```dart
  /// final user = await userRepository.findOne('user123');
  /// if (user != null) {
  ///   await user.delete();
  /// }
  /// ```
  Future<void> delete({
    DataSavePolicy savePolicy = DataSavePolicy.localFirst,
    Map<String, dynamic>? extra,
  }) async {
    _log.fine('delete() called on ${T.toString()} instance with ID $id');

    try {
      // Get the database instance
      final database = DatabaseProvider.instance;

      // Get repository using RepositoryProvider
      final repository = SynquillRepositoryProvider.getFrom<T>(database);

      await repository.delete(id, savePolicy: savePolicy, extra: extra);

      _log.fine('Successfully deleted ${T.toString()} with ID $id');
    } catch (e, stackTrace) {
      _log.severe(
        'Failed to delete ${T.toString()} with ID $id',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Gets detailed synchronization information for this model instance.
  ///
  /// This getter provides comprehensive sync status information including
  /// error details, retry scheduling, and operation types from the sync queue.
  ///
  /// Returns a [SyncDetails] object containing:
  /// - lastError: The most recent error message (if any)
  /// - nextRetryAt: When the next retry is scheduled (if any)
  /// - attemptCount: Number of sync attempts made
  /// - status: Current sync status
  /// - operation: Type of pending operation (create, update, delete)
  ///
  /// If there are no sync queue entries for this model, returns
  /// [SyncDetails.synced()].
  Future<SyncDetails> get getSyncDetails async {
    try {
      final database = SynquillStorage.database;

      // Get ALL tasks for this model, including dead ones for getSyncDetails
      final results = await database.customSelect(
        'SELECT * FROM sync_queue_items WHERE model_type = ? AND model_id = ?',
        variables: [
          Variable.withString(T.toString()),
          Variable.withString(id),
        ],
      ).get();

      final tasks = results.map((row) => row.data).toList();

      if (tasks.isEmpty) {
        return const SyncDetails.synced();
      }

      // Get the most recent task (highest ID or latest created_at)
      tasks.sort((a, b) {
        final aCreatedAt = a['created_at'] as int?;
        final bCreatedAt = b['created_at'] as int?;

        if (aCreatedAt != null && bCreatedAt != null) {
          return bCreatedAt.compareTo(aCreatedAt);
        }

        // Fallback to ID comparison
        final aId = a['id'] as int?;
        final bId = b['id'] as int?;

        if (aId != null && bId != null) {
          return bId.compareTo(aId);
        }

        return 0;
      });

      final mostRecentTask = tasks.first;
      return SyncDetails.fromSyncQueueTask(mostRecentTask);
    } catch (e) {
      // If we can't access the sync queue, return synced status
      return const SyncDetails.synced();
    }
  }

  /// Refreshes this model instance by fetching the latest data.
  ///
  /// Returns the refreshed instance if found, or null if the instance
  /// no longer exists.
  ///
  /// Throws [StateError] if no repository is associated with this model
  /// instance.
  ///
  /// Example:
  /// ```dart
  /// final user = await userRepository.findOne('user123');
  /// if (user != null) {
  ///   final refreshedUser = await user.refresh();
  ///   if (refreshedUser != null) {
  ///     // Use the refreshed data
  ///   }
  /// }
  /// ```
  /// Disabled due to potential issues with the current implementation.
  /*
  Future<T?> refresh({
    DataLoadPolicy loadPolicy = DataLoadPolicy.remoteFirst,
    Map<String, dynamic>? extra,
  }) async {
    _log.fine(
      'refresh() called on ${T.toString()} instance with ID $id'
      ' using policy ${loadPolicy.name}',
    );

    try {
      // Get the database instance
      final database = DatabaseProvider.instance;

      // Get repository using RepositoryProvider
      final repository = SynquillRepositoryProvider.getFrom<T>(database);

      final result = await repository.findOne(id, loadPolicy: loadPolicy, 
        extra: extra);

      if (result != null) {
        _log.fine('Successfully refreshed ${T.toString()} with ID $id');
      } else {
        _log.info('${T.toString()} with ID $id no longer exists');
      }

      return result;
    } catch (e, stackTrace) {
      _log.severe(
        'Failed to refresh ${T.toString()} with ID $id',
        e,
        stackTrace,
      );
      rethrow;
    }
  }*/
}
