import 'package:json_annotation/json_annotation.dart';
import 'index.dart';

part 'app_user.g.dart';

mixin AppUserApiAdapter on BasicApiAdapter<AppUser> {
  @override
  String get type => 'users';
}

@JsonSerializable()
@SynquillRepository(adapters: [JsonApiAdapter, AppUserApiAdapter])
class AppUser extends ContactBase<AppUser> {
  final int timeZone;
  final int utcNotificationHour;
  final bool notifyTenDays;
  final bool notifyThreeDays;
  final bool notifyOneDay;
  final bool notifyEmail;

  @OneToMany(target: Contact, mappedBy: 'userId')
  final List<String> contactIds;

  AppUser({
    super.id,
    super.fullName,
    super.avatarUrl,
    super.birthday,
    super.email,
    super.phoneNumber,
    this.timeZone = 0,
    this.contactIds = const [],
    this.utcNotificationHour = 0,
    this.notifyTenDays = true,
    this.notifyThreeDays = true,
    this.notifyOneDay = true,
    this.notifyEmail = true,
  });

  @override
  factory AppUser.fromJson(Map<String, dynamic> json) =>
      _$AppUserFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$AppUserToJson(this);

  AppUser.fromDb({
    required String super.id,
    required super.fullName,
    required super.avatarUrl,
    required super.birthday,
    required super.email,
    required super.phoneNumber,
    required this.timeZone,
    this.contactIds = const [],
    required this.utcNotificationHour,
    required this.notifyTenDays,
    required this.notifyThreeDays,
    required this.notifyOneDay,
    required this.notifyEmail,
    super.fetchedAt,
  });
}
