import 'package:synquill/synquill.dart';

/// Test model for GraphQL adapter testing.
class TestModel extends SynquillDataModel<TestModel> {
  @override
  final String id;

  /// Name property.
  final String name;

  /// Value property.
  final int value;

  /// Constructor.
  TestModel({required this.id, required this.name, required this.value});

  /// Factory constructor for empty model.
  factory TestModel.empty() => TestModel(id: '', name: '', value: 0);

  /// Helper to deserialize.
  static TestModel fromJsonData(Map<String, dynamic> json) {
    return TestModel(
      id: json['id'] as String,
      name: json['name'] as String,
      value: json['value'] as int,
    );
  }

  /// Deserialization override for base interface.
  @override
  TestModel fromJson(Map<String, dynamic> json) => fromJsonData(json);

  /// Serialization override for base interface.
  @override
  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'value': value};
  }

  @override
  TestModel fromDb() {
    throw UnimplementedError(
        'Database serialization is not used in GraphQL adapter tests');
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TestModel &&
        other.id == id &&
        other.name == name &&
        other.value == value;
  }

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ value.hashCode;
}
