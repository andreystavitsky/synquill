import 'package:json_annotation/json_annotation.dart';

import 'index.dart';

part 'contact.g.dart';

@JsonSerializable()
@SynquillRepository()
class Contact extends ContactBase<Contact> {
  final String? importedContactId;

  @ManyToOne(target: User, foreignKeyColumn: 'userId')
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
