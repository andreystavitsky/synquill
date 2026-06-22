import 'dart:async';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:supabase/supabase.dart';
import 'package:synquill/synquill_contracts.dart';
import 'package:synquill_supabase/src/supabase_transport.dart';

/// Base class for implementing Supabase API adapters in Synquill.
abstract class SupabaseApiAdapter<TModel extends SynquillDataModel<TModel>>
    extends ApiAdapterBase<TModel> implements RealtimeApiAdapter<TModel> {
  final Map<StreamController<RealtimeEvent<TModel>>,
          StreamSubscription<SupabaseRealtimePayload>>
      _activeRealtimeSubscriptions = <StreamController<RealtimeEvent<TModel>>,
          StreamSubscription<SupabaseRealtimePayload>>{};
  bool _disposed = false;

  /// The Supabase client used by this adapter.
  SupabaseClient get supabaseClient;

  /// The Postgres schema used by this adapter.
  String get schema => 'public';

  /// The Supabase table or view used by this adapter.
  String get tableName => pluralType;

  /// The column that stores Synquill model ids.
  String get idColumn => 'id';

  /// The columns requested from Supabase.
  String get selectColumns => '*';

  /// Boundary used for executing Supabase operations.
  SupabaseTransport get transport => SupabaseSdkTransport(supabaseClient);

  @override
  Uri get baseUrl => Uri.parse('supabase://$schema/$tableName');

  /// Logger for Supabase adapter operations.
  Logger get logger => Logger('SupabaseApiAdapter');

  SupabaseSelectRequest _selectRequest({
    String? id,
    QueryParams? queryParams,
    required Map<String, String> headers,
  }) {
    final mapped = queryParamsToSupabaseQuery(queryParams);
    return SupabaseSelectRequest(
      schema: schema,
      table: tableName,
      selectColumns: selectColumns,
      idColumn: idColumn,
      id: id,
      filters: mapped.filters,
      sorts: mapped.sorts,
      limit: mapped.limit,
      rangeFrom: mapped.rangeFrom,
      rangeTo: mapped.rangeTo,
      headers: headers,
    );
  }

  SupabaseMutationRequest _mutationRequest({
    required Map<String, dynamic> values,
    required Map<String, String> headers,
    String? id,
  }) {
    return SupabaseMutationRequest(
      schema: schema,
      table: tableName,
      selectColumns: selectColumns,
      idColumn: idColumn,
      id: id,
      values: values,
      headers: headers,
    );
  }

  SupabaseDeleteRequest _deleteRequest(
    String id, {
    required Map<String, String> headers,
  }) {
    return SupabaseDeleteRequest(
      schema: schema,
      table: tableName,
      idColumn: idColumn,
      id: id,
      headers: headers,
    );
  }

  SupabaseRealtimeRequest _realtimeRequest({
    String? id,
    QueryParams? queryParams,
  }) {
    final realtimeFilters = _realtimeFilters(queryParams, id: id);
    return SupabaseRealtimeRequest(
      schema: schema,
      table: tableName,
      idColumn: idColumn,
      id: id,
      filters: realtimeFilters,
    );
  }

  List<SupabaseFilter> _realtimeFilters(
    QueryParams? queryParams, {
    String? id,
  }) {
    final filters = queryParams?.filters ?? const <FilterCondition>[];
    if (filters.isEmpty) return const [];

    if (id != null) {
      throw ApiException(
        'Supabase realtime id subscriptions do not support additional '
        'query filters.',
      );
    }
    if (filters.length > 1) {
      throw ApiException(
        'Supabase realtime subscriptions support at most one query filter.',
      );
    }

    return [_filterToSupabaseRealtimeFilter(filters.single)];
  }

  SupabaseFilter _filterToSupabaseRealtimeFilter(FilterCondition filter) {
    final mapped = _filterToSupabaseFilter(filter);
    return SupabaseFilter(
      field: mapped.field,
      operator: _realtimeFilterOperator(mapped.operator),
      value: mapped.value,
    );
  }

  String _realtimeFilterOperator(String operator) {
    switch (operator) {
      case 'eq':
      case 'neq':
      case 'gt':
      case 'gte':
      case 'lt':
      case 'lte':
        return operator;
      case 'in':
        return operator;
      default:
        throw ApiException(
          'Supabase realtime subscriptions do not support filter operator '
          '$operator.',
        );
    }
  }

  /// Converts a model into values for Supabase insert.
  @protected
  Map<String, dynamic> toSupabaseInsertJson(TModel model) =>
      (this as ApiAdapterBase<TModel>).toJson(model);

  /// Converts a model into values for Supabase update.
  @protected
  Map<String, dynamic> toSupabaseUpdateJson(TModel model) =>
      (this as ApiAdapterBase<TModel>).toJson(model);

  /// Converts a model into values for Supabase replace.
  @protected
  Map<String, dynamic> toSupabaseReplaceJson(TModel model) =>
      (this as ApiAdapterBase<TModel>).toJson(model);

  /// Converts Synquill query parameters to a Supabase query plan.
  @protected
  SupabaseQueryPlan queryParamsToSupabaseQuery(QueryParams? queryParams) {
    if (queryParams == null || !queryParams.hasParameters) {
      return const SupabaseQueryPlan();
    }

    final filters = queryParams.filters.map(_filterToSupabaseFilter).toList();
    final sorts = queryParams.sorts.map((sort) {
      return SupabaseSort(
        field: sort.field.fieldName,
        ascending: sort.direction == SortDirection.ascending,
      );
    }).toList();

    final pagination = queryParams.pagination;
    if (pagination == null) {
      return SupabaseQueryPlan(filters: filters, sorts: sorts);
    }

    final limit = pagination.limit;
    final offset = pagination.offset;
    if (limit != null && limit <= 0) {
      throw ApiException('Supabase pagination limit must be greater than 0.');
    }
    if (offset != null && offset < 0) {
      throw ApiException('Supabase pagination offset cannot be negative.');
    }
    if (offset != null && limit == null) {
      throw ApiException(
        'Supabase offset pagination requires a limit so an inclusive range '
        'can be calculated.',
      );
    }
    if (offset != null) {
      return SupabaseQueryPlan(
        filters: filters,
        sorts: sorts,
        rangeFrom: offset,
        rangeTo: offset + limit! - 1,
      );
    }

    return SupabaseQueryPlan(
      filters: filters,
      sorts: sorts,
      limit: limit,
    );
  }

  SupabaseFilter _filterToSupabaseFilter(FilterCondition filter) {
    final field = filter.field.fieldName;
    final value = filter.value;

    switch (filter.operator) {
      case FilterOperator.equals:
        return SupabaseFilter(
          field: field,
          operator: 'eq',
          value: _singleFilterValue(value, filter.operator),
        );
      case FilterOperator.notEquals:
        return SupabaseFilter(
          field: field,
          operator: 'neq',
          value: _singleFilterValue(value, filter.operator),
        );
      case FilterOperator.greaterThan:
        return SupabaseFilter(
          field: field,
          operator: 'gt',
          value: _singleFilterValue(value, filter.operator),
        );
      case FilterOperator.greaterThanOrEqual:
        return SupabaseFilter(
          field: field,
          operator: 'gte',
          value: _singleFilterValue(value, filter.operator),
        );
      case FilterOperator.lessThan:
        return SupabaseFilter(
          field: field,
          operator: 'lt',
          value: _singleFilterValue(value, filter.operator),
        );
      case FilterOperator.lessThanOrEqual:
        return SupabaseFilter(
          field: field,
          operator: 'lte',
          value: _singleFilterValue(value, filter.operator),
        );
      case FilterOperator.contains:
        return SupabaseFilter(
          field: field,
          operator: 'ilike',
          value: '%${_singleFilterValue(value, filter.operator)}%',
        );
      case FilterOperator.startsWith:
        return SupabaseFilter(
          field: field,
          operator: 'ilike',
          value: '${_singleFilterValue(value, filter.operator)}%',
        );
      case FilterOperator.endsWith:
        return SupabaseFilter(
          field: field,
          operator: 'ilike',
          value: '%${_singleFilterValue(value, filter.operator)}',
        );
      case FilterOperator.inList:
        return SupabaseFilter(
          field: field,
          operator: 'in',
          value: _listFilterValue(value, filter.operator),
        );
      case FilterOperator.notInList:
        return SupabaseFilter(
          field: field,
          operator: 'not.in',
          value: _listFilterValue(value, filter.operator),
        );
      case FilterOperator.isNull:
        return SupabaseFilter(field: field, operator: 'is', value: null);
      case FilterOperator.isNotNull:
        return SupabaseFilter(field: field, operator: 'not.is', value: null);
    }
  }

  Object? _singleFilterValue(FilterValue value, FilterOperator operator) {
    if (value is SingleValue) {
      return value.value;
    }
    throw ApiException('Supabase filter $operator requires a single value.');
  }

  List<Object?> _listFilterValue(FilterValue value, FilterOperator operator) {
    if (value is ListValue) {
      if (value.values.isEmpty) {
        throw ApiException('Supabase filter $operator requires values.');
      }
      return List<Object?>.from(value.values);
    }
    throw ApiException('Supabase filter $operator requires a list value.');
  }

  /// Maps a Supabase transport error into Synquill exceptions.
  @protected
  SynquillStorageException mapSupabaseErrorToSynquillException(
    SupabaseTransportException error,
  ) {
    if (error.isNetworkError || error.isTimeout) {
      return NetworkException(error.message);
    }

    switch (error.statusCode) {
      case 400:
        if (error.fieldErrors != null) {
          return ValidationException(error.message, error.fieldErrors);
        }
        return ApiException(error.message, statusCode: error.statusCode);
      case 401:
        return AuthenticationException(error.message);
      case 403:
        return AuthorizationException(error.message);
      case 404:
        return ApiExceptionNotFound(error.message);
      case 409:
        return ConflictException(error.message);
      case 410:
        return ApiExceptionGone(error.message);
      default:
        final statusCode = error.statusCode;
        if (statusCode != null && statusCode >= 500) {
          return ServerException(error.message);
        }
        return ApiException(error.message, statusCode: statusCode);
    }
  }

  Future<TResult> _executeTransport<TResult>(
    String operation,
    Future<TResult> Function() action,
  ) async {
    try {
      return await action();
    } on SupabaseTransportException catch (e) {
      throw mapSupabaseErrorToSynquillException(e);
    } on SynquillStorageException {
      rethrow;
    } catch (e, st) {
      logger.severe('Unexpected Supabase $operation error', e, st);
      throw ApiException('Supabase $operation failed: $e');
    }
  }

  TModel? _parseOptionalRow(Map<String, dynamic>? row, String operation) {
    if (row == null) return null;
    try {
      return fromJson(row);
    } catch (e, st) {
      logger.severe('Error parsing Supabase $operation row', e, st);
      throw ApiException('Failed to parse Supabase row for $operation: $e');
    }
  }

  List<TModel> _parseRows(
    List<Map<String, dynamic>> rows,
    String operation,
  ) {
    try {
      return rows.map(fromJson).toList();
    } catch (e, st) {
      logger.severe('Error parsing Supabase $operation rows', e, st);
      throw ApiException('Failed to parse Supabase row for $operation: $e');
    }
  }

  @override
  Future<TModel?> findOne(
    String id, {
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    final mergedHeaders = await mergeHeaders(headers, extra: extra);
    final row = await _executeTransport(
      'findOne',
      () => transport.selectOne(
        _selectRequest(
          id: id,
          queryParams: queryParams,
          headers: mergedHeaders,
        ),
      ),
    );
    return _parseOptionalRow(row, 'findOne');
  }

  @override
  Future<List<TModel>> findAll({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    final mergedHeaders = await mergeHeaders(headers, extra: extra);
    final rows = await _executeTransport(
      'findAll',
      () => transport.selectMany(
        _selectRequest(queryParams: queryParams, headers: mergedHeaders),
      ),
    );
    return _parseRows(rows, 'findAll');
  }

  @override
  Future<TModel?> createOne(
    TModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final mergedHeaders = await mergeHeaders(headers, extra: extra);
    final row = await _executeTransport(
      'createOne',
      () => transport.insert(
        _mutationRequest(
          values: toSupabaseInsertJson(model),
          headers: mergedHeaders,
        ),
      ),
    );
    return _parseOptionalRow(row, 'createOne');
  }

  @override
  Future<TModel?> updateOne(
    TModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final mergedHeaders = await mergeHeaders(headers, extra: extra);
    final row = await _executeTransport(
      'updateOne',
      () => transport.update(
        _mutationRequest(
          id: model.id,
          values: toSupabaseUpdateJson(model),
          headers: mergedHeaders,
        ),
      ),
    );
    return _parseOptionalRow(row, 'updateOne');
  }

  @override
  Future<TModel?> replaceOne(
    TModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final mergedHeaders = await mergeHeaders(headers, extra: extra);
    final row = await _executeTransport(
      'replaceOne',
      () => transport.update(
        _mutationRequest(
          id: model.id,
          values: toSupabaseReplaceJson(model),
          headers: mergedHeaders,
        ),
      ),
    );
    return _parseOptionalRow(row, 'replaceOne');
  }

  @override
  Future<void> deleteOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final mergedHeaders = await mergeHeaders(headers, extra: extra);
    return _executeTransport(
      'deleteOne',
      () => transport.delete(_deleteRequest(id, headers: mergedHeaders)),
    );
  }

  @override
  Stream<RealtimeEvent<TModel>> subscribeEvents({
    String? id,
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) {
    late final StreamController<RealtimeEvent<TModel>> controller;

    Future<void> cleanup() async {
      final subscription = _activeRealtimeSubscriptions.remove(controller);
      await subscription?.cancel();
    }

    controller = StreamController<RealtimeEvent<TModel>>(
      onListen: () {
        if (_disposed) {
          controller
              .addError(ApiException('Supabase adapter has been disposed.'));
          unawaited(controller.close());
          return;
        }

        try {
          final subscription = transport
              .subscribeEvents(
                  _realtimeRequest(id: id, queryParams: queryParams))
              .listen(
            (payload) {
              try {
                controller.add(parseSupabaseRealtimePayload(payload));
              } catch (e, st) {
                controller.addError(
                  e is SynquillStorageException
                      ? e
                      : ApiException(
                          'Failed to parse Supabase realtime payload: $e'),
                  st,
                );
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              controller.addError(
                error is SupabaseTransportException
                    ? mapSupabaseErrorToSynquillException(error)
                    : error,
                stackTrace,
              );
            },
            onDone: () {
              _activeRealtimeSubscriptions.remove(controller);
              if (!controller.isClosed) {
                unawaited(controller.close());
              }
            },
          );
          _activeRealtimeSubscriptions[controller] = subscription;
        } catch (e, st) {
          controller.addError(
            e is SynquillStorageException
                ? e
                : ApiException('Supabase realtime subscription failed: $e'),
            st,
          );
          unawaited(controller.close());
        }
      },
      onCancel: cleanup,
    );

    return controller.stream;
  }

  /// Parses a Supabase realtime payload into Synquill's transport-neutral event.
  @protected
  RealtimeEvent<TModel> parseSupabaseRealtimePayload(
    SupabaseRealtimePayload payload,
  ) {
    final eventType = payload.eventType.toUpperCase();
    return switch (eventType) {
      'INSERT' => _parseRealtimeMutation(
          RealtimeEventType.created,
          payload.newRecord,
          payload,
        ),
      'UPDATE' => _parseRealtimeMutation(
          RealtimeEventType.updated,
          payload.newRecord,
          payload,
        ),
      'DELETE' => _parseRealtimeDelete(payload),
      _ => throw ApiException(
          'Unsupported Supabase realtime event type ${payload.eventType}.',
        ),
    };
  }

  RealtimeEvent<TModel> _parseRealtimeMutation(
    RealtimeEventType type,
    Map<String, dynamic>? record,
    SupabaseRealtimePayload payload,
  ) {
    if (record == null) {
      throw ApiException('Supabase realtime ${type.name} event missing row.');
    }
    final item = _parseOptionalRow(record, 'realtime ${type.name}');
    if (item == null) {
      throw ApiException('Supabase realtime ${type.name} event missing row.');
    }
    return RealtimeEvent<TModel>(
      type: type,
      id: item.id,
      item: item,
      raw: _rawRealtimePayload(payload),
    );
  }

  RealtimeEvent<TModel> _parseRealtimeDelete(
    SupabaseRealtimePayload payload,
  ) {
    final idValue =
        payload.oldRecord?[idColumn] ?? payload.newRecord?[idColumn];
    if (idValue is! String || idValue.isEmpty) {
      throw ApiException(
        'Supabase realtime delete event missing string id column "$idColumn".',
      );
    }
    return RealtimeEvent<TModel>(
      type: RealtimeEventType.deleted,
      id: idValue,
      raw: _rawRealtimePayload(payload),
    );
  }

  Map<String, dynamic> _rawRealtimePayload(SupabaseRealtimePayload payload) {
    return <String, dynamic>{
      'eventType': payload.eventType,
      if (payload.newRecord != null) 'newRecord': payload.newRecord,
      if (payload.oldRecord != null) 'oldRecord': payload.oldRecord,
    };
  }

  /// Disposes active realtime streams owned by this adapter.
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    final exception = ApiException('Supabase adapter has been disposed.');
    for (final controller in _activeRealtimeSubscriptions.keys.toList()) {
      if (!controller.isClosed) {
        controller.addError(exception);
        unawaited(controller.close());
      }
    }
    for (final subscription in _activeRealtimeSubscriptions.values.toList()) {
      unawaited(subscription.cancel());
    }
    _activeRealtimeSubscriptions.clear();
  }
}

/// Transport-neutral query plan produced from [QueryParams].
class SupabaseQueryPlan {
  /// Creates a query plan.
  const SupabaseQueryPlan({
    this.filters = const [],
    this.sorts = const [],
    this.limit,
    this.rangeFrom,
    this.rangeTo,
  });

  /// Filters to apply.
  final List<SupabaseFilter> filters;

  /// Sorts to apply.
  final List<SupabaseSort> sorts;

  /// Limit to apply.
  final int? limit;

  /// Inclusive range start.
  final int? rangeFrom;

  /// Inclusive range end.
  final int? rangeTo;
}

/// Default Supabase SDK transport.
class SupabaseSdkTransport implements SupabaseTransport {
  /// Creates an SDK transport.
  const SupabaseSdkTransport(this.client);

  static int _realtimeTopicSequence = 0;

  /// Supabase client to call.
  final SupabaseClient client;

  static int _nextRealtimeTopicSequence() {
    _realtimeTopicSequence += 1;
    return _realtimeTopicSequence;
  }

  dynamic _table(SupabaseSelectRequest request) {
    final dynamic dynamicClient = client;
    if (request.schema == 'public') {
      return dynamicClient.from(request.table);
    }
    return dynamicClient.schema(request.schema).from(request.table);
  }

  dynamic _mutationTable(SupabaseMutationRequest request) {
    final dynamic dynamicClient = client;
    if (request.schema == 'public') {
      return dynamicClient.from(request.table);
    }
    return dynamicClient.schema(request.schema).from(request.table);
  }

  dynamic _deleteTable(SupabaseDeleteRequest request) {
    final dynamic dynamicClient = client;
    if (request.schema == 'public') {
      return dynamicClient.from(request.table);
    }
    return dynamicClient.schema(request.schema).from(request.table);
  }

  @override
  Future<Map<String, dynamic>?> selectOne(
    SupabaseSelectRequest request,
  ) async {
    final dynamic result = await _wrapSdkCall(() {
      dynamic query = _table(request)
          .select(request.selectColumns)
          .eq(request.idColumn, request.id);
      query = _applyQueryPlan(query, request);
      query = _applyHeaders(query, request.headers);
      return query.maybeSingle();
    });
    if (result == null) return null;
    return _asStringDynamicMap(result);
  }

  @override
  Future<List<Map<String, dynamic>>> selectMany(
    SupabaseSelectRequest request,
  ) async {
    final dynamic result = await _wrapSdkCall(() {
      dynamic query = _table(request).select(request.selectColumns);
      query = _applyQueryPlan(query, request);
      query = _applyHeaders(query, request.headers);
      return query;
    });
    if (result is! List) return const [];
    return result.map((row) => _asStringDynamicMap(row)).toList();
  }

  @override
  Future<Map<String, dynamic>?> insert(
    SupabaseMutationRequest request,
  ) async {
    final dynamic result = await _wrapSdkCall(() {
      dynamic query = _mutationTable(request)
          .insert(request.values)
          .select(request.selectColumns)
          .maybeSingle();
      query = _applyHeaders(query, request.headers);
      return query;
    });
    if (result == null) return null;
    return _asStringDynamicMap(result);
  }

  @override
  Future<Map<String, dynamic>?> update(
    SupabaseMutationRequest request,
  ) async {
    final dynamic result = await _wrapSdkCall(() {
      dynamic query = _mutationTable(request)
          .update(request.values)
          .eq(request.idColumn, request.id)
          .select(request.selectColumns)
          .maybeSingle();
      query = _applyHeaders(query, request.headers);
      return query;
    });
    if (result == null) return null;
    return _asStringDynamicMap(result);
  }

  @override
  Future<void> delete(SupabaseDeleteRequest request) async {
    await _wrapSdkCall(() {
      dynamic query = _deleteTable(request).delete().eq(
            request.idColumn,
            request.id,
          );
      query = _applyHeaders(query, request.headers);
      return query;
    });
  }

  @override
  Stream<SupabaseRealtimePayload> subscribeEvents(
    SupabaseRealtimeRequest request,
  ) {
    final controller = StreamController<SupabaseRealtimePayload>();
    final dynamic dynamicClient = client;
    var cancelled = false;
    final dynamic channel = dynamicClient.channel(
      'synquill:${request.schema}:${request.table}:${request.id ?? '*'}:'
      '${_nextRealtimeTopicSequence()}',
    );

    void addErrorAndClose(SupabaseTransportException error) {
      scheduleMicrotask(() {
        if (cancelled || controller.isClosed) return;
        controller.addError(error);
        unawaited(controller.close());
      });
    }

    try {
      final filter = _postgresChangeFilter(request);
      final dynamic configured = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: request.schema,
        table: request.table,
        filter: filter,
        callback: (dynamic payload) {
          controller.add(SupabaseRealtimePayload.fromSdk(payload));
        },
      );
      configured.subscribe(
        (RealtimeSubscribeStatus status, [Object? error]) {
          switch (status) {
            case RealtimeSubscribeStatus.subscribed:
              return;
            case RealtimeSubscribeStatus.timedOut:
              addErrorAndClose(
                const SupabaseTransportException(
                  'Supabase realtime subscription timed out.',
                  isNetworkError: true,
                  isTimeout: true,
                ),
              );
            case RealtimeSubscribeStatus.closed:
              if (cancelled) return;
              addErrorAndClose(
                const SupabaseTransportException(
                  'Supabase realtime subscription closed.',
                  isNetworkError: true,
                ),
              );
            case RealtimeSubscribeStatus.channelError:
              addErrorAndClose(
                SupabaseTransportException(
                  'Supabase realtime subscription failed: '
                  '${error ?? 'channel error'}',
                ),
              );
          }
        },
      );
    } on SupabaseTransportException catch (e, st) {
      scheduleMicrotask(() {
        controller.addError(e, st);
        unawaited(controller.close());
      });
    } catch (e, st) {
      scheduleMicrotask(() {
        controller.addError(
          _transportExceptionFromSdk(e),
          st,
        );
        unawaited(controller.close());
      });
    }

    controller.onCancel = () async {
      cancelled = true;
      await dynamicClient.removeChannel(channel);
    };
    return controller.stream;
  }

  Future<TResult> _wrapSdkCall<TResult>(
    FutureOr<TResult> Function() action,
  ) async {
    try {
      return await action();
    } on SupabaseTransportException {
      rethrow;
    } catch (e, st) {
      Error.throwWithStackTrace(_transportExceptionFromSdk(e), st);
    }
  }

  SupabaseTransportException _transportExceptionFromSdk(Object error) {
    if (error is SupabaseTransportException) return error;
    if (error is PostgrestException) {
      final code = error.code;
      return SupabaseTransportException(
        error.message,
        code: code,
        statusCode: _numericStatusCode(code),
      );
    }
    if (error is TimeoutException) {
      return SupabaseTransportException(
        error.message ?? error.toString(),
        isNetworkError: true,
        isTimeout: true,
      );
    }
    if (_isSocketException(error)) {
      return SupabaseTransportException(
        _messageFromSdkException(error),
        isNetworkError: true,
      );
    }
    if (_isClientException(error)) {
      return SupabaseTransportException(
        error.toString(),
        isNetworkError: true,
      );
    }
    return SupabaseTransportException('Supabase SDK request failed: $error');
  }

  int? _numericStatusCode(String? code) {
    if (code == null) return null;
    final numericCode = int.tryParse(code);
    if (numericCode != null && numericCode >= 100 && numericCode <= 599) {
      return numericCode;
    }
    return _knownPostgrestStatusCode(code);
  }

  int? _knownPostgrestStatusCode(String code) {
    return switch (code) {
      // PostgreSQL unique_violation. PostgREST commonly reports this as 409.
      '23505' => 409,
      _ => null,
    };
  }

  bool _isClientException(Object error) {
    final typeName = error.runtimeType.toString();
    return typeName == 'ClientException' ||
        typeName.endsWith('ClientException');
  }

  bool _isSocketException(Object error) {
    final typeName = error.runtimeType.toString();
    return typeName == 'SocketException' ||
        typeName.endsWith('SocketException');
  }

  String _messageFromSdkException(Object error) {
    final dynamic dynamicError = error;
    try {
      final message = dynamicError.message;
      if (message is String && message.isNotEmpty) return message;
    } catch (_) {
      // Fall through to the full exception text.
    }
    return error.toString();
  }

  PostgresChangeFilter? _postgresChangeFilter(
    SupabaseRealtimeRequest request,
  ) {
    final id = request.id;
    if (id != null) {
      if (request.filters.isNotEmpty) {
        throw const SupabaseTransportException(
          'Supabase realtime id subscriptions do not support additional '
          'query filters.',
          statusCode: 400,
        );
      }
      return PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: request.idColumn,
        value: id,
      );
    }

    if (request.filters.isEmpty) return null;
    if (request.filters.length > 1) {
      throw const SupabaseTransportException(
        'Supabase realtime subscriptions support at most one query filter.',
        statusCode: 400,
      );
    }

    final filter = request.filters.single;
    return PostgresChangeFilter(
      type: _postgresChangeFilterType(filter.operator),
      column: filter.field,
      value: filter.value,
    );
  }

  PostgresChangeFilterType _postgresChangeFilterType(String operator) {
    switch (operator) {
      case 'eq':
        return PostgresChangeFilterType.eq;
      case 'neq':
        return PostgresChangeFilterType.neq;
      case 'lt':
        return PostgresChangeFilterType.lt;
      case 'lte':
        return PostgresChangeFilterType.lte;
      case 'gt':
        return PostgresChangeFilterType.gt;
      case 'gte':
        return PostgresChangeFilterType.gte;
      case 'in':
      case 'inFilter':
        return PostgresChangeFilterType.inFilter;
      default:
        throw SupabaseTransportException(
          'Unsupported Supabase realtime filter operator $operator',
          statusCode: 400,
        );
    }
  }

  Map<String, dynamic> _asStringDynamicMap(Object? value) {
    if (value is! Map) {
      throw StateError(
          'Expected Supabase row object, got ${value.runtimeType}');
    }
    return value.map((key, val) => MapEntry(key.toString(), val));
  }

  dynamic _applyQueryPlan(dynamic query, SupabaseSelectRequest request) {
    var current = query;
    for (final filter in request.filters) {
      current = _applyFilter(current, filter);
    }
    for (final sort in request.sorts) {
      current = current.order(sort.field, ascending: sort.ascending);
    }
    final rangeFrom = request.rangeFrom;
    final rangeTo = request.rangeTo;
    if (rangeFrom != null && rangeTo != null) {
      current = current.range(rangeFrom, rangeTo);
    } else if (request.limit != null) {
      current = current.limit(request.limit);
    }
    return current;
  }

  dynamic _applyHeaders(dynamic query, Map<String, String> headers) {
    var current = query;
    for (final entry in headers.entries) {
      current = current.setHeader(entry.key, entry.value);
    }
    return current;
  }

  dynamic _applyFilter(dynamic query, SupabaseFilter filter) {
    switch (filter.operator) {
      case 'eq':
        return query.eq(filter.field, filter.value);
      case 'neq':
        return query.neq(filter.field, filter.value);
      case 'gt':
        return query.gt(filter.field, filter.value);
      case 'gte':
        return query.gte(filter.field, filter.value);
      case 'lt':
        return query.lt(filter.field, filter.value);
      case 'lte':
        return query.lte(filter.field, filter.value);
      case 'ilike':
        return query.ilike(filter.field, filter.value);
      case 'in':
        return query.inFilter(filter.field, filter.value);
      case 'not.in':
        return query.not(filter.field, 'in', filter.value);
      case 'is':
        return query.isFilter(filter.field, filter.value);
      case 'not.is':
        return query.not(filter.field, 'is', filter.value);
      default:
        throw SupabaseTransportException(
          'Unsupported Supabase filter operator ${filter.operator}',
          statusCode: 400,
        );
    }
  }
}
