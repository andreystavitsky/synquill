import 'package:test/test.dart';
import 'package:synquill/synquill.dart';
import 'package:synquill_graphql/synquill_graphql.dart';
import 'helpers/test_model.dart';

// Create a dummy adapter class mixing in the target mixin
class ParsingTestingAdapter extends ApiAdapterBase<TestModel>
    with GraphQLResponseParsingMixin<TestModel> {
  @override
  Uri get baseUrl => Uri.parse('https://api.test.com/graphql');

  @override
  Logger get logger => Logger('ParsingTestingAdapter');

  @override
  TestModel fromJson(Map<String, dynamic> json) => TestModel.fromJsonData(json);

  @override
  Map<String, dynamic> toJson(TestModel model) => model.toJson();

  // Expose protected methods for testing
  TestModel? testParseFindOne(Map<String, dynamic> data, String fieldName) {
    return parseFindOneGraphQLResponse(data, fieldName);
  }

  List<TestModel> testParseFindAll(
      Map<String, dynamic> data, String fieldName) {
    return parseFindAllGraphQLResponse(data, fieldName);
  }

  TestModel? testParseCreate(Map<String, dynamic> data, String fieldName) {
    return parseCreateGraphQLResponse(data, fieldName);
  }

  TestModel? testParseUpdate(Map<String, dynamic> data, String fieldName) {
    return parseUpdateGraphQLResponse(data, fieldName);
  }

  TestModel? testParseReplace(Map<String, dynamic> data, String fieldName) {
    return parseReplaceGraphQLResponse(data, fieldName);
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

// Custom parser to test Relay-style overridability
class RelayParsingAdapter extends ParsingTestingAdapter {
  @override
  List<TestModel> parseFindAllGraphQLResponse(
      Map<String, dynamic> data, String fieldName) {
    final fieldVal = data[fieldName];
    if (fieldVal == null) return [];
    if (fieldVal is! Map<String, dynamic>) {
      throw ApiException('Expected map for Relay connections');
    }
    final edges = fieldVal['edges'];
    if (edges is! List) return [];
    return edges
        .map((edge) {
          if (edge is Map<String, dynamic> && edge.containsKey('node')) {
            final node = edge['node'];
            if (node is Map<String, dynamic>) {
              return fromJson(node);
            }
          }
          throw ApiException('Invalid edge structure');
        })
        .toList();
  }
}

void main() {
  group('GraphQLResponseParsingMixin Tests', () {
    late ParsingTestingAdapter adapter;

    setUp(() {
      adapter = ParsingTestingAdapter();
    });

    group('findOne Parsing', () {
      test('extracts model from named field', () {
        final data = {
          'test_model': {'id': '123', 'name': 'John', 'value': 42}
        };
        final result = adapter.testParseFindOne(data, 'test_model');
        expect(result, equals(TestModel(id: '123', name: 'John', value: 42)));
      });

      test('returns null for null field value', () {
        final data = {'test_model': null};
        final result = adapter.testParseFindOne(data, 'test_model');
        expect(result, isNull);
      });

      test('returns null when field is missing', () {
        final data = <String, dynamic>{};
        final result = adapter.testParseFindOne(data, 'test_model');
        expect(result, isNull);
      });

      test('throws on invalid data type (non-Map)', () {
        final data = {'test_model': 'invalid_string'};
        expect(
          () => adapter.testParseFindOne(data, 'test_model'),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('findAll Parsing', () {
      test('extracts list from named field', () {
        final data = {
          'test_models': [
            {'id': '1', 'name': 'John', 'value': 42},
            {'id': '2', 'name': 'Doe', 'value': 24}
          ]
        };
        final result = adapter.testParseFindAll(data, 'test_models');
        expect(result, hasLength(2));
        expect(result[0], equals(TestModel(id: '1', name: 'John', value: 42)));
        expect(result[1], equals(TestModel(id: '2', name: 'Doe', value: 24)));
      });

      test('returns empty list for null field', () {
        final data = {'test_models': null};
        final result = adapter.testParseFindAll(data, 'test_models');
        expect(result, isEmpty);
      });

      test('returns empty list for missing field', () {
        final data = <String, dynamic>{};
        final result = adapter.testParseFindAll(data, 'test_models');
        expect(result, isEmpty);
      });

      test('returns empty list for empty array', () {
        final data = {'test_models': []};
        final result = adapter.testParseFindAll(data, 'test_models');
        expect(result, isEmpty);
      });

      test('throws on non-list field', () {
        final data = {'test_models': 'not_a_list'};
        expect(
          () => adapter.testParseFindAll(data, 'test_models'),
          throwsA(isA<ApiException>()),
        );
      });

      test('handles nested data structure (overridable for Relay-style)', () {
        final relayAdapter = RelayParsingAdapter();
        final data = {
          'test_models': {
            'edges': [
              {
                'node': {'id': '1', 'name': 'John', 'value': 42}
              },
              {
                'node': {'id': '2', 'name': 'Doe', 'value': 24}
              }
            ]
          }
        };
        final result = relayAdapter.testParseFindAll(data, 'test_models');
        expect(result, hasLength(2));
        expect(result[0], equals(TestModel(id: '1', name: 'John', value: 42)));
        expect(result[1], equals(TestModel(id: '2', name: 'Doe', value: 24)));
      });
    });

    group('create/update/replace Parsing', () {
      test('parseCreateGraphQLResponse extracts model from mutation field', () {
        final data = {
          'createTestModel': {'id': '1', 'name': 'New', 'value': 100}
        };
        final result = adapter.testParseCreate(data, 'createTestModel');
        expect(result, equals(TestModel(id: '1', name: 'New', value: 100)));
      });

      test('parseUpdateGraphQLResponse extracts model from mutation field', () {
        final data = {
          'updateTestModel': {'id': '1', 'name': 'Updated', 'value': 200}
        };
        final result = adapter.testParseUpdate(data, 'updateTestModel');
        expect(result, equals(TestModel(id: '1', name: 'Updated', value: 200)));
      });

      test(
          'parseReplaceGraphQLResponse extracts model '
          'from mutation field',
          () {
        final data = {
          'updateTestModel': {'id': '1', 'name': 'Replaced', 'value': 300}
        };
        final result = adapter.testParseReplace(data, 'updateTestModel');
        expect(result,
            equals(TestModel(id: '1', name: 'Replaced', value: 300)));
      });

      test('parseCreateGraphQLResponse returns null for null field', () {
        final data = {'createTestModel': null};
        final result = adapter.testParseCreate(data, 'createTestModel');
        expect(result, isNull);
      });
    });
  });
}
