// ignore_for_file: deprecated_member_use, depend_on_referenced_packages

part of synquill_gen;

/// Information about a model with @SynquillDataRepository annotation
class ModelInfo {
  /// The name of the model class.
  final String className;

  /// The name of the database table for this model.
  final String tableName;

  /// The API endpoint for this model.
  final String endpoint;

  /// The import path for the model file.
  final String importPath;

  /// The fields of the model.
  final List<FieldInfo> fields;

  /// The adapters for this model (if any).
  final List<AdapterInfo>? adapters;

  /// Class-level relationships (OneToMany and ManyToOne) defined in
  /// @SynquillRepository.
  final List<RelationInfo> relations;

  /// Whether this repository should work in local-only mode.
  /// When true, the repository will not attempt to sync with remote API.
  final bool localOnly;

  /// ID generation strategy for this model.
  /// Determines whether IDs are generated on client or server side.
  final String idGeneration;

  /// Creates a new instance of [ModelInfo].
  const ModelInfo({
    required this.className,
    required this.tableName,
    required this.endpoint,
    required this.importPath,
    required this.fields,
    this.adapters,
    this.relations = const [],
    this.localOnly = false,
    this.idGeneration = 'client',
  });

  /// Whether this model uses server-generated IDs.
  bool get usesServerGeneratedId => idGeneration == 'server';
}

/// Information about a field in a model
class FieldInfo {
  /// The name of the field.
  final String name;

  /// The Dart type of the field.
  final DartType dartType;

  /// Whether this field is a OneToMany relation
  final bool isOneToMany;

  /// Whether this field is a ManyToOne relation
  final bool isManyToOne;

  /// For ManyToOne relations, the foreign key column name
  final String? foreignKeyColumn;

  /// For OneToMany relations, the field in the target model that maps back
  final String? mappedBy;

  /// The target type for relations
  final String? relationTarget;

  /// Whether cascade delete is enabled for this relation
  final bool cascadeDelete;

  /// Whether this field should be indexed in the database
  final bool isIndexed;

  /// The name of the index (if indexed)
  final String? indexName;

  /// Whether the index should be unique (if indexed)
  final bool isUniqueIndex;

  /// Creates a new instance of [FieldInfo].
  const FieldInfo({
    required this.name,
    required this.dartType,
    this.isOneToMany = false,
    this.isManyToOne = false,
    this.foreignKeyColumn,
    this.mappedBy,
    this.relationTarget,
    this.cascadeDelete = false,
    this.isIndexed = false,
    this.indexName,
    this.isUniqueIndex = false,
  });
}

/// Information about a class-level relationship defined in @SynquillRepository
class RelationInfo {
  /// Type of the relation (OneToMany or ManyToOne)
  final RelationType relationType;

  /// The target model type name
  final String targetType;

  /// The field name in the target model that maps back to this model.
  /// Used for OneToMany relations.
  final String? mappedBy;

  /// The foreign key column name in the current model.
  /// Used for ManyToOne relations.
  final String? foreignKeyColumn;

  /// Whether cascade delete is enabled for this relation
  final bool cascadeDelete;

  /// Creates a new [RelationInfo]
  const RelationInfo({
    required this.relationType,
    required this.targetType,
    this.mappedBy,
    this.foreignKeyColumn,
    this.cascadeDelete = false,
  });
}

/// Type of relation
enum RelationType {
  /// One-to-many relationship
  oneToMany,

  /// Many-to-one relationship
  manyToOne,
}
