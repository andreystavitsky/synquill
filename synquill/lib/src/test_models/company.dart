// ignore_for_file: public_member_api_docs

import 'package:json_annotation/json_annotation.dart';

import 'package:synquill/src/test_models/index.dart';
part 'company.g.dart';

@JsonSerializable()
@SynquillRepository(
  relations: [
    OneToMany(target: Department, mappedBy: 'companyId', cascadeDelete: true),
    ManyToOne(target: Department, foreignKeyColumn: 'departmentId'),
  ],
)
class Company extends SynquillDataModel<Company> {
  @override
  final String id;
  final String name;

  // Company can be owned by a department (creating bidirectional cascade)
  final String? departmentId;

  Company({
    /// Unique identifier for the company (CUID)
    String? id,

    /// The name of the company
    required this.name,

    /// Optional department that owns this company
    this.departmentId,
  }) : id = id ?? generateCuid();

  Company.fromDb({required this.id, required this.name, this.departmentId});

  @override
  factory Company.fromJson(Map<String, dynamic> json) =>
      _$CompanyFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$CompanyToJson(this);
}
