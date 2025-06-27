// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todo.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Todo _$TodoFromJson(Map<String, dynamic> json) => Todo(
      id: idMapper(json, 'id') as String?,
      title: json['title'] as String,
      userId: idMapper(json, 'userId') as String,
      isCompleted: json['completed'] as bool,
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

Map<String, dynamic> _$TodoToJson(Todo instance) => <String, dynamic>{
      'lastSyncedAt': instance.lastSyncedAt?.toIso8601String(),
      'createdAt': instance.createdAt?.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
      'syncStatus': _$SyncStatusEnumMap[instance.syncStatus],
      'id': instance.id,
      'title': instance.title,
      'completed': instance.isCompleted,
      'userId': instance.userId,
    };

const _$SyncStatusEnumMap = {
  SyncStatus.pending: 'pending',
  SyncStatus.processing: 'processing',
  SyncStatus.synced: 'synced',
  SyncStatus.dead: 'dead',
};
