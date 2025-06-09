import 'package:json_annotation/json_annotation.dart';

import 'index.dart';
part 'user.g.dart';

@JsonSerializable()
@SynquillRepository(
  relations: [
    OneToMany(target: Todo, mappedBy: 'userId'),
    OneToMany(target: Post, mappedBy: 'userId'),
    OneToMany(target: Project, mappedBy: 'ownerId'),
    OneToMany(target: LocalNote, mappedBy: 'ownerId'),
  ],
)
class User extends SynquillDataModel<User> {
  @override
  final String id;
  final String name;

  User({String? id, required this.name}) : id = id ?? generateCuid();

  User.fromDb({
    required this.id,
    required this.name,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSyncedAt,
  }) {
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
    this.lastSyncedAt = lastSyncedAt;
  }

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$UserToJson(this);
}
