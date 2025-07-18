// ignore_for_file: public_member_api_docs

import 'package:json_annotation/json_annotation.dart';

import 'package:synquill/src/test_models/index.dart';

part 'contact.g.dart';

@JsonSerializable()
@SynquillRepository(
  relations: [ManyToOne(target: User, foreignKeyColumn: 'userId')],
)
class Contact extends ContactBase<Contact> {
  final String? importedContactId;

  final String userId;

  Contact({
    super.id,
    required super.fullName,
    super.avatarUrl,
    super.email,
    super.phoneNumber,
    required this.userId,
    this.importedContactId,
  });
  Contact.fromDb({
    required String super.id,
    required super.fullName,
    required super.avatarUrl,
    required super.email,
    required super.phoneNumber,
    required this.userId,
    this.importedContactId,
    super.birthday,
    super.fetchedAt,
  });

  /// Create Contact from JSON using generated function
  factory Contact.fromJson(Map<String, dynamic> json) =>
      _$ContactFromJson(json);

  /// Convert Contact to JSON using generated function
  @override
  Map<String, dynamic> toJson() => _$ContactToJson(this);
}
