part of synquill;

/// {@template http_execution_mixin}
/// Mixin that provides HTTP execution functionality for API adapters.
///
/// Handles:
/// - Low-level HTTP request execution
/// - Operation-specific request methods (findOne, findAll, create, etc.)
/// - Request headers and parameters handling
/// {@endtemplate}
mixin HttpExecutionMixin<TModel extends SynquillDataModel<TModel>>
    on
        ApiAdapterBase<TModel>,
        DioClientMixin<TModel>,
        ErrorHandlingMixin<TModel> {
  // ==========================================================================
  // Protected HTTP Execution Methods
  // ==========================================================================

  /// Executes an HTTP request using the configured Dio client.
  ///
  /// This is the low-level method that performs the actual HTTP request.
  /// Override this method to customize request execution (e.g., custom
  /// authentication, request signing, retry logic).
  ///
  /// Handles HTTP-level errors (network, timeouts, HTTP status codes) and
  /// throws appropriate [SynquillStorageException]s.
  @protected
  Future<Response<T>> executeRequest<T>({
    required String method,
    required Uri uri,
    Object? data,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? extra,
  }) async {
    try {
      return await dio.request<T>(
        uri.toString(),
        data: data,
        queryParameters:
            queryParameters?.isNotEmpty == true ? queryParameters : null,
        options: Options(method: method, headers: headers),
      );
    } on DioException catch (e) {
      throw mapDioErrorToSyncedStorageException(e);
    }
  }

  // ==========================================================================
  // Protected Operation-Specific Request Methods
  // ==========================================================================

  /// Executes a findOne request.
  ///
  /// Override this method to customize how single resource queries are executed
  /// (e.g., adding caching, custom error handling).
  @protected
  Future<TModel?> executeFindOneRequest({
    required String id,
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    try {
      final mergedHeaders = await mergeHeaders(headers, extra: extra);
      final httpQueryParams = queryParamsToHttpParams(queryParams);
      final uri = await urlForFindOne(id, extra: extra);

      final response = await executeRequest<dynamic>(
        method: methodForFind(extra: extra),
        uri: uri,
        headers: mergedHeaders,
        queryParameters: httpQueryParams.isNotEmpty ? httpQueryParams : null,
        extra: extra,
      );

      return parseFindOneResponse(response.data, response);
    } on ApiExceptionNotFound catch (_) {
      // For findOne, 404 should return null instead of throwing
      return null;
    } on ApiExceptionGone catch (_) {
      // For findOne, 410 should return null instead of throwing
      return null;
    }
  }

  /// Executes a findAll request.
  ///
  /// Override this method to customize how collection queries are executed
  /// (e.g., automatic pagination, custom filtering).
  @protected
  Future<List<TModel>> executeFindAllRequest({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    final mergedHeaders = await mergeHeaders(headers, extra: extra);
    final httpQueryParams = queryParamsToHttpParams(queryParams);
    final uri = await urlForFindAll(extra: extra);

    final response = await executeRequest<dynamic>(
      method: methodForFind(extra: extra),
      uri: uri,
      headers: mergedHeaders,
      queryParameters: httpQueryParams.isNotEmpty ? httpQueryParams : null,
      extra: extra,
    );

    return parseFindAllResponse(response.data, response);
  }

  /// Executes a create request.
  ///
  /// Override this method to customize how resource creation is executed
  /// (e.g., validation, side effects).
  @protected
  Future<TModel?> executeCreateRequest({
    required TModel model,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final mergedHeaders = await mergeHeaders(headers, extra: extra);
    final uri = await urlForCreate(extra: extra);

    final response = await executeRequest<dynamic>(
      method: methodForCreate(extra: extra),
      uri: uri,
      data: toJson(model),
      headers: mergedHeaders,
      extra: extra,
    );

    return parseCreateResponse(response.data, response);
  }

  /// Executes an update request.
  ///
  /// Override this method to customize how resource updates are executed
  /// (e.g., optimistic updates, conflict resolution).
  @protected
  Future<TModel?> executeUpdateRequest({
    required TModel model,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final mergedHeaders = await mergeHeaders(headers, extra: extra);
    final uri = await urlForUpdate(model.id, extra: extra);

    final response = await executeRequest<dynamic>(
      method: methodForUpdate(extra: extra),
      uri: uri,
      data: toJson(model),
      headers: mergedHeaders,
      extra: extra,
    );

    return parseUpdateResponse(response.data, response);
  }

  /// Executes a replace request.
  ///
  /// Override this method to customize how resource replacement is executed
  /// (e.g., validation, side effects).
  @protected
  Future<TModel?> executeReplaceRequest({
    required TModel model,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final mergedHeaders = await mergeHeaders(headers, extra: extra);
    final uri = await urlForReplace(model.id, extra: extra);

    final response = await executeRequest<dynamic>(
      method: methodForReplace(extra: extra),
      uri: uri,
      data: toJson(model),
      headers: mergedHeaders,
      extra: extra,
    );

    return parseReplaceResponse(response.data, response);
  }

  /// Executes a delete request.
  ///
  /// Override this method to customize how resource deletion is executed
  /// (e.g., soft deletes, cascading deletes).
  @protected
  Future<void> executeDeleteRequest({
    required String id,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final mergedHeaders = await mergeHeaders(headers, extra: extra);
    final uri = await urlForDelete(id, extra: extra);

    await executeRequest<void>(
      method: methodForDelete(extra: extra),
      uri: uri,
      headers: mergedHeaders,
      extra: extra,
    );
  }

  // ==========================================================================
  // Abstract Response Parsing Methods (implemented by ResponseParsingMixin)
  // ==========================================================================

  /// Parses a findOne response.
  ///
  /// Override this method to customize how single resource responses
  /// are parsed.
  @protected
  TModel? parseFindOneResponse(dynamic responseData, Response response);

  /// Parses a findAll response.
  ///
  /// Override this method to customize how collection responses are parsed.
  @protected
  List<TModel> parseFindAllResponse(dynamic responseData, Response response);

  /// Parses a create response.
  ///
  /// Override this method to customize how creation responses are parsed.
  @protected
  TModel? parseCreateResponse(dynamic responseData, Response response);

  /// Parses an update response.
  ///
  /// Override this method to customize how update responses are parsed.
  @protected
  TModel? parseUpdateResponse(dynamic responseData, Response response);

  /// Parses a replace response.
  ///
  /// Override this method to customize how replace responses are parsed.
  @protected
  TModel? parseReplaceResponse(dynamic responseData, Response response);
}
