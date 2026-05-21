import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:mockito/mockito.dart';
import 'package:synquill/synquill.dart';
import 'package:synquill_graphql/synquill_graphql.dart';
import 'package:test/test.dart';

import 'graphql_execution_test.mocks.dart';
import 'helpers/mock_graphql_responses.dart';
import 'helpers/test_graphql_adapter.dart';
import 'helpers/test_model.dart';

class BatchingTestAdapter extends TestGraphQLAdapter {
  BatchingTestAdapter({
    this.options = const GraphQLBatchOptions(
      enabled: true,
      window: Duration(milliseconds: 5),
      maxBatchSize: 10,
    ),
  });

  final GraphQLBatchOptions options;

  @override
  GraphQLBatchOptions get batchOptions => options;

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
  final Object? body;
  final Options options;
}

void main() {
  group('GraphQL query batching', () {
    late MockDio mockDio;

    void stubPostFromBody(Object? Function(Object? body) dataForBody) {
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
      ).thenAnswer((invocation) async {
        final body = invocation.namedArguments[#data];
        return Response<dynamic>(
          data: dataForBody(body),
          statusCode: 200,
          requestOptions: RequestOptions(path: ''),
        );
      });
    }

    void stubPost(dynamic data) {
      stubPostFromBody((_) => data);
    }

    List<CapturedPost> capturePosts() {
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

      final posts = <CapturedPost>[];
      for (var i = 0; i < captured.length; i += 3) {
        posts.add(
          CapturedPost(
            path: captured[i] as String,
            body: captured[i + 1],
            options: captured[i + 2] as Options,
          ),
        );
      }
      return posts;
    }

    setUp(() {
      mockDio = MockDio();
      SynquillStorage.setConfigForTesting(
        SynquillStorageConfig(dio: mockDio),
      );
    });

    tearDown(() {
      SynquillStorage.setConfigForTesting(const SynquillStorageConfig());
    });

    test('is disabled by default and keeps the existing object body', () async {
      final adapter = TestGraphQLAdapter();
      stubPost(
        graphqlSuccess('test_model', {
          'id': '1',
          'name': 'One',
          'value': 1,
        }),
      );

      final result = await adapter.findOne('1');

      expect(result, equals(TestModel(id: '1', name: 'One', value: 1)));
      final posts = capturePosts();
      expect(posts, hasLength(1));
      expect(posts.single.body, isA<Map<String, dynamic>>());
      expect(
        posts.single.body,
        equals({
          'query': adapter.findOneQuery,
          'variables': {'id': '1'},
        }),
      );
    });

    test('batches concurrent findOne queries within the configured window', () {
      fakeAsync((async) {
        final adapter = BatchingTestAdapter();
        stubPost([
          graphqlSuccess('test_model', {
            'id': '1',
            'name': 'One',
            'value': 1,
          }),
          graphqlSuccess('test_model', {
            'id': '2',
            'name': 'Two',
            'value': 2,
          }),
        ]);

        List<TestModel?>? results;
        Object? error;
        Future.wait([
          adapter.findOne('1'),
          adapter.findOne('2'),
        ]).then(
          (value) => results = value,
          onError: (Object e) {
            error = e;
          },
        );

        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 5));
        async.flushMicrotasks();

        expect(error, isNull);
        expect(
          results,
          equals([
            TestModel(id: '1', name: 'One', value: 1),
            TestModel(id: '2', name: 'Two', value: 2),
          ]),
        );

        final posts = capturePosts();
        expect(posts, hasLength(1));
        expect(posts.single.path, equals('https://api.test.com/graphql'));
        expect(posts.single.body, isA<List<Map<String, dynamic>>>());
        expect(
          posts.single.body,
          equals([
            {
              'query': adapter.findOneQuery,
              'variables': {'id': '1'},
            },
            {
              'query': adapter.findOneQuery,
              'variables': {'id': '2'},
            },
          ]),
        );
      });
    });

    test('flushes by timer when below max batch size', () {
      fakeAsync((async) {
        final adapter = BatchingTestAdapter(
          options: const GraphQLBatchOptions(
            enabled: true,
            window: Duration(milliseconds: 5),
            maxBatchSize: 10,
          ),
        );
        stubPost(
          [
            graphqlSuccess('test_model', {
              'id': '1',
              'name': 'One',
              'value': 1,
            }),
          ],
        );

        TestModel? result;
        Object? error;
        adapter.findOne('1').then(
          (value) => result = value,
          onError: (Object e) {
            error = e;
          },
        );

        async.flushMicrotasks();
        verifyNever(
          mockDio.post<dynamic>(
            any,
            data: anyNamed('data'),
            queryParameters: anyNamed('queryParameters'),
            options: anyNamed('options'),
            cancelToken: anyNamed('cancelToken'),
            onSendProgress: anyNamed('onSendProgress'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        );

        async.elapse(const Duration(milliseconds: 5));
        async.flushMicrotasks();

        expect(error, isNull);
        expect(result, equals(TestModel(id: '1', name: 'One', value: 1)));
        final posts = capturePosts();
        expect(posts, hasLength(1));
        expect(posts.single.body, isA<List<Map<String, dynamic>>>());
        expect(posts.single.body, hasLength(1));
      });
    });

    test('flushes immediately when maxBatchSize is reached', () async {
      final adapter = BatchingTestAdapter(
        options: const GraphQLBatchOptions(
          enabled: true,
          window: Duration(hours: 1),
          maxBatchSize: 2,
        ),
      );
      stubPost([
        graphqlSuccess('test_model', {
          'id': '1',
          'name': 'One',
          'value': 1,
        }),
        graphqlSuccess('test_model', {
          'id': '2',
          'name': 'Two',
          'value': 2,
        }),
      ]);

      final results = await Future.wait([
        adapter.findOne('1'),
        adapter.findOne('2'),
      ]).timeout(const Duration(milliseconds: 100));

      expect(results, hasLength(2));
      final posts = capturePosts();
      expect(posts, hasLength(1));
      expect(posts.single.body, hasLength(2));
    });

    test('keeps requests with different headers in separate batches', () async {
      final adapter = BatchingTestAdapter();
      stubPostFromBody((body) {
        final operations = body as List<dynamic>;
        final variables = operations.single as Map<String, dynamic>;
        final id = (variables['variables'] as Map<String, dynamic>)['id'];
        return [
          graphqlSuccess('test_model', {
            'id': id,
            'name': 'Item $id',
            'value': int.parse(id as String),
          }),
        ];
      });

      final results = await Future.wait([
        adapter.findOne('1', headers: {'X-Tenant': 'a'}),
        adapter.findOne('2', headers: {'X-Tenant': 'b'}),
      ]);

      expect(results[0]!.id, equals('1'));
      expect(results[1]!.id, equals('2'));

      final posts = capturePosts();
      expect(posts, hasLength(2));
      expect(posts.map((post) => post.body), everyElement(hasLength(1)));
      expect(
        posts.map((post) => post.options.headers?['X-Tenant']),
        unorderedEquals(['a', 'b']),
      );
    });

    test('does not batch mutations', () async {
      final adapter = BatchingTestAdapter();
      final model = TestModel(id: '1', name: 'One', value: 1);
      stubPost(graphqlSuccess('createTest_model', model.toJson()));

      final result = await adapter.createOne(model);

      expect(result, equals(model));
      final posts = capturePosts();
      expect(posts, hasLength(1));
      expect(posts.single.body, isA<Map<String, dynamic>>());
      expect((posts.single.body as Map<String, dynamic>)['query'],
          equals(adapter.createMutation));
    });

    test('batches explicit query with leading comments', () {
      fakeAsync((async) {
        final adapter = BatchingTestAdapter();
        const operation = '''
# Fetch one model
query GetTestModel(\$id: ID!) {
  testModel(id: \$id) { id name value }
}
''';
        stubPost([
          graphqlSuccess('test_model', {
            'id': '1',
            'name': 'One',
            'value': 1,
          }),
        ]);

        Map<String, dynamic>? result;
        Object? error;
        adapter.executeTestOperation(
          operation: operation,
          variables: {'id': '1'},
        ).then(
          (value) => result = value,
          onError: (Object e) {
            error = e;
          },
        );

        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 5));
        async.flushMicrotasks();

        expect(error, isNull);
        expect(
            result,
            equals({
              'test_model': {'id': '1', 'name': 'One', 'value': 1}
            }));
        final posts = capturePosts();
        expect(posts, hasLength(1));
        expect(posts.single.body, isA<List<Map<String, dynamic>>>());
      });
    });

    test('does not batch mutation with leading comments', () async {
      final adapter = BatchingTestAdapter();
      const operation = '''
# Create one model
mutation CreateTestModel(\$input: CreateInput!) {
  createTestModel(input: \$input) { id name value }
}
''';
      stubPost(
        graphqlSuccess('createTest_model', {
          'id': '1',
          'name': 'One',
          'value': 1,
        }),
      );

      await adapter.executeTestOperation(operation: operation);

      final posts = capturePosts();
      expect(posts, hasLength(1));
      expect(posts.single.body, isA<Map<String, dynamic>>());
    });

    test('does not batch subscriptions', () async {
      final adapter = BatchingTestAdapter();
      const operation = '''
subscription WatchTestModel {
  testModelUpdated { id name value }
}
''';
      stubPost(
        graphqlSuccess('testModelUpdated', {
          'id': '1',
          'name': 'One',
          'value': 1,
        }),
      );

      await adapter.executeTestOperation(operation: operation);

      final posts = capturePosts();
      expect(posts, hasLength(1));
      expect(posts.single.body, isA<Map<String, dynamic>>());
    });

    test('invalid GraphQL document fails before a Dio call', () async {
      final adapter = BatchingTestAdapter();

      await expectLater(
        adapter.executeTestOperation(operation: 'query Broken {'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('Invalid GraphQL document'),
          ),
        ),
      );

      verifyNever(
        mockDio.post<dynamic>(
          any,
          data: anyNamed('data'),
          queryParameters: anyNamed('queryParameters'),
          options: anyNamed('options'),
          cancelToken: anyNamed('cancelToken'),
          onSendProgress: anyNamed('onSendProgress'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        ),
      );
    });

    test('does not batch requests with non-null extra by default', () async {
      final adapter = BatchingTestAdapter();
      stubPost(
        graphqlSuccess('test_model', {
          'id': '1',
          'name': 'One',
          'value': 1,
        }),
      );

      await adapter.findOne('1', extra: {'traceId': 'abc'});

      final posts = capturePosts();
      expect(posts, hasLength(1));
      expect(posts.single.body, isA<Map<String, dynamic>>());
      expect(posts.single.options.extra, equals({'traceId': 'abc'}));
    });

    test('fails only the matching future for item-level GraphQL errors',
        () async {
      final adapter = BatchingTestAdapter();
      stubPost([
        graphqlSuccess('test_model', {
          'id': '1',
          'name': 'One',
          'value': 1,
        }),
        graphqlError('Resolver failed'),
      ]);

      final success = adapter.findOne('1');
      final failure = adapter.findOne('2');

      await expectLater(
        failure,
        throwsA(isA<ApiException>()),
      );
      expect(await success, equals(TestModel(id: '1', name: 'One', value: 1)));
    });

    test('maps DioException failures to every operation in the batch',
        () async {
      final adapter = BatchingTestAdapter();
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

      final first = adapter.findOne('1');
      final second = adapter.findOne('2');

      await expectLater(first, throwsA(isA<NetworkException>()));
      await expectLater(second, throwsA(isA<NetworkException>()));
    });

    test('fails all operations when batch response format is malformed',
        () async {
      final adapter = BatchingTestAdapter();
      stubPost({'data': 'not a batch list'});

      final first = adapter.findOne('1');
      final second = adapter.findOne('2');

      await expectLater(
        first,
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('Invalid GraphQL batch response format'),
          ),
        ),
      );
      await expectLater(second, throwsA(isA<ApiException>()));
    });

    test('dispose cancels pending timer and fails queued operations', () {
      fakeAsync((async) {
        final adapter = BatchingTestAdapter(
          options: const GraphQLBatchOptions(
            enabled: true,
            window: Duration(hours: 1),
            maxBatchSize: 10,
          ),
        );
        stubPost([
          graphqlSuccess('test_model', {
            'id': '1',
            'name': 'One',
            'value': 1,
          }),
        ]);

        Object? error;
        adapter.findOne('1').then(
          (_) {},
          onError: (Object e) {
            error = e;
          },
        );
        async.flushMicrotasks();

        adapter.dispose();
        async.elapse(const Duration(hours: 1));
        async.flushMicrotasks();

        expect(error, isA<ApiException>());
        verifyNever(
          mockDio.post<dynamic>(
            any,
            data: anyNamed('data'),
            queryParameters: anyNamed('queryParameters'),
            options: anyNamed('options'),
            cancelToken: anyNamed('cancelToken'),
            onSendProgress: anyNamed('onSendProgress'),
            onReceiveProgress: anyNamed('onReceiveProgress'),
          ),
        );
      });
    });

    test('dispose is idempotent', () {
      final adapter = BatchingTestAdapter();

      adapter.dispose();
      expect(adapter.dispose, returnsNormally);
    });

    test('requests after dispose fail immediately without a Dio call',
        () async {
      final adapter = BatchingTestAdapter();

      adapter.dispose();

      await expectLater(
        adapter.findOne('1'),
        throwsA(isA<ApiException>()),
      );
      verifyNever(
        mockDio.post<dynamic>(
          any,
          data: anyNamed('data'),
          queryParameters: anyNamed('queryParameters'),
          options: anyNamed('options'),
          cancelToken: anyNamed('cancelToken'),
          onSendProgress: anyNamed('onSendProgress'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        ),
      );
    });

    test('dispose during in-flight batch fails futures and ignores response',
        () async {
      final adapter = BatchingTestAdapter(
        options: const GraphQLBatchOptions(
          enabled: true,
          window: Duration(milliseconds: 1),
          maxBatchSize: 2,
        ),
      );
      final responseCompleter = Completer<Response<dynamic>>();
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
      ).thenAnswer((_) => responseCompleter.future);

      final first = adapter.findOne('1');
      final second = adapter.findOne('2');
      await Future<void>.delayed(Duration.zero);

      adapter.dispose();
      await expectLater(first, throwsA(isA<ApiException>()));
      await expectLater(second, throwsA(isA<ApiException>()));

      responseCompleter.complete(
        Response<dynamic>(
          data: [
            graphqlSuccess('test_model', {
              'id': '1',
              'name': 'One',
              'value': 1,
            }),
            graphqlSuccess('test_model', {
              'id': '2',
              'name': 'Two',
              'value': 2,
            }),
          ],
          statusCode: 200,
          requestOptions: RequestOptions(path: ''),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final posts = capturePosts();
      expect(posts, hasLength(1));
    });
  });
}
