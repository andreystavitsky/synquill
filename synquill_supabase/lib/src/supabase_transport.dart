import 'dart:async';

/// Transport-neutral description of a Supabase select request.
class SupabaseSelectRequest {
  /// Creates a select request.
  const SupabaseSelectRequest({
    required this.schema,
    required this.table,
    required this.selectColumns,
    required this.idColumn,
    this.filters = const [],
    this.sorts = const [],
    this.id,
    this.limit,
    this.rangeFrom,
    this.rangeTo,
    this.headers = const {},
  });

  /// The Postgres schema name.
  final String schema;

  /// The Supabase table or view name.
  final String table;

  /// The columns passed to Supabase `select()`.
  final String selectColumns;

  /// The model identity column.
  final String idColumn;

  /// Optional model id for single-record lookups.
  final String? id;

  /// Filters applied to the select request.
  final List<SupabaseFilter> filters;

  /// Sorts applied to the select request.
  final List<SupabaseSort> sorts;

  /// Supabase limit value.
  final int? limit;

  /// Inclusive range start.
  final int? rangeFrom;

  /// Inclusive range end.
  final int? rangeTo;

  /// Request headers merged from adapter defaults and per-call overrides.
  final Map<String, String> headers;
}

/// A transport-neutral Supabase filter.
class SupabaseFilter {
  /// Creates a filter.
  const SupabaseFilter({
    required this.field,
    required this.operator,
    required this.value,
  });

  /// Column name.
  final String field;

  /// Supabase/PostgREST operator.
  final String operator;

  /// Filter value.
  final Object? value;
}

/// A transport-neutral Supabase sort.
class SupabaseSort {
  /// Creates a sort.
  const SupabaseSort({
    required this.field,
    required this.ascending,
  });

  /// Column name.
  final String field;

  /// Whether the sort is ascending.
  final bool ascending;
}

/// Transport-neutral description of a Supabase mutation request.
class SupabaseMutationRequest {
  /// Creates a mutation request.
  const SupabaseMutationRequest({
    required this.schema,
    required this.table,
    required this.selectColumns,
    required this.idColumn,
    required this.values,
    this.id,
    this.headers = const {},
  });

  /// The Postgres schema name.
  final String schema;

  /// The Supabase table or view name.
  final String table;

  /// The columns passed to Supabase `select()`.
  final String selectColumns;

  /// The model identity column.
  final String idColumn;

  /// Optional model id for update-like mutations.
  final String? id;

  /// Values sent to Supabase.
  final Map<String, dynamic> values;

  /// Request headers merged from adapter defaults and per-call overrides.
  final Map<String, String> headers;
}

/// Transport-neutral description of a Supabase delete request.
class SupabaseDeleteRequest {
  /// Creates a delete request.
  const SupabaseDeleteRequest({
    required this.schema,
    required this.table,
    required this.idColumn,
    required this.id,
    this.headers = const {},
  });

  /// The Postgres schema name.
  final String schema;

  /// The Supabase table or view name.
  final String table;

  /// The model identity column.
  final String idColumn;

  /// The model id to delete.
  final String id;

  /// Request headers merged from adapter defaults and per-call overrides.
  final Map<String, String> headers;
}

/// Transport-neutral description of a Supabase realtime subscription.
class SupabaseRealtimeRequest {
  /// Creates a realtime request.
  const SupabaseRealtimeRequest({
    required this.schema,
    required this.table,
    required this.idColumn,
    this.id,
    this.filters = const [],
  });

  /// The Postgres schema name.
  final String schema;

  /// The Supabase table or view name.
  final String table;

  /// The model identity column.
  final String idColumn;

  /// Optional model id filter.
  final String? id;

  /// Additional query filters requested by Synquill.
  final List<SupabaseFilter> filters;
}

/// Transport-neutral Supabase realtime payload.
class SupabaseRealtimePayload {
  /// Creates a realtime payload.
  const SupabaseRealtimePayload({
    required this.eventType,
    this.newRecord,
    this.oldRecord,
    this.raw,
  });

  /// Supabase event type, such as INSERT, UPDATE, or DELETE.
  final String eventType;

  /// New row data for insert/update events.
  final Map<String, dynamic>? newRecord;

  /// Old row data for update/delete events.
  final Map<String, dynamic>? oldRecord;

  /// Raw SDK payload for diagnostics.
  final Object? raw;

  /// Creates a transport payload from a Supabase SDK payload.
  factory SupabaseRealtimePayload.fromSdk(Object payload) {
    final dynamic dynamicPayload = payload;
    return SupabaseRealtimePayload(
      eventType: _readDynamicString(dynamicPayload, 'eventType') ??
          _readDynamicString(dynamicPayload, 'type') ??
          dynamicPayload.toString(),
      newRecord: _readDynamicMap(dynamicPayload, 'newRecord') ??
          _readDynamicMap(dynamicPayload, 'new_record'),
      oldRecord: _readDynamicMap(dynamicPayload, 'oldRecord') ??
          _readDynamicMap(dynamicPayload, 'old_record'),
      raw: payload,
    );
  }
}

/// Testable boundary around the Supabase SDK.
abstract class SupabaseTransport {
  /// Selects zero or one row.
  Future<Map<String, dynamic>?> selectOne(SupabaseSelectRequest request);

  /// Selects many rows.
  Future<List<Map<String, dynamic>>> selectMany(
    SupabaseSelectRequest request,
  );

  /// Inserts one row and returns the selected server row when available.
  Future<Map<String, dynamic>?> insert(SupabaseMutationRequest request);

  /// Updates one row and returns the selected server row when available.
  Future<Map<String, dynamic>?> update(SupabaseMutationRequest request);

  /// Deletes one row.
  Future<void> delete(SupabaseDeleteRequest request);

  /// Subscribes to Supabase realtime row changes.
  Stream<SupabaseRealtimePayload> subscribeEvents(
    SupabaseRealtimeRequest request,
  );
}

/// Exception raised by the Supabase transport boundary.
class SupabaseTransportException implements Exception {
  /// Creates a transport exception.
  const SupabaseTransportException(
    this.message, {
    this.statusCode,
    this.code,
    this.fieldErrors,
    this.isNetworkError = false,
    this.isTimeout = false,
  });

  /// Error message.
  final String message;

  /// HTTP status code when available.
  final int? statusCode;

  /// Supabase/PostgREST error code when available.
  final String? code;

  /// Field validation errors when available.
  final Map<String, List<String>>? fieldErrors;

  /// Whether this represents a network failure.
  final bool isNetworkError;

  /// Whether this represents a timeout.
  final bool isTimeout;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' (Status: $statusCode)';
    return 'SupabaseTransportException: $message$status';
  }
}

String? _readDynamicString(dynamic object, String member) {
  try {
    final value = object.toJson?[member] ?? object[member];
    if (value is String) return value;
  } catch (_) {
    // Fall through to property access.
  }
  try {
    final value = switch (member) {
      'eventType' => object.eventType,
      'type' => object.type,
      _ => null,
    };
    if (value is String) return value;
    if (value != null) return value.toString().split('.').last;
  } catch (_) {
    return null;
  }
  return null;
}

Map<String, dynamic>? _readDynamicMap(dynamic object, String member) {
  Object? value;
  try {
    value = object.toJson?[member] ?? object[member];
  } catch (_) {
    // Fall through to property access.
  }
  try {
    value ??= switch (member) {
      'newRecord' => object.newRecord,
      'new_record' => object.newRecord,
      'oldRecord' => object.oldRecord,
      'old_record' => object.oldRecord,
      _ => null,
    };
  } catch (_) {
    return null;
  }
  if (value is! Map) return null;
  return value.map((key, val) => MapEntry(key.toString(), val));
}
