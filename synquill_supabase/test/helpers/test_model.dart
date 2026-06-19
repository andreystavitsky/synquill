import 'package:synquill/synquill_contracts.dart';

class TestModel extends SynquillDataModel<TestModel> {
  TestModel({
    required this.id,
    required this.name,
    required this.value,
  });

  factory TestModel.fromJsonData(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final value = json['value'];
    if (id is! String || name is! String || value is! int) {
      throw ArgumentError('Invalid TestModel JSON: $json');
    }
    return TestModel(id: id, name: name, value: value);
  }

  @override
  final String id;

  final String name;
  final int value;

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'value': value,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TestModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          value == other.value;

  @override
  int get hashCode => Object.hash(id, name, value);

  @override
  String toString() => 'TestModel(id: $id, name: $name, value: $value)';
}
