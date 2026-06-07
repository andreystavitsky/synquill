// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'category.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Category _$CategoryFromJson(Map<String, dynamic> json) => Category(
      id: json['id'] as String?,
      name: json['name'] as String,
      color: json['color'] as String,
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

Map<String, dynamic> _$CategoryToJson(Category instance) => <String, dynamic>{
      'lastSyncedAt': instance.lastSyncedAt?.toIso8601String(),
      'createdAt': instance.createdAt?.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
      'syncStatus': _$SyncStatusEnumMap[instance.syncStatus],
      'id': instance.id,
      'name': instance.name,
      'color': instance.color,
    };

const _$SyncStatusEnumMap = {
  SyncStatus.pending: 'pending',
  SyncStatus.processing: 'processing',
  SyncStatus.synced: 'synced',
  SyncStatus.dead: 'dead',
};
