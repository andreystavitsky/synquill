part of synquill;

/// {@template error_handling_mixin}
/// Mixin that provides error handling functionality for API adapters.
///
/// Handles:
/// - Mapping DioException to SynquillStorageException
/// - Extracting validation errors from responses
/// - HTTP status code specific error handling
/// {@endtemplate}
mixin ErrorHandlingMixin<TModel extends SynquillDataModel<TModel>>
    on ApiAdapterBase<TModel> {
  /// Logger instance for error handling.
  Logger get logger;

  /// Maps a DioException to the appropriate SynquillStorageException.
  @protected
  SynquillStorageException mapDioErrorToSyncedStorageException(
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
}
