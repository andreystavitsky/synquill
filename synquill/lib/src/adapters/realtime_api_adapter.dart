import 'dart:async';

import 'package:synquill/src/core/query_parameters.dart';
import 'package:synquill/src/core/realtime_event.dart';
import 'package:synquill/src/core/synquill_data_model.dart';

/// Optional capability for adapters that can stream remote realtime changes.
abstract class RealtimeApiAdapter<TModel extends SynquillDataModel<TModel>> {
  /// Subscribes to remote realtime events for this model type.
  ///
  /// [id] scopes the stream to one model when provided. [queryParams] may be
  /// passed to transports that support filtered subscriptions.
  Stream<RealtimeEvent<TModel>> subscribeEvents({
    String? id,
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  });
}
