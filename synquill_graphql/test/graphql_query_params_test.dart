import 'package:test/test.dart';
import 'package:synquill/synquill.dart';
import 'package:synquill_graphql/synquill_graphql.dart';
import 'helpers/test_model.dart';

// Create a dummy adapter class mixing in the target mixin
class ParamsTestingAdapter extends ApiAdapterBase<TestModel>
    with
        DioClientMixin<TestModel>,
        GraphQLErrorHandlingMixin<TestModel>,
        GraphQLResponseParsingMixin<TestModel>,
        GraphQLExecutionMixin<TestModel> {
  @override
  Uri get baseUrl => Uri.parse('https://api.test.com/graphql');

  @override
  Logger get logger => Logger('ParamsTestingAdapter');

  @override
  TestModel fromJson(Map<String, dynamic> json) => TestModel.fromJsonData(json);

  @override
  Map<String, dynamic> toJson(TestModel model) => model.toJson();

  // Expose protected method for testing
  Map<String, dynamic> testQueryParamsToGraphQLVariables(
      QueryParams? queryParams) {
    return queryParamsToGraphQLVariables(queryParams);
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

// Custom format overrides for testing extensibility
class HasuraParamsTestingAdapter extends ParamsTestingAdapter {
  @override
  Map<String, dynamic> queryParamsToGraphQLVariables(
      QueryParams? queryParams) {
    if (queryParams == null || !queryParams.hasParameters) {
      return {};
    }

    final where = <String, dynamic>{};
    for (final filter in queryParams.filters) {
      final key = filter.field.fieldName;
      final op = _getHasuraOperator(filter.operator);
      final value = _getFilterValue(filter.value);
      where[key] = {op: value};
    }

    return {'where': where};
  }

  String _getHasuraOperator(FilterOperator op) {
    switch (op) {
      case FilterOperator.equals:
        return '_eq';
      case FilterOperator.notEquals:
        return '_neq';
      case FilterOperator.greaterThan:
        return '_gt';
      case FilterOperator.lessThan:
        return '_lt';
      default:
        return '_eq';
    }
  }

  dynamic _getFilterValue(FilterValue value) {
    if (value is SingleValue) return value.value;
    if (value is ListValue) return value.values;
    return null;
  }
}

void main() {
  group('QueryParamsToVariables Tests', () {
    late ParamsTestingAdapter adapter;
    const nameField = FieldSelector<String>('name', String);
    const ageField = FieldSelector<int>('age', int);

    setUp(() {
      adapter = ParamsTestingAdapter();
    });

    group('Filters mapping', () {
      test('converts equals filter', () {
        final queryParams = QueryParams(filters: [nameField.equals('John')]);
        final vars = adapter.testQueryParamsToGraphQLVariables(queryParams);
        expect(
          vars['filter'],
          equals({
            'name': {'eq': 'John'}
          }),
        );
      });

      test('converts notEquals filter', () {
        final queryParams = QueryParams(filters: [nameField.notEquals('John')]);
        final vars = adapter.testQueryParamsToGraphQLVariables(queryParams);
        expect(
          vars['filter'],
          equals({
            'name': {'neq': 'John'}
          }),
        );
      });

      test('converts greaterThan / greaterThanOrEqual filter', () {
        final queryParams = QueryParams(filters: [
          ageField.greaterThan(18),
          ageField.greaterThanOrEqual(21),
        ]);
        final vars = adapter.testQueryParamsToGraphQLVariables(queryParams);
        expect(
          vars['filter'],
          equals({
            'age': {
              'gt': 18,
              'gte': 21,
            }
          }),
        );
      });

      test('converts lessThan / lessThanOrEqual filter', () {
        final queryParams = QueryParams(filters: [
          ageField.lessThan(60),
          ageField.lessThanOrEqual(65),
        ]);
        final vars = adapter.testQueryParamsToGraphQLVariables(queryParams);
        expect(
          vars['filter'],
          equals({
            'age': {
              'lt': 60,
              'lte': 65,
            }
          }),
        );
      });

      test('converts contains filter', () {
        final queryParams = QueryParams(filters: [nameField.contains('an')]);
        final vars = adapter.testQueryParamsToGraphQLVariables(queryParams);
        expect(
          vars['filter'],
          equals({
            'name': {'contains': 'an'}
          }),
        );
      });

      test('converts startsWith filter', () {
        final queryParams = QueryParams(filters: [nameField.startsWith('Jo')]);
        final vars = adapter.testQueryParamsToGraphQLVariables(queryParams);
        expect(
          vars['filter'],
          equals({
            'name': {'startsWith': 'Jo'}
          }),
        );
      });

      test('converts endsWith filter', () {
        final queryParams = QueryParams(filters: [nameField.endsWith('hn')]);
        final vars = adapter.testQueryParamsToGraphQLVariables(queryParams);
        expect(
          vars['filter'],
          equals({
            'name': {'endsWith': 'hn'}
          }),
        );
      });

      test('converts inList filter', () {
        final queryParams = QueryParams(
          filters: [nameField.inList(['John', 'Jane'])],
        );
        final vars = adapter.testQueryParamsToGraphQLVariables(queryParams);
        expect(
          vars['filter'],
          equals({
            'name': {
              'in': ['John', 'Jane']
            }
          }),
        );
      });

      test('converts isNull filter', () {
        final queryParams = QueryParams(filters: [nameField.isNull()]);
        final vars = adapter.testQueryParamsToGraphQLVariables(queryParams);
        expect(
          vars['filter'],
          equals({
            'name': {'isNull': true}
          }),
        );
      });

      test('converts isNotNull filter', () {
        final queryParams = QueryParams(filters: [nameField.isNotNull()]);
        final vars = adapter.testQueryParamsToGraphQLVariables(queryParams);
        expect(
          vars['filter'],
          equals({
            'name': {'isNotNull': true}
          }),
        );
      });

      test('converts multiple filters (AND logic / field merging)', () {
        final queryParams = QueryParams(filters: [
          nameField.equals('John'),
          ageField.greaterThan(18),
        ]);
        final vars = adapter.testQueryParamsToGraphQLVariables(queryParams);
        expect(
          vars['filter'],
          equals({
            'name': {'eq': 'John'},
            'age': {'gt': 18},
          }),
        );
      });
    });

    group('Sorting mapping', () {
      test('converts single sort ascending', () {
        const queryParams = QueryParams(sorts: [
          SortCondition.ascending(nameField),
        ]);
        final vars = adapter.testQueryParamsToGraphQLVariables(queryParams);
        expect(
          vars['sort'],
          equals([
            {'field': 'name', 'direction': 'ASC'}
          ]),
        );
      });

      test('converts single sort descending', () {
        const queryParams = QueryParams(sorts: [
          SortCondition.descending(nameField),
        ]);
        final vars = adapter.testQueryParamsToGraphQLVariables(queryParams);
        expect(
          vars['sort'],
          equals([
            {'field': 'name', 'direction': 'DESC'}
          ]),
        );
      });

      test('converts multiple sorts', () {
        const queryParams = QueryParams(sorts: [
          SortCondition.ascending(nameField),
          SortCondition.descending(ageField),
        ]);
        final vars = adapter.testQueryParamsToGraphQLVariables(queryParams);
        expect(
          vars['sort'],
          equals([
            {'field': 'name', 'direction': 'ASC'},
            {'field': 'age', 'direction': 'DESC'},
          ]),
        );
      });
    });

    group('Pagination mapping', () {
      test('converts pagination with limit and offset', () {
        const queryParams = QueryParams(
          pagination: PaginationParams(limit: 10, offset: 20),
        );
        final vars = adapter.testQueryParamsToGraphQLVariables(queryParams);
        expect(
          vars['pagination'],
          equals({'limit': 10, 'offset': 20}),
        );
      });

      test('converts pagination with only limit', () {
        const queryParams = QueryParams(
          pagination: PaginationParams.limit(10),
        );
        final vars = adapter.testQueryParamsToGraphQLVariables(queryParams);
        expect(
          vars['pagination'],
          equals({'limit': 10, 'offset': null}),
        );
      });
    });

    group('Combined mapping', () {
      test('converts combined filters, sorts, and pagination', () {
        final queryParams = QueryParams(
          filters: [nameField.equals('John')],
          sorts: const [SortCondition.ascending(nameField)],
          pagination: const PaginationParams(limit: 10, offset: 20),
        );
        final vars = adapter.testQueryParamsToGraphQLVariables(queryParams);
        expect(
          vars['filter'],
          equals({
            'name': {'eq': 'John'}
          }),
        );
        expect(
          vars['sort'],
          equals([
            {'field': 'name', 'direction': 'ASC'}
          ]),
        );
        expect(
          vars['pagination'],
          equals({'limit': 10, 'offset': 20}),
        );
      });

      test('returns empty map for empty QueryParams', () {
        final vars =
            adapter.testQueryParamsToGraphQLVariables(QueryParams.empty);
        expect(vars, isEmpty);
      });

      test('returns empty map for null QueryParams', () {
        final vars = adapter.testQueryParamsToGraphQLVariables(null);
        expect(vars, isEmpty);
      });
    });

    group('Custom overrides', () {
      test('can be overridden for Hasura style where', () {
        final hasura = HasuraParamsTestingAdapter();
        final queryParams = QueryParams(
          filters: [
            nameField.equals('John'),
            ageField.greaterThan(18),
          ],
        );
        final vars = hasura.queryParamsToGraphQLVariables(queryParams);
        expect(
          vars['where'],
          equals({
            'name': {'_eq': 'John'},
            'age': {'_gt': 18},
          }),
        );
      });
    });
  });
}
