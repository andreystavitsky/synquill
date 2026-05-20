import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:synquill/synquill.dart';
import 'package:test/test.dart';

import 'helpers/mock_graphql_responses.dart';
import 'helpers/test_graphql_adapter.dart';
import 'helpers/test_model.dart';
@GenerateNiceMocks([MockSpec<Dio>()])
import 'graphql_api_adapter_test.mocks.dart';

class CustomReplaceAdapter extends TestGraphQLAdapter {
  @override
  String get replaceMutation =>
      r'mutation ReplaceTestModel($id: ID!, $input: ReplaceInput!) { '
      r'replaceTestModel(id: $id, input: $input) { id name value } }';

  @override
  String get replaceResponseField => 'replaceTest_model';
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
  group('GraphQLApiAdapter', () {
    late MockDio mockDio;
    late TestGraphQLAdapter adapter;

    void stubPost(dynamic data) {
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
          statusCode: 200,
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
      adapter = TestGraphQLAdapter();
      SynquillStorage.setConfigForTesting(
        SynquillStorageConfig(dio: mockDio),
      );
    });

    tearDown(() {
      SynquillStorage.setConfigForTesting(const SynquillStorageConfig());
    });

    group('basic configuration', () {
      test('baseUrl matches graphqlEndpoint', () {
        expect(adapter.baseUrl, equals(adapter.graphqlEndpoint));
        expect(
          adapter.baseUrl.toString(),
          equals('https://api.test.com/graphql'),
        );
      });

      test('logger name is GraphQLApiAdapter', () {
        expect(adapter.logger.name, equals('GraphQLApiAdapter'));
      });

      test('default response fields are configured correctly', () {
        expect(adapter.type, equals('test_model'));
        expect(adapter.pluralType, equals('test_models'));

        expect(adapter.findOneResponseField, equals('test_model'));
        expect(adapter.findAllResponseField, equals('test_models'));
        expect(adapter.createResponseField, equals('createTest_model'));
        expect(adapter.updateResponseField, equals('updateTest_model'));
        expect(adapter.replaceResponseField, equals('updateTest_model'));
        expect(adapter.deleteResponseField, equals('deleteTest_model'));
      });

      test('replace mutation defaults to update mutation', () {
        expect(adapter.replaceMutation, equals(adapter.updateMutation));
      });
    });

    group('findOne', () {
      test('sends correct GraphQL query with id variable and parses model',
          () async {
        stubPost(
          graphqlSuccess('test_model', {
            'id': '123',
            'name': 'Found Item',
            'value': 10,
          }),
        );

        final result = await adapter.findOne('123');

        expect(result,
            equals(TestModel(id: '123', name: 'Found Item', value: 10)));

        final post = capturePost();
        expect(post.path, equals('https://api.test.com/graphql'));
        expect(post.body['query'], equals(adapter.findOneQuery));
        expect(post.body['variables'], equals({'id': '123'}));
      });

      test('returns null when response field is null', () async {
        stubPost(graphqlSuccess('test_model', null));

        final result = await adapter.findOne('missing');

        expect(result, isNull);
      });

      test('passes custom headers and forwards extra parameter', () async {
        stubPost(
          graphqlSuccess('test_model', {
            'id': '123',
            'name': 'Found Item',
            'value': 10,
          }),
        );

        await adapter.findOne(
          '123',
          headers: {'Authorization': 'Bearer token'},
          extra: {'traceId': 'abc'},
        );

        final post = capturePost();
        expect(post.options.headers?['Authorization'], equals('Bearer token'));
        expect(post.options.extra, equals({'traceId': 'abc'}));
      });
    });

    group('findAll', () {
      test('sends correct GraphQL query and converts QueryParams', () async {
        stubPost(
          graphqlSuccess('test_models', [
            {'id': '1', 'name': 'Item A', 'value': 10},
            {'id': '2', 'name': 'Item B', 'value': 20},
          ]),
        );

        const nameField = FieldSelector<String>('name', String);
        final result = await adapter.findAll(
          queryParams: QueryParams(
            filters: [nameField.equals('Item A')],
            sorts: const [SortCondition.ascending(nameField)],
          ),
        );

        expect(result.length, equals(2));
        expect(result.first.name, equals('Item A'));

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

      test('returns empty list when response field is empty or null', () async {
        stubPost(graphqlSuccess('test_models', null));

        final nullResult = await adapter.findAll();
        expect(nullResult, isEmpty);

        stubPost(graphqlSuccess('test_models', <dynamic>[]));

        final emptyResult = await adapter.findAll();
        expect(emptyResult, isEmpty);
      });
    });

    group('mutations', () {
      test('createOne sends model data as input and returns parsed model',
          () async {
        final model = TestModel(id: '1', name: 'Created', value: 11);
        stubPost(graphqlSuccess('createTest_model', model.toJson()));

        final result = await adapter.createOne(model);

        expect(result, equals(model));

        final post = capturePost();
        expect(post.body['query'], equals(adapter.createMutation));
        expect(post.body['variables'], equals({'input': model.toJson()}));
      });

      test('createOne returns null for null mutation response', () async {
        final model = TestModel(id: '1', name: 'Created', value: 11);
        stubPost(graphqlSuccess('createTest_model', null));

        final result = await adapter.createOne(model);

        expect(result, isNull);
      });

      test('updateOne sends id and input variables', () async {
        final model = TestModel(id: '1', name: 'Updated', value: 12);
        stubPost(graphqlSuccess('updateTest_model', model.toJson()));

        final result = await adapter.updateOne(model);

        expect(result, equals(model));

        final post = capturePost();
        expect(post.body['query'], equals(adapter.updateMutation));
        expect(
          post.body['variables'],
          equals({'id': '1', 'input': model.toJson()}),
        );
      });

      test('replaceOne defaults to update mutation and response field',
          () async {
        final model = TestModel(id: '1', name: 'Replaced', value: 13);
        stubPost(graphqlSuccess('updateTest_model', model.toJson()));

        final result = await adapter.replaceOne(model);

        expect(result, equals(model));

        final post = capturePost();
        expect(post.body['query'], equals(adapter.updateMutation));
        expect(
          post.body['variables'],
          equals({'id': '1', 'input': model.toJson()}),
        );
      });

      test('replaceOne uses custom replace mutation when overridden', () async {
        adapter = CustomReplaceAdapter();
        final model = TestModel(id: '1', name: 'Replaced', value: 13);
        stubPost(graphqlSuccess('replaceTest_model', model.toJson()));

        final result = await adapter.replaceOne(model);

        expect(result, equals(model));

        final post = capturePost();
        expect(post.body['query'], equals(adapter.replaceMutation));
      });

      test('deleteOne sends delete mutation with id variable', () async {
        stubPost(graphqlSuccess('deleteTest_model', {'id': '1'}));

        await adapter.deleteOne('1');

        final post = capturePost();
        expect(post.body['query'], equals(adapter.deleteMutation));
        expect(post.body['variables'], equals({'id': '1'}));
      });
    });
  });
}
