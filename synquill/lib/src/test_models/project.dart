import 'package:json_annotation/json_annotation.dart';

import 'index.dart';
part 'project.g.dart';

@JsonSerializable()
@SynquillRepository()
class Project extends SynquillDataModel<Project> {
  @override
  final String id;

  @Indexed(name: 'project_name', unique: true)
  final String name;
  final String description;

  // Project belongs to a User (owner/creator)
  @ManyToOne(target: User, foreignKeyColumn: 'ownerId')
  final String ownerId;

  // Project belongs to a Category
  @ManyToOne(target: Category, foreignKeyColumn: 'categoryId')
  final String categoryId;

  Project({
    /// Unique identifier for the project (CUID)
    String? id,

    /// The name of the project
    required this.name,

    /// The description of the project
    required this.description,

    /// The ID of the user who owns this project
    required this.ownerId,

    /// The ID of the category this project belongs to
    required this.categoryId,
  }) : id = id ?? generateCuid();

  Project.fromDb({
    required this.id,
    required this.name,
    required this.description,
    required this.ownerId,
    required this.categoryId,
  });

  @override
  factory Project.fromJson(Map<String, dynamic> json) =>
      _$ProjectFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$ProjectToJson(this);
}
