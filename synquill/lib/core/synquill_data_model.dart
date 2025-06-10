part of synquill;

/// Generates a new CUID (Collision-resistant Universal Identifier).
///
/// This is a convenience function that can be used to generate unique IDs
/// for model instances. CUIDs are client-generated and collision-resistant.
String generateCuid() => cuid();

/// Base class for all data models that are to be managed by SynquillStorage.
///
/// **IMPORTANT:**
/// All concrete subclasses MUST implement [toJson] and [fromJson].
/// These methods are required for serialization and deserialization.
///
/// All concrete subclasses MUST implement [fromDb].
/// This method is required for deserializing from the database format.
///
/// It enforces contracts for unique identification (`id`), serialization
/// (`toJson`), deserialization (`fromJson`), and holds a reference to its
/// corresponding repository, which is injected by the code generator.
///
/// The base class provides CUID by default through the [generateCuid] function,
/// which concrete model classes should use for ID generation.
///
/// Type `T` is expected to be the concrete model class itself
/// (e.g., `class MyModel extends SynquillDataModel<MyModel>`).
abstract class SynquillDataModel<T extends SynquillDataModel<T>> {
  /// A unique identifier for the model instance.
  ///
  /// This should be a collision-resistant unique identifier (CUID).
  /// Use [generateCuid()] to create new IDs for model instances.
  ///
  /// Example usage in a concrete model:
  /// ```dart
  /// class MyModel extends SynquillDataModel<MyModel> {
  ///   @override
  ///   final String id;
  ///   final String name;
  ///
  ///   MyModel({String? id, required this.name})
  ///     : id = id ?? generateCuid();
  /// }
  /// ```
  ///
  /// For Freezed models:
  /// ```dart
  /// @freezed
  /// sealed class MyModel extends SynquillDataModel<MyModel> with _$MyModel {
  ///   const factory MyModel({
  ///     required String id,
  ///     required String name,
  ///   }) = _MyModel;
  ///
  ///   // Factory for creating new instances with auto-generated ID
  ///   factory MyModel.create({required String name}) =>
  ///     MyModel(id: generateCuid(), name: name);
  /// }
  /// ```

  /// A unique identifier for the model instance.
  ///
  /// This getter must be overridden in concrete model classes as a final field.
  /// It should be a collision-resistant unique identifier (CUID).
  /// Use [generateCuid()] to create new IDs for model instances.
  ///
  /// Concrete classes should override this as a final field:
  /// ```dart
  /// @override
  /// final String id;
  /// ```
  String get id;

  // JSON serialization methods will be provided by generated mixin

  /// Internal field to hold the repository instance.
  /// It's nullable and not final because it's assigned by generated code
  /// post-construction or initialization.
  /// "Protected" by convention (leading underscore would make it
  /// library-private, but generated part files might need access across
  /// library boundaries if not strictly part files, or if extensions are in
  /// different files but same package).
  /// Using `$` prefix for generated/internal API.
  SynquillRepositoryBase<T>? _$repository;

  /// Allows generated code or internal mechanisms to set the repository
  /// instance associated with this model. This is not intended for direct
  /// use by end-users.
  void $setRepository(SynquillRepositoryBase<T> repository) {
    _$repository = repository;
  }

  /// Provides access to the repository associated with this model instance.
  ///
  /// Throws a [StateError] if the repository has not been set, which typically
  /// indicates an issue with the code generation process or an attempt to use
  /// repository-dependent features before the model is fully initialized.
  SynquillRepositoryBase<T> get $repository {
    if (_$repository == null) {
      throw StateError(
        'Repository not set for this model instance of type $T. '
        'Ensure code generation is complete and the model is properly '
        'initialized.',
      );
    }
    return _$repository!;
  }

  /// Converts the model instance to a JSON map.
  ///
  /// **MUST be implemented in every concrete subclass.**
  ///
  /// This method should be overridden in concrete model classes to provide
  /// the specific fields that need to be serialized.
  ///
  /// Alternatively, you can use @JsonSerializable or @freezed annotations
  /// to auto-generate this method. The build system will check for its
  /// existence during code generation.
  ///
  /// Example implementation:
  /// ```dart
  /// @override
  /// Map<String, dynamic> toJson() => {
  ///   'id': id,
  ///   'name': name,
  ///   'value': value,
  /// };
  /// ```
  Map<String, dynamic> toJson() {
    throw UnimplementedError(
      'toJson() must be implemented in concrete model classes or generated '
      'using @JsonSerializable or @freezed annotations.',
    );
  }

  /// Converts a JSON map to an instance of the model.
  ///
  /// **MUST be implemented in every concrete subclass.**
  ///
  /// This method should be overridden in concrete model classes to provide
  /// the specific fields that need to be deserialized.
  ///
  /// Alternatively, you can use @JsonSerializable or @freezed annotations
  /// to auto-generate this method. The build system will check for its
  /// existence during code generation.
  ///
  /// Example implementation:
  /// ```dart
  /// @override
  /// factory MyModel.fromJson(Map<String, dynamic> json) {
  ///   return MyModel(
  ///     id: json['id'] as String,
  ///     name: json['name'] as String,
  ///     value: json['value'] as int,
  ///   );
  /// }
  /// ```
  T fromJson(Map<String, dynamic> json) {
    throw UnimplementedError(
      'fromJson() must be implemented in concrete model classes or generated '
      'using @JsonSerializable or @freezed annotations.',
    );
  }

  /// Converts a database record to an instance of the model.
  ///
  /// **MUST be implemented in every concrete subclass.**
  ///
  /// This method should be overridden in concrete model classes to provide
  /// the specific logic for deserializing from the database format.
  ///
  /// Example implementation:
  /// ```dart
  /// @override
  /// MyModel.fromDB({required this.id, ...});
  /// ```
  ///
  T fromDb() {
    throw UnimplementedError('Must be implemented by subclasses');
  }

  /// The last time this model instance was synced with the server.
  ///
  /// This field is updated whenever the model is successfully synchronized
  /// with the remote server.
  DateTime? lastSyncedAt;

  /// The time when this model instance was created.
  ///
  /// This should be set by the library when the model is created.
  DateTime? createdAt;

  /// The last time this model instance was updated.
  ///
  /// This should be set by the library when the model is updated.
  DateTime? updatedAt;

  /// The current synchronization status of this model instance.
  ///
  /// This field is automatically managed by the sync system based on
  /// sync queue state:
  /// - `pending`: The model has pending sync operations
  /// - `synced`: The model is fully synchronized
  /// - `dead`: The model has failed sync operations marked as dead
  ///
  /// The actual status is stored in the database and updated automatically
  /// when sync queue operations occur. This getter returns a default value;
  /// concrete implementations should override this to return the real
  /// database value.
  SyncStatus get syncStatus => SyncStatus.pending;
}
