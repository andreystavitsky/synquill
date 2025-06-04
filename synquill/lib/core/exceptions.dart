part of synquill;

/// Base class for all exceptions thrown by the synquill package.
class SynquillStorageException implements Exception {
  /// The error message describing the exception.
  final String message;

  /// The stack trace associated with the exception, if any.
  final StackTrace? stackTrace;

  /// Creates a [SynquillStorageException] with an optional [stackTrace].
  SynquillStorageException(this.message, [this.stackTrace]);

  @override
  String toString() => 'SynquillStorageException: $message';
}

/// Thrown when an operation is attempted on a Freezed union type
/// that is not supported for unions.
class UnsupportedFreezedUnionError extends SynquillStorageException {
  /// Creates an [UnsupportedFreezedUnionError] with an optional [stackTrace].
  UnsupportedFreezedUnionError(String message, [StackTrace? stackTrace])
    : super('Unsupported Freezed union operation: $message', stackTrace);
}

/// Thrown when a repository can't find a requested item.
class NotFoundException extends SynquillStorageException {
  /// Creates a [NotFoundException] with an optional [stackTrace].
  NotFoundException(super.message, [super.stackTrace]);
}

/// Thrown when a model no longer exists locally but a sync operation is
/// pending. This typically happens when a model is deleted locally while a
/// sync operation for that model is still in the retry queue.
class ModelNoLongerExistsException extends SynquillStorageException {
  /// Creates a [ModelNoLongerExistsException] with an optional [stackTrace].
  ModelNoLongerExistsException(super.message, [super.stackTrace]);
}

/// Thrown when an operation requires an online connection
class OfflineException extends SynquillStorageException {
  /// Creates a [OfflineException] with an optional [stackTrace].
  OfflineException(super.message, [super.stackTrace]);
}

/// Base class for errors originating from the remote API interaction.
class ApiError extends SynquillStorageException {
  /// The HTTP status code, if available.
  final int? statusCode;

  /// Creates an [ApiError] with an optional [statusCode] and [stackTrace].
  ApiError(String message, {this.statusCode, StackTrace? stackTrace})
    : super(message, stackTrace);

  @override
  String toString() =>
      'ApiError: $message${statusCode != null ? ' (Status: $statusCode)' : ''}';
}

/// Thrown when a network connection error occurs.
class NetworkException extends SynquillStorageException {
  /// Creates a [NetworkException] with an optional [stackTrace].
  NetworkException(super.message, [super.stackTrace]);
}

/// General API exception for HTTP errors.
class ApiException extends SynquillStorageException {
  /// The HTTP status code, if available.
  final int? statusCode;

  /// Creates an [ApiException] with an optional [statusCode] and [stackTrace].
  ApiException(String message, {this.statusCode, StackTrace? stackTrace})
    : super(message, stackTrace);

  @override
  String toString() {
    final statusText = statusCode != null ? ' (Status: $statusCode)' : '';
    return 'ApiException: $message$statusText';
  }
}

/// General API exception for HTTP errors.
class ApiExceptionGone extends ApiException {
  /// Creates an [ApiException] with an optional [statusCode] and [stackTrace].
  ApiExceptionGone(super.message, {super.stackTrace});

  @override
  String toString() {
    const statusText = '(Status: 410)';
    return 'ApiExceptionGone: $message$statusText';
  }
}

/// General API exception for HTTP errors.
class ApiExceptionNotFound extends ApiException {
  /// Creates an [ApiException] with an optional [statusCode] and [stackTrace].
  ApiExceptionNotFound(super.message, {super.stackTrace});

  @override
  String toString() {
    const statusText = '(Status: 404)';
    return 'ApiExceptionNotFound: $message$statusText';
  }
}

/// Thrown when authentication is required but not provided.
class AuthenticationException extends SynquillStorageException {
  /// Creates an [AuthenticationException] with an optional [stackTrace].
  AuthenticationException(super.message, [super.stackTrace]);
}

/// Thrown when the authenticated user lacks permission for an operation.
class AuthorizationException extends SynquillStorageException {
  /// Creates an [AuthorizationException] with an optional [stackTrace].
  AuthorizationException(super.message, [super.stackTrace]);
}

/// Thrown when there's a conflict with the current state of the resource.
class ConflictException extends SynquillStorageException {
  /// Creates a [ConflictException] with an optional [stackTrace].
  ConflictException(super.message, [super.stackTrace]);
}

/// Thrown when validation fails on the server side.
class ValidationException extends SynquillStorageException {
  /// Field-specific validation errors, if provided by the server.
  final Map<String, List<String>>? fieldErrors;

  /// Creates a [ValidationException] with optional [fieldErrors] and
  /// [stackTrace].
  ValidationException(super.message, [this.fieldErrors, super.stackTrace]);

  @override
  String toString() {
    final base = 'ValidationException: $message';
    if (fieldErrors != null && fieldErrors!.isNotEmpty) {
      final errors = fieldErrors!.entries
          .map((e) => '  ${e.key}: ${e.value.join(", ")}')
          .join('\n');
      return '$base\nField errors:\n$errors';
    }
    return base;
  }
}

/// Thrown when the server encounters an internal error.
class ServerException extends SynquillStorageException {
  /// Creates a [ServerException] with an optional [stackTrace].
  ServerException(super.message, [super.stackTrace]);
}

/// Thrown when both update and create operations fail with 404.
/// This indicates an API configuration issue and should not use
/// exponential backoff retry logic.
class DoubleFallbackException extends SynquillStorageException {
  /// The original update error.
  final ApiExceptionNotFound originalError;

  /// The create fallback error.
  final ApiExceptionNotFound createError;

  /// Creates a [DoubleFallbackException] with the original and create errors.
  DoubleFallbackException(
    String message, {
    required this.originalError,
    required this.createError,
    StackTrace? stackTrace,
  }) : super(message, stackTrace);

  @override
  String toString() =>
      'DoubleFallbackException: $message '
      '(Update: ${originalError.message}, Create: ${createError.message})';
}
