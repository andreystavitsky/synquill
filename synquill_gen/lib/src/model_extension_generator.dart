// ignore_for_file: deprecated_member_use, depend_on_referenced_packages

part of synquill_gen;

/// Generates model extension methods for loading related objects
class ModelExtensionGenerator {
  /// Generate extension methods for a model
  static String generateModelExtensions(
    ModelInfo model,
    List<ModelInfo> allModels,
  ) {
    final buffer = StringBuffer();

    // Generate ID management mixin for ALL models (this replaces extensions)
    buffer.writeln(_generateIdManagementExtension(model));
    buffer.writeln();

    final className = model.className;

    // Find relation fields that need load methods (field-level annotations)
    final relationFields = model.fields
        .where((field) => field.isOneToMany || field.isManyToOne)
        .toList();

    // Also include class-level relations
    final hasRelations =
        relationFields.isNotEmpty || model.relations.isNotEmpty;

    if (!hasRelations) {
      return buffer.toString(); // Return ID management mixin if no relations
    }

    buffer.writeln('/// Generated extension methods for loading ');
    buffer.writeln(
      '/// related objects for $className',
    );
    buffer.writeln('extension ${className}RelationExtensions on $className {');
    buffer.writeln('  /// Logger for the $className relation extensions.');
    buffer.writeln('  static Logger get _log {');
    buffer.writeln('    try {');
    buffer.writeln('      return SynquillStorage.logger;');
    buffer.writeln('    } catch (_) {');
    buffer.writeln('      return Logger(\'${className}RelationExtensions\');');
    buffer.writeln('    }');
    buffer.writeln('  }');
    buffer.writeln();

    // Generate methods for class-level relations
    for (final relation in model.relations) {
      if (relation.relationType == RelationType.oneToMany) {
        _generateClassLevelOneToManyLoadMethod(buffer, relation, allModels);
        _generateClassLevelOneToManyWatchMethod(buffer, relation, allModels);
      } else if (relation.relationType == RelationType.manyToOne) {
        _generateClassLevelManyToOneLoadMethod(buffer, relation, allModels);
        _generateClassLevelManyToOneWatchMethod(
          buffer,
          relation,
          allModels,
          className,
        );
      }
    }

    // Note: QueryParams merging is now handled by
    // QueryParams.withRequiredFilter() in the core library,
    // so we no longer generate duplicate utility methods

    buffer.writeln('}');
    return buffer.toString();
  }

  /// Generate load method for class-level OneToMany relation
  static void _generateClassLevelOneToManyLoadMethod(
    StringBuffer buffer,
    RelationInfo relation,
    List<ModelInfo> allModels,
  ) {
    final targetClassName = relation.targetType;
    final methodName =
        'load${PluralizationUtils.PascalCasePlural(targetClassName)}';
    final mappedBy = relation.mappedBy;

    if (mappedBy == null) {
      buffer.writeln('  // Skipping $methodName - mappedBy not specified');
      return;
    }

    buffer.writeln(
      '  /// Load related ${PluralizationUtils.PascalCasePlural(targetClassName)} objects',
    );
    buffer.writeln(
      '  /// Uses mappedBy field \'$mappedBy\' in $targetClassName',
    );
    buffer.writeln('  Future<List<$targetClassName>> $methodName({');
    buffer.writeln('    DataLoadPolicy? loadPolicy,');
    buffer.writeln('    Map<String, String>? headers,');
    buffer.writeln('    Map<String, dynamic>? extra,');
    buffer.writeln('    QueryParams? queryParams,');
    buffer.writeln('  }) async {');
    buffer.writeln('    try {');
    buffer.writeln('      final database = DatabaseProvider.instance;');
    buffer.writeln('      final repository = SynquillRepositoryProvider');
    buffer.writeln('          .getFrom<$targetClassName>(database);');
    buffer.writeln('      ');
    buffer.writeln('      // Create required filter for the relation');
    buffer.writeln(
      '      final requiredFilter = '
      '${targetClassName}Fields.$mappedBy.equals(id);',
    );
    buffer.writeln('      ');
    buffer.writeln('      // Merge user queryParams with required filter');
    buffer.writeln(
      '      final mergedQueryParams = QueryParams.withRequiredFilter(',
    );
    buffer.writeln('        queryParams,');
    buffer.writeln('        requiredFilter,');
    buffer.writeln('      );');
    buffer.writeln('      ');
    buffer.writeln('      return await repository.findAll(');
    buffer.writeln(
      '        loadPolicy: loadPolicy ?? DataLoadPolicy.localOnly,',
    );
    buffer.writeln('        queryParams: mergedQueryParams,');
    buffer.writeln('        headers: headers,');
    buffer.writeln('        extra: extra,');
    buffer.writeln('      );');
    buffer.writeln('    } catch (e, stackTrace) {');
    buffer.writeln('      _log.severe(');
    buffer.writeln(
      '        \'Failed to load '
      '${PluralizationUtils.PascalCasePlural(targetClassName)} '
      'for \$runtimeType[\$id]\', e, stackTrace);',
    );
    buffer.writeln('      rethrow;');
    buffer.writeln('    }');
    buffer.writeln('  }');
    buffer.writeln();
  }

  /// Generate watch method for class-level OneToMany relation
  static void _generateClassLevelOneToManyWatchMethod(
    StringBuffer buffer,
    RelationInfo relation,
    List<ModelInfo> allModels,
  ) {
    final targetClassName = relation.targetType;
    final methodName = 'watch'
        '${PluralizationUtils.PascalCasePlural(targetClassName)}';
    final mappedBy = relation.mappedBy;

    if (mappedBy == null) {
      buffer.writeln('  // Skipping $methodName - mappedBy not specified');
      return;
    }

    buffer.writeln(
      '  /// Watch related '
      '${PluralizationUtils.PascalCasePlural(targetClassName)} '
      'objects as a stream',
    );
    buffer.writeln(
      '  /// Uses mappedBy field \'$mappedBy\' in $targetClassName',
    );
    buffer.writeln('  Stream<List<$targetClassName>> $methodName({');
    buffer.writeln('    QueryParams? queryParams,');
    buffer.writeln('  }) {');
    buffer.writeln('    try {');
    buffer.writeln('      final database = DatabaseProvider.instance;');
    buffer.writeln('      final repository = SynquillRepositoryProvider');
    buffer.writeln('          .getFrom<$targetClassName>(database);');
    buffer.writeln('      ');
    buffer.writeln('      // Create required filter for the relation');
    buffer.writeln(
      '      final requiredFilter = '
      '${targetClassName}Fields.$mappedBy.equals(id);',
    );
    buffer.writeln('      ');
    buffer.writeln('      // Merge user queryParams with required filter');
    buffer.writeln(
      '      final mergedQueryParams = QueryParams.withRequiredFilter(',
    );
    buffer.writeln('        queryParams,');
    buffer.writeln('        requiredFilter,');
    buffer.writeln('      );');
    buffer.writeln('      ');
    buffer.writeln('      return repository.watchAll(');
    buffer.writeln('        queryParams: mergedQueryParams,');
    buffer.writeln('      );');
    buffer.writeln('    } catch (e, stackTrace) {');
    buffer.writeln('      _log.severe(');
    buffer.writeln(
      '        \'Failed to watch'
      '${PluralizationUtils.PascalCasePlural(targetClassName)} '
      'for \$runtimeType[\$id]\', e, stackTrace);',
    );
    buffer.writeln('      rethrow;');
    buffer.writeln('    }');
    buffer.writeln('  }');
    buffer.writeln();
  }

  /// Generate load method for class-level ManyToOne relation
  static void _generateClassLevelManyToOneLoadMethod(
    StringBuffer buffer,
    RelationInfo relation,
    List<ModelInfo> allModels,
  ) {
    final targetClassName = relation.targetType;
    final methodName = 'load$targetClassName';
    final foreignKeyColumn =
        relation.foreignKeyColumn ?? '${targetClassName.toLowerCase()}Id';

    buffer.writeln('  /// Load related $targetClassName object');
    buffer.writeln('  /// Uses foreign key field \'$foreignKeyColumn\'');
    buffer.writeln('  Future<$targetClassName?> $methodName({');
    buffer.writeln('    DataLoadPolicy? loadPolicy,');
    buffer.writeln('    Map<String, String>? headers,');
    buffer.writeln('    Map<String, dynamic>? extra,');
    buffer.writeln('  }) async {');
    buffer.writeln('    try {');
    buffer.writeln('      final foreignKey = $foreignKeyColumn;');
    buffer.writeln('      if (foreignKey == null) return null;');
    buffer.writeln('      final database = DatabaseProvider.instance;');
    buffer.writeln('      final repository = SynquillRepositoryProvider');
    buffer.writeln('          .getFrom<$targetClassName>(database);');
    buffer.writeln('      return await repository.findOne(');
    buffer.writeln('        foreignKey.toString(),');
    buffer.writeln(
      '        loadPolicy: loadPolicy ?? DataLoadPolicy.localOnly,',
    );
    buffer.writeln('        headers: headers,');
    buffer.writeln('        extra: extra,');
    buffer.writeln('      );');
    buffer.writeln('    } catch (e, stackTrace) {');
    buffer.writeln('      _log.severe(');
    buffer.writeln(
      '        \'Failed to load $targetClassName for \$runtimeType[\$id]\',',
    );
    buffer.writeln('        e,');
    buffer.writeln('        stackTrace,');
    buffer.writeln('      );');
    buffer.writeln('      rethrow;');
    buffer.writeln('    }');
    buffer.writeln('  }');
    buffer.writeln();
  }

  /// Generate watch method for class-level ManyToOne relation
  static void _generateClassLevelManyToOneWatchMethod(
    StringBuffer buffer,
    RelationInfo relation,
    List<ModelInfo> allModels,
    String sourceClassName,
  ) {
    final targetClassName = relation.targetType;
    final methodName = 'watch$targetClassName';
    final foreignKeyColumn =
        relation.foreignKeyColumn ?? '${targetClassName.toLowerCase()}Id';

    buffer.writeln('  /// Watch related $targetClassName object as a stream');
    buffer.writeln('  /// Uses foreign key field \'$foreignKeyColumn\'');
    buffer.writeln(
      '  /// Automatically switches to new target when foreign key changes',
    );
    buffer.writeln('  Stream<$targetClassName?> $methodName({');
    buffer.writeln('    DataLoadPolicy? loadPolicy,');
    buffer.writeln('    Map<String, String>? headers,');
    buffer.writeln('    Map<String, dynamic>? extra,');
    buffer.writeln('  }) {');
    buffer.writeln('    try {');
    buffer.writeln('      final database = DatabaseProvider.instance;');
    buffer.writeln('      final sourceRepository = SynquillRepositoryProvider');
    buffer.writeln('          .getFrom<$sourceClassName>(database);');
    buffer.writeln('      final targetRepository = SynquillRepositoryProvider');
    buffer.writeln('          .getFrom<$targetClassName>(database);');
    buffer.writeln();
    buffer.writeln(
      '      // Watch the source object for changes in foreign key',
    );
    buffer.writeln('      return sourceRepository.watchOne(id)');
    buffer.writeln('          .switchMap((sourceObject) {');
    buffer.writeln('        if (sourceObject == null) {');
    buffer.writeln('          return Stream.value(null);');
    buffer.writeln('        }');
    buffer.writeln();
    buffer
        .writeln('        final foreignKey = sourceObject.$foreignKeyColumn;');
    buffer.writeln('        if (foreignKey == null) {');
    buffer.writeln('          return Stream.value(null);');
    buffer.writeln('        }');
    buffer.writeln();
    buffer.writeln('        // Switch to watching the target object');
    buffer.writeln('        return targetRepository.watchOne(');
    buffer.writeln('          foreignKey.toString(),');
    buffer.writeln(
      '          loadPolicy: loadPolicy ?? DataLoadPolicy.localOnly,',
    );
    buffer.writeln('        );');
    buffer.writeln('      });');
    buffer.writeln('    } catch (e, stackTrace) {');
    buffer.writeln('      _log.severe(');
    buffer.writeln(
      '        \'Failed to watch $targetClassName for '
      '$sourceClassName[\$id]\',',
    );
    buffer.writeln('        e,');
    buffer.writeln('        stackTrace,');
    buffer.writeln('      );');
    buffer.writeln('      rethrow;');
    buffer.writeln('    }');
    buffer.writeln('  }');
    buffer.writeln();
  }

  /// Generate ID management mixin for all models
  static String _generateIdManagementExtension(ModelInfo model) {
    final buffer = StringBuffer();
    final className = model.className;
    final mixinName = '${className}IdManagement';

    buffer.writeln('/// Generated ID management extension for $className');
    buffer.writeln('extension $mixinName on $className {');

    // Generate the main properties based on ID generation strategy
    buffer.writeln('  /// Whether this model uses server-generated IDs');
    buffer.writeln('  bool get \$usesServerGeneratedId => ');
    buffer.writeln('      ${model.usesServerGeneratedId};');

    // Generate $replaceIdEverywhere method for all models
    buffer.writeln('');
    buffer.writeln('  /// Create a new model instance with a different ID');
    buffer.writeln('  /// This is used during ID negotiation when server '
        'assigns a different ID');
    buffer.writeln('  $className \$replaceIdEverywhere(String newId) {');
    buffer.writeln('    final json = toJson();');
    buffer.writeln('    json[\'id\'] = newId;');
    buffer.writeln('    return fromJson(json);');
    buffer.writeln('  }');

    // For server-generated ID models, add helper methods
    if (model.usesServerGeneratedId) {
      buffer.writeln('');
      buffer.writeln('  /// Whether this model currently has a temporary ID');
      buffer.writeln('  /// Note: Use repository.hasTemporaryId(model) for '
          'actual status');
      buffer.writeln('  bool get \$hasTemporaryId => false;');

      buffer.writeln('');
      buffer.writeln('  /// Get temporary client ID for this model');
      buffer.writeln('  /// Note: Use repository.getTemporaryClientId(model) '
          'for actual value');
      buffer.writeln('  String? get \$temporaryClientId => null;');
    } else {
      buffer.writeln('');
      buffer.writeln('  /// Whether this model currently has a temporary ID ');
      buffer.writeln('  /// (always false for client-generated IDs)');
      buffer.writeln('  bool get \$hasTemporaryId => false;');

      buffer.writeln('');
      buffer.writeln('  /// Get temporary client ID for this model ');
      buffer.writeln('  /// (always null for client-generated IDs)');
      buffer.writeln('  String? get \$temporaryClientId => null;');
    }

    if (model.usesServerGeneratedId) {
      buffer.writeln('');
      buffer
          .writeln('  /// Note: Use repository.hasTemporaryId(model) to check '
              'temporary ID status');
      buffer.writeln(
          '  /// Note: Use repository.getTemporaryClientId(model) to get '
          'temporary client ID');
    }

    buffer.writeln('}');
    return buffer.toString();
  }
}
