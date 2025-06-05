import 'package:json_annotation/json_annotation.dart';
import 'index.dart';
part 'post.g.dart';

@JsonSerializable()
@SynquillRepository(
  relations: [ManyToOne(target: User, foreignKeyColumn: 'userId')],
)
class Post extends SynquillDataModel<Post> {
  @override
  final String id;
  final String title;
  final String body;

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
