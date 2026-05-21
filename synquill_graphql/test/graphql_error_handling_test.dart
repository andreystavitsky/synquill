import 'package:test/test.dart';
import 'package:synquill/synquill.dart';
import 'package:synquill_graphql/synquill_graphql.dart';
import 'helpers/test_model.dart';

// Create a dummy adapter class mixing in the target mixin
class ErrorTestingAdapter extends ApiAdapterBase<TestModel>
    with GraphQLErrorHandlingMixin<TestModel> {
  @override
  Uri get baseUrl => Uri.parse('https://api.test.com/graphql');

  @override
  Logger get logger => Logger('ErrorTestingAdapter');

  @override
  TestModel fromJson(Map<String, dynamic> json) => TestModel.fromJsonData(json);

  @override
  Map<String, dynamic> toJson(TestModel model) => model.toJson();

  // Expose protected methods for testing
  SynquillStorageException testMapGraphQLError(
      Map<String, dynamic> error, int? httpStatusCode) {
    return mapGraphQLErrorToException(error, httpStatusCode);
  }

  SynquillStorageException testMapDioError(DioException error) {
    return mapDioErrorToSynquillStorageException(error);
  }

  void testCheckGraphQLErrors(
      Map<String, dynamic> responseData, int? statusCode) {
    checkGraphQLErrors(responseData, statusCode);
  }

  // Implement concrete CRUD overrides required by ApiAdapterBase
  @override
  Future<TestModel?> findOne(String id,
          {Map<String, String>? headers,
          QueryParams? queryParams,
          Map<String, dynamic>? extra}) =>
      throw UnimplementedError();
  @override
  Future<List<TestModel>> findAll(
          {Map<String, String>? headers,
          QueryParams? queryParams,
          Map<String, dynamic>? extra}) =>
      throw UnimplementedError();
  @override
  Future<TestModel?> createOne(TestModel model,
          {Map<String, String>? headers, Map<String, dynamic>? extra}) =>
      throw UnimplementedError();
  @override
  Future<TestModel?> updateOne(TestModel model,
          {Map<String, String>? headers, Map<String, dynamic>? extra}) =>
      throw UnimplementedError();
  @override
  Future<TestModel?> replaceOne(TestModel model,
          {Map<String, String>? headers, Map<String, dynamic>? extra}) =>
      throw UnimplementedError();
  @override
  Future<void> deleteOne(String id,
          {Map<String, String>? headers, Map<String, dynamic>? extra}) =>
      throw UnimplementedError();
}

void main() {
  group('GraphQLErrorHandlingMixin Tests', () {
    late ErrorTestingAdapter adapter;

    setUp(() {
      adapter = ErrorTestingAdapter();
    });

    group('GraphQL Error Code Mapping', () {
      test('maps UNAUTHENTICATED to AuthenticationException', () {
        final error = {
          'message': 'Session expired',
          'extensions': {'code': 'UNAUTHENTICATED'},
        };
        final exception = adapter.testMapGraphQLError(error, 200);
        expect(exception, isA<AuthenticationException>());
        expect(exception.message, contains('Session expired'));
      });

      test('maps FORBIDDEN to AuthorizationException', () {
        final error = {
          'message': 'No access',
          'extensions': {'code': 'FORBIDDEN'},
        };
        final exception = adapter.testMapGraphQLError(error, 200);
        expect(exception, isA<AuthorizationException>());
        expect(exception.message, contains('No access'));
      });

      test('maps NOT_FOUND to ApiExceptionNotFound', () {
        final error = {
          'message': 'Not found',
          'extensions': {'code': 'NOT_FOUND'},
        };
        final exception = adapter.testMapGraphQLError(error, 200);
        expect(exception, isA<ApiExceptionNotFound>());
        expect(exception.message, contains('Not found'));
      });

      test('maps BAD_USER_INPUT to ValidationException', () {
        final error = {
          'message': 'Invalid age',
          'extensions': {'code': 'BAD_USER_INPUT'},
        };
        final exception = adapter.testMapGraphQLError(error, 200);
        expect(exception, isA<ValidationException>());
        expect(exception.message, contains('Invalid age'));
      });

      test('maps VALIDATION_ERROR to ValidationException', () {
        final error = {
          'message': 'Validation failed',
          'extensions': {'code': 'VALIDATION_ERROR'},
        };
        final exception = adapter.testMapGraphQLError(error, 200);
        expect(exception, isA<ValidationException>());
        expect(exception.message, contains('Validation failed'));
      });

      test(
          'maps BAD_USER_INPUT with field errors to '
          'ValidationException with fieldErrors', () {
        final error = {
          'message': 'Validation failed',
          'extensions': {
            'code': 'BAD_USER_INPUT',
            'fieldErrors': {
              'age': ['Must be positive', 'Must be integer'],
              'email': 'Invalid email format',
            },
          },
        };
        final exception =
            adapter.testMapGraphQLError(error, 200) as ValidationException;
        expect(exception, isA<ValidationException>());
        expect(exception.fieldErrors, isNotNull);
        expect(exception.fieldErrors!['age'],
            equals(['Must be positive', 'Must be integer']));
        expect(
            exception.fieldErrors!['email'], equals(['Invalid email format']));
      });

      test('maps BAD_USER_INPUT with mixed/non-string field errors safely', () {
        final error = {
          'message': 'Validation failed',
          'extensions': {
            'code': 'BAD_USER_INPUT',
            'fieldErrors': {
              'age': ['Must be positive', 456],
              'email': 'Invalid email format',
              'status': 400,
            },
          },
        };
        final exception =
            adapter.testMapGraphQLError(error, 200) as ValidationException;
        expect(exception, isA<ValidationException>());
        expect(exception.fieldErrors, isNotNull);
        expect(
            exception.fieldErrors!['age'], equals(['Must be positive', '456']));
        expect(
            exception.fieldErrors!['email'], equals(['Invalid email format']));
        expect(exception.fieldErrors!['status'], equals(['400']));
      });

      test('maps CONFLICT to ConflictException', () {
        final error = {
          'message': 'Conflict state',
          'extensions': {'code': 'CONFLICT'},
        };
        final exception = adapter.testMapGraphQLError(error, 200);
        expect(exception, isA<ConflictException>());
        expect(exception.message, contains('Conflict state'));
      });

      test('maps INTERNAL_SERVER_ERROR to ServerException', () {
        final error = {
          'message': 'Crash',
          'extensions': {'code': 'INTERNAL_SERVER_ERROR'},
        };
        final exception = adapter.testMapGraphQLError(error, 200);
        expect(exception, isA<ServerException>());
        expect(exception.message, contains('Crash'));
      });

      test('maps unknown error code to generic ApiException', () {
        final error = {
          'message': 'Weird error',
          'extensions': {'code': 'SOMETHING_WEIRD'},
        };
        final exception =
            adapter.testMapGraphQLError(error, 200) as ApiException;
        expect(exception, isA<ApiException>());
        expect(exception.message, contains('Weird error'));
        expect(exception.statusCode, equals(200));
      });

      test('maps error without extensions to ApiException', () {
        final error = {
          'message': 'No extensions error',
        };
        final exception =
            adapter.testMapGraphQLError(error, 400) as ApiException;
        expect(exception, isA<ApiException>());
        expect(exception.message, contains('No extensions error'));
        expect(exception.statusCode, equals(400));
      });
    });

    group('Dio Error Mapping', () {
      test('maps DioException connectionTimeout to NetworkException', () {
        final dioException = DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.connectionTimeout,
          message: 'Timeout occurred',
        );
        final exception = adapter.testMapDioError(dioException);
        expect(exception, isA<NetworkException>());
        expect(exception.message, contains('Timeout occurred'));
      });

      test('maps DioException connectionError to NetworkException', () {
        final dioException = DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.connectionError,
          message: 'Offline',
        );
        final exception = adapter.testMapDioError(dioException);
        expect(exception, isA<NetworkException>());
        expect(exception.message, contains('Offline'));
      });

      test('maps DioException badResponse 401 to AuthenticationException', () {
        final dioException = DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(),
            statusCode: 401,
            statusMessage: 'Unauthorized',
          ),
        );
        final exception = adapter.testMapDioError(dioException);
        expect(exception, isA<AuthenticationException>());
      });

      test('maps DioException badResponse 404 to ApiExceptionNotFound', () {
        final dioException = DioException(
          requestOptions: RequestOptions(path: '/graphql'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/graphql'),
            statusCode: 404,
          ),
        );
        final exception = adapter.testMapDioError(dioException);
        expect(exception, isA<ApiExceptionNotFound>());
      });

      test('maps DioException badResponse 500 to ServerException', () {
        final dioException = DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(),
            statusCode: 500,
          ),
        );
        final exception = adapter.testMapDioError(dioException);
        expect(exception, isA<ServerException>());
      });

      test(
          'maps DioException badResponse 400 with non-string/mixed type validation errors safely',
          () {
        final dioException = DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(),
            statusCode: 400,
            data: {
              'errors': {
                'age': ['Must be positive', 123],
                'email': 'Invalid email format',
                'status': 500,
              }
            },
          ),
        );
        final exception =
            adapter.testMapDioError(dioException) as ValidationException;
        expect(exception, isA<ValidationException>());
        expect(exception.fieldErrors, isNotNull);
        expect(
            exception.fieldErrors!['age'], equals(['Must be positive', '123']));
        expect(
            exception.fieldErrors!['email'], equals(['Invalid email format']));
        expect(exception.fieldErrors!['status'], equals(['500']));
      });
    });

    group('Multiple Errors', () {
      test(
          'checkGraphQLErrors throws validation exception '
          'aggregated from multiple entries', () {
        final response = {
          'data': null,
          'errors': [
            {
              'message': 'Invalid input',
              'extensions': {
                'code': 'BAD_USER_INPUT',
                'fieldErrors': {
                  'age': ['Must be positive'],
                },
              },
            },
            {
              'message': 'Required field missing',
              'extensions': {
                'code': 'BAD_USER_INPUT',
                'fieldErrors': {
                  'name': ['Required'],
                },
              },
            },
          ],
        };

        expect(
          () => adapter.testCheckGraphQLErrors(response, 200),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.fieldErrors,
              'fieldErrors',
              equals({
                'age': ['Must be positive'],
                'name': ['Required'],
              }),
            ),
          ),
        );
      });

      test(
          'checkGraphQLErrors uses first error for non-validation '
          'multiple errors', () {
        final response = {
          'data': null,
          'errors': [
            {
              'message': 'First server crash',
              'extensions': {'code': 'INTERNAL_SERVER_ERROR'},
            },
            {
              'message': 'Forbidden access',
              'extensions': {'code': 'FORBIDDEN'},
            },
          ],
        };

        expect(
          () => adapter.testCheckGraphQLErrors(response, 200),
          throwsA(isA<ServerException>().having(
              (e) => e.message, 'message', contains('First server crash'))),
        );
      });
    });

    group('Partial Errors Flow', () {
      test(
          'checkGraphQLErrors throws even when data is present '
          '(default partial error strategy)', () {
        final response = {
          'data': {
            'test_model': {'id': '1', 'name': 'Partially Good'}
          },
          'errors': [
            {
              'message': 'Some field failed to resolve',
              'extensions': {'code': 'NOT_FOUND'},
            }
          ]
        };

        expect(
          () => adapter.testCheckGraphQLErrors(response, 200),
          throwsA(isA<ApiExceptionNotFound>()),
        );
      });

      test('checkGraphQLErrors does not throw when errors array is empty', () {
        final response = {
          'data': {
            'test_model': {'id': '1'}
          },
          'errors': [],
        };
        expect(
          () => adapter.testCheckGraphQLErrors(response, 200),
          returnsNormally,
        );
      });

      test('checkGraphQLErrors does not throw when errors key is absent', () {
        final response = {
          'data': {
            'test_model': {'id': '1'}
          },
        };
        expect(
          () => adapter.testCheckGraphQLErrors(response, 200),
          returnsNormally,
        );
      });
    });
  });
}
