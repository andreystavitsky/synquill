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

  /// Creates a new instance of [ModelInfo].
  const ModelInfo({
    required this.className,
    required this.tableName,
    required this.endpoint,
    required this.importPath,
    required this.fields,
    this.adapters,
  });
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
