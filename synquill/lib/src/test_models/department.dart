// ignore_for_file: public_member_api_docs

import 'package:json_annotation/json_annotation.dart';

import 'package:synquill/src/test_models/index.dart';
part 'department.g.dart';

@JsonSerializable()
@SynquillRepository(
  relations: [
    ManyToOne(target: Company, foreignKeyColumn: 'companyId'),
    OneToMany(target: Company, mappedBy: 'departmentId', cascadeDelete: true),
  ],
)
class Department extends SynquillDataModel<Department> {
  @override
  final String id;
  final String name;

  // Department belongs to a company
  final String companyId;

  Department({
    /// Unique identifier for the department (CUID)
    String? id,

    /// The name of the department
    required this.name,

    /// The company this department belongs to
    required this.companyId,
  }) : id = id ?? generateCuid();

  Department.fromDb({
    required this.id,
    required this.name,
    required this.companyId,
  });

  @override
  factory Department.fromJson(Map<String, dynamic> json) =>
      _$DepartmentFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$DepartmentToJson(this);
}
