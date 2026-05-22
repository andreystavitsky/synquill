import 'dart:async';

import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:synquill/synquill.dart';
import 'package:test/test.dart';

import 'helpers/mock_graphql_responses.dart';
import 'helpers/test_graphql_adapter.dart';
import 'helpers/test_model.dart';
@GenerateNiceMocks([MockSpec<Dio>()])
import 'graphql_execution_test.mocks.dart';

class ExecutionTestingAdapter extends TestGraphQLAdapter {
  ExecutionTestingAdapter({this.base = const {'Accept': 'application/json'}});

  final Map<String, String> base;

  @override
  Map<String, String> get baseHeaders => base;

  Future<Map<String, dynamic>> executeTestOperation({
    required String operation,
    Map<String, dynamic>? variables,
    Map<String, String>? headers,
    String? operationName,
    Map<String, dynamic>? extra,
  }) {
    return executeGraphQLOperation(
      operation: operation,
      variables: variables,
      headers: headers,
      operationName: operationName,
      extra: extra,
    );
  }
}

class CapturedPost {
  CapturedPost({
    required this.path,
    required this.body,
    required this.options,
  });

  final String path;
  final Map<String, dynamic> body;
  final Options options;
}

void main() {
  group('GraphQLExecutionMixin Tests', () {
    late MockDio mockDio;
    late ExecutionTestingAdapter adapter;

    void stubPost(dynamic data, {int statusCode = 200}) {
      when(
        mockDio.post<dynamic>(
          any,
          data: anyNamed('data'),
          queryParameters: anyNamed('queryParameters'),
          options: anyNamed('options'),
          cancelToken: anyNamed('cancelToken'),
          onSendProgress: anyNamed('onSendProgress'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        ),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          data: data,
          statusCode: statusCode,
          requestOptions: RequestOptions(path: ''),
        ),
      );
    }

    CapturedPost capturePost() {
      final captured = verify(
        mockDio.post<dynamic>(
          captureAny,
          data: captureAnyNamed('data'),
          queryParameters: anyNamed('queryParameters'),
          options: captureAnyNamed('options'),
          cancelToken: anyNamed('cancelToken'),
          onSendProgress: anyNamed('onSendProgress'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        ),
      ).captured;

      return CapturedPost(
        path: captured[0] as String,
        body: captured[1] as Map<String, dynamic>,
        options: captured[2] as Options,
      );
    }

    setUp(() {
      mockDio = MockDio();
      adapter = ExecutionTestingAdapter();

      SynquillStorage.setConfigForTesting(
        SynquillStorageConfig(dio: mockDio),
      );
    });

    tearDown(() {
      SynquillStorage.setConfigForTesting(const SynquillStorageConfig());
    });

    group('executeGraphQLOperation', () {
      test('sends POST with query, variables, operationName, and JSON headers',
          () async {
        stubPost({
          'data': {'ok': true},
        });

        final result = await adapter.executeTestOperation(
          operation: 'query Ping { ping }',
          variables: {'id': '123'},
          operationName: 'Ping',
          headers: {'Authorization': 'Bearer token'},
          extra: {'traceId': 'trace-1'},
        );

        expect(result, equals({'ok': true}));

        final post = capturePost();
        expect(post.path, equals('https://api.test.com/graphql'));
        expect(
          post.body,
          equals({
            'query': 'query Ping { ping }',
            'variables': {'id': '123'},
            'operationName': 'Ping',
          }),
        );
        expect(post.options.headers?['Accept'], equals('application/json'));
        expect(
            post.options.headers?['Content-Type'], equals('application/json'));
        expect(post.options.headers?['Authorization'], equals('Bearer token'));
        expect(post.options.extra, equals({'traceId': 'trace-1'}));
      });

      test('queue cancellation reaches a GraphQL mutation POST', () async {
        final capturedErrors = <Object>[];

        await runZonedGuarded(() async {
          final requestStarted = Completer<void>();
          final requestSettled = Completer<Response<dynamic>>();
          CancelToken? requestCancelToken;

          when(
            mockDio.post<dynamic>(
              any,
              data: anyNamed('data'),
              queryParameters: anyNamed('queryParameters'),
              options: anyNamed('options'),
              cancelToken: anyNamed('cancelToken'),
              onSendProgress: anyNamed('onSendProgress'),
              onReceiveProgress: anyNamed('onReceiveProgress'),
            ),
          ).thenAnswer((invocation) {
            requestCancelToken =
                invocation.namedArguments[#cancelToken] as CancelToken?;
            if (!requestStarted.isCompleted) {
              requestStarted.complete();
            }
            requestCancelToken?.whenCancel.then((_) {
              if (!requestSettled.isCompleted) {
                requestSettled.completeError(
                  DioException(
                    requestOptions: RequestOptions(path: '/graphql'),
                    type: DioExceptionType.cancel,
                  ),
                );
              }
            });
            return requestSettled.future;
          });

          final mgr = RequestQueueManager();
          final model = TestModel(id: 'gql-cancel', name: 'Cancel', value: 1);
          final enqueueFuture = mgr
              .enqueueTask(
                NetworkTask<TestModel?>(
                  exec: () => adapter.createOne(model),
                  idempotencyKey: 'graphql-cancel-create',
                  operation: SyncOperation.create,
                  modelType: 'TestModel',
                  modelId: model.id,
                ),
                queueType: QueueType.background,
              )
              .catchError((_) => null);

          try {
            await requestStarted.future;
            await mgr.clearQueuesOnDisconnect();

            expect(requestCancelToken, isNotNull);
            expect(requestCancelToken!.isCancelled, isTrue);
          } finally {
            if (!requestSettled.isCompleted) {
              requestSettled.complete(
                Response<dynamic>(
                  data: {
                    'data': {
                      'createTestModel': model.toJson(),
                    },
                  },
                  statusCode: 200,
                  requestOptions: RequestOptions(path: '/graphql'),
                ),
              );
            }
            await enqueueFuture;
            await mgr.dispose();
          }
        }, (error, _) => capturedErrors.add(error));

        expect(
          capturedErrors.where(
            (error) =>
                error.runtimeType.toString() != 'QueueCancelledException',
          ),
          isEmpty,
        );
      });

      test('omits operationName and variables when they are null', () async {
        stubPost({
          'data': {'ok': true},
        });

        await adapter.executeTestOperation(operation: 'query Ping { ping }');

        final post = capturePost();
        expect(post.body, equals({'query': 'query Ping { ping }'}));
      });

      test('includes empty variables map when explicitly provided', () async {
        stubPost({
          'data': {'ok': true},
        });

        await adapter.executeTestOperation(
          operation: 'query Ping { ping }',
          variables: const {},
        );

        final post = capturePost();
        expect(
          post.body,
          equals({
            'query': 'query Ping { ping }',
            'variables': <String, dynamic>{},
          }),
        );
      });

      test('request headers override base headers', () async {
        adapter = ExecutionTestingAdapter(
          base: const {
            'Accept': 'application/json',
            'X-Base': 'base',
            'X-Override': 'base',
          },
        );
        stubPost({
          'data': {'ok': true},
        });

        await adapter.executeTestOperation(
          operation: 'query Ping { ping }',
          headers: {'X-Override': 'request'},
        );

        final post = capturePost();
        expect(post.options.headers?['X-Base'], equals('base'));
        expect(post.options.headers?['X-Override'], equals('request'));
        expect(
            post.options.headers?['Content-Type'], equals('application/json'));
      });

      test('succeeds and returns data on 200 OK with no errors', () async {
        stubPost(
          graphqlSuccess('test_model', {
            'id': '123',
            'name': 'GraphQL Item',
            'value': 42,
          }),
        );

        final result = await adapter.findOne('123');

        expect(result, isNotNull);
        expect(result!.id, equals('123'));
        expect(result.name, equals('GraphQL Item'));
        expect(result.value, equals(42));

        final post = capturePost();
        expect(post.body['query'], equals(adapter.findOneQuery));
        expect(post.body['variables'], equals({'id': '123'}));
      });

      test('throws validation exception when server returns validation errors',
          () async {
        stubPost(
          graphqlError(
            'Invalid fields',
            code: 'VALIDATION_ERROR',
            extensions: {
              'fieldErrors': {
                'name': ['Name is too short'],
              },
            },
          ),
        );

        expect(
          () => adapter.findOne('123'),
          throwsA(
            isA<ValidationException>().having(
              (e) => e.fieldErrors?['name'],
              'fieldErrors.name',
              contains('Name is too short'),
            ),
          ),
        );
      });

      test('throws on partial errors even when data is present', () async {
        stubPost(
          graphqlPartialError(
            'test_model',
            {'id': '123', 'name': 'GraphQL Item', 'value': 42},
            'Resolver warning',
          ),
        );

        expect(
          () => adapter.findOne('123'),
          throwsA(isA<ApiException>()),
        );
      });

      test('maps DioException to SynquillStorageException on failure',
          () async {
        when(
          mockDio.post<dynamic>(
            any,
            data: anyNamed('data'),
            queryParameters: anyNamed('queryParameters'),
            options: anyNamed('options'),
            cancelToken: anyNamed('cancelToken'),
            onSendProgress: anyNamed('onSendProgress'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.connectionTimeout,
          ),
        );

        expect(
          () => adapter.findOne('123'),
          throwsA(isA<NetworkException>()),
        );
      });

      test('throws ApiException for non-object GraphQL responses', () async {
        stubPost(['not', 'an', 'object']);

        expect(
          () => adapter.executeTestOperation(operation: 'query Ping { ping }'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              contains('Invalid GraphQL response format'),
            ),
          ),
        );
      });
    });

    group('operation-specific requests', () {
      test('executeFindAllRequest converts query params and executes query',
          () async {
        stubPost(
          graphqlSuccess('test_models', [
            {'id': '1', 'name': 'Item A', 'value': 10},
            {'id': '2', 'name': 'Item B', 'value': 20},
          ]),
        );

        const nameField = FieldSelector<String>('name', String);
        final queryParams = QueryParams(
          filters: [nameField.equals('Item A')],
          sorts: const [SortCondition.ascending(nameField)],
        );

        final result = await adapter.findAll(queryParams: queryParams);

        expect(result.length, equals(2));
        expect(result[0].name, equals('Item A'));

        final post = capturePost();
        expect(post.body['query'], equals(adapter.findAllQuery));
        expect(
          post.body['variables'],
          equals({
            'filter': {
              'name': {'eq': 'Item A'},
            },
            'sort': [
              {'field': 'name', 'direction': 'ASC'},
            ],
          }),
        );
      });

      test('executeCreateRequest submits model JSON under input variable',
          () async {
        final newItem = TestModel(id: '789', name: 'New Item', value: 99);
        stubPost(graphqlSuccess('createTest_model', newItem.toJson()));

        final result = await adapter.createOne(newItem);

        expect(result, equals(newItem));

        final post = capturePost();
        expect(post.body['query'], equals(adapter.createMutation));
        expect(post.body['variables'], equals({'input': newItem.toJson()}));
      });

      test('executeUpdateRequest submits id and input updates', () async {
        final updatedModel = TestModel(
          id: '123',
          name: 'Updated Item',
          value: 100,
        );
        stubPost(graphqlSuccess('updateTest_model', updatedModel.toJson()));

        final result = await adapter.updateOne(updatedModel);

        expect(result, equals(updatedModel));

        final post = capturePost();
        expect(post.body['query'], equals(adapter.updateMutation));
        expect(
          post.body['variables'],
          equals({
            'id': '123',
            'input': updatedModel.toJson(),
          }),
        );
      });

      test('executeReplaceRequest submits model for replace', () async {
        final model = TestModel(id: '123', name: 'Replaced Item', value: 200);
        stubPost(graphqlSuccess('updateTest_model', model.toJson()));

        final result = await adapter.replaceOne(model);

        expect(result, equals(model));

        final post = capturePost();
        expect(post.body['query'], equals(adapter.replaceMutation));
        expect(
          post.body['variables'],
          equals({
            'id': '123',
            'input': model.toJson(),
          }),
        );
      });

      test('executeDeleteRequest submits id and succeeds', () async {
        stubPost(graphqlSuccess('deleteTest_model', {'id': '123'}));

        await adapter.deleteOne('123');

        final post = capturePost();
        expect(post.body['query'], equals(adapter.deleteMutation));
        expect(post.body['variables'], equals({'id': '123'}));
      });
    });
  });
}
