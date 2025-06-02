part of synquill_gen;

/// Generates concrete repository implementations that extend
/// SynquillRepositoryBase
class RepositoryGenerator {
  /// Generates a concrete adapter class for a model
  static String generateAdapterClass(ModelInfo model) {
    final className = model.className;
    final adapterClassName = '_${className}Adapter';
    final adapters = model.adapters;

    if (adapters == null || adapters.isEmpty) {
      // No adapters specified, generate a basic adapter that throws
      return '''
/// Generated adapter for $className - no adapters specified
class $adapterClassName extends BasicApiAdapter<$className> {
  @override
  Uri get baseUrl => 
    throw UnimplementedError('baseUrl not configured for $className');

  @override
  $className fromJson(Map<String, dynamic> json) {
    // Try to call fromJson if it exists, otherwise throw
    try {
      return $className.fromJson(json);
    } on NoSuchMethodError {
      throw UnimplementedError('fromJson not implemented for $className');
    }
  }

  @override
  Map<String, dynamic> toJson($className model) {
    // Try to call toJson if it exists, otherwise throw
    try {
      return model.toJson();
    } on NoSuchMethodError {
      throw UnimplementedError('toJson not implemented for $className');
    }
  }
}
''';
    }

    // Extract adapter type names
    final adapterNames =
        adapters.map((adapter) => adapter.adapterName).toList();

    // Generate class with mixins
    // Model-specific adapters (e.g., TodoApiAdapter) don't need type parameters
    // because they're already defined for a specific type
    // Generic adapters (e.g., BaseJsonApiAdapter<T>) need type parameters
    final mixinParts =
        adapterNames.map((name) {
          // Check if this is a generic adapter by looking at the isGeneric flag
          final adapter = adapters.firstWhere((a) => a.adapterName == name);
          if (adapter.isGeneric) {
            // Generic adapters need type parameters
            return '$name<$className>';
          } else {
            // Model-specific adapters already have their type constraint
            return name;
          }
        }).toList();

    final mixinClause =
        mixinParts.isNotEmpty ? ' with ${mixinParts.join(', ')}' : '';

    return '''
/// Generated adapter for $className
class $adapterClassName extends BasicApiAdapter<$className>
    $mixinClause {
  @override
  $className fromJson(Map<String, dynamic> json) {
    // Try to call fromJson if it exists, otherwise throw
    try {
      return $className.fromJson(json);
    } on NoSuchMethodError {
      throw UnimplementedError('fromJson not implemented for $className');
    }
  }

  @override
  Map<String, dynamic> toJson($className model) {
    // Try to call toJson if it exists, otherwise throw
    try {
      return model.toJson();
    } on NoSuchMethodError {
      throw UnimplementedError('toJson not implemented for $className');
    }
  }
}
''';
  }

  /// Generates a concrete repository class for a model
  static String generateRepositoryClass(ModelInfo model) {
    final className = model.className;
    final repositoryName = '${className}Repository';
    final daoName = '${className}Dao';

    // Generate apiAdapter getter based on whether adapters are defined
    final apiAdapterGetter =
        (model.adapters == null || model.adapters!.isEmpty)
            ? '''  @override
  ApiAdapterBase<$className> get apiAdapter {
    throw UnimplementedError('No adapters specified for $className');
  }'''
            : '''  @override
  ApiAdapterBase<$className> get apiAdapter {
    return _${className}Adapter();
  }''';

    return '''
/// Concrete repository implementation for $className
class $repositoryName extends SynquillRepositoryBase<$className> 
    with RepositoryHelpersMixin<$className> {
  late final $daoName _dao;
  static Logger get _log {
    try {
      return SynquillStorage.logger;
    } catch (_) {
      return Logger('$repositoryName');
    }
  }

  /// Creates a new $className repository instance
  /// 
  /// [db] The database instance to use for data operations
  $repositoryName(super.db) {
    _dao = $daoName(db as SynquillDatabase);
  }

  @override
  DatabaseAccessor get dao => _dao;

$apiAdapterGetter

  @override
  Future<$className?> fetchFromRemote(String id, {
      QueryParams? queryParams, 
      Map<String, String>? headers, 
      Map<String, dynamic>? extra
    }) async {
    try {
      final result = await apiAdapter.findOne(id, queryParams: queryParams,
        extra: extra);
      _log.fine('fetchFromRemote() for $className successful: '
        'found item with id \$id');
      return result;
    } on ApiExceptionNotFound {
      _log.fine('fetchFromRemote() for $className: item with id \$id '
        'not found in remote API');
      // Rethrow the exception so SynquillRepositoryBase can remove the 
      // item from local storage
      rethrow;
    } on ApiExceptionGone {
      _log.fine('fetchFromRemote() for $className: item with id \$id '
        'is gone from remote API');
      // Rethrow the exception so SynquillRepositoryBase can remove the 
      // item from local storage
      rethrow;
    } catch (e, stackTrace) {
      _log.warning('fetchFromRemote() for $className failed '
        'for id \$id', e, stackTrace);
      rethrow;
    }
  }

  @override
  Future<List<$className>> fetchAllFromRemote({
      QueryParams? queryParams, 
      Map<String, String>? headers, 
      Map<String, dynamic>? extra
    }) async {
    try {
      final result = await apiAdapter.findAll(
        queryParams: queryParams, extra: extra
      );
      _log.fine('fetchAllFromRemote() for $className successful: '
        'found \${result.length} items');
      return result;
    } catch (e, stackTrace) {
      _log.warning('fetchAllFromRemote() for $className failed', e, stackTrace);
      rethrow;
    }
  }
}
''';
  }

  /// Generates repository registration calls for SynquillRepositoryProvider
  static String generateRepositoryRegistrations(List<ModelInfo> models) {
    final buffer = StringBuffer();

    buffer.writeln(
      '/// Register all repository factories with SynquillRepositoryProvider',
    );
    buffer.writeln('void registerAllRepositories() {');

    for (final model in models) {
      final className = model.className;
      final repositoryName = '${className}Repository';

      buffer.writeln('  SynquillRepositoryProvider.register<$className>(');
      buffer.writeln('    (db) => $repositoryName(db),');
      buffer.writeln('  );');
    }

    buffer.writeln('}');
    buffer.writeln();

    // Generate dependency registration method
    buffer.writeln(
      '/// Register all model dependencies for hierarchical sync ordering',
    );
    buffer.writeln('void registerModelDependencies() {');

    for (final model in models) {
      final className = model.className;

      // Find all @ManyToOne relationships in this model
      final manyToOneFields = model.fields.where((field) => field.isManyToOne);

      for (final field in manyToOneFields) {
        if (field.relationTarget != null) {
          buffer.writeln(
            '  // $className depends on ${field.relationTarget} via '
            '${field.name}',
          );
          buffer.writeln(
            '  DependencyResolver.registerDependency(\'$className\', '
            '\'${field.relationTarget}\');',
          );
        }
      }
    }

    buffer.writeln('}');
    buffer.writeln();

    // Add initialization function
    buffer.writeln('/// Initialize the synced storage system');
    buffer.writeln(
      '/// This function should be accessible from background isolates',
    );
    buffer.writeln("@pragma('vm:entry-point')");
    buffer.writeln(
      'void initializeSynquillStorage(GeneratedDatabase database) {',
    );
    buffer.writeln('  // Set up global database access');
    buffer.writeln('  DatabaseProvider.setInstance(database);');
    buffer.writeln('  ');
    buffer.writeln('  // Register all repository factories');
    buffer.writeln('  registerAllRepositories();');
    buffer.writeln('  ');
    buffer.writeln('  // Register model dependencies for hierarchical sync');
    buffer.writeln('  registerModelDependencies();');
    buffer.writeln('  ');
    buffer.writeln('  // Register model cascade delete relations');
    buffer.writeln('  registerModelCascadeDeleteRelations();');
    buffer.writeln('  ');
    buffer.writeln('}');

    return buffer.toString();
  }

  /// Generates convenient repository access extension for SynquillStorage
  static String generateSynquillStorageExtension(List<ModelInfo> models) {
    final buffer = StringBuffer();

    buffer.writeln(
      '/// Extension providing convenient repository access on SynquillStorage',
    );
    buffer.writeln(
      'extension SynquillStorageRepositories on SynquillStorage {',
    );

    // Generate getter for each model
    for (final model in models) {
      final className = model.className;
      final repositoryName = '${className}Repository';
      final propertyName = BuilderUtils.toCamelCasePlural(className);

      buffer.writeln('  /// Access repository for $className models');
      buffer.writeln('  $repositoryName get $propertyName {');
      buffer.writeln(
        '    return getRepository<$className>() as $repositoryName;',
      );
      buffer.writeln('  }');
      buffer.writeln();
    }

    buffer.writeln('}');
    buffer.writeln();

    return buffer.toString();
  }
}
