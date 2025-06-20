part of synquill_gen;

/// Generates model info registry code for cascade delete and foreign key
class ModelInfoRegistryGenerator {
  /// Generates model registry initialization code
  static String generateModelInfoRegistry(List<ModelInfo> models) {
    final buffer = StringBuffer();

    buffer.writeln('/// Register all model relations');
    buffer.writeln('void registerModelRelations() {');

    // Generate cascade delete registrations
    _generateCascadeDeleteRegistrations(buffer, models);

    // Generate foreign key registrations
    _generateForeignKeyRegistrations(buffer, models);

    buffer.writeln('}');
    return buffer.toString();
  }

  /// Generates cascade delete relation registration code
  static void _generateCascadeDeleteRegistrations(
    StringBuffer buffer,
    List<ModelInfo> models,
  ) {
    buffer.writeln('  // === CASCADE DELETE RELATIONS ===');

    for (final model in models) {
      final className = model.className;

      // Find class-level relations with cascade delete enabled
      final cascadeDeleteRelations = model.relations
          .where(
            (relation) =>
                relation.relationType == RelationType.oneToMany &&
                relation.cascadeDelete,
          )
          .toList();

      if (cascadeDeleteRelations.isNotEmpty) {
        buffer.writeln('  // Register cascade delete relations for $className');
        buffer.writeln(
          '  ModelInfoRegistryProvider.registerCascadeDeleteRelations(',
        );
        buffer.writeln('    \'$className\',');
        buffer.writeln('    [');

        for (final relation in cascadeDeleteRelations) {
          buffer.writeln('      const CascadeDeleteRelation(');
          buffer.writeln(
            '        fieldName: \''
            '${PluralizationUtils.toCamelCasePlural(relation.targetType)}\',',
          );
          buffer.writeln('        targetType: \'${relation.targetType}\',');
          buffer.writeln('        mappedBy: \'${relation.mappedBy}\',');
          buffer.writeln('      ),');
        }

        buffer.writeln('    ],');
        buffer.writeln('  );');
      }
    }
  }

  /// Generates foreign key relation registration code
  static void _generateForeignKeyRegistrations(
    StringBuffer buffer,
    List<ModelInfo> models,
  ) {
    buffer.writeln();
    buffer.writeln('  // === FOREIGN KEY RELATIONS ===');

    // Group foreign key relations by target type
    final Map<String, List<ForeignKeyInfo>> foreignKeysByTarget = {};

    for (final model in models) {
      final tableName = model.tableName;

      // Find ManyToOne relations (which create foreign keys)
      for (final relation in model.relations) {
        if (relation.relationType == RelationType.manyToOne &&
            relation.foreignKeyColumn != null) {
          final targetType = relation.targetType;
          foreignKeysByTarget.putIfAbsent(targetType, () => []);
          foreignKeysByTarget[targetType]!.add(
            ForeignKeyInfo(
              fieldName: relation.foreignKeyColumn!,
              sourceTable: tableName,
            ),
          );
        }
      }

      // Find field-level foreign key references
      for (final field in model.fields) {
        if (field.isManyToOne &&
            field.relationTarget != null &&
            field.foreignKeyColumn != null) {
          final targetType = field.relationTarget!;
          foreignKeysByTarget.putIfAbsent(targetType, () => []);
          foreignKeysByTarget[targetType]!.add(
            ForeignKeyInfo(
              fieldName: field.foreignKeyColumn!,
              sourceTable: tableName,
            ),
          );
        }
      }
    }

    // Generate registration code for each target type
    for (final entry in foreignKeysByTarget.entries) {
      final targetType = entry.key;
      final foreignKeys = entry.value;

      buffer.writeln('  // Register foreign key relations for $targetType');
      buffer.writeln(
        '  ModelInfoRegistryProvider.registerForeignKeyRelations(',
      );
      buffer.writeln('    \'$targetType\',');
      buffer.writeln('    [');

      for (final fk in foreignKeys) {
        buffer.writeln('      const ForeignKeyRelation(');
        buffer.writeln('        fieldName: \'${fk.fieldName}\',');
        buffer.writeln('        targetType: \'$targetType\',');
        buffer.writeln('        sourceTable: \'${fk.sourceTable}\',');
        buffer.writeln('      ),');
      }

      buffer.writeln('    ],');
      buffer.writeln('  );');
    }
  }
}

/// Helper class for foreign key information
class ForeignKeyInfo {
  /// The name of the foreign key field.
  final String fieldName;

  /// The name of the source table for the foreign key.
  final String sourceTable;

  /// Creates a [ForeignKeyInfo] with the given [fieldName] and [sourceTable].
  const ForeignKeyInfo({
    required this.fieldName,
    required this.sourceTable,
  });
}
