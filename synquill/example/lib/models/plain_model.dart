import "index.dart";

@SynquillRepository()
class PlainModel extends SynquillDataModel<PlainModel> {
  @override
  final String id;
  final String name;
  final int value;

  PlainModel({
    required this.id,
    required this.name,
    required this.value,
  });

  // Constructor for Drift to use
  @override
  PlainModel.fromDb({
    required this.id,
    required this.name,
    required this.value,
    // The following fields are part of SyncedDataModel but not typically
    // serialized/deserialized in the core model.
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSyncedAt,
  }) {
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
    this.lastSyncedAt = lastSyncedAt;
  }
  // fromJson and toJson methods should be expected by the ApiAdapter
  // These are placeholders and would typically be generated or implemented
  // based on the actual API contract.

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'value': value,
        // createdAt, updatedAt, lastSyncedAt are part of SyncedDataModel
        // and handled by the repository/sync layer, not typically part of
        // core model serialization to general API unless API expects them.
      };

  @override
  factory PlainModel.fromJson(Map<String, dynamic> json) {
    return PlainModel(
      id: json['id'] as String,
      name: json['name'] as String,
      value: json['value'] as int,
      // createdAt, updatedAt, lastSyncedAt are not deserialized here;
      // they are managed by the sync/storage layer.
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlainModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          value == other.value;

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ value.hashCode;

  @override
  String toString() => 'PlainModel(id: $id, name: $name, value: $value)';
}
