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
            final tableName = reader.peek('tableName')?.stringValue ??
                PluralizationUtils.toSnakeCasePlural(element.name);

            final endpoint = reader.peek('endpoint')?.stringValue ??
                '/${PluralizationUtils.toSnakeCasePlural(element.name)}';

            // Extract adapter information with import paths
            final adapters = await _extractAdapterInfo(
              reader.peek('adapters')?.listValue ?? [],
              buildStep,
            );

            // Extract class-level relations from relations field
            final relations = _extractClassLevelRelations(
              reader.peek('relations')?.listValue ?? [],
            );

            // Extract localOnly parameter
            final localOnly = reader.peek('localOnly')?.boolValue ?? false;

            // Extract idGeneration parameter
            final idGenerationConstant = reader.peek('idGeneration');
            // Default to client for backward compatibility
            String idGeneration = 'client';

            if (idGenerationConstant != null) {
              // The idGeneration field is an enum, get its string
              // representation
              final enumValue = idGenerationConstant.objectValue
                  .getField('_name')
                  ?.toStringValue();
              if (enumValue == 'server') {
                idGeneration = 'server';
              }
            }

            final fields = extractFields(element, relations);

            annotatedModels.add(
              ModelInfo(
                className: element.name,
                importPath: asset.uri.toString(),
                tableName: tableName,
                endpoint: endpoint,
                fields: fields,
                adapters: adapters,
                relations: relations,
                localOnly: localOnly,
                idGeneration: idGeneration,
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

    final models = uniqueModels.values.toList();

    // Validate relations
    _validateRelations(models);

    return models;
  }

  /// Collect all fields from a class including inherited fields
  static List<FieldElement> _collectAllFields(ClassElement element) {
    final allFields = <String, FieldElement>{};

    // Traverse up the inheritance hierarchy
    _traverseInheritance(element, allFields);

    return allFields.values.toList();
  }

  /// Recursively traverse the inheritance hierarchy to collect fields
  static void _traverseInheritance(
    ClassElement element,
    Map<String, FieldElement> allFields,
  ) {
    // Add fields from the current class
    for (final field in element.fields) {
      // Only add if we haven't seen this field name before
      // (child overrides parent)
      if (!allFields.containsKey(field.name)) {
        allFields[field.name] = field;
      }
    }

    // Traverse superclass if it exists and is not Object
    final superclass = element.supertype;
    if (superclass != null && !superclass.isDartCoreObject) {
      final superElement = superclass.element;
      if (superElement is ClassElement) {
        _traverseInheritance(superElement, allFields);
      }
    }

    // Also traverse mixins
    for (final mixin in element.mixins) {
      final mixinElement = mixin.element;
      if (mixinElement is ClassElement) {
        _traverseInheritance(mixinElement, allFields);
      } else {
        // Handle MixinElement separately
        _traverseMixinFields(mixinElement, allFields);
      }
    }
  }

  /// Handle fields from mixins (which are InterfaceElements)
  static void _traverseMixinFields(
    InterfaceElement element,
    Map<String, FieldElement> allFields,
  ) {
    // Add fields from the mixin
    for (final field in element.fields) {
      // Only add if we haven't seen this field name before
      if (!allFields.containsKey(field.name)) {
        allFields[field.name] = field;
      }
    }

    // Traverse mixin's superclass constraints if it has any
    if (element is MixinElement) {
      for (final constraint in element.superclassConstraints) {
        if (!constraint.isDartCoreObject) {
          final constraintElement = constraint.element;
          if (constraintElement is ClassElement) {
            _traverseInheritance(constraintElement, allFields);
          }
        }
      }
    }
  }

  /// Extract fields from a class element
  static List<FieldInfo> extractFields(
    ClassElement element, [
    List<RelationInfo>? classLevelRelations,
  ]) {
    final fields = <FieldInfo>[];

    // Collect all fields including inherited ones
    final allFields = _collectAllFields(element);

    // Build a map of foreign key fields from class-level ManyToOne relations
    final foreignKeyFields = <String, RelationInfo>{};
    if (classLevelRelations != null) {
      for (final relation in classLevelRelations) {
        if (relation.relationType == RelationType.manyToOne) {
          final foreignKeyColumn = relation.foreignKeyColumn;
          if (foreignKeyColumn != null) {
            foreignKeyFields[foreignKeyColumn] = relation;
          }
        }
      }
    }

    // Analyze all public, non-static fields
    for (final field in allFields) {
      if (!field.isStatic &&
          field.isPublic &&
          field.name != 'hashCode' &&
          field.name != 'runtimeType') {
        // Skip internal fields that start with $ (like $repository getter)
        if (field.name.startsWith('\$')) {
          continue;
        }

        // Check for relation annotations (deprecated field-level annotations)
        final oneToManyAnnotation = _oneToManyChecker.firstAnnotationOf(field);
        final manyToOneAnnotation = _manyToOneChecker.firstAnnotationOf(field);
        final indexedAnnotation = _indexedChecker.firstAnnotationOf(field);

        bool isManyToOne = false;
        String? foreignKeyColumn;
        String? mappedBy;
        String? relationTarget;
        bool cascadeDelete = false;
        bool isIndexed = false;
        String? indexName;
        bool isUniqueIndex = false;

        // Check if this field is a foreign key field from class-level relations
        final relationInfo = foreignKeyFields[field.name];
        if (relationInfo != null) {
          isManyToOne = true;
          relationTarget = relationInfo.targetType;
          foreignKeyColumn = field.name;
          cascadeDelete = relationInfo.cascadeDelete;
        }

        // Check for field-level relation annotations -
        // these should cause an error
        if (oneToManyAnnotation != null) {
          throw InvalidGenerationSourceError(
            'Field "${field.name}" in class "${element.name}" has @OneToMany '
            'annotation. Field-level relation annotations are not allowed.\n\n'
            'Use class-level relations instead in @SynquillRepository:\n\n'
            '@SynquillRepository(\n'
            '  relations: [\n'
            '    OneToMany(target: TargetModel, mappedBy: "fieldName"),\n'
            '  ],\n'
            ')\n'
            'class ${element.name} extends '
            'SynquillDataModel<${element.name}> {\n'
            '  // ... your model fields\n'
            '}',
            element: element,
          );
        } else if (manyToOneAnnotation != null) {
          throw InvalidGenerationSourceError(
            'Field "${field.name}" in class "${element.name}" has @ManyToOne '
            'annotation. Field-level relation annotations are not allowed.\n\n'
            'Use class-level relations instead in @SynquillRepository:\n\n'
            '@SynquillRepository(\n'
            '  relations: [\n'
            '    ManyToOne(target: TargetModel, '
            'foreignKeyColumn: "${field.name}"),\n'
            '  ],\n'
            ')\n'
            'class ${element.name} extends '
            'SynquillDataModel<${element.name}> {\n'
            '  final ${field.type.getDisplayString(withNullability: true)} '
            '${field.name};\n'
            '  // ... your other model fields\n'
            '}',
            element: element,
          );
        }

        // Check for @Indexed annotation on relation fields - this should
        // cause an error
        if (indexedAnnotation != null && (isManyToOne)) {
          throw ArgumentError(
            'Field "${field.name}" in class "${element.name}" is a foreign key '
            'or relation field and cannot have @Indexed annotation. Foreign '
            'key fields are automatically indexed for optimal query '
            'performance.',
          );
        }

        if (indexedAnnotation != null) {
          isIndexed = true;
          final reader = ConstantReader(indexedAnnotation);
          indexName = reader.peek('name')?.stringValue;
          isUniqueIndex = reader.peek('unique')?.boolValue ?? false;
        }

        // Automatically index foreign key fields for better query performance
        if (isManyToOne) {
          isIndexed = true;
          // Use default index naming for auto-indexed foreign key fields
          indexName = null;
          isUniqueIndex = false;
        }

        fields.add(
          FieldInfo(
            name: field.name,
            dartType: field.type,
            isOneToMany: false,
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

  /// Extract class-level relations from @SynquillRepository annotations
  static List<RelationInfo> _extractClassLevelRelations(
    List<DartObject> relations,
  ) {
    final List<RelationInfo> relationInfoList = [];

    for (final relation in relations) {
      final relationType = relation.type;
      if (relationType == null) continue;

      final relationName = relationType.element?.name;
      if (relationName == null) continue;

      final reader = ConstantReader(relation);

      if (relationName == 'OneToMany') {
        final target = _getRelationTarget(reader.peek('target'));
        final mappedBy = reader.peek('mappedBy')?.stringValue;
        final cascadeDelete = reader.peek('cascadeDelete')?.boolValue ?? false;

        if (target != null && mappedBy != null) {
          relationInfoList.add(
            RelationInfo(
              relationType: RelationType.oneToMany,
              targetType: target,
              mappedBy: mappedBy,
              cascadeDelete: cascadeDelete,
            ),
          );
        }
      } else if (relationName == 'ManyToOne') {
        final target = _getRelationTarget(reader.peek('target'));
        final foreignKeyColumn = reader.peek('foreignKeyColumn')?.stringValue;
        final cascadeDelete = reader.peek('cascadeDelete')?.boolValue ?? false;

        if (target != null) {
          relationInfoList.add(
            RelationInfo(
              relationType: RelationType.manyToOne,
              targetType: target,
              foreignKeyColumn: foreignKeyColumn,
              cascadeDelete: cascadeDelete,
            ),
          );
        }
      }
    }

    return relationInfoList;
  }

  /// Validate that all relation fields exist in the referenced models
  /// and ensure mappedBy fields for OneToMany relations are indexed
  static void _validateRelations(List<ModelInfo> models) {
    // Create a map for quick model lookup
    final modelMap = <String, ModelInfo>{};
    for (final model in models) {
      modelMap[model.className] = model;
    }

    // Track fields that should be indexed due to OneToMany mappedBy
    final fieldsToIndex = <String, Set<String>>{};

    for (final model in models) {
      for (final relation in model.relations) {
        if (relation.relationType == RelationType.oneToMany) {
          // For OneToMany, check that the target model has the mappedBy field
          final targetModel = modelMap[relation.targetType];
          if (targetModel == null) {
            throw ArgumentError(
              'OneToMany relation in ${model.className} references '
              'unknown target type ${relation.targetType}',
            );
          }

          final mappedBy = relation.mappedBy;
          if (mappedBy == null) {
            throw ArgumentError(
              'OneToMany relation in ${model.className} must specify mappedBy',
            );
          }

          final hasField = targetModel.fields.any((f) => f.name == mappedBy);
          if (!hasField) {
            throw ArgumentError(
              'OneToMany relation in ${model.className} specifies '
              'mappedBy="$mappedBy", but ${relation.targetType} '
              'does not have a field named "$mappedBy"',
            );
          }

          // Mark the mappedBy field for indexing
          fieldsToIndex.putIfAbsent(relation.targetType, () => <String>{});
          fieldsToIndex[relation.targetType]!.add(mappedBy);
        } else if (relation.relationType == RelationType.manyToOne) {
          // For ManyToOne, check that current model has foreignKeyColumn field
          final targetModel = modelMap[relation.targetType];
          if (targetModel == null) {
            throw ArgumentError(
              'ManyToOne relation in ${model.className} references '
              'unknown target type ${relation.targetType}',
            );
          }

          final foreignKeyColumn = relation.foreignKeyColumn;
          if (foreignKeyColumn != null) {
            final hasField = model.fields.any(
              (f) => f.name == foreignKeyColumn,
            );
            if (!hasField) {
              throw ArgumentError(
                'ManyToOne relation in ${model.className} specifies '
                'foreignKeyColumn="$foreignKeyColumn", but ${model.className} '
                'does not have a field named "$foreignKeyColumn"',
              );
            }
          }
        }
      }
    }

    // Apply indexing to mappedBy fields and validate @Indexed conflicts
    for (final model in models) {
      final modelFieldsToIndex = fieldsToIndex[model.className] ?? <String>{};

      for (final field in model.fields) {
        final shouldBeIndexed = modelFieldsToIndex.contains(field.name);

        // Check for @Indexed annotation conflict on mappedBy fields
        if (shouldBeIndexed &&
            field.isIndexed &&
            !field.isManyToOne &&
            !field.isOneToMany) {
          throw ArgumentError(
            'Field "${field.name}" in class "${model.className}" is a '
            'mappedBy field for a OneToMany relation and cannot have @Indexed '
            'annotation. Such fields are automatically indexed for optimal '
            'query performance.',
          );
        }

        // Auto-index mappedBy fields
        if (shouldBeIndexed && !field.isIndexed) {
          // We need to modify the field to mark it as indexed
          // Since FieldInfo is immutable, we'll handle this in the generator
        }
      }
    }
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
      final upLevels = fromPath.length -
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
