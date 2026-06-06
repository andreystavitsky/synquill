import 'dart:async';

import 'package:dio/dio.dart';
import 'package:synquill/src/core/exceptions.dart';
import 'package:synquill/src/core/repository_mixins/repository_types.dart';

/// The terminal action chosen for a failed sync/retry operation.
enum RetryDecisionAction {
  /// Retry the operation with normal retry scheduling.
  retry,

  /// Keep the task for diagnostics, but stop retrying it.
  markDead,

  /// Remove the task because the desired state has already been reached.
  discard,
}

/// Result of classifying a failed operation.
class RetryDecision {
  /// The action that should be applied to the failed task.
  final RetryDecisionAction action;

  /// Short diagnostic reason for logs and tests.
  final String reason;

  /// Creates a retry decision.
  const RetryDecision(this.action, this.reason);

  /// Creates a retry decision.
  const RetryDecision.retry(String reason)
      : this(RetryDecisionAction.retry, reason);

  /// Creates a terminal dead-letter decision.
  const RetryDecision.markDead(String reason)
      : this(RetryDecisionAction.markDead, reason);

  /// Creates a discard decision.
  const RetryDecision.discard(String reason)
      : this(RetryDecisionAction.discard, reason);
}

/// Shared retry classifier for sync queue, ID negotiation, and realtime retry.
///
/// The policy is intentionally deny-by-default. Only clearly transient
/// failures are retried.
class RetryPolicy {
  static const Set<int> _retryableHttpStatusCodes = {408, 425, 429};

  /// Classifies [error] in the context of [operation].
  static RetryDecision evaluate(
    Object error, {
    SyncOperation? operation,
  }) {
    if (error is ModelNoLongerExistsException) {
      return const RetryDecision.discard('model no longer exists locally');
    }

    if (operation == SyncOperation.delete &&
        (error is ApiExceptionNotFound || error is ApiExceptionGone)) {
      return const RetryDecision.discard('remote resource already gone');
    }

    if (error is TimeoutException) {
      return const RetryDecision.retry('timeout');
    }

    if (error is OfflineException) {
      return const RetryDecision.retry('offline');
    }

    if (error is QueueCapacityExceededException ||
        error is DuplicateSyncTaskException) {
      return const RetryDecision.retry('transient local queue failure');
    }

    if (error is BadCertificateException) {
      return const RetryDecision.markDead('bad certificate');
    }

    if (error is NetworkException) {
      if (_isBadCertificateMessage(error.message)) {
        return const RetryDecision.markDead('bad certificate');
      }
      return const RetryDecision.retry('network failure');
    }

    if (error is ServerException) {
      return const RetryDecision.retry('server failure');
    }

    if (error is ApiExceptionNotFound || error is ApiExceptionGone) {
      return const RetryDecision.markDead('resource not found');
    }

    if (error is ApiException) {
      return _isRetryableHttpStatus(error.statusCode)
          ? const RetryDecision.retry('retryable HTTP status')
          : const RetryDecision.markDead('non-retryable HTTP status');
    }

    if (error is DioException) {
      return _isRetryableDioException(error)
          ? const RetryDecision.retry('retryable Dio error')
          : const RetryDecision.markDead('non-retryable Dio error');
    }

    if (error is InvalidSyncQueueTaskException ||
        error is SyncQueueConfigurationException ||
        error is DoubleFallbackException ||
        error is IdConflictException ||
        error is ValidationException ||
        error is AuthenticationException ||
        error is AuthorizationException ||
        error is ConflictException ||
        error is ArgumentError ||
        error is StateError ||
        error is FormatException ||
        error is TypeError ||
        error is SynquillStorageException) {
      return const RetryDecision.markDead('terminal failure');
    }

    return const RetryDecision.markDead('unknown failure');
  }

  static bool _isRetryableDioException(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        return _isRetryableHttpStatus(error.response?.statusCode);
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return false;
    }
  }

  static bool _isRetryableHttpStatus(int? statusCode) {
    if (statusCode == null) return false;
    return _retryableHttpStatusCodes.contains(statusCode) || statusCode >= 500;
  }

  static bool _isBadCertificateMessage(String message) {
    return message.toLowerCase().contains('bad certificate');
  }
}
