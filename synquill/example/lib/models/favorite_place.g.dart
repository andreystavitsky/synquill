// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite_place.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FavoritePlace _$FavoritePlaceFromJson(Map<String, dynamic> json) =>
    FavoritePlace(
      id: json['placeId'] as String?,
      title: json['title'] as String,
      address: json['address'] as String,
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

Map<String, dynamic> _$FavoritePlaceToJson(FavoritePlace instance) =>
    <String, dynamic>{
      'lastSyncedAt': instance.lastSyncedAt?.toIso8601String(),
      'createdAt': instance.createdAt?.toIso8601String(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
      'syncStatus': _$SyncStatusEnumMap[instance.syncStatus],
      'placeId': instance.id,
      'title': instance.title,
      'address': instance.address,
    };

const _$SyncStatusEnumMap = {
  SyncStatus.pending: 'pending',
  SyncStatus.processing: 'processing',
  SyncStatus.synced: 'synced',
  SyncStatus.dead: 'dead',
};
