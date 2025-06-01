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

      // Find fields with cascade delete enabled
      final cascadeDeleteFields =
          model.fields
              .where((field) => field.isOneToMany && field.cascadeDelete)
              .toList();

      if (cascadeDeleteFields.isNotEmpty) {
        buffer.writeln('  // Register cascade delete relations for $className');
        buffer.writeln(
          '  ModelInfoRegistryProvider.registerCascadeDeleteRelations(',
        );
        buffer.writeln('    \'$className\',');
        buffer.writeln('    [');

        for (final field in cascadeDeleteFields) {
          buffer.writeln('      CascadeDeleteRelation(');
          buffer.writeln('        fieldName: \'${field.name}\',');
          buffer.writeln('        targetType: \'${field.relationTarget}\',');
          buffer.writeln('        mappedBy: \'${field.mappedBy}\',');
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
