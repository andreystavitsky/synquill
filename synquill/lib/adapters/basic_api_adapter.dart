part of synquill;

/// {@template base_api_adapter}
/// Concrete implementation of [ApiAdapterBase] using Dio for HTTP requests.
///
/// This is the standard adapter provided by the library that users can extend
/// by simply overriding [baseUrl] and optionally [fromJson]/[toJson] methods.
///
/// Features:
/// - Complete HTTP implementation using Dio
/// - Automatic JSON serialization/deserialization
/// - Configurable timeouts and retry logic
/// - Proper error handling with typed exceptions
/// - Support for custom headers per request
/// - Request/response logging
///
/// Example usage:
/// ```dart
/// class EventAdapter extends BaseApiAdapter<Event> {
///   @override
///   Uri get baseUrl => Uri.parse('https://api.example.com/v1/');
///
///   @override
///   Event fromJson(Map<String, dynamic> json) => Event.fromJson(json);
///
///   @override
///   Map<String, dynamic> toJson(Event model) => model.toJson();
/// }
/// ```
/// {@endtemplate}
abstract class BasicApiAdapter<TModel extends SynquillDataModel<TModel>>
    extends ApiAdapterBase<TModel>
    with
        DioClientMixin<TModel>,
        ErrorHandlingMixin<TModel>,
        HttpExecutionMixin<TModel>,
        ResponseParsingMixin<TModel> {
  @override
  Future<TModel?> findOne(
    String id, {
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    return await executeFindOneRequest(
      id: id,
      headers: headers,
      queryParams: queryParams,
      extra: extra,
    );
  }

  @override
  Future<List<TModel>> findAll({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    return await executeFindAllRequest(
      headers: headers,
      queryParams: queryParams,
      extra: extra,
    );
  }

  @override
  Future<TModel?> createOne(
    TModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    logger.fine('Creating ${TModel.toString()} with ID ${model.id}');

    final result = await executeCreateRequest(
      model: model,
      headers: headers,
      extra: extra,
    );

    return result;
  }

  @override
  Future<TModel?> updateOne(
    TModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return await executeUpdateRequest(
      model: model,
      headers: headers,
      extra: extra,
    );
  }

  @override
  Future<TModel?> replaceOne(
    TModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return await executeReplaceRequest(
      model: model,
      headers: headers,
      extra: extra,
    );
  }

  @override
  Future<void> deleteOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return await executeDeleteRequest(id: id, headers: headers, extra: extra);
  }
}
