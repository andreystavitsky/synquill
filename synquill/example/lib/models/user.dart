import 'dart:async';

import 'package:json_annotation/json_annotation.dart';
import 'index.dart';

part 'user.g.dart';

/// Example User model ApiAdapter
// Now extends BaseJsonApiAdapter to inherit global header overrides and baseUrl.
mixin UserApiAdapter on BasicApiAdapter<User> {
  // baseUrl is inherited from BaseJsonApiAdapter.
  // baseHeaders are inherited and extended from BaseJsonApiAdapter.

  @override
  Logger get logger => Logger('UserApiAdapter');

  // Model-specific endpoint path component.
  @override
  String get type => 'user';

  // Example: Override specific headers for User model if needed
  @override
  FutureOr<Map<String, String>> get baseHeaders async {
    final headers =
        await super.baseHeaders; // Gets headers from BaseJsonApiAdapter
    headers['X-User-Specific-Header'] = 'UserValue';
    return headers;
  }
}

@JsonSerializable()
// BaseJsonApiAdapter provides global settings, UserApiAdapter provides specifics.
// The SynquillStorage system will merge configurations from these adapters.
@SynquillRepository(
  adapters: [JsonApiAdapter, UserApiAdapter],
  relations: [
    OneToMany(target: Todo, mappedBy: 'userId'),
    OneToMany(target: Post, mappedBy: 'userId'),
    OneToMany(target: LocalNote, mappedBy: 'ownerId'),
  ],
)
class User extends SynquillDataModel<User> {
  @override
  @JsonKey(readValue: idMapper)
  final String id;

  final String name;

  User({String? id, required this.name}) : id = id ?? generateCuid();

  User.fromDb({
    required this.id,
    required this.name,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
  }) {
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
    this.syncStatus = syncStatus ?? SyncStatus.synced;
  }

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$UserToJson(this);
}
