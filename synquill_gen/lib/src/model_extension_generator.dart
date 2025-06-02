// ignore_for_file: deprecated_member_use, depend_on_referenced_packages

part of synquill_gen;

/// Generates model extension methods for loading related objects
class ModelExtensionGenerator {
  /// Generate the base relation helper mixin
  static String generateRelationHelperMixin() {
    return '''
/// Base mixin for relation loading operations to reduce code duplication
mixin RelationHelperMixin {
  /// Model ID for relation operations
  String get id;
  
  /// Load related objects using OneToMany relation
  Future<List<T>> loadOneToManyRelation<T extends SynquillDataModel<T>>({
    required String mappedByField,
    required String targetFieldsClass,
    DataLoadPolicy? loadPolicy,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    try {
      final database = DatabaseProvider.instance;
      final repository = SynquillRepositoryProvider.getFrom<T>(database);
      
      // Create filter dynamically using reflection or field selector
      final queryParams = QueryParams(
        filters: [
          FieldFilter(
            field: mappedByField,
            operator: FilterOperator.equals,
            value: SingleValue(id),
          ),
        ],
      );
      
      return await repository.findAll(
        loadPolicy: loadPolicy ?? DataLoadPolicy.localOnly,
        queryParams: queryParams,
        headers: headers,
        extra: extra,
      );
    } catch (e) {
      rethrow;
    }
  }
  
  /// Watch related objects using OneToMany relation
  Stream<List<T>> watchOneToManyRelation<T extends SynquillDataModel<T>>({
    required String mappedByField,
    required String targetFieldsClass,
  }) {
    try {
      final database = DatabaseProvider.instance;
      final repository = SynquillRepositoryProvider.getFrom<T>(database);
      
      final queryParams = QueryParams(
        filters: [
          FieldFilter(
            field: mappedByField,
            operator: FilterOperator.equals,
            value: SingleValue(id),
          ),
        ],
      );
      
      return repository.watchAll(queryParams: queryParams);
    } catch (e) {
      rethrow;
    }
  }
  
  /// Load related object using ManyToOne relation
  Future<T?> loadManyToOneRelation<T extends SynquillDataModel<T>>({
    required String foreignKeyValue,
    DataLoadPolicy? loadPolicy,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    try {
      final database = DatabaseProvider.instance;
      final repository = SynquillRepositoryProvider.getFrom<T>(database);
      
      return await repository.findOne(
        foreignKeyValue,
        loadPolicy: loadPolicy ?? DataLoadPolicy.localOnly,
        headers: headers,
        extra: extra,
      );
    } catch (e) {
      rethrow;
    }
  }
  
  /// Watch related object using ManyToOne relation
  Stream<T?> watchManyToOneRelation<T extends SynquillDataModel<T>, S extends SynquillDataModel<S>>({
    required String foreignKeyField,
  }) {
    try {
      final database = DatabaseProvider.instance;
      final sourceRepository = SynquillRepositoryProvider.getFrom<S>(database);
      final targetRepository = SynquillRepositoryProvider.getFrom<T>(database);
      
      return sourceRepository.watchOne(id).switchMap((sourceObject) {
        final foreignKey = _getForeignKeyValue(sourceObject, foreignKeyField);
        return foreignKey == null
            ? Stream.value(null)
            : targetRepository.watchOne(foreignKey);
      });
    } catch (e) {
      rethrow;
    }
  }
  
  /// Helper method to get foreign key value using reflection
  dynamic _getForeignKeyValue(dynamic object, String fieldName) {
    // Simple reflection-like approach
    // In practice, this would need proper implementation
    try {
      return object?.toJson()[fieldName];
    } catch (e) {
      return null;
    }
  }
}

''';
  }

  /// Generate extension methods for a model
  static String generateModelExtensions(
    ModelInfo model,
    List<ModelInfo> allModels,
  ) {
    final buffer = StringBuffer();
    final className = model.className;

    // Find relation fields that need load methods (field-level annotations)
    final relationFields =
        model.fields
            .where((field) => field.isOneToMany || field.isManyToOne)
            .toList();

    // Also include class-level relations
    final hasRelations =
        relationFields.isNotEmpty || model.relations.isNotEmpty;

    if (!hasRelations) {
      return ''; // No relations, no extensions needed
    }

    buffer.writeln(
      '/// Generated extension methods for loading related objects for $className',
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

    for (final field in relationFields) {
      if (field.isOneToMany) {
        _generateOneToManyLoadMethod(buffer, field, allModels);
        _generateOneToManyWatchMethod(buffer, field, allModels);
      } else if (field.isManyToOne) {
        _generateManyToOneLoadMethod(buffer, field, allModels);
        _generateManyToOneWatchMethod(buffer, field, allModels);
      }
    }

    // Generate methods for class-level relations
    for (final relation in model.relations) {
      if (relation.relationType == RelationType.oneToMany) {
        _generateClassLevelOneToManyLoadMethod(buffer, relation, allModels);
        _generateClassLevelOneToManyWatchMethod(buffer, relation, allModels);
      } else if (relation.relationType == RelationType.manyToOne) {
        _generateClassLevelManyToOneLoadMethod(buffer, relation, allModels);
        _generateClassLevelManyToOneWatchMethod(buffer, relation, allModels);
      }
    }

    buffer.writeln('}');
    return buffer.toString();
  }

  /// Generate load method for @OneToMany relation
  static void _generateOneToManyLoadMethod(
    StringBuffer buffer,
    FieldInfo field,
    List<ModelInfo> allModels,
  ) {
    final targetClassName = field.relationTarget!;
    final methodName = 'load${_pluralize(targetClassName)}';
    final mappedBy = field.mappedBy;

    if (mappedBy == null) {
      buffer.writeln('  // Skipping $methodName - mappedBy not specified');
      return;
    }

    buffer.writeln(
      '  /// Load related ${_pluralize(targetClassName).toLowerCase()} objects',
    );
    buffer.writeln(
      '  /// Uses mappedBy field \'$mappedBy\' in $targetClassName',
    );
    buffer.writeln('  Future<List<$targetClassName>> $methodName({');
    buffer.writeln('    DataLoadPolicy? loadPolicy,');
    buffer.writeln('    Map<String, String>? headers,');
    buffer.writeln('    Map<String, dynamic>? extra,');
    buffer.writeln('  }) async {');
    buffer.writeln('    try {');
    buffer.writeln('      final database = DatabaseProvider.instance;');
    buffer.writeln('      final repository = SynquillRepositoryProvider');
    buffer.writeln('          .getFrom<$targetClassName>(database);');
    buffer.writeln('      final queryParams = QueryParams(');
    buffer.writeln('        filters: [');
    buffer.writeln('          ${targetClassName}Fields.$mappedBy.equals(id),');
    buffer.writeln('        ],');
    buffer.writeln('      );');
    buffer.writeln('      return await repository.findAll(');
    buffer.writeln(
      '        loadPolicy: loadPolicy ?? DataLoadPolicy.localOnly,',
    );
    buffer.writeln('        queryParams: queryParams,');
    buffer.writeln('        headers: headers,');
    buffer.writeln('        extra: extra,');
    buffer.writeln('      );');
    buffer.writeln('    } catch (e, stackTrace) {');
    buffer.writeln('      _log.severe(');
    buffer.writeln(
      '        \'Failed to load ${_pluralize(targetClassName).toLowerCase()} '
      'for \$runtimeType[\$id]\', e, stackTrace);',
    );
    buffer.writeln('      rethrow;');
    buffer.writeln('    }');
    buffer.writeln('  }');
    buffer.writeln();
  }

  /// Generate watch method for @OneToMany relation
  static void _generateOneToManyWatchMethod(
    StringBuffer buffer,
    FieldInfo field,
    List<ModelInfo> allModels,
  ) {
    final targetClassName = field.relationTarget!;
    final methodName = 'watch${_pluralize(targetClassName)}';
    final mappedBy = field.mappedBy;

    if (mappedBy == null) {
      buffer.writeln('  // Skipping $methodName - mappedBy not specified');
      return;
    }

    buffer.writeln(
      '  /// Watch related ${_pluralize(targetClassName).toLowerCase()} objects as a stream',
    );
    buffer.writeln(
      '  /// Uses mappedBy field \'$mappedBy\' in $targetClassName',
    );
    buffer.writeln('  Stream<List<$targetClassName>> $methodName() {');
    buffer.writeln('    try {');
    buffer.writeln('      final database = DatabaseProvider.instance;');
    buffer.writeln('      final repository = SynquillRepositoryProvider');
    buffer.writeln('          .getFrom<$targetClassName>(database);');
    buffer.writeln('      final queryParams = QueryParams(');
    buffer.writeln('        filters: [');
    buffer.writeln('          ${targetClassName}Fields.$mappedBy.equals(id),');
    buffer.writeln('        ],');
    buffer.writeln('      );');
    buffer.writeln('      return repository.watchAll(');
    buffer.writeln('        queryParams: queryParams,');
    buffer.writeln('      );');
    buffer.writeln('    } catch (e, stackTrace) {');
    buffer.writeln('      _log.severe(');
    buffer.writeln(
      '        \'Failed to watch ${_pluralize(targetClassName).toLowerCase()} '
      'for \$runtimeType[\$id]\',',
    );
    buffer.writeln('        e,');
    buffer.writeln('        stackTrace,');
    buffer.writeln('      );');
    buffer.writeln('      rethrow;');
    buffer.writeln('    }');
    buffer.writeln('  }');
    buffer.writeln();
  }

  /// Generate load method for @ManyToOne relation
  static void _generateManyToOneLoadMethod(
    StringBuffer buffer,
    FieldInfo field,
    List<ModelInfo> allModels,
  ) {
    final targetClassName = field.relationTarget!;
    final methodName = 'load$targetClassName';
    final foreignKeyColumn = field.foreignKeyColumn;

    if (foreignKeyColumn == null) {
      buffer.writeln(
        '  // Skipping $methodName - foreignKeyColumn not specified',
      );
      return;
    }

    // The foreign key field should be the current field itself (like userId)
    final foreignKeyFieldName = field.name; // This is 'userId' in Todo model

    buffer.writeln('  /// Load related $targetClassName object');
    buffer.writeln('  /// Uses foreign key \'$foreignKeyFieldName\'');
    buffer.writeln('  Future<$targetClassName?> $methodName({');
    buffer.writeln('    DataLoadPolicy? loadPolicy,');
    buffer.writeln('    Map<String, String>? headers,');
    buffer.writeln('    Map<String, dynamic>? extra,');
    buffer.writeln('  }) async {');
    buffer.writeln('    try {');
    buffer.writeln('      final database = DatabaseProvider.instance;');
    buffer.writeln('      final repository = SynquillRepositoryProvider');
    buffer.writeln('          .getFrom<$targetClassName>(database);');
    buffer.writeln('      return await repository.findOne(');
    buffer.writeln('        $foreignKeyFieldName, // Foreign key value');
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

  /// Generate watch method for @ManyToOne relation
  static void _generateManyToOneWatchMethod(
    StringBuffer buffer,
    FieldInfo field,
    List<ModelInfo> allModels,
  ) {
    final targetClassName = field.relationTarget!;
    final methodName = 'watch$targetClassName';
    final foreignKeyColumn = field.foreignKeyColumn;

    if (foreignKeyColumn == null) {
      buffer.writeln(
        '  // Skipping $methodName - foreignKeyColumn not specified',
      );
      return;
    }

    // The foreign key field should be the current field itself (like userId)
    final foreignKeyFieldName = field.name; // This is 'userId' in Todo model

    // Find the source model info to get the class name
    final sourceClassName =
        allModels.firstWhere((model) => model.fields.contains(field)).className;

    buffer.writeln('  /// Watch related $targetClassName object as a stream');
    buffer.writeln('  /// Uses foreign key \'$foreignKeyFieldName\'');
    buffer.writeln('  /// Stream updates when the foreign key changes');
    buffer.writeln('  Stream<$targetClassName?> $methodName() {');
    buffer.writeln('    try {');
    buffer.writeln('      final database = DatabaseProvider.instance;');
    buffer.writeln('      final sourceRepository = SynquillRepositoryProvider');
    buffer.writeln('          .getFrom<$sourceClassName>(database);');
    buffer.writeln('      final targetRepository = SynquillRepositoryProvider');
    buffer.writeln('          .getFrom<$targetClassName>(database);');
    buffer.writeln(
      '      return sourceRepository.watchOne(id).switchMap((sourceObject) {',
    );
    buffer.writeln(
      '        final foreignKey = sourceObject?.$foreignKeyFieldName;',
    );
    buffer.writeln('        return foreignKey == null');
    buffer.writeln('            ? Stream.value(null)');
    buffer.writeln('            : targetRepository.watchOne(foreignKey);');
    buffer.writeln('      });');
    buffer.writeln('    } catch (e, stackTrace) {');
    buffer.writeln('      _log.severe(');
    buffer.writeln(
      '        \'Failed to watch $targetClassName for \$runtimeType[\$id]\',',
    );
    buffer.writeln('        e,');
    buffer.writeln('        stackTrace,');
    buffer.writeln('      );');
    buffer.writeln('      rethrow;');
    buffer.writeln('    }');
    buffer.writeln('  }');
    buffer.writeln();
  }

  /// Generate load method for class-level OneToMany relation
  static void _generateClassLevelOneToManyLoadMethod(
    StringBuffer buffer,
    RelationInfo relation,
    List<ModelInfo> allModels,
  ) {
    final targetClassName = relation.targetType;
    final methodName = 'load${_pluralize(targetClassName)}';
    final mappedBy = relation.mappedBy;

    if (mappedBy == null) {
      buffer.writeln('  // Skipping $methodName - mappedBy not specified');
      return;
    }

    buffer.writeln(
      '  /// Load related ${_pluralize(targetClassName).toLowerCase()} objects',
    );
    buffer.writeln(
      '  /// Uses mappedBy field \'$mappedBy\' in $targetClassName',
    );
    buffer.writeln('  Future<List<$targetClassName>> $methodName({');
    buffer.writeln('    DataLoadPolicy? loadPolicy,');
    buffer.writeln('    Map<String, String>? headers,');
    buffer.writeln('    Map<String, dynamic>? extra,');
    buffer.writeln('  }) async {');
    buffer.writeln('    try {');
    buffer.writeln('      final database = DatabaseProvider.instance;');
    buffer.writeln('      final repository = SynquillRepositoryProvider');
    buffer.writeln('          .getFrom<$targetClassName>(database);');
    buffer.writeln('      final queryParams = QueryParams(');
    buffer.writeln('        filters: [');
    buffer.writeln('          ${targetClassName}Fields.$mappedBy.equals(id),');
    buffer.writeln('        ],');
    buffer.writeln('      );');
    buffer.writeln('      return await repository.findAll(');
    buffer.writeln(
      '        loadPolicy: loadPolicy ?? DataLoadPolicy.localOnly,',
    );
    buffer.writeln('        queryParams: queryParams,');
    buffer.writeln('        headers: headers,');
    buffer.writeln('        extra: extra,');
    buffer.writeln('      );');
    buffer.writeln('    } catch (e, stackTrace) {');
    buffer.writeln('      _log.severe(');
    buffer.writeln(
      '        \'Failed to load ${_pluralize(targetClassName).toLowerCase()} '
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
    final methodName = 'watch${_pluralize(targetClassName)}';
    final mappedBy = relation.mappedBy;

    if (mappedBy == null) {
      buffer.writeln('  // Skipping $methodName - mappedBy not specified');
      return;
    }

    buffer.writeln(
      '  /// Watch related ${_pluralize(targetClassName).toLowerCase()} objects as a stream',
    );
    buffer.writeln(
      '  /// Uses mappedBy field \'$mappedBy\' in $targetClassName',
    );
    buffer.writeln('  Stream<List<$targetClassName>> $methodName({');
    buffer.writeln('    DataLoadPolicy? loadPolicy,');
    buffer.writeln('    Map<String, String>? headers,');
    buffer.writeln('    Map<String, dynamic>? extra,');
    buffer.writeln('  }) {');
    buffer.writeln('    try {');
    buffer.writeln('      final database = DatabaseProvider.instance;');
    buffer.writeln('      final repository = SynquillRepositoryProvider');
    buffer.writeln('          .getFrom<$targetClassName>(database);');
    buffer.writeln('      final queryParams = QueryParams(');
    buffer.writeln('        filters: [');
    buffer.writeln('          ${targetClassName}Fields.$mappedBy.equals(id),');
    buffer.writeln('        ],');
    buffer.writeln('      );');
    buffer.writeln('      return repository.watchAll(');
    buffer.writeln('        queryParams: queryParams,');
    buffer.writeln('      );');
    buffer.writeln('    } catch (e, stackTrace) {');
    buffer.writeln('      _log.severe(');
    buffer.writeln(
      '        \'Failed to watch ${_pluralize(targetClassName).toLowerCase()} '
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
    buffer.writeln('      final foreignKey = toJson()[\'$foreignKeyColumn\'];');
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
  ) {
    final targetClassName = relation.targetType;
    final methodName = 'watch$targetClassName';
    final foreignKeyColumn =
        relation.foreignKeyColumn ?? '${targetClassName.toLowerCase()}Id';

    buffer.writeln('  /// Watch related $targetClassName object as a stream');
    buffer.writeln('  /// Uses foreign key field \'$foreignKeyColumn\'');
    buffer.writeln('  Stream<$targetClassName?> $methodName({');
    buffer.writeln('    DataLoadPolicy? loadPolicy,');
    buffer.writeln('    Map<String, String>? headers,');
    buffer.writeln('    Map<String, dynamic>? extra,');
    buffer.writeln('  }) {');
    buffer.writeln('    try {');
    buffer.writeln('      final foreignKey = toJson()[\'$foreignKeyColumn\'];');
    buffer.writeln('      if (foreignKey == null) {');
    buffer.writeln('        return Stream.value(null);');
    buffer.writeln('      }');
    buffer.writeln('      final database = DatabaseProvider.instance;');
    buffer.writeln('      final repository = SynquillRepositoryProvider');
    buffer.writeln('          .getFrom<$targetClassName>(database);');
    buffer.writeln('      return repository.watchOne(');
    buffer.writeln('        foreignKey.toString(),');
    buffer.writeln(
      '        loadPolicy: loadPolicy ?? DataLoadPolicy.localOnly,',
    );
    buffer.writeln('      );');
    buffer.writeln('    } catch (e, stackTrace) {');
    buffer.writeln('      _log.severe(');
    buffer.writeln(
      '        \'Failed to watch $targetClassName for \$runtimeType[\$id]\',',
    );
    buffer.writeln('        e,');
    buffer.writeln('        stackTrace,');
    buffer.writeln('      );');
    buffer.writeln('      rethrow;');
    buffer.writeln('    }');
    buffer.writeln('  }');
    buffer.writeln();
  }

  /// Simple pluralization helper
  static String _pluralize(String singular) {
    if (singular.endsWith('y')) {
      return '${singular.substring(0, singular.length - 1)}ies';
    } else if (singular.endsWith('s') ||
        singular.endsWith('sh') ||
        singular.endsWith('ch') ||
        singular.endsWith('x') ||
        singular.endsWith('z')) {
      return '${singular}es';
    } else {
      return '${singular}s';
    }
  }
}
