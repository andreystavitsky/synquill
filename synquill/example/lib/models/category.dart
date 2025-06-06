import 'package:json_annotation/json_annotation.dart';

import 'index.dart';
part 'category.g.dart';

@JsonSerializable()
@SynquillRepository(
  relations: [
    OneToMany(target: Project, mappedBy: 'categoryId', cascadeDelete: true),
  ],
)
class Category extends SynquillDataModel<Category> {
  @override
  final String id;
  final String name;
  final String color;

  Category({
    /// Unique identifier for the category (CUID)
    String? id,

    /// The name of the category
    required this.name,

    /// The color code for the category (hex)
    required this.color,
  }) : id = id ?? generateCuid();

  Category.fromDb({required this.id, required this.name, required this.color});

  @override
  factory Category.fromJson(Map<String, dynamic> json) =>
      _$CategoryFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$CategoryToJson(this);
}
