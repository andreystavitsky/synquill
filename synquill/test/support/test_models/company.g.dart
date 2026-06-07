// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'company.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Company _$CompanyFromJson(Map<String, dynamic> json) => Company(
      id: json['id'] as String?,
      name: json['name'] as String,
      departmentId: json['departmentId'] as String?,
    )
      ..lastSyncedAt = json['lastSyncedAt'] == null
          ? null
          : DateTime.parse(json['lastSyncedAt'] as String)
      ..createdAt = json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String)
      ..updatedAt = json['updatedAt'] == null
          ? null
          : DateTime.parse(json['updatedAt'] as String)
      ..syncStatus =
          $enumDecodeNullable(_$SyncStatusEnumMap, json['syncStatus']);

Map<String, dynamic> _$CompanyToJson(Company instance) => <String, dynamic>{
      'lastSyncedAt': instance.lastSyncedAt?.toIso8601String(),
      'createdAt': instance.createdAt?.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
      'syncStatus': _$SyncStatusEnumMap[instance.syncStatus],
      'id': instance.id,
      'name': instance.name,
      'departmentId': instance.departmentId,
    };

const _$SyncStatusEnumMap = {
  SyncStatus.pending: 'pending',
  SyncStatus.processing: 'processing',
  SyncStatus.synced: 'synced',
  SyncStatus.dead: 'dead',
};
