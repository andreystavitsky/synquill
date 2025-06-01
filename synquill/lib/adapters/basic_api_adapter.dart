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
    extends ApiAdapterBase<TModel> {
  /// The Dio client used for HTTP requests.
  ///
  /// Lazily initialized. If `SynquillStorage.config?.dio` is provided,
  /// it's used; otherwise, a new client is created with default settings.
  late final Dio _dio = SynquillStorage.config?.dio ?? _createDioClient();

  /// Logger instance for this adapter.
  Logger get logger => Logger('BasicApiAdapter');

  Dio _createDioClient() {
    final dio = Dio();
    final config = SynquillStorage.config;

    dio.options = BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      responseType: ResponseType.json,
      followRedirects: true,
      maxRedirects: 3,
    );

    dio.interceptors.add(
      LogInterceptor(
        logPrint: (obj) => logger.info(obj.toString()),
        requestBody: config?.recordRequestBody ?? false,
        responseBody: config?.recordResponseBody ?? false,
        requestHeader: config?.recordRequestHeaders ?? false,
        responseHeader: config?.recordResponseHeaders ?? false,
      ),
    );

    // Error handling interceptor:
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException e, handler) {
          logger.severe(
            'DioError in Interceptor: ${e.type}',
            e.error,
            e.stackTrace,
          );
          return handler.next(e);
        },
      ),
    );

    return dio;
  }

  SynquillStorageException _mapDioErrorToSyncedStorageException(
    DioException error,
  ) {
    logger.warning(
      'Mapping DioError: ${error.type}',
      error.error,
      error.stackTrace,
    );
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkException(
          'Connection timeout: ${error.message ?? "Unknown error"}',
          error.stackTrace,
        );
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        final responseData = error.response?.data;
        final validationErrors = _extractValidationErrors(responseData);

        switch (statusCode) {
          case 400:
            if (validationErrors != null) {
              return ValidationException(
                'Validation failed',
                validationErrors,
                error.stackTrace,
              );
            }
            break;
          case 401:
            return AuthenticationException(
              'Authentication failed: '
              '${error.message ?? "Invalid credentials"}',
              error.stackTrace,
            );
          case 403:
            return AuthorizationException(
              'Authorization failed: '
              '${error.message ?? "Permission denied"}',
              error.stackTrace,
            );
          case 404:
            return ApiExceptionNotFound(
              error.requestOptions.path,
              stackTrace: error.stackTrace,
            );
          case 409:
            return ConflictException(
              'Conflict: ${error.message ?? "Resource conflict"}',
              error.stackTrace,
            );
          case 410:
            return ApiExceptionGone(
              error.requestOptions.path,
              stackTrace: error.stackTrace,
            );
          default:
            if (statusCode != null && statusCode >= 500) {
              return ServerException(
                'Server error: ${error.message ?? "Internal server error"}',
                error.stackTrace,
              );
            }
        }
        return ApiException(
          'API error: ${error.message ?? "Unknown API error"}',
          statusCode: statusCode,
          stackTrace: error.stackTrace,
        );
      case DioExceptionType.connectionError:
        return NetworkException(
          'Connection error: '
          '${error.message ?? "Failed to connect to the server"}',
          error.stackTrace,
        );
      case DioExceptionType.badCertificate:
        return NetworkException(
          'Bad certificate: ${error.message ?? "Invalid SSL certificate"}',
          error.stackTrace,
        );
      case DioExceptionType.cancel:
        return ApiException(
          'Request cancelled: ${error.message ?? "Request was cancelled"}',
          stackTrace: error.stackTrace,
        );
      case DioExceptionType.unknown:
        return ApiException(
          'Unknown API error: '
          '${error.message ?? "An unexpected error occurred"}',
          stackTrace: error.stackTrace,
        );
    }
  }

  Map<String, List<String>>? _extractValidationErrors(dynamic responseData) {
    if (responseData is Map<String, dynamic>) {
      // Use switch on keys for better clarity and extensibility
      for (final key in ['errors', 'validation_errors']) {
        if (responseData.containsKey(key) && responseData[key] is Map) {
          final errorsMap = responseData[key] as Map;
          return errorsMap.map((k, value) {
            if (value is List) {
              return MapEntry(k.toString(), value.cast<String>().toList());
            } else if (value is String) {
              return MapEntry(k.toString(), [value]);
            }
            return MapEntry(k.toString(), [value.toString()]);
          });
        }
      }
    }
    return null;
  }

  @override
  Future<TModel?> findOne(
    String id, {
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    try {
      final mergedHeaders = await mergeHeaders(headers, extra: extra);

      // Convert QueryParams to HTTP query parameters
      final httpQueryParams = queryParamsToHttpParams(queryParams);
      final uri = await urlForFindOne(id, extra: extra);

      final response = await _dio.request<Map<String, dynamic>>(
        uri.toString(),
        queryParameters: httpQueryParams.isNotEmpty ? httpQueryParams : null,
        options: Options(
          method: methodForFind(extra: extra),
          headers: mergedHeaders,
        ),
      );

      if (response.data == null) {
        return null;
      }
      return fromJson(response.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw ApiExceptionNotFound(
          'Resource not found: $id',
          stackTrace: e.stackTrace,
        );
      }
      if (e.response?.statusCode == 410) {
        throw ApiExceptionGone(
          'Resource not found: $id',
          stackTrace: e.stackTrace,
        );
      }
      throw _mapDioErrorToSyncedStorageException(e);
    } catch (e, st) {
      logger.severe('Error in findOne', e, st);
      throw ApiException(
        'Failed to parse response or unexpected error in findOne: $e',
      );
    }
  }

  @override
  Future<List<TModel>> findAll({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    try {
      final mergedHeaders = await mergeHeaders(headers, extra: extra);

      // Convert QueryParams to HTTP query parameters
      final httpQueryParams = queryParamsToHttpParams(queryParams);

      final uri = await urlForFindAll(extra: extra);

      final response = await _dio.request<dynamic>(
        uri.toString(),
        queryParameters: httpQueryParams.isNotEmpty ? httpQueryParams : null,
        options: Options(
          method: methodForFind(extra: extra),
          headers: mergedHeaders,
        ),
      );

      if (response.data == null) {
        return [];
      }

      List<dynamic> items;
      if (response.data is List) {
        items = response.data as List<dynamic>;
      } else if (response.data is Map<String, dynamic>) {
        final Map<String, dynamic> dataMap =
            response.data as Map<String, dynamic>;
        if (dataMap.containsKey('data') && dataMap['data'] is List) {
          items = dataMap['data'] as List<dynamic>;
        } else if (dataMap.containsKey(pluralType) &&
            dataMap[pluralType] is List) {
          items = dataMap[pluralType] as List<dynamic>;
        } else {
          throw ApiException(
            'Failed to parse findAll response: Expected a list or a map '
            'containing a list under "data" or "$pluralType" key.',
            statusCode: response.statusCode,
          );
        }
      } else {
        throw ApiException(
          'Failed to parse findAll response: Unexpected response type '
          '${response.data.runtimeType}. Expected List or Map.',
          statusCode: response.statusCode,
        );
      }

      return items
          .map((item) => fromJson(item as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _mapDioErrorToSyncedStorageException(e);
    } catch (e, st) {
      logger.severe('Error in findAll', e, st);
      throw ApiException(
        'Failed to parse response or unexpected error in findAll: $e',
      );
    }
  }

  @override
  Future<TModel?> createOne(
    TModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    try {
      final mergedHeaders = await mergeHeaders(headers, extra: extra);
      final uri = await urlForCreate(extra: extra);
      final response = await _dio.request<Map<String, dynamic>>(
        uri.toString(),
        data: toJson(model),
        options: Options(
          method: methodForCreate(extra: extra),
          headers: mergedHeaders,
        ),
      );

      if (response.data == null) {
        // For 204 No Content, data will be null. This is a valid success.
        // For other statuses, null data might indicate an issue or be intended.
        return null;
      }
      return fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapDioErrorToSyncedStorageException(e);
    } catch (e, st) {
      logger.severe('Error in createOne', e, st);
      throw ApiException(
        'Failed to parse response or unexpected error in createOne: $e',
      );
    }
  }

  @override
  Future<TModel?> updateOne(
    TModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    try {
      final mergedHeaders = await mergeHeaders(headers, extra: extra);
      final uri = await urlForUpdate(model.id, extra: extra);
      final response = await _dio.request<Map<String, dynamic>>(
        uri.toString(),
        data: toJson(model),
        options: Options(
          method: methodForUpdate(extra: extra),
          headers: mergedHeaders,
        ),
      );

      if (response.data == null) {
        return null;
      }
      return fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapDioErrorToSyncedStorageException(e);
    } catch (e, st) {
      logger.severe('Error in updateOne', e, st);
      throw ApiException(
        'Failed to parse response or unexpected error in updateOne: $e',
      );
    }
  }

  @override
  Future<TModel?> replaceOne(
    TModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    try {
      final mergedHeaders = await mergeHeaders(headers, extra: extra);
      final uri = await urlForReplace(model.id, extra: extra);
      final response = await _dio.request<Map<String, dynamic>>(
        uri.toString(),
        data: toJson(model),
        options: Options(
          method: methodForReplace(extra: extra),
          headers: mergedHeaders,
        ),
      );

      if (response.data == null) {
        return null;
      }
      return fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapDioErrorToSyncedStorageException(e);
    } catch (e, st) {
      logger.severe('Error in replaceOne', e, st);
      throw ApiException(
        'Failed to parse response or unexpected error in replaceOne: $e',
      );
    }
  }

  @override
  Future<void> deleteOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    try {
      final mergedHeaders = await mergeHeaders(headers, extra: extra);
      final uri = await urlForDelete(id, extra: extra);
      await _dio.request<void>(
        uri.toString(),
        options: Options(
          method: methodForDelete(extra: extra),
          headers: mergedHeaders,
        ),
      );
    } on DioException catch (e) {
      throw _mapDioErrorToSyncedStorageException(e);
    } catch (e, st) {
      logger.severe('Error in deleteOne', e, st);
      throw ApiException('Unexpected error in deleteOne: $e');
    }
  }

  /// Disposes the Dio client and cleans up resources.
  ///
  /// Call this method when the adapter is no longer needed to prevent
  /// memory leaks. This is only relevant if Dio was NOT provided via
  /// [SynquillStorageConfig.dio].
  void dispose() {
    if (SynquillStorage.config?.dio == null) {
      _dio.close();
    }
  }
}
