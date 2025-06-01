part of synquill;

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
  String toString() =>
      'CascadeDeleteRelation(fieldName: $fieldName, '
      'targetType: $targetType, mappedBy: $mappedBy)';
}

/// Global provider for model metadata including cascade delete relationships
///
/// This class follows the same pattern as SyncedRepositoryProvider to provide
/// runtime access to generated model metadata.
class ModelInfoRegistryProvider {
  ModelInfoRegistryProvider._(); // Private constructor to prevent instantiation

  /// Map from model type name to its cascade delete relations
  static final Map<String, List<CascadeDeleteRelation>>
  _cascadeDeleteRelations = {};

  static final _log = () {
    try {
      return SynquillStorage.logger;
    } catch (_) {
      // Fallback to a local logger if SyncedStorage is not initialized
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

  /// Clears all registered model information
  ///
  /// Primarily used for cleaning up state in tests.
  static void reset() {
    _log.info(
      'Resetting ModelInfoRegistryProvider: clearing all model information.',
    );
    _cascadeDeleteRelations.clear();
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
