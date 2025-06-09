part of synquill_gen;

/// Generates model info registry code for cascade delete support
class ModelInfoRegistryGenerator {
  /// Generates cascade delete relation registration code
  static String generateModelInfoRegistry(List<ModelInfo> models) {
    final buffer = StringBuffer();

    buffer.writeln('/// Register all model cascade delete relations');
    buffer.writeln('void registerModelCascadeDeleteRelations() {');

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
            '        fieldName: \'${relation.targetType.toLowerCase()}s\',',
          );
          buffer.writeln('        targetType: \'${relation.targetType}\',');
          buffer.writeln('        mappedBy: \'${relation.mappedBy}\',');
          buffer.writeln('      ),');
        }

        buffer.writeln('    ],');
        buffer.writeln('  );');
      }
    }

    buffer.writeln('}');
    return buffer.toString();
  }
}
