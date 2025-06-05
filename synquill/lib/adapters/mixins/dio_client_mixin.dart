part of synquill;

/// {@template dio_client_mixin}
/// Mixin that provides Dio client management functionality for API adapters.
///
/// Handles:
/// - Lazy initialization of Dio client
/// - Default configuration setup
/// - Logging and error interceptors
/// - Integration with SynquillStorage configuration
/// {@endtemplate}
mixin DioClientMixin<TModel extends SynquillDataModel<TModel>>
    on ApiAdapterBase<TModel> {
  /// The Dio client used for HTTP requests.
  ///
  /// Lazily initialized. If `SynquillStorage.config?.dio` is provided,
  /// it's used; otherwise, a new client is created with default settings.
  late final Dio _dio = SynquillStorage.config?.dio ?? _createDioClient();

  /// Logger instance for this adapter.
  Logger get logger => Logger('BasicApiAdapter');

  /// Access to the underlying Dio client.
  ///
  /// Protected getter for use by other mixins and subclasses.
  @protected
  Dio get dio => _dio;

  Dio _createDioClient() {
    final dio = Dio();
    final config = SynquillStorage.config;

    // Use maximumNetworkTimeout from config for HTTP-level timeouts
    final networkTimeout =
        config?.maximumNetworkTimeout ?? const Duration(seconds: 20);

    dio.options = BaseOptions(
      connectTimeout: networkTimeout,
      receiveTimeout: networkTimeout,
      sendTimeout: networkTimeout,
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
}
