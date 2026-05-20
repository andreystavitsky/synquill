import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:synquill/synquill.dart';
import 'package:synquill_graphql/src/graphql_batch_options.dart';
import 'package:synquill_graphql/src/mixins/graphql_error_handling_mixin.dart';
import 'package:synquill_graphql/src/mixins/graphql_response_parsing_mixin.dart';

/// Mixin for executing GraphQL operations using the Dio HTTP client.
mixin GraphQLExecutionMixin<TModel extends SynquillDataModel<TModel>>
    on
        ApiAdapterBase<TModel>,
        DioClientMixin<TModel>,
        GraphQLErrorHandlingMixin<TModel>,
        GraphQLResponseParsingMixin<TModel> {
  final Map<_GraphQLBatchKey, _GraphQLBatch> _graphqlBatches =
      <_GraphQLBatchKey, _GraphQLBatch>{};

  /// Configuration for GraphQL HTTP query batching.
  GraphQLBatchOptions get batchOptions => const GraphQLBatchOptions.disabled();

  /// Determines whether a GraphQL operation should use the batch queue.
  @protected
  bool shouldBatchGraphQLOperation({
    required String operation,
    Map<String, dynamic>? variables,
    Map<String, String>? headers,
    String? operationName,
    Map<String, dynamic>? extra,
  }) {
    if (!batchOptions.enabled || extra != null) return false;

    final trimmedOperation = operation.trimLeft();
    return trimmedOperation.startsWith('{') ||
        trimmedOperation.startsWith(RegExp(r'query\b'));
  }

  /// Core method: sends a GraphQL operation via POST to the endpoint.
  @protected
  Future<Map<String, dynamic>> executeGraphQLOperation({
    required String operation,
    Map<String, dynamic>? variables,
    Map<String, String>? headers,
    String? operationName,
    Map<String, dynamic>? extra,
  }) async {
    final operationBody = _GraphQLTransportOperation(
      operation: operation,
      variables: variables,
      operationName: operationName,
    );

    try {
      final mergedHeaders = await mergeHeadersWithContentType(
        headers,
        extra: extra,
      );

      if (shouldBatchGraphQLOperation(
        operation: operation,
        variables: variables,
        headers: headers,
        operationName: operationName,
        extra: extra,
      )) {
        return _enqueueGraphQLOperation(
          operation: operationBody,
          headers: mergedHeaders,
        );
      }

      final response = await _postGraphQLOperation(
        data: operationBody.toJson(),
        headers: mergedHeaders,
        extra: extra,
      );

      final responseData = response.data;
      if (responseData is! Map<String, dynamic>) {
        throw ApiException(
          'Invalid GraphQL response format. Expected JSON Object.',
          statusCode: response.statusCode,
        );
      }

      checkGraphQLErrors(responseData, response.statusCode);

      final data = responseData['data'];
      if (data is! Map<String, dynamic>) {
        return const {};
      }
      return data;
    } on DioException catch (e) {
      throw mapDioErrorToSynquillStorageException(e);
    } catch (e, st) {
      if (e is SynquillStorageException) rethrow;
      logger.severe('Unexpected error executing GraphQL operation', e, st);
      throw ApiException('GraphQL execution failed: $e');
    }
  }

  Future<Response<dynamic>> _postGraphQLOperation({
    required Object data,
    required Map<String, String> headers,
    Map<String, dynamic>? extra,
  }) {
    return dio.post<dynamic>(
      baseUrl.toString(),
      data: data,
      options: Options(
        headers: headers,
        extra: extra,
      ),
    );
  }

  Future<Map<String, dynamic>> _enqueueGraphQLOperation({
    required _GraphQLTransportOperation operation,
    required Map<String, String> headers,
  }) {
    final key = _GraphQLBatchKey(
      endpoint: baseUrl.toString(),
      headersKey: _canonicalHeadersKey(headers),
    );
    final batch = _graphqlBatches.putIfAbsent(
      key,
      () => _GraphQLBatch(
        timer: Timer(batchOptions.window, () => _flushGraphQLBatch(key)),
      ),
    );

    final completer = Completer<Map<String, dynamic>>();
    batch.items.add(
      _GraphQLBatchItem(
        operation: operation,
        headers: headers,
        completer: completer,
      ),
    );

    if (batch.items.length >= batchOptions.maxBatchSize) {
      _flushGraphQLBatch(key);
    }

    return completer.future;
  }

  void _flushGraphQLBatch(_GraphQLBatchKey key) {
    final batch = _graphqlBatches.remove(key);
    if (batch == null || batch.items.isEmpty) return;

    batch.timer.cancel();
    unawaited(_executeGraphQLBatch(batch.items));
  }

  Future<void> _executeGraphQLBatch(List<_GraphQLBatchItem> items) async {
    try {
      final response = await _postGraphQLOperation(
        data: items.map((item) => item.operation.toJson()).toList(),
        headers: items.first.headers,
      );

      final responseData = response.data;
      if (responseData is! List || responseData.length != items.length) {
        throw ApiException(
          'Invalid GraphQL batch response format. Expected JSON Array with '
          '${items.length} entries.',
          statusCode: response.statusCode,
        );
      }

      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        try {
          final entry = responseData[i];
          if (entry is! Map<String, dynamic>) {
            throw ApiException(
              'Invalid GraphQL batch response format. Expected JSON Object.',
              statusCode: response.statusCode,
            );
          }

          checkGraphQLErrors(entry, response.statusCode);

          final data = entry['data'];
          item.completer.complete(
            data is Map<String, dynamic> ? data : const <String, dynamic>{},
          );
        } catch (e, st) {
          item.completer.completeError(e, st);
        }
      }
    } on DioException catch (e, st) {
      final exception = mapDioErrorToSynquillStorageException(e);
      for (final item in items) {
        item.completer.completeError(exception, st);
      }
    } catch (e, st) {
      final exception = e is SynquillStorageException
          ? e
          : ApiException('GraphQL batch execution failed: $e');
      for (final item in items) {
        item.completer.completeError(exception, st);
      }
    }
  }

  String _canonicalHeadersKey(Map<String, String> headers) {
    final sortedKeys = headers.keys.toList()..sort();
    return jsonEncode({
      for (final key in sortedKeys) key: headers[key],
    });
  }

  /// Converts [QueryParams] to GraphQL variables.
  @protected
  Map<String, dynamic> queryParamsToGraphQLVariables(QueryParams? queryParams) {
    if (queryParams == null || !queryParams.hasParameters) {
      return const {};
    }

    final variables = <String, dynamic>{};

    // 1. Map Filters
    if (queryParams.hasFilters) {
      final filterMap = <String, Map<String, dynamic>>{};
      for (final filter in queryParams.filters) {
        final fieldName = filter.field.fieldName;
        final op = _getOperatorString(filter.operator);
        final val = _getFilterValue(filter.value);

        filterMap.putIfAbsent(fieldName, () => {})[op] = val;
      }
      variables['filter'] = filterMap;
    }

    // 2. Map Sorts
    if (queryParams.hasSorts) {
      final sortList = queryParams.sorts.map((sort) {
        return {
          'field': sort.field.fieldName,
          'direction':
              sort.direction == SortDirection.ascending ? 'ASC' : 'DESC',
        };
      }).toList();
      variables['sort'] = sortList;
    }

    // 3. Map Pagination
    if (queryParams.hasPagination) {
      final pag = queryParams.pagination!;
      variables['pagination'] = {
        'limit': pag.limit,
        'offset': pag.offset,
      };
    }

    return variables;
  }

  String _getOperatorString(FilterOperator op) {
    switch (op) {
      case FilterOperator.equals:
        return 'eq';
      case FilterOperator.notEquals:
        return 'neq';
      case FilterOperator.greaterThan:
        return 'gt';
      case FilterOperator.greaterThanOrEqual:
        return 'gte';
      case FilterOperator.lessThan:
        return 'lt';
      case FilterOperator.lessThanOrEqual:
        return 'lte';
      case FilterOperator.contains:
        return 'contains';
      case FilterOperator.startsWith:
        return 'startsWith';
      case FilterOperator.endsWith:
        return 'endsWith';
      case FilterOperator.inList:
        return 'in';
      case FilterOperator.notInList:
        return 'notIn';
      case FilterOperator.isNull:
        return 'isNull';
      case FilterOperator.isNotNull:
        return 'isNotNull';
    }
  }

  dynamic _getFilterValue(FilterValue value) {
    switch (value) {
      case SingleValue(:final value):
        return value;
      case ListValue(:final values):
        return values;
      case NoValue():
        return true;
    }
  }

  /// Executes a single document findOne request.
  @protected
  Future<TModel?> executeFindOneRequest({
    required String query,
    required String responseField,
    required String id,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final data = await executeGraphQLOperation(
      operation: query,
      variables: {'id': id},
      headers: headers,
      extra: extra,
    );
    return parseFindOneGraphQLResponse(data, responseField);
  }

  /// Executes a findAll query request.
  @protected
  Future<List<TModel>> executeFindAllRequest({
    required String query,
    required String responseField,
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final vars = queryParamsToGraphQLVariables(queryParams);
    final data = await executeGraphQLOperation(
      operation: query,
      variables: vars.isEmpty ? null : vars,
      headers: headers,
      extra: extra,
    );
    return parseFindAllGraphQLResponse(data, responseField);
  }

  /// Executes a createOne mutation request.
  @protected
  Future<TModel?> executeCreateRequest({
    required String mutation,
    required String responseField,
    required TModel model,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final data = await executeGraphQLOperation(
      operation: mutation,
      variables: {'input': toJson(model)},
      headers: headers,
      extra: extra,
    );
    return parseCreateGraphQLResponse(data, responseField);
  }

  /// Executes an updateOne mutation request.
  @protected
  Future<TModel?> executeUpdateRequest({
    required String mutation,
    required String responseField,
    required String id,
    required Map<String, dynamic> updateFields,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final data = await executeGraphQLOperation(
      operation: mutation,
      variables: {'id': id, 'input': updateFields},
      headers: headers,
      extra: extra,
    );
    return parseUpdateGraphQLResponse(data, responseField);
  }

  /// Executes a replaceOne mutation request.
  @protected
  Future<TModel?> executeReplaceRequest({
    required String mutation,
    required String responseField,
    required TModel model,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final data = await executeGraphQLOperation(
      operation: mutation,
      variables: {'id': model.id, 'input': toJson(model)},
      headers: headers,
      extra: extra,
    );
    return parseReplaceGraphQLResponse(data, responseField);
  }

  /// Executes a deleteOne mutation request.
  @protected
  Future<void> executeDeleteRequest({
    required String mutation,
    required String responseField,
    required String id,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    await executeGraphQLOperation(
      operation: mutation,
      variables: {'id': id},
      headers: headers,
      extra: extra,
    );
  }
}

class _GraphQLTransportOperation {
  const _GraphQLTransportOperation({
    required this.operation,
    this.variables,
    this.operationName,
  });

  final String operation;
  final Map<String, dynamic>? variables;
  final String? operationName;

  Map<String, dynamic> toJson() {
    return {
      'query': operation,
      if (variables != null) 'variables': variables,
      if (operationName != null) 'operationName': operationName,
    };
  }
}

class _GraphQLBatchKey {
  const _GraphQLBatchKey({
    required this.endpoint,
    required this.headersKey,
  });

  final String endpoint;
  final String headersKey;

  @override
  bool operator ==(Object other) {
    return other is _GraphQLBatchKey &&
        endpoint == other.endpoint &&
        headersKey == other.headersKey;
  }

  @override
  int get hashCode => Object.hash(endpoint, headersKey);
}

class _GraphQLBatch {
  _GraphQLBatch({required this.timer});

  final Timer timer;
  final List<_GraphQLBatchItem> items = <_GraphQLBatchItem>[];
}

class _GraphQLBatchItem {
  _GraphQLBatchItem({
    required this.operation,
    required this.headers,
    required this.completer,
  });

  final _GraphQLTransportOperation operation;
  final Map<String, String> headers;
  final Completer<Map<String, dynamic>> completer;
}
