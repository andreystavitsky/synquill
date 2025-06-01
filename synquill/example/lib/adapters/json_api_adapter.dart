import 'dart:async';

import 'package:synquill/synquill.dart';

/// A base adapter for JSON APIs that can be extended by model-specific adapters.
/// It overrides the baseHeaders to include a custom 'X-App-Version' header.
mixin JsonApiAdapter<TModel extends SynquillDataModel<TModel>>
    on BasicApiAdapter<TModel> {
  @override
  final Logger logger = Logger('JsonApiAdapter');
  // All models using this adapter will share this base URL unless overridden
  // by a more specific adapter.
  @override
  Uri get baseUrl => Uri.parse('https://jsonplaceholder.typicode.com/');

  @override
  FutureOr<Map<String, String>> get baseHeaders async {
    final headers = await super.baseHeaders;

    return {
      ...headers,
      ...{
        'X-App-Version': '1.0.0-example',
        'X-Custom-Global-Header': 'GlobalValue'
      }
    };
  }

  // fromJson and toJson must be implemented by concrete model-specific
  // adapters that extend this class, or by the models themselves if
  // this adapterwere to be used directly (which is not the case here as
  // it's a base).

  @override
  TModel fromJson(Map<String, dynamic> json) {
    // This will be effectively overridden by the model-specific adapter's
    // fromJson or the model's fromJson if this adapter were used directly.
    // Throwing an error here to ensure it's implemented by subclasses.
    throw UnimplementedError('fromJson must be implemented in the '
        'concrete model-specific adapter or model.');
  }

  @override
  Map<String, dynamic> toJson(TModel model) {
    // This will be effectively overridden by the model-specific adapter's
    // toJson or the model's toJson if this adapter were used directly.
    // Throwing an error here to ensure it's implemented by subclasses.
    throw UnimplementedError('toJson must be implemented in the '
        'concrete model-specific adapter or model.');
  }
}

Object? idMapper(Map<dynamic, dynamic> json, String field) {
  final value = json[field];
  if (value == null) return null;
  if (value is String) return value;
  if (value is int) return value.toString();
  if (value is List<int>) return value.map((e) => e.toString()).toList();
  return value.toString();
}
