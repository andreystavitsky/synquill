part of synquill;

/// Enum representing different data store policies.
enum DataSavePolicy {
  /// Save to local database first, then queue for remote sync
  localFirst,

  /// Save to remote API first, then save to local database on success, and
  /// throw an exception on failure
  remoteFirst,
}

/// Enum representing different data store policies.
enum DataLoadPolicy {
  /// look for data in local database
  localOnly,

  /// look for data in local database first, then load from remote API
  /// in the background
  localThenRemote,

  /// Load from remote API first, then save to local database on success
  remoteFirst,
}

/// Defines a factory function for creating repository instances.
/// The factory takes a [SynquillDatabase] instance and returns a repository
/// of type [SyncedRepositoryBase<M>].
/// [M] is the model type.
typedef RepositoryFactory<M extends SynquillDataModel<M>> =
    SynquillRepositoryBase<M> Function(GeneratedDatabase db);

/// Provides a centralized mechanism for registering and retrieving repository
/// instances.
/// This allows for dependency injection of repositories, primarily for testing
/// and decoupling model logic from concrete repository implementations.
class SynquillRepositoryProvider {
  SynquillRepositoryProvider._();

  static final Map<Type, RepositoryFactory<SynquillDataModel<dynamic>>>
  _factories = {};
  // Cache: Type -> SyncedDatabase instance -> Repository instance
  static final Map<
    Type,
    Map<GeneratedDatabase, SynquillRepositoryBase<SynquillDataModel<dynamic>>>
  >
  _instances = {};
  // Mapping from model type string names to Type objects for runtime lookup
  static final Map<String, Type> _typeNameMapping = {};

  static final _log = Logger('SyncedRepositoryProvider');

  /// Registers a factory function for creating instances of a repository for a
  /// specific model type [M].
  ///
  /// - [M]: The type of the [SynquillDataModel] the repository handles.
  /// - [factory]: A function that takes a [SyncedDatabase] and returns an
  /// instance of `SyncedRepositoryBase<M>`.
  ///
  /// Example:
  /// ```dart
  /// SyncedRepositoryProvider.register<MyModel>((db) => MyRepository(db));
  /// ```
  static void register<M extends SynquillDataModel<M>>(
    RepositoryFactory<M> factory,
  ) {
    _log.fine('Registering repository factory for type $M');
    _factories[M] = factory as RepositoryFactory<SynquillDataModel<dynamic>>;

    // Register type name mapping for runtime lookup
    final typeName = M.toString();
    _typeNameMapping[typeName] = M;
    _log.fine('Registered type name mapping: "$typeName" -> $M');

    // Clear any cached instances for this type, as the factory might have
    // changed.
    _instances.remove(M);
  }

  /// Retrieves a repository instance for the given model type [M] and database
  /// [db].
  ///
  /// If a repository instance for the specific [db] and type [M] has been
  /// created before,
  /// it's returned from a cache. Otherwise, the registered factory is used to
  /// create,
  /// cache, and return a new instance.
  ///
  /// - [M]: The type of the [SynquillDataModel] for which to get the repository
  /// - [db]: The [SyncedDatabase] instance the repository will operate on.
  ///
  /// Throws an [Exception] if no factory is registered for type [M].
  ///
  /// Example:
  /// ```dart
  /// final myRepo = SyncedRepositoryProvider.get<MyModel>(database);
  /// ```
  static SynquillRepositoryBase<M> getFrom<M extends SynquillDataModel<M>>(
    GeneratedDatabase db,
  ) {
    _log.fine('Getting repository for type $M for db#${db.hashCode}');
    final factory = _factories[M];
    if (factory == null) {
      final errorMsg =
          'No repository factory registered for type $M. '
          'Call SyncedRepositoryProvider.register<$M>((db) => YourRepo(db)) '
          'first.';
      _log.severe(errorMsg);
      throw Exception(errorMsg);
    }

    final typeInstances = _instances.putIfAbsent(M, () => {});

    var repo = typeInstances[db];
    if (repo == null) {
      _log.finer(
        'Creating new instance of repository for type $M'
        ' with db#${db.hashCode}',
      );
      repo = factory(db);
      typeInstances[db] = repo;
    } else {
      _log.finer(
        'Returning cached instance of repository for type $M'
        ' with db#${db.hashCode}',
      );
    }
    return repo as SynquillRepositoryBase<M>;
  }

  /// Retrieves a repository instance for the given model type [M] using the
  /// default database from [DatabaseProvider].
  ///
  /// This is a convenience method that uses the global database instance
  /// set via [DatabaseProvider.setInstance] or [initializeSyncedStorage].
  ///
  /// - [M]: The type of the [SynquillDataModel] for which to get the repository
  ///
  /// Throws a [StateError] if no default database has been configured.
  /// Throws an [Exception] if no factory is registered for type [M].
  ///
  /// Example:
  /// ```dart
  /// // After initialization
  /// await initializeSyncedStorage(database);
  ///
  /// // Get repository anywhere without database injection
  /// final myRepo = SyncedRepositoryProvider.getDefault<MyModel>();
  /// ```
  static SynquillRepositoryBase<M> get<M extends SynquillDataModel<M>>() {
    final db = DatabaseProvider.instance; // Will throw if not initialized
    return getFrom<M>(db);
  }

  /// Retrieves a repository instance for the given model type [M] using the
  /// default database, or returns null if no default database is configured.
  ///
  /// This is a null-safe version of [getDefault] that won't throw if the
  /// database hasn't been initialized.
  ///
  /// - [M]: The type of the [SynquillDataModel] for which to get the repository
  ///
  /// Returns null if no default database has been configured.
  /// Throws an [Exception] if no factory is registered for type [M].
  ///
  /// Example:
  /// ```dart
  /// final myRepo = SyncquillRepositoryProvider.tryGetDefault<MyModel>();
  /// if (myRepo != null) {
  ///   // Use repository
  /// } else {
  ///   // Handle case where database isn't initialized
  /// }
  /// ```
  static SynquillRepositoryBase<M>? tryGet<M extends SynquillDataModel<M>>() {
    try {
      final db = DatabaseProvider.instance;
      return getFrom<M>(db);
    } on StateError {
      // Database provider not initialized
      return null;
    }
  }

  /// Retrieves a repository instance by model type string name.
  ///
  /// This method allows lookup of repositories when only the string model type
  /// name is known (e.g., from sync queue operations), using the default
  /// database.
  ///
  /// - [modelTypeName]: The string name of the model type
  ///   (e.g., 'User', 'Todo')
  ///
  /// Returns the repository instance for the given model type, or null if no
  /// repository is registered for that type or if no default database is
  /// configured.
  ///
  /// Example:
  /// ```dart
  /// final userRepo = SyncedRepositoryProvider.getByTypeName('User');
  /// if (userRepo != null) {
  ///   // Use the repository
  /// }
  /// ```
  static SynquillRepositoryBase<SynquillDataModel<dynamic>>? getByTypeName(
    String modelTypeName,
  ) {
    try {
      final db = DatabaseProvider.instance;
      return getByTypeNameFrom(modelTypeName, db);
    } on StateError {
      // Database provider not initialized
      return null;
    }
  }

  /// Retrieves a repository instance by model type string name for a specific
  /// database.
  ///
  /// This method allows lookup of repositories when only the string model type
  /// name is known (e.g., from sync queue operations).
  ///
  /// - [modelTypeName]: The string name of the model type
  ///   (e.g., 'User', 'Todo')
  /// - [db]: The database instance to use
  ///
  /// Returns the repository instance for the given model type, or null if no
  /// repository is registered for that type.
  ///
  /// Example:
  /// ```dart
  /// final userRepo = SyncedRepositoryProvider.getByTypeNameFrom(
  ///   'User',
  ///   database,
  /// );
  /// if (userRepo != null) {
  ///   // Use the repository
  /// }
  /// ```
  static SynquillRepositoryBase<SynquillDataModel<dynamic>>? getByTypeNameFrom(
    String modelTypeName,
    GeneratedDatabase db,
  ) {
    _log.fine('Looking up repository for model type name: "$modelTypeName"');

    // Look up the Type object from the string name
    final modelType = _typeNameMapping[modelTypeName];
    if (modelType == null) {
      _log.fine('No type mapping found for model type name: "$modelTypeName"');
      return null;
    }

    // Get the factory for this type
    final factory = _factories[modelType];
    if (factory == null) {
      _log.warning('No factory registered for type: $modelType');
      return null;
    }

    // Get or create repository instance
    final typeInstances = _instances.putIfAbsent(modelType, () => {});
    var repo = typeInstances[db];
    if (repo == null) {
      _log.finer(
        'Creating new repository instance for type $modelType '
        'with db#${db.hashCode}',
      );
      repo = factory(db);
      typeInstances[db] = repo;
    } else {
      _log.finer(
        'Returning cached repository instance for type $modelType '
        'with db#${db.hashCode}',
      );
    }

    return repo;
  }

  /// Clears all registered factories and cached repository instances.
  /// Primarily used for cleaning up state in tests.
  static void reset() {
    _log.info(
      'Resetting SyncedRepositoryProvider: clearing all factories and '
      'instances.',
    );
    _factories.clear();
    _instances.clear();
    _typeNameMapping.clear();
  }
}
