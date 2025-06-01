// ignore_for_file: deprecated_member_use, depend_on_referenced_packages

part of synquill_gen;

// TypeCheckers for relation annotations
const _oneToManyChecker = TypeChecker.fromRuntime(OneToMany);
const _manyToOneChecker = TypeChecker.fromRuntime(ManyToOne);
const _indexedChecker = TypeChecker.fromRuntime(Indexed);

/// Analyzes Dart source files to extract model information
class ModelAnalyzer {
  /// Finds all models with @SynquillRepository annotation in the project
  static Future<List<ModelInfo>> findAnnotatedModels(
    BuildStep buildStep,
  ) async {
    // Find all Dart files in lib/
    final dartFiles = <AssetId>[];
    await for (final input in buildStep.findAssets(Glob('lib/**.dart'))) {
      dartFiles.add(input);
    }

    // Collect all models with @SynquillRepository annotation
    final annotatedModels = <ModelInfo>[];

    for (final asset in dartFiles) {
      // Skip part files - they can't be processed as libraries
      final content = await buildStep.readAsString(asset);
      if (content.trimLeft().startsWith('part of ')) {
        continue;
      }

      final library = await buildStep.resolver.libraryFor(asset);

      for (final element in library.topLevelElements) {
        if (element is ClassElement) {
          final annotation = const TypeChecker.fromRuntime(
            SynquillRepository,
          ).firstAnnotationOf(element);

          if (annotation != null) {
            final reader = ConstantReader(annotation);
            final tableName =
                reader.peek('tableName')?.stringValue ??
                '${element.name.toLowerCase()}s';
            final endpoint =
                reader.peek('endpoint')?.stringValue ??
                '/${element.name.toLowerCase()}s';

            // Extract adapter information with import paths
            final adapters = await _extractAdapterInfo(
              reader.peek('adapters')?.listValue ?? [],
              buildStep,
            );

            final fields = extractFields(element);

            annotatedModels.add(
              ModelInfo(
                className: element.name,
                importPath: asset.uri.toString(),
                tableName: tableName,
                endpoint: endpoint,
                fields: fields,
                adapters: adapters,
              ),
            );
          }
        }
      }
    }

    // Remove duplicates based on className
    final uniqueModels = <String, ModelInfo>{};
    for (final model in annotatedModels) {
      if (!uniqueModels.containsKey(model.className)) {
        uniqueModels[model.className] = model;
      }
    }

    return uniqueModels.values.toList();
  }

  /// Extract fields from a class element
  static List<FieldInfo> extractFields(ClassElement element) {
    final fields = <FieldInfo>[];

    // Analyze all public, non-static fields
    for (final field in element.fields) {
      if (!field.isStatic &&
          field.isPublic &&
          field.name != 'hashCode' &&
          field.name != 'runtimeType') {
        // Check for relation annotations
        final oneToManyAnnotation = _oneToManyChecker.firstAnnotationOf(field);
        final manyToOneAnnotation = _manyToOneChecker.firstAnnotationOf(field);
        final indexedAnnotation = _indexedChecker.firstAnnotationOf(field);

        bool isOneToMany = false;
        bool isManyToOne = false;
        String? foreignKeyColumn;
        String? mappedBy;
        String? relationTarget;
        bool cascadeDelete = false;
        bool isIndexed = false;
        String? indexName;
        bool isUniqueIndex = false;

        if (oneToManyAnnotation != null) {
          isOneToMany = true;
          final reader = ConstantReader(oneToManyAnnotation);
          relationTarget = _getRelationTarget(reader.peek('target'));
          mappedBy = reader.peek('mappedBy')?.stringValue;
          cascadeDelete = reader.peek('cascadeDelete')?.boolValue ?? false;
        } else if (manyToOneAnnotation != null) {
          isManyToOne = true;
          final reader = ConstantReader(manyToOneAnnotation);
          relationTarget = _getRelationTarget(reader.peek('target'));
          foreignKeyColumn = reader.peek('foreignKeyColumn')?.stringValue;
          cascadeDelete = reader.peek('cascadeDelete')?.boolValue ?? false;
        }

        if (indexedAnnotation != null) {
          isIndexed = true;
          final reader = ConstantReader(indexedAnnotation);
          indexName = reader.peek('name')?.stringValue;
          isUniqueIndex = reader.peek('unique')?.boolValue ?? false;
        }

        // Automatically index relation fields for better query performance
        if (isManyToOne && !isIndexed) {
          isIndexed = true;
          // Use default index naming for auto-indexed relation fields
          indexName = null;
          isUniqueIndex = false;
        }

        fields.add(
          FieldInfo(
            name: field.name,
            dartType: field.type,
            isOneToMany: isOneToMany,
            isManyToOne: isManyToOne,
            foreignKeyColumn: foreignKeyColumn,
            mappedBy: mappedBy,
            relationTarget: relationTarget,
            cascadeDelete: cascadeDelete,
            isIndexed: isIndexed,
            indexName: indexName,
            isUniqueIndex: isUniqueIndex,
          ),
        );
      }
    }

    return fields;
  }

  /// Extract the target type from a relation annotation
  static String? _getRelationTarget(ConstantReader? targetReader) {
    if (targetReader == null) return null;

    if (targetReader.isString) {
      // Target is specified as string to avoid circular imports
      return targetReader.stringValue;
    } else if (targetReader.isType) {
      // Target is specified as Type
      return targetReader.typeValue.element?.name;
    }

    return null;
  }

  /// Extract adapter information from the adapters annotation field
  static Future<List<AdapterInfo>> _extractAdapterInfo(
    List<DartObject> adapters,
    BuildStep buildStep,
  ) async {
    final List<AdapterInfo> adapterInfoList = [];

    for (final adapter in adapters) {
      final adapterType = adapter.toTypeValue();
      if (adapterType == null) continue;

      final element = adapterType.element;
      if (element == null) continue;

      // Get the source of the adapter to determine its import path
      final source = element.source;
      if (source == null) continue;

      // Convert the source URI to an import path
      String importPath;
      final sourceUri = source.uri;

      if (sourceUri.scheme == 'package') {
        // It's a package import
        importPath = sourceUri.toString();
      } else if (sourceUri.scheme == 'file') {
        // It's a local file, we need to make it relative to the current package
        final currentUri = buildStep.inputId.uri;
        importPath = _makeRelativeImport(currentUri, sourceUri);
      } else {
        // Fallback - use the URI as is
        importPath = sourceUri.toString();
      }

      // Check if the adapter is generic (has type parameters)
      final isGeneric =
          (element is ClassElement && element.typeParameters.isNotEmpty) ||
          (element is MixinElement && element.typeParameters.isNotEmpty);

      adapterInfoList.add(
        AdapterInfo(
          adapterName: element.name!,
          importPath: importPath,
          dartType: adapterType,
          isGeneric: isGeneric,
        ),
      );
    }

    return adapterInfoList;
  }

  /// Convert absolute file URI to relative import path
  static String _makeRelativeImport(Uri from, Uri to) {
    // If it's a package URI, return as is
    if (to.scheme == 'package') {
      return to.toString();
    }

    // For file URIs, make them relative
    if (from.scheme == 'file' && to.scheme == 'file') {
      final fromPath = from.pathSegments;
      final toPath = to.pathSegments;

      // Find common prefix
      int commonLength = 0;
      final minLength =
          fromPath.length < toPath.length ? fromPath.length : toPath.length;

      for (int i = 0; i < minLength; i++) {
        if (fromPath[i] == toPath[i]) {
          commonLength++;
        } else {
          break;
        }
      }

      // Build relative path
      final List<String> relativeParts = [];

      // Add '..' for each directory we need to go up from the 'from' file
      final upLevels =
          fromPath.length -
          commonLength -
          1; // -1 because last segment is filename
      for (int i = 0; i < upLevels; i++) {
        relativeParts.add('..');
      }

      // Add the remaining path segments from 'to'
      for (int i = commonLength; i < toPath.length; i++) {
        relativeParts.add(toPath[i]);
      }

      return relativeParts.join('/');
    }

    // Fallback
    return to.toString();
  }
}
