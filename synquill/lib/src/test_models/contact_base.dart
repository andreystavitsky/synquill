// ignore_for_file: public_member_api_docs

import 'package:synquill/src/test_models/index.dart';

abstract class ContactBase<T extends ContactBase<T>>
    extends SynquillDataModel<T> {
  @override
  final String id;

  final DateTime? birthday;

  final String? fullName;

  final String? avatarUrl;

  final String? phoneNumber;

  final String? email;

  final DateTime fetchedAt;

  ContactBase({
    String? id,
    this.birthday,
    this.fullName,
    this.avatarUrl,
    this.phoneNumber,
    this.email,
    DateTime? fetchedAt,
  })  : fetchedAt = fetchedAt ?? DateTime.now(),
        id = id ?? generateCuid();
}
