// ignore_for_file: deprecated_member_use, depend_on_referenced_packages

part of synquill_gen;

/// Builder for generating the aggregate synced_storage.generated.dart file
Builder aggregateBuilder(BuilderOptions options) => AggregateBuilder();

/// Builder that scans all annotated models and generates
/// the main synced_storage.generated.dart file with imports and part directives
/// and all modular generated files
class AggregateBuilder implements Builder {
  @override
  final buildExtensions = const {
    r'$lib$': [
      'synquill.generated.dart',
      'generated/tables.g.dart',
      'generated/dao.g.dart',
      'generated/database.g.dart',
      'generated/repositories.g.dart',
      'generated/api_adapters.g.dart',
      'generated/model_extensions.g.dart',
      'generated/database.generated.dart',
    ],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    // Find all models with @SynquillDataRepository annotation
    final models = await ModelAnalyzer.findAnnotatedModels(buildStep);

    // Helper function to get ClassElement for validation
    Future<ClassElement?> getClassElement(String className) async {
      final dartFiles = <AssetId>[];
      await for (final input in buildStep.findAssets(Glob('lib/**.dart'))) {
        dartFiles.add(input);
      }

      for (final asset in dartFiles) {
        // Skip part files - they can't be processed as libraries
        final content = await buildStep.readAsString(asset);
        if (content.trimLeft().startsWith('part of ')) {
          continue;
        }

        final library = await buildStep.resolver.libraryFor(asset);
        for (final element in library.topLevelElements) {
          if (element is ClassElement && element.name == className) {
            return element;
          }
        }
      }
      return null;
    }

    // Validate models have required methods
    await FieldValidator.validateModelRequirements(models, getClassElement);

    // Generate all files
    await _generateAllFiles(buildStep, models);
  }

  /// Generate all modular files and the main aggregate file
  Future<void> _generateAllFiles(
    BuildStep buildStep,
    List<ModelInfo> models,
  ) async {
    // Generate main aggregate file
    final mainAssetId = AssetId(
      buildStep.inputId.package,
      'lib/synquill.generated.dart',
    );

    final generatedDatabaseAssetId = AssetId(
      buildStep.inputId.package,
      'lib/generated/database.generated.dart',
    );
    final mainContent = FileAggregator.generateAggregateFile(models);
    await buildStep.writeAsString(mainAssetId, mainContent);

    final generatedDatabaseContent = FileAggregator.generateDatabaseFile(
      models,
    );
    await buildStep.writeAsString(
      generatedDatabaseAssetId,
      generatedDatabaseContent,
    );

    // Generate tables file
    final tablesAssetId = AssetId(
      buildStep.inputId.package,
      'lib/generated/tables.g.dart',
    );
    final tablesContent = _generateTablesFile(models);
    await buildStep.writeAsString(tablesAssetId, tablesContent);

    // Generate dao file
    final daoAssetId = AssetId(
      buildStep.inputId.package,
      'lib/generated/dao.g.dart',
    );
    final daoContent = _generateDaoFile(models);
    await buildStep.writeAsString(daoAssetId, daoContent);

    // Generate database file
    final databaseAssetId = AssetId(
      buildStep.inputId.package,
      'lib/generated/database.g.dart',
    );
    final databaseContent = await _generateDatabaseFile(models, buildStep);
    await buildStep.writeAsString(databaseAssetId, databaseContent);

    // Generate repositories file
    final repositoriesAssetId = AssetId(
      buildStep.inputId.package,
      'lib/generated/repositories.g.dart',
    );
    final repositoriesContent = _generateRepositoriesFile(models);
    await buildStep.writeAsString(repositoriesAssetId, repositoriesContent);

    // Generate api adapters file
    final apiAdaptersAssetId = AssetId(
      buildStep.inputId.package,
      'lib/generated/api_adapters.g.dart',
    );
    final apiAdaptersContent = _generateApiAdaptersFile(models);
    await buildStep.writeAsString(apiAdaptersAssetId, apiAdaptersContent);

    // Generate model extensions file
    final modelExtensionsAssetId = AssetId(
      buildStep.inputId.package,
      'lib/generated/model_extensions.g.dart',
    );
    final modelExtensionsContent = _generateModelExtensionsFile(models);
    await buildStep.writeAsString(
      modelExtensionsAssetId,
      modelExtensionsContent,
    );
  }

  /// Generate tables.g.dart file
  String _generateTablesFile(List<ModelInfo> models) {
    final buffer = StringBuffer();

    // File header
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln('// Generated by synquill aggregate_builder');
    buffer.writeln();
    buffer.writeln('part of \'database.generated.dart\';');
    buffer.writeln();

    // Generate tables
    for (final model in models) {
      final tableCode = TableGenerator.generateTableClass(model);
      buffer.writeln(tableCode);
      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Generate dao.g.dart file
  String _generateDaoFile(List<ModelInfo> models) {
    final buffer = StringBuffer();

    // File header
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln('// Generated by synquill aggregate_builder');
    buffer.writeln();
    buffer.writeln('part of \'database.generated.dart\';');
    buffer.writeln();

    buffer.writeln(DaoGenerator.generateAllDaoCode(models));

    return buffer.toString();
  }

  /// Generate database.g.dart file
  Future<String> _generateDatabaseFile(
    List<ModelInfo> models,
    BuildStep buildStep,
  ) async {
    final buffer = StringBuffer();

    // File header
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln('// Generated by synquill aggregate_builder');
    buffer.writeln();
    buffer.writeln('part of \'database.generated.dart\';');
    buffer.writeln();

    // Generate database
    buffer.writeln(TableGenerator.generateSyncQueueItemsTable());
    final databaseCode = await DatabaseGenerator.generateDatabaseClass(
      models,
      buildStep,
    );
    buffer.writeln(databaseCode);

    return buffer.toString();
  }

  /// Generate repositories.g.dart file
  String _generateRepositoriesFile(List<ModelInfo> models) {
    final buffer = StringBuffer();

    // File header
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln('// Generated by synquill aggregate_builder');
    buffer.writeln();
    buffer.writeln('part of \'../synquill.generated.dart\';');
    buffer.writeln();

    // Generate repositories
    for (final model in models) {
      final repositoryCode = RepositoryGenerator.generateRepositoryClass(model);
      buffer.writeln(repositoryCode);
      buffer.writeln();
    }

    // Generate repository registration
    buffer.writeln(RepositoryGenerator.generateRepositoryRegistrations(models));

    // Generate model info registry for cascade delete
    buffer.writeln(
      ModelInfoRegistryGenerator.generateModelInfoRegistry(models),
    );

    // Generate SynquillStorage extension for convenient repository access
    buffer.writeln(
      RepositoryGenerator.generateSynquillStorageExtension(models),
    );

    //buffer.writeln(RepositoryGenerator.generateRepositoryHelpersMixin());

    return buffer.toString();
  }

  /// Generate api_adapters.g.dart file
  String _generateApiAdaptersFile(List<ModelInfo> models) {
    final buffer = StringBuffer();

    // File header
    buffer.writeln('// ignore_for_file: lines_longer_than_80_chars');
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln('// Generated by synquill aggregate_builder');
    buffer.writeln();
    buffer.writeln('part of \'../synquill.generated.dart\';');
    buffer.writeln();

    // Generate adapter classes
    for (final model in models) {
      if (model.adapters != null && model.adapters!.isNotEmpty) {
        buffer.writeln(RepositoryGenerator.generateAdapterClass(model));
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  /// Generate model_extensions.g.dart file
  String _generateModelExtensionsFile(List<ModelInfo> models) {
    final buffer = StringBuffer();

    // File header
    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln('// Generated by synquill aggregate_builder');
    buffer.writeln();
    buffer.writeln('part of \'../synquill.generated.dart\';');
    buffer.writeln();

    // Generate model extensions
    for (final model in models) {
      final extensionCode = ModelExtensionGenerator.generateModelExtensions(
        model,
        models,
      );
      buffer.writeln(extensionCode);
      buffer.writeln();
    }

    return buffer.toString();
  }
}
