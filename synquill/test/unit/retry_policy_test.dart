import 'dart:async';

import 'package:dio/dio.dart';
import 'package:queue/queue.dart';
import 'package:synquill/src/core/exceptions.dart';
import 'package:synquill/src/core/repository_mixins/repository_types.dart';
import 'package:synquill/src/runtime/retry_policy.dart';
import 'package:test/test.dart';

void main() {
  group('RetryPolicy', () {
    RetryDecisionAction actionFor(
      Object error, {
      SyncOperation operation = SyncOperation.create,
    }) {
      return RetryPolicy.evaluate(error, operation: operation).action;
    }

    Object captureError(void Function() body) {
      try {
        body();
      } catch (error) {
        return error;
      }
      throw StateError('Expected body to throw');
    }

    group('retryable errors', () {
      test('retries timeouts and transient connectivity failures', () {
        expect(
          actionFor(TimeoutException('timed out')),
          RetryDecisionAction.retry,
        );
        expect(
          actionFor(OfflineException('offline')),
          RetryDecisionAction.retry,
        );
        expect(
          actionFor(NetworkException('connection reset')),
          RetryDecisionAction.retry,
        );
        expect(
          actionFor(ServerException('server unavailable')),
          RetryDecisionAction.retry,
        );
      });

      test('retries retryable HTTP statuses', () {
        for (final statusCode in [408, 425, 429, 500, 502, 503, 504]) {
          expect(
            actionFor(ApiException('http $statusCode', statusCode: statusCode)),
            RetryDecisionAction.retry,
            reason: 'HTTP $statusCode should be retryable',
          );
        }
      });

      test('retries retryable raw Dio errors', () {
        for (final type in [
          DioExceptionType.connectionTimeout,
          DioExceptionType.sendTimeout,
          DioExceptionType.receiveTimeout,
          DioExceptionType.connectionError,
        ]) {
          expect(
            actionFor(
              DioException(
                requestOptions: RequestOptions(path: '/test'),
                type: type,
              ),
            ),
            RetryDecisionAction.retry,
            reason: '$type should be retryable',
          );
        }

        expect(
          actionFor(
            DioException(
              requestOptions: RequestOptions(path: '/test'),
              type: DioExceptionType.badResponse,
              response: Response(
                requestOptions: RequestOptions(path: '/test'),
                statusCode: 503,
              ),
            ),
          ),
          RetryDecisionAction.retry,
        );
      });

      test('retries transient local queue errors', () {
        expect(
          actionFor(QueueCapacityExceededException('background queue full')),
          RetryDecisionAction.retry,
        );
        expect(
          actionFor(DuplicateSyncTaskException('duplicate idempotency key')),
          RetryDecisionAction.retry,
        );
      });

      test('retries queue cancellation from lifecycle changes', () {
        expect(
          actionFor(QueueCancelledException()),
          RetryDecisionAction.retry,
        );
      });
    });

    group('dead-letter errors', () {
      test('marks invalid sync queue data and configuration failures dead', () {
        expect(
          actionFor(InvalidSyncQueueTaskException('missing id')),
          RetryDecisionAction.markDead,
        );
        expect(
          actionFor(SyncQueueConfigurationException('missing repository')),
          RetryDecisionAction.markDead,
        );
      });

      test('marks permanent API errors dead', () {
        for (final error in <Object>[
          ValidationException('invalid'),
          AuthenticationException('auth'),
          AuthorizationException('forbidden'),
          ConflictException('conflict'),
          ApiExceptionNotFound('/missing'),
          ApiExceptionGone('/gone'),
          ApiException('bad request', statusCode: 400),
          ApiException('not allowed', statusCode: 405),
        ]) {
          expect(
            actionFor(error),
            RetryDecisionAction.markDead,
            reason: '$error should be terminal',
          );
        }
      });

      test('marks local programming and invariant errors dead', () {
        final typeError = captureError(() {
          final value = <String, dynamic>{};
          value['id'] as String;
        });

        for (final error in <Object>[
          ArgumentError('bad operation'),
          StateError('unsupported operation'),
          const FormatException('bad json'),
          typeError,
          SynquillStorageException('generic storage failure'),
          BadCertificateException('bad certificate'),
          DioException(
            requestOptions: RequestOptions(path: '/test'),
            type: DioExceptionType.badCertificate,
          ),
        ]) {
          expect(
            actionFor(error),
            RetryDecisionAction.markDead,
            reason: '$error should be terminal',
          );
        }
      });

      test('marks double fallback and ID conflict failures dead', () {
        expect(
          actionFor(
            DoubleFallbackException(
              'fallback failed',
              originalError: ApiExceptionNotFound('/update'),
              createError: ApiExceptionNotFound('/create'),
            ),
          ),
          RetryDecisionAction.markDead,
        );

        expect(
          actionFor(
            const IdConflictException(
              'conflict',
              temporaryId: 'tmp',
              proposedServerId: 'server',
              modelType: 'TestUser',
            ),
          ),
          RetryDecisionAction.markDead,
        );
      });
    });

    group('discard errors', () {
      test('discards tasks for locally deleted models', () {
        expect(
          actionFor(ModelNoLongerExistsException('gone locally')),
          RetryDecisionAction.discard,
        );
      });

      test('discards delete tasks when remote resource is already gone', () {
        expect(
          actionFor(
            ApiExceptionNotFound('/missing'),
            operation: SyncOperation.delete,
          ),
          RetryDecisionAction.discard,
        );
        expect(
          actionFor(
            ApiExceptionGone('/gone'),
            operation: SyncOperation.delete,
          ),
          RetryDecisionAction.discard,
        );
      });
    });
  });
}
