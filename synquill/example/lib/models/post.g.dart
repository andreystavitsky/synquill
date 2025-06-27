// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'post.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Post _$PostFromJson(Map<String, dynamic> json) => Post(
      id: idMapper(json, 'id') as String?,
      title: json['title'] as String,
      userId: idMapper(json, 'userId') as String,
      body: json['body'] as String,
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

Map<String, dynamic> _$PostToJson(Post instance) => <String, dynamic>{
      'lastSyncedAt': instance.lastSyncedAt?.toIso8601String(),
      'createdAt': instance.createdAt?.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
      'syncStatus': _$SyncStatusEnumMap[instance.syncStatus],
      'id': instance.id,
      'title': instance.title,
      'body': instance.body,
      'userId': instance.userId,
    };

const _$SyncStatusEnumMap = {
  SyncStatus.pending: 'pending',
  SyncStatus.processing: 'processing',
  SyncStatus.synced: 'synced',
  SyncStatus.dead: 'dead',
};
