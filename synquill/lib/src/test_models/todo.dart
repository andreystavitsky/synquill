// ignore_for_file: public_member_api_docs

import 'package:json_annotation/json_annotation.dart';

import 'package:synquill/src/test_models/index.dart';
part 'todo.g.dart';

@JsonSerializable()
@SynquillRepository(
  relations: [ManyToOne(target: User, foreignKeyColumn: 'userId')],
)
class Todo extends ContactBase<Todo> {
  final String title;
  final bool isCompleted;

  final String userId;

  Todo({
    /// Unique identifier for the todo item (CUID)
    super.id,

    /// The title/description of the todo item
    required this.title,

    /// The ID of the user this todo belongs to
    required this.userId,

    /// Whether the todo item is completed
    required this.isCompleted,
  });

  Todo.fromDb({
    super.id,
    required this.title,
    required this.userId,
    required this.isCompleted,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSyncedAt,
  }) {
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
    this.lastSyncedAt = lastSyncedAt;
  }

  // Required for JsonSerializable
  factory Todo.fromJson(Map<String, dynamic> json) => _$TodoFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$TodoToJson(this);
}
