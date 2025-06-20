part of synquill;

/// Function type for getting column name using DAO's getColumnForField method
typedef GetColumnForFieldFunction = String? Function(
  String tableName,
  String fieldName,
);

/// Service for updating foreign key references when model IDs change.
///
/// This service handles the complex task of updating all foreign key references
/// in related models when a primary model's ID changes, typically during
/// server ID negotiation for models with server-generated IDs.
class ForeignKeyUpdateService {
  /// The database instance.
  final GeneratedDatabase _db;

  /// Function to get table info for proper column name resolution
  final Set<TableInfo<Table, dynamic>>? Function(String tableName)
      _getTableInfo;

  /// Logger instance for this service
  static Logger get _log {
    try {
      return SynquillStorage.logger;
    } catch (_) {
      return Logger('ForeignKeyUpdateService');
    }
  }

  /// Creates a new [ForeignKeyUpdateService] instance.
  ForeignKeyUpdateService(
    this._db,
    this._getTableInfo,
  );

  /// Updates all foreign key references when a model's ID changes.
  ///
  /// This method finds all foreign key fields that reference the changed model
  /// and updates them to point to the new ID. This is typically called during
  /// server ID negotiation when a temporary ID is replaced with a server ID.
  ///
  /// Important: This method should be called within a database transaction
  /// to ensure consistency.
  ///
  /// - [oldId]: The old ID that was changed
  /// - [newId]: The new ID assigned by the server
  /// - [modelType]: The type of model whose ID was changed
  Future<void> updateForeignKeyReferences(
    String oldId,
    String newId,
    String modelType,
  ) async {
    try {
      // Get all foreign key relations that reference this model type
      final foreignKeyRelations =
          ModelInfoRegistryProvider.getForeignKeyRelations(modelType);

      // Deduplicate relations to avoid multiple updates to the same field
      final deduplicatedRelations = <ForeignKeyRelation>[];
      final seenRelations = <String>{};

      for (final relation in foreignKeyRelations) {
        final key = '${relation.sourceTable}.${relation.fieldName}';
        if (!seenRelations.contains(key)) {
          deduplicatedRelations.add(relation);
          seenRelations.add(key);
        }
      }

      if (deduplicatedRelations.isEmpty) {
        _log.fine('No foreign key relations found for $modelType');
        return;
      }

      _log.info(
        'Updating ${deduplicatedRelations.length} foreign key references '
        'for $modelType: $oldId -> $newId',
      );

      // Update each foreign key reference using appropriate DAO
      for (final relation in deduplicatedRelations) {
        await _updateSingleForeignKeyReference(
          relation,
          oldId,
          newId,
          modelType,
        );
      }

      _log.info(
        'Completed foreign key reference updates for $modelType',
      );
    } catch (e, stackTrace) {
      _log.severe(
        'Error updating foreign key references for '
        '$modelType: $oldId -> $newId',
        e,
        stackTrace,
      );
      // Don't rethrow - we want the main ID replacement to succeed
      // even if foreign key updates fail
    }
  }

  /// Updates a single foreign key reference using the appropriate DAO.
  Future<void> _updateSingleForeignKeyReference(
    ForeignKeyRelation relation,
    String oldId,
    String newId,
    String modelType,
  ) async {
    final sourceTable = relation.sourceTable;
    final foreignKeyField = relation.fieldName;

    try {
      // Get proper column name from Drift table info

      final relationColumnName =
          PluralizationUtils.toSnakeCase(foreignKeyField);

      final updateCount = await _db.customUpdate(
        'UPDATE $sourceTable SET $relationColumnName = ? '
        'WHERE $relationColumnName = ?',
        variables: [
          Variable.withString(newId),
          Variable.withString(oldId),
        ],
        updates: _getTableInfo(sourceTable),
        updateKind: UpdateKind.update,
      );

      _log.fine(
        'Updated $updateCount foreign key references in '
        '$sourceTable.$relationColumnName: $oldId -> $newId',
      );
    } catch (e, stackTrace) {
      _log.warning(
        'Failed to update foreign key reference '
        '$sourceTable.$foreignKeyField: $oldId -> $newId',
        e,
        stackTrace,
      );
      // Continue with other relations even if one fails
    }
  }
}
