import 'dart:async';

import 'package:json_annotation/json_annotation.dart';
import 'index.dart';

part 'post.g.dart';

/// Example Todo model ApiAdapter
// Now extends BaseJsonApiAdapter to inherit global header overrides and baseUrl.
mixin PostApiAdapter on BasicApiAdapter<Post> {
  // baseUrl is inherited from BaseJsonApiAdapter.
  // baseHeaders are inherited and extended from BaseJsonApiAdapter.

  // Model-specific endpoint path component.
  // @override
  // String get type => 'todo';

  @override
  Logger get logger => Logger('PostApiAdapter');

  @override
  FutureOr<Uri> urlForUpdate(String id, {Map<String, dynamic>? extra}) =>
      baseUrl.resolve('$pluralType/$id');

  @override
  FutureOr<Uri> urlForFindAll({Map<String, dynamic>? extra}) async {
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
    headers['X-Post-Specific-Header'] = 'PostValue';
    return headers;
  }
}

@JsonSerializable()
// BaseJsonApiAdapter provides global settings, PostApiAdapter provides specifics.
// The SyncedStorage system will merge configurations from these adapters.
@SynquillRepository(
  adapters: [JsonApiAdapter, PostApiAdapter],
  relations: [
    ManyToOne(target: User, foreignKeyColumn: 'userId'),
  ],
)
class Post extends SynquillDataModel<Post> {
  @override
  @JsonKey(readValue: idMapper)
  final String id;
  final String title;
  final String body;

  @JsonKey(readValue: idMapper)
  final String userId;

  Post({
    /// Unique identifier for the post item (CUID)
    String? id,

    /// The title/description of the post item
    required this.title,

    /// The ID of the user this post belongs to
    required this.userId,

    /// Whether the post item is completed
    required this.body,
  }) : id = id ?? generateCuid();

  Post.fromDb({
    required this.id,
    required this.title,
    required this.userId,
    required this.body,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSyncedAt,
  }) {
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
    this.lastSyncedAt = lastSyncedAt;
  }

  // Required for JsonSerializable
  factory Post.fromJson(Map<String, dynamic> json) => _$PostFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$PostToJson(this);
}
