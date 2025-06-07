// ignore_for_file: deprecated_member_use, depend_on_referenced_packages

part of synquill_gen;

/// Validates that models meet the requirements for code generation
class FieldValidator {
  /// Validates that all models have required methods
  static Future<void> validateModelRequirements(
    List<ModelInfo> models,
    Future<ClassElement?> Function(String className) getClassElement,
  ) async {
    for (final model in models) {
      final classElement = await getClassElement(model.className);
      if (classElement == null) continue;

      await validateJsonMethods(classElement, model.localOnly);
      validateFromDbConstructor(classElement);
    }
  }

  /// Validates that the model has required toJson and fromJson methods
  /// For localOnly models, these methods are not required
  static Future<void> validateJsonMethods(
    ClassElement element, [
    bool localOnly = false,
  ]) async {
    final className = element.name;

    // Skip JSON method validation for localOnly models
    if (localOnly) {
      return;
    }

    // Check if model has @JsonSerializable annotation
    final hasJsonSerializable = element.metadata.any((annotation) {
      final source = annotation.toSource();
      return source.contains('JsonSerializable');
    });

    if (hasJsonSerializable) {
      // For @JsonSerializable models, the methods will be generated
      // We don't need to check for manual implementation
      return;
    }

    // For plain models, both methods must be manually implemented

    // Check for toJson method (instance method returning Map<String, dynamic>)
    final hasToJson = element.methods.any(
      (method) =>
          !method.isStatic &&
          method.name == 'toJson' &&
          method.parameters.isEmpty &&
          method.returnType.getDisplayString(withNullability: false) ==
              'Map<String, dynamic>',
    );

    // Check for fromJson method (factory constructor or static method)
    final hasFactoryFromJson = element.constructors.any(
      (constructor) =>
          constructor.isFactory &&
          constructor.name == 'fromJson' &&
          constructor.parameters.length == 1 &&
          constructor.parameters.first.type.getDisplayString(
                withNullability: false,
              ) ==
              'Map<String, dynamic>',
    );

    final hasStaticFromJson = element.methods.any(
      (method) =>
          method.isStatic &&
          method.name == 'fromJson' &&
          method.parameters.length == 1 &&
          method.parameters.first.type.getDisplayString(
                withNullability: false,
              ) ==
              'Map<String, dynamic>' &&
          method.returnType.getDisplayString(withNullability: false) ==
              className,
    );

    final hasFromJson = hasFactoryFromJson || hasStaticFromJson;

    if (!hasToJson || !hasFromJson) {
      final missingMethods = <String>[];
      if (!hasToJson) missingMethods.add('toJson()');
      if (!hasFromJson) missingMethods.add('fromJson()');

      throw InvalidGenerationSourceError(
        'Model "$className" annotated with @SynquillRepository '
        'must implement the following methods: '
        '${missingMethods.join(', ')}.\n\n'
        'Either:\n'
        '1. Manually implement these methods:\n'
        '   - Map<String, dynamic> toJson()\n'
        '   - factory $className.fromJson(Map<String, dynamic> json) or\n'
        '   - static $className fromJson(Map<String, dynamic> json)\n\n'
        '2. Or use @JsonSerializable annotation to auto-generate them:\n'
        '   @JsonSerializable()\n'
        '   @SynquillRepository()\n'
        '   class $className extends SynquillDataModel<$className> { ... }\n\n'
        '3. Or use @freezed annotation with JSON serialization support.',
        element: element,
      );
    }
  }

  /// Validates that the model has a fromDb constructor
  static void validateFromDbConstructor(ClassElement element) {
    final className = element.name;

    // Check for fromDb constructor
    final hasFromDbConstructor = element.constructors.any(
      (constructor) => constructor.name == 'fromDb',
    );

    if (!hasFromDbConstructor) {
      throw InvalidGenerationSourceError(
        'Model "$className" annotated with @SynquillRepository '
        'must have a "fromDb" constructor.\n\n'
        'Add a fromDb constructor to your model:\n'
        '  $className.fromDb({required this.id, required this.name, ...});',
        element: element,
      );
    }
  }
}
