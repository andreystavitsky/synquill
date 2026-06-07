import 'dart:async';

import 'package:json_annotation/json_annotation.dart';
import 'index.dart';

part 'favorite_place.g.dart';

/// Example adapter for APIs that expose the model id as `placeId`.
mixin FavoritePlaceApiAdapter on BasicApiAdapter<FavoritePlace> {
  @override
  Logger get logger => Logger('FavoritePlaceApiAdapter');

  @override
  String get type => 'favorite_place';

  @override
  FutureOr<Uri> urlForUpdate(String id, {Map<String, dynamic>? extra}) {
    return baseUrl.resolve('$pluralType/$id');
  }

  @override
  FutureOr<Uri> urlForDelete(String id, {Map<String, dynamic>? extra}) {
    return baseUrl.resolve('$pluralType/$id');
  }
}

@JsonSerializable()
@SynquillRepository(
  adapters: [JsonApiAdapter, FavoritePlaceApiAdapter],
)
class FavoritePlace extends SynquillDataModel<FavoritePlace> {
  @override
  @JsonKey(name: 'placeId')
  final String id;

  final String title;
  final String address;

  FavoritePlace({
    String? id,
    required this.title,
    required this.address,
  }) : id = id ?? generateCuid();

  FavoritePlace.fromDb({
    required this.id,
    required this.title,
    required this.address,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSyncedAt,
  }) {
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
    this.lastSyncedAt = lastSyncedAt;
  }

  factory FavoritePlace.fromJson(Map<String, dynamic> json) {
    return _$FavoritePlaceFromJson(json);
  }

  @override
  Map<String, dynamic> toJson() => _$FavoritePlaceToJson(this);
}
