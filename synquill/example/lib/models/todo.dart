import 'dart:async';

import 'package:json_annotation/json_annotation.dart';
import 'index.dart';

part 'todo.g.dart';

/// Example Todo model ApiAdapter
// Now extends BaseJsonApiAdapter to inherit global header overrides and baseUrl.
mixin TodoApiAdapter on BasicApiAdapter<Todo> {
  // baseUrl is inherited from BaseJsonApiAdapter.
  // baseHeaders are inherited and extended from BaseJsonApiAdapter.

  // Model-specific endpoint path component.
  @override
  String get type => pluralType;

  @override
  Logger get logger => Logger('TodoApiAdapter');

  @override
  FutureOr<Uri> urlForUpdate(String id, {Map<String, dynamic>? extra}) =>
      baseUrl.resolve('$pluralType/$id');

  @override
  FutureOr<Uri> urlForDelete(String id, {Map<String, dynamic>? extra}) =>
      baseUrl.resolve('$pluralType/$id');

  @override
  FutureOr<Uri> urlForFindAll({
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    final users = await SynquillStorage.instance.users
        .findAll(loadPolicy: DataLoadPolicy.localOnly);

    if (users.isEmpty) {
      return baseUrl.resolve(pluralType);
    }
    final userId = users.first.id;
    return baseUrl.resolve('users/$userId/$pluralType');
  }

  // Example: Override specific headers for Todo model if needed
  @override
  FutureOr<Map<String, String>> get baseHeaders async {
    final headers = await super.baseHeaders;
    headers['X-Todo-Specific-Header'] = 'TodoValue';
    return headers;
  }
}

@JsonSerializable()
// BaseJsonApiAdapter provides global settings, TodoApiAdapter provides specifics.
// The SyncedStorage system will merge configurations from these adapters.
@SynquillRepository(
  adapters: [JsonApiAdapter, TodoApiAdapter],
  relations: [ManyToOne(target: User, foreignKeyColumn: 'userId')],
)
class Todo extends ContactBase<Todo> {
  String title;

  @JsonKey(name: 'completed')
  bool isCompleted;

  @JsonKey(readValue: idMapper)
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
