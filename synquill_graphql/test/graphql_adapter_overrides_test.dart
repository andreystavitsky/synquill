import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:synquill/synquill.dart';
import 'package:test/test.dart';

import 'helpers/test_graphql_adapter.dart';
import 'helpers/test_model.dart';
@GenerateNiceMocks([MockSpec<Dio>()])
import 'graphql_adapter_overrides_test.mocks.dart';

class AuthHeaderAdapter extends TestGraphQLAdapter {
  @override
  Future<Map<String, dynamic>> executeGraphQLOperation({
    required String operation,
    Map<String, dynamic>? variables,
    Map<String, String>? headers,
    String? operationName,
    Map<String, dynamic>? extra,
  }) {
    return super.executeGraphQLOperation(
      operation: operation,
      variables: variables,
      headers: {
        'Authorization': 'Bearer generated-token',
        if (headers != null) ...headers,
      },
      operationName: operationName,
      extra: extra,
    );
  }
}

class HasuraVariablesAdapter extends TestGraphQLAdapter {
  Map<String, dynamic> exposeQueryParamsToGraphQLVariables(
    QueryParams? queryParams,
  ) {
    return queryParamsToGraphQLVariables(queryParams);
  }

  @override
  Map<String, dynamic> queryParamsToGraphQLVariables(QueryParams? queryParams) {
    if (queryParams == null || !queryParams.hasParameters) {
      return const {};
    }

    final where = <String, dynamic>{};
    for (final filter in queryParams.filters) {
      final fieldName = filter.field.fieldName;
      final value = switch (filter.value) {
        SingleValue(:final value) => value,
        ListValue(:final values) => values,
        NoValue() => true,
      };
      final operator = switch (filter.operator) {
        FilterOperator.equals => '_eq',
        FilterOperator.notEquals => '_neq',
        FilterOperator.greaterThan => '_gt',
        FilterOperator.greaterThanOrEqual => '_gte',
        FilterOperator.lessThan => '_lt',
        FilterOperator.lessThanOrEqual => '_lte',
        FilterOperator.contains => '_ilike',
        FilterOperator.startsWith => '_ilike',
        FilterOperator.endsWith => '_ilike',
        FilterOperator.inList => '_in',
        FilterOperator.notInList => '_nin',
        FilterOperator.isNull => '_is_null',
        FilterOperator.isNotNull => '_is_null',
      };
      where[fieldName] = {operator: value};
    }

    return {'where': where};
  }
}

class RelayFindAllAdapter extends TestGraphQLAdapter {
  @override
  List<TestModel> parseFindAllGraphQLResponse(
    Map<String, dynamic> data,
    String fieldName,
  ) {
    final connection = data[fieldName];
    if (connection is! Map<String, dynamic>) {
      return const [];
    }

    final edges = connection['edges'];
    if (edges is! List) {
      return const [];
    }

    return edges.map((edge) {
      final edgeMap = edge as Map<String, dynamic>;
      final node = edgeMap['node'] as Map<String, dynamic>;
      return fromJson(node);
    }).toList();
  }
}

class CustomErrorAdapter extends TestGraphQLAdapter {
  @override
  SynquillStorageException mapGraphQLErrorToException(
    Map<String, dynamic> error,
    int? httpStatusCode,
  ) {
    final extensions = error['extensions'];
    if (extensions is Map<String, dynamic> &&
        extensions['code'] == 'RATE_LIMITED') {
      return ApiException('Too many GraphQL requests', statusCode: 429);
    }
    return super.mapGraphQLErrorToException(error, httpStatusCode);
  }
}

class HasuraRelayAdapter extends RelayFindAllAdapter {
  @override
  Map<String, dynamic> queryParamsToGraphQLVariables(QueryParams? queryParams) {
    return HasuraVariablesAdapter()
        .exposeQueryParamsToGraphQLVariables(queryParams);
  }
}

class CapturedPost {
  CapturedPost({
    required this.body,
    required this.options,
  });

  final Map<String, dynamic> body;
  final Options options;
}

void main() {
  group('GraphQL adapter override tests', () {
    late MockDio mockDio;

    void configureAdapter() {
      SynquillStorage.setConfigForTesting(
        SynquillStorageConfig(dio: mockDio),
      );
    }

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
          any,
          data: captureAnyNamed('data'),
          queryParameters: anyNamed('queryParameters'),
          options: captureAnyNamed('options'),
          cancelToken: anyNamed('cancelToken'),
          onSendProgress: anyNamed('onSendProgress'),
          onReceiveProgress: anyNamed('onReceiveProgress'),
        ),
      ).captured;

      return CapturedPost(
        body: captured[0] as Map<String, dynamic>,
        options: captured[1] as Options,
      );
    }

    setUp(() {
      mockDio = MockDio();
    });

    tearDown(() {
      SynquillStorage.setConfigForTesting(const SynquillStorageConfig());
    });

    test('executeGraphQLOperation can add custom auth headers', () async {
      final adapter = AuthHeaderAdapter();
      configureAdapter();
      stubPost({
        'data': {
          'test_model': {'id': '1', 'name': 'Secured', 'value': 1},
        },
      });

      await adapter.findOne('1');

      final post = capturePost();
      expect(
        post.options.headers?['Authorization'],
        equals('Bearer generated-token'),
      );
    });

    test('queryParamsToGraphQLVariables can be overridden for Hasura', () {
      final adapter = HasuraVariablesAdapter();
      const nameField = FieldSelector<String>('name', String);
      final queryParams = QueryParams(filters: [nameField.equals('Ada')]);

      final variables =
          adapter.exposeQueryParamsToGraphQLVariables(queryParams);

      expect(
        variables,
        equals({
          'where': {
            'name': {'_eq': 'Ada'},
          },
        }),
      );
    });

    test('parseFindAllGraphQLResponse can handle Relay connections', () async {
      final adapter = RelayFindAllAdapter();
      configureAdapter();
      stubPost({
        'data': {
          'test_models': {
            'edges': [
              {
                'node': {'id': '1', 'name': 'Relay A', 'value': 10},
              },
              {
                'node': {'id': '2', 'name': 'Relay B', 'value': 20},
              },
            ],
          },
        },
      });

      final result = await adapter.findAll();

      expect(result, [
        TestModel(id: '1', name: 'Relay A', value: 10),
        TestModel(id: '2', name: 'Relay B', value: 20),
      ]);
    });

    test('mapGraphQLErrorToException can handle custom error codes', () async {
      final adapter = CustomErrorAdapter();
      configureAdapter();
      stubPost({
        'data': null,
        'errors': [
          {
            'message': 'Rate limited',
            'extensions': {'code': 'RATE_LIMITED'},
          },
        ],
      });

      expect(
        () => adapter.findOne('1'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Too many GraphQL requests')
              .having((e) => e.statusCode, 'statusCode', 429),
        ),
      );
    });

    test('multiple overrides work together', () async {
      final adapter = HasuraRelayAdapter();
      configureAdapter();
      stubPost({
        'data': {
          'test_models': {
            'edges': [
              {
                'node': {'id': '1', 'name': 'Combined', 'value': 30},
              },
            ],
          },
        },
      });

      const nameField = FieldSelector<String>('name', String);
      final result = await adapter.findAll(
        queryParams: QueryParams(filters: [nameField.equals('Combined')]),
      );

      expect(result.single, TestModel(id: '1', name: 'Combined', value: 30));

      final post = capturePost();
      expect(
        post.body['variables'],
        equals({
          'where': {
            'name': {'_eq': 'Combined'},
          },
        }),
      );
    });
  });
}
