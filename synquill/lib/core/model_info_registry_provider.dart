part of synquill;

/// Represents a foreign key relationship where this model references another
class ForeignKeyRelation {
  /// The field name that contains the foreign key
  final String fieldName;

  /// The target model type name that this field references
  final String targetType;

  /// The table name that contains this foreign key
  final String sourceTable;

  /// Creates a [ForeignKeyRelation] describing a foreign key relationship.
  ///
  /// [fieldName] is the field that contains the foreign key,
  /// [targetType] is the name of the target model type,
  /// and [sourceTable] is the table name containing this foreign key.
  const ForeignKeyRelation({
    required this.fieldName,
    required this.targetType,
    required this.sourceTable,
  });

  @override
  String toString() => 'ForeignKeyRelation(fieldName: $fieldName, '
      'targetType: $targetType, sourceTable: $sourceTable)';
}

/// Represents a cascade delete relationship between models
class CascadeDeleteRelation {
  /// The field name that has the cascade delete relation
  final String fieldName;

  /// The target model type name
  final String targetType;

  /// The field name in the target model that maps back to this model
  final String mappedBy;

  /// Creates a [CascadeDeleteRelation] describing a cascade
  /// delete relationship.
  ///
  /// [fieldName] is the field in the source model,
  /// [targetType] is the name of the target model type,
  /// and [mappedBy] is the field in the target model that maps
  /// back to the source.
  const CascadeDeleteRelation({
    required this.fieldName,
    required this.targetType,
    required this.mappedBy,
  });

  @override
  String toString() => 'CascadeDeleteRelation(fieldName: $fieldName, '
      'targetType: $targetType, mappedBy: $mappedBy)';
}

/// Global provider for model metadata including cascade delete relationships
///
/// This class follows the same pattern as SynquillRepositoryProvider to provide
/// runtime access to generated model metadata.
class ModelInfoRegistryProvider {
  ModelInfoRegistryProvider._(); // Private constructor to prevent instantiation

  /// Map from model type name to its cascade delete relations
  static final Map<String, List<CascadeDeleteRelation>>
      _cascadeDeleteRelations = {};

  /// Map from target model type to all models that reference it
  static final Map<String, List<ForeignKeyRelation>> _foreignKeyRelations = {};

  static final _log = () {
    try {
      return SynquillStorage.logger;
    } catch (_) {
      // Fallback to a local logger if SynquillStorage is not initialized
      return Logger('ModelInfoRegistryProvider');
    }
  }();

  /// Registers cascade delete relations for a model type
  ///
  /// This method is called by generated code during initialization.
  ///
  /// - [modelTypeName]: The string name of the model type (e.g., 'Category')
  /// - [relations]: List of cascade delete relations for this model
  ///
  /// Example:
  /// ```dart
  /// ModelInfoRegistryProvider.registerCascadeDeleteRelations(
  ///   'Category',
  ///   [
  ///     CascadeDeleteRelation(
  ///       fieldName: 'projectIds',
  ///       targetType: 'Project',
  ///       mappedBy: 'categoryId',
  ///     ),
  ///   ],
  /// );
  /// ```
  static void registerCascadeDeleteRelations(
    String modelTypeName,
    List<CascadeDeleteRelation> relations,
  ) {
    _log.fine(
      'Registering ${relations.length} cascade delete relations '
      'for $modelTypeName',
    );
    _cascadeDeleteRelations[modelTypeName] = relations;

    for (final relation in relations) {
      _log.fine(
        'Registered cascade delete: $modelTypeName.${relation.fieldName} -> '
        '${relation.targetType} via ${relation.mappedBy}',
      );
    }
  }

  /// Gets cascade delete relations for a model type
  ///
  /// - [modelTypeName]: The string name of the model type (e.g., 'Category')
  ///
  /// Returns a list of cascade delete relations for the given model type.
  /// Returns an empty list if no cascade delete relations are registered.
  ///
  /// Example:
  /// ```dart
  /// final relations = ModelInfoRegistryProvider
  ///     .getCascadeDeleteRelations('Category');
  /// for (final relation in relations) {
  ///   print('Cascade delete to ${relation.targetType}');
  /// }
  /// ```
  static List<CascadeDeleteRelation> getCascadeDeleteRelations(
    String modelTypeName,
  ) {
    final relations = _cascadeDeleteRelations[modelTypeName] ?? [];
    _log.fine(
      'Retrieved ${relations.length} cascade delete relations '
      'for $modelTypeName',
    );
    return relations;
  }

  /// Gets all registered model types that have cascade delete relations
  ///
  /// Returns a list of model type names that have cascade delete relations
  /// registered. Useful for debugging and introspection.
  static List<String> getModelsWithCascadeDelete() {
    return _cascadeDeleteRelations.keys.toList();
  }

  /// Registers foreign key relations for a target model type
  ///
  /// This method is called by generated code during initialization.
  ///
  /// - [targetModelType]: The model type that is referenced by foreign keys
  /// - [relations]: List of foreign key relations that reference this model
  ///
  /// Example:
  /// ```dart
  /// ModelInfoRegistryProvider.registerForeignKeyRelations(
  ///   'User',
  ///   [
  ///     ForeignKeyRelation(
  ///       fieldName: 'userId',
  ///       targetType: 'User',
  ///       sourceTable: 'posts',
  ///     ),
  ///   ],
  /// );
  /// ```
  static void registerForeignKeyRelations(
    String targetModelType,
    List<ForeignKeyRelation> relations,
  ) {
    _log.fine(
      'Registering ${relations.length} foreign key relations '
      'for target $targetModelType',
    );
    _foreignKeyRelations[targetModelType] = relations;

    for (final relation in relations) {
      _log.fine(
        'Registered foreign key: '
        '${relation.sourceTable}.${relation.fieldName} -> '
        '${relation.targetType}',
      );
    }
  }

  /// Gets all foreign key relations that reference a target model type
  ///
  /// - [targetModelType]: The model type being referenced (e.g., 'User')
  ///
  /// Returns a list of foreign key relations that reference this model type.
  /// Returns an empty list if no foreign key relations are registered.
  ///
  /// Example:
  /// ```dart
  /// final relations = ModelInfoRegistryProvider
  ///     .getForeignKeyRelations('User');
  /// for (final relation in relations) {
  ///   print('Foreign key: ${relation.sourceTable}.${relation.fieldName}');
  /// }
  /// ```
  static List<ForeignKeyRelation> getForeignKeyRelations(
    String targetModelType,
  ) {
    final relations = _foreignKeyRelations[targetModelType] ?? [];
    _log.fine(
      'Retrieved ${relations.length} foreign key relations '
      'for target $targetModelType',
    );
    return relations;
  }

  /// Clears all registered model information
  ///
  /// Primarily used for cleaning up state in tests.
  static void reset() {
    _log.info(
      'Resetting ModelInfoRegistryProvider: clearing all model information.',
    );
    _cascadeDeleteRelations.clear();
    _foreignKeyRelations.clear();
  }

  /// Gets debug information about the current registry state
  ///
  /// Returns a map containing debug information about registered models
  /// and their cascade delete relations.
  static Map<String, dynamic> getDebugInfo() {
    return {
      'totalModels': _cascadeDeleteRelations.length,
      'modelsWithCascadeDelete': _cascadeDeleteRelations.keys.toList(),
      'cascadeDeleteRelations':
          Map<String, List<Map<String, String>>>.fromEntries(
        _cascadeDeleteRelations.entries.map(
          (entry) => MapEntry(
            entry.key,
            entry.value
                .map(
                  (relation) => {
                    'fieldName': relation.fieldName,
                    'targetType': relation.targetType,
                    'mappedBy': relation.mappedBy,
                  },
                )
                .toList(),
          ),
        ),
      ),
    };
  }
}
