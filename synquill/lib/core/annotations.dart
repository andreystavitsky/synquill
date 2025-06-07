part of synquill;

/// An annotation to mark a class as a data model for which
/// a Drift table and repository should be generated.
///
/// **IMPORTANT**: Any class annotated with `@SynquillRepository` MUST either:
/// 1. Implement `toJson()` and `fromJson()` methods
/// 2. Use `@JsonSerializable` annotation
/// 3. Use `@freezed` annotation with appropriate JSON serialization
///
/// The build system will throw an error if these requirements are not met.
class SynquillRepository {
  /// A list of API adapter types to be used with this repository.
  /// For Stage 1, this might be a placeholder or a single adapter type.
  final List<Type>? adapters; // Example: [JsonApiAdapter]

  /// Optional path for the generated Drift table file.
  /// If not provided, defaults to `model_name.drift.dart`.
  final String? tableFile;

  /// Relations defined at class level (OneToMany and ManyToOne).
  /// This is a cleaner alternative to field-level annotations.
  /// Each element should be either OneToMany or ManyToOne annotation.
  final List<Object>? relations;

  /// Whether this repository should work in local-only mode.
  /// When set to `true`, the repository will not attempt to sync
  /// with remote API and will only work with local Drift database storage.
  /// Defaults to `false` for backward compatibility.
  final bool localOnly;

  /// Creates a new [SynquillRepository] annotation.
  const SynquillRepository({
    this.adapters,
    this.tableFile,
    this.relations,
    this.localOnly = false,
  });
}

/// Annotation to mark a field as a relation to another model.
/// This creates a foreign key constraint in the database.
class Relation {
  /// The target model class for this relation.
  /// Can be a Type or a String to avoid circular imports.
  final dynamic target;

  /// Whether to cascade delete when the parent is deleted.
  /// Default is false for safety.
  final bool cascadeDelete;

  /// The name of the foreign key column in the database.
  /// If not specified, defaults to '${fieldName}_id'.
  final String? foreignKeyColumn;

  /// Creates a new [Relation] annotation.
  const Relation({
    required this.target,
    this.cascadeDelete = false,
    this.foreignKeyColumn,
  });
}

/// Annotation to mark a field as a one-to-many relation.
/// This field should be of type List\<T\> where T is the related model.
class OneToMany {
  /// The target model class for this relation.
  /// Can be a Type or a String to avoid circular imports.
  final dynamic target;

  /// The field name in the target model that references this model.
  final String mappedBy;

  /// Whether to cascade delete all related entities when this entity is
  /// deleted. Default is false for safety.
  final bool cascadeDelete;

  /// Creates a new [OneToMany] annotation.
  const OneToMany({
    required this.target,
    required this.mappedBy,
    this.cascadeDelete = false,
  });
}

/// Annotation to mark a field as a many-to-one relation.
/// This creates a foreign key constraint in the database.
class ManyToOne {
  /// The target model class for this relation.
  /// Can be a Type or a String to avoid circular imports.
  final dynamic target;

  /// Whether to cascade delete when the parent is deleted.
  /// Default is false for safety.
  final bool cascadeDelete;

  /// The name of the foreign key column in the database.
  /// If not specified, defaults to '${fieldName}_id'.
  final String? foreignKeyColumn;

  /// Creates a new [ManyToOne] annotation.
  const ManyToOne({
    required this.target,
    this.cascadeDelete = false,
    this.foreignKeyColumn,
  });
}

/// Annotation to mark a field for database indexing.
/// This will create a database index on the annotated field to improve
/// query performance.
class Indexed {
  /// The name of the index. If not provided, a default name will be generated
  /// based on the table and field name.
  final String? name;

  /// Whether this index should be unique. Default is false.
  final bool unique;

  /// Creates a new [Indexed] annotation.
  const Indexed({this.name, this.unique = false});
}

/// Annotation to specify the database schema version.
/// This annotation can be placed anywhere in the application code where
/// SynquillStorage is initialized. If no annotation is present, the default
/// version is 1.
///
/// Example:
/// ```dart
/// @SynqillDatabaseVersion(2)
/// void main() {
///   // Your app initialization
/// }
/// ```
class SynqillDatabaseVersion {
  /// The database schema version number.
  /// Must be a positive integer.
  final int version;

  /// Creates a new [SynqillDatabaseVersion] annotation.
  const SynqillDatabaseVersion(this.version);
}
