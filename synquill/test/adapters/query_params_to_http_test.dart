import 'package:test/test.dart';
import 'package:mockito/mockito.dart';
import 'package:synquill/synquill.dart';

// Mock classes
class MockDio extends Mock implements Dio {}

class MockRequestOptions extends Mock implements RequestOptions {}

class MockResponse<T> extends Mock implements Response<T> {}

/// Test model for API adapter testing
class TestModel extends SynquillDataModel<TestModel> {
  @override
  final String id;
  final String name;

  TestModel({required this.id, required this.name});

  TestModel copyWith({String? id, String? name}) {
    return TestModel(id: id ?? this.id, name: name ?? this.name);
  }

  @override
  TestModel fromJson(Map<String, dynamic> json) {
    return TestModel(id: json['id'] as String, name: json['name'] as String);
  }

  @override
  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name};
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TestModel && other.id == id && other.name == name;
  }

  @override
  int get hashCode => id.hashCode ^ name.hashCode;
}

/// Test implementation of ApiAdapter for testing
class TestApiAdapter extends ApiAdapterBase<TestModel> {
  TestApiAdapter({Dio? dio});

  @override
  Uri get baseUrl => Uri.parse('https://api.example.com/v1/');

  @override
  Future<Map<String, String>> get baseHeaders async => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  @override
  String get type => 'testmodel';

  @override
  String get pluralType => 'testmodels';

  @override
  TestModel fromJson(Map<String, dynamic> json) {
    return TestModel(id: json['id'] as String, name: json['name'] as String);
  }

  @override
  Map<String, dynamic> toJson(TestModel model) {
    return model.toJson();
  }

  // Mock implementations for abstract methods
  @override
  Future<TestModel?> findOne(
    String id, {
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    throw UnimplementedError('Mock implementation');
  }

  @override
  Future<List<TestModel>> findAll({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    throw UnimplementedError('Mock implementation');
  }

  @override
  Future<TestModel?> createOne(
    TestModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    throw UnimplementedError('Mock implementation');
  }

  @override
  Future<TestModel?> updateOne(
    TestModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    throw UnimplementedError('Mock implementation');
  }

  @override
  Future<TestModel?> replaceOne(
    TestModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    throw UnimplementedError('Mock implementation');
  }

  @override
  Future<void> deleteOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    throw UnimplementedError('Mock implementation');
  }
}

// Test field selectors
const nameField = FieldSelector<String>('name', String);
const ageField = FieldSelector<int>('age', int);
const tagsField = FieldSelector<String>('tags', String);
const deletedAtField = FieldSelector<DateTime?>('deletedAt', DateTime);
const createdAtField = FieldSelector<DateTime>('createdAt', DateTime);
const statusField = FieldSelector<String>('status', String);
const priorityField = FieldSelector<int>('priority', int);
const updatedAtField = FieldSelector<DateTime>('updatedAt', DateTime);
const descriptionField = FieldSelector<String>('description', String);
const titleField = FieldSelector<String>('title', String);
const field1 = FieldSelector<String>('field1', String);
const field2 = FieldSelector<String>('field2', String);
const field3 = FieldSelector<int>('field3', int);
const field4 = FieldSelector<int>('field4', int);
const field5 = FieldSelector<int>('field5', int);
const field6 = FieldSelector<int>('field6', int);
const field7 = FieldSelector<String>('field7', String);
const field8 = FieldSelector<String>('field8', String);
const field9 = FieldSelector<String>('field9', String);
const field10 = FieldSelector<String>('field10', String);
const field11 = FieldSelector<String>('field11', String);
const field12 = FieldSelector<String?>('field12', String);
const field13 = FieldSelector<String>('field13', String);
const isActiveField = FieldSelector<bool>('isActive', bool);
const isDeletedField = FieldSelector<bool>('isDeleted', bool);

void main() {
  group('ApiAdapterBase QueryParams to HTTP conversion', () {
    late MockDio mockDio;
    late TestApiAdapter apiAdapter;

    setUp(() {
      mockDio = MockDio();
      apiAdapter = TestApiAdapter(dio: mockDio);
    });

    group('queryParamsToHttpParams', () {
      test('should convert basic filters correctly', () {
        final queryParams = QueryParams(
          filters: [
            nameField.equals('John'),
            ageField.greaterThan(18),
            tagsField.contains('tag1,tag2,tag3'),
            deletedAtField.isNull(),
            createdAtField.isNotNull(),
          ],
        );

        final httpParams = apiAdapter.queryParamsToHttpParams(queryParams);

        expect(httpParams['filter[name][equals]'], 'John');
        expect(httpParams['filter[age][greaterThan]'], '18');
        expect(httpParams['filter[tags][contains]'], 'tag1,tag2,tag3');
        expect(httpParams['filter[deletedAt][isNull]'], '');
        expect(httpParams['filter[createdAt][isNotNull]'], '');
      });

      test('should convert sort conditions correctly', () {
        const queryParams = QueryParams(
          sorts: [
            SortCondition.ascending(nameField),
            SortCondition.descending(createdAtField),
          ],
        );

        final httpParams = apiAdapter.queryParamsToHttpParams(queryParams);

        expect(httpParams['sort'], 'name:asc,createdAt:desc');
      });

      test('should convert pagination correctly', () {
        const queryParams = QueryParams(
          pagination: PaginationParams(limit: 20, offset: 40),
        );

        final httpParams = apiAdapter.queryParamsToHttpParams(queryParams);

        expect(httpParams['limit'], '20');
        expect(httpParams['offset'], '40');
      });

      test(
        'should handle complex query with filters, sorts, and pagination',
        () {
          final queryParams = QueryParams(
            filters: [statusField.equals('active'), priorityField.lessThan(10)],
            sorts: [const SortCondition.descending(updatedAtField)],
            pagination: const PaginationParams(limit: 15, offset: 30),
          );

          final httpParams = apiAdapter.queryParamsToHttpParams(queryParams);

          expect(httpParams['filter[status][equals]'], 'active');
          expect(httpParams['filter[priority][lessThan]'], '10');
          expect(httpParams['sort'], 'updatedAt:desc');
          expect(httpParams['limit'], '15');
          expect(httpParams['offset'], '30');
        },
      );

      test('should handle special characters in filter values', () {
        final queryParams = QueryParams(
          filters: [
            descriptionField.equals('Test with spaces & symbols'),
            titleField.contains('Special/chars'),
          ],
        );

        final httpParams = apiAdapter.queryParamsToHttpParams(queryParams);

        expect(
          httpParams['filter[description][equals]'],
          'Test with spaces & symbols',
        );
        expect(httpParams['filter[title][contains]'], 'Special/chars');
      });

      test('should handle all filter operators', () {
        final queryParams = QueryParams(
          filters: [
            field1.equals('value1'),
            field2.notEquals('value2'),
            field3.greaterThan(100),
            field4.greaterThanOrEqual(50),
            field5.lessThan(200),
            field6.lessThanOrEqual(150),
            field7.contains('substring'),
            field8.startsWith('prefix'),
            field9.endsWith('suffix'),
            field10.contains('a,b,c'),
            field11.contains('x,y'),
            field12.isNull(),
            field13.isNotNull(),
          ],
        );

        final httpParams = apiAdapter.queryParamsToHttpParams(queryParams);

        expect(httpParams['filter[field1][equals]'], 'value1');
        expect(httpParams['filter[field2][notEquals]'], 'value2');
        expect(httpParams['filter[field3][greaterThan]'], '100');
        expect(httpParams['filter[field4][greaterThanOrEqual]'], '50');
        expect(httpParams['filter[field5][lessThan]'], '200');
        expect(httpParams['filter[field6][lessThanOrEqual]'], '150');
        expect(httpParams['filter[field7][contains]'], 'substring');
        expect(httpParams['filter[field8][startsWith]'], 'prefix');
        expect(httpParams['filter[field9][endsWith]'], 'suffix');
        expect(httpParams['filter[field10][contains]'], 'a,b,c');
        expect(httpParams['filter[field11][contains]'], 'x,y');
        expect(httpParams['filter[field12][isNull]'], '');
        expect(httpParams['filter[field13][isNotNull]'], '');
      });

      test('should handle DateTime values', () {
        final dateTime = DateTime(2024, 1, 15, 10, 30, 0);
        final queryParams = QueryParams(
          filters: [createdAtField.greaterThan(dateTime)],
        );

        final httpParams = apiAdapter.queryParamsToHttpParams(queryParams);

        expect(
          httpParams['filter[createdAt][greaterThan]'],
          dateTime.toIso8601String(),
        );
      });

      test('should handle bool values', () {
        final queryParams = QueryParams(
          filters: [isActiveField.equals(true), isDeletedField.equals(false)],
        );

        final httpParams = apiAdapter.queryParamsToHttpParams(queryParams);

        expect(httpParams['filter[isActive][equals]'], 'true');
        expect(httpParams['filter[isDeleted][equals]'], 'false');
      });

      test('should handle edge cases', () {
        final queryParams = QueryParams(
          filters: [
            field1.equals(''),
            field2.equals('value'),
            field10.contains(''),
          ],
        );

        final httpParams = apiAdapter.queryParamsToHttpParams(queryParams);

        expect(httpParams['filter[field1][equals]'], '');
        expect(httpParams['filter[field2][equals]'], 'value');
        expect(httpParams['filter[field10][contains]'], '');
      });

      test('should return empty map for empty query params', () {
        const queryParams = QueryParams();

        final httpParams = apiAdapter.queryParamsToHttpParams(queryParams);

        expect(httpParams.isEmpty, true);
      });
    });
  });
}
