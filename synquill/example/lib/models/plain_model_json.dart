import 'package:json_annotation/json_annotation.dart';

import "index.dart";

part 'plain_model_json.g.dart';

@JsonSerializable()
@SynquillRepository()
class PlainModelJson extends SynquillDataModel<PlainModelJson> {
  @override
  final String id;
  final String name;
  final int value;

  PlainModelJson({required this.id, required this.name, required this.value});
  PlainModelJson.fromDb(
      {required this.id, required this.name, required this.value});

  @override
  factory PlainModelJson.fromJson(Map<String, dynamic> json) =>
      _$PlainModelJsonFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$PlainModelJsonToJson(this);
}
