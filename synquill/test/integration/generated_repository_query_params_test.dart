import 'package:test/test.dart';

import 'package:synquill/synquill.generated.dart';

import 'package:synquill/src/test_models/index.dart';

void main() {
  group('Generated Repository TypedQueryParams Integration Tests', () {
    late SynquillDatabase db;
    late PlainModelRepository repository;

    setUp(() async {
      db = SynquillDatabase(NativeDatabase.memory());
      repository = PlainModelRepository(db);

      await SynquillStorage.init(
        database: db,
        config: const SynquillStorageConfig(
          defaultSavePolicy: DataSavePolicy.localFirst,
          defaultLoadPolicy: DataLoadPolicy.localOnly,
          foregroundQueueConcurrency: 1,
          backgroundQueueConcurrency: 1,
        ),
        logger: Logger('TestSyncedStorage'),
        initializeFn: initializeSynquillStorage,
        enableInternetMonitoring: false, // Disable for testing
      );

      // Insert test data
      await _insertTestData(repository);
    });

    tearDown(() async {
      await SynquillStorage.close();
    });

    test('should filter PlainModel by name with TypedQueryParams', () async {
      final queryParams = QueryParams(
        filters: [PlainModelFields.name.contains('Test')],
      );

      final results = await repository.findAll(queryParams: queryParams);

      expect(results, hasLength(5)); // 5 models with "Test" in name
      expect(results.every((item) => item.name.contains('Test')), isTrue);
    });

    test('should filter by identical name and get 10 results', () async {
      final queryParams = QueryParams(
        filters: [PlainModelFields.name.equals('Duplicate Name')],
      );

      final results = await repository.findAll(queryParams: queryParams);

      expect(results, hasLength(10)); // All 10 models with "Duplicate Name"
      expect(results.every((item) => item.name == 'Duplicate Name'), isTrue);
    });

    test('should filter by name AND value and get 3 results', () async {
      final queryParams = QueryParams(
        filters: [
          PlainModelFields.name.equals('Duplicate Name'),
          PlainModelFields.value.equals(300),
        ],
      );

      final results = await repository.findAll(queryParams: queryParams);

      expect(results, hasLength(3)); // 3 models: "Duplicate Name" AND value=300
      expect(
        results.every(
          (item) => item.name == 'Duplicate Name' && item.value == 300,
        ),
        isTrue,
      );
    });

    test('should filter with range queries and complex conditions', () async {
      final queryParams = QueryParams(
        filters: [
          PlainModelFields.value.greaterThanOrEqual(100),
          PlainModelFields.value.lessThanOrEqual(500),
          PlainModelFields.name.contains('Product'),
        ],
      );

      final results = await repository.findAll(queryParams: queryParams);

      expect(results, hasLength(4)); // Products B, C, D, E in range
      expect(
        results.every(
          (item) =>
              item.value >= 100 &&
              item.value <= 500 &&
              item.name.contains('Product'),
        ),
        isTrue,
      );
    });

    test(
      'should sort PlainModel by value descending with TypedQueryParams',
      () async {
        final queryParams = QueryParams(
          filters: [PlainModelFields.name.equals('Duplicate Name')],
          sorts: [
            const SortCondition(
              field: PlainModelFields.value,
              direction: SortDirection.descending,
            ),
          ],
        );

        final results = await repository.findAll(queryParams: queryParams);

        expect(results, hasLength(10));
        expect(results[0].value, equals(800)); // Highest value first
        expect(results[1].value, equals(700));
        expect(results[2].value, equals(600));
        expect(results[9].value, equals(100)); // Lowest value last
      },
    );

    test('should sort by multiple fields', () async {
      const queryParams = QueryParams(
        sorts: [
          SortCondition(
            field: PlainModelFields.name,
            direction: SortDirection.ascending,
          ),
          SortCondition(
            field: PlainModelFields.value,
            direction: SortDirection.descending,
          ),
        ],
      );

      final results = await repository.findAll(queryParams: queryParams);

      expect(results, hasLength(20)); // All 20 models
      expect(results[0].name, equals('Duplicate Name')); // Alphabetically first
      expect(results[0].value, equals(800)); // Highest value for that name
    });

    test('should handle complex pagination with filtering', () async {
      final queryParams = QueryParams(
        filters: [PlainModelFields.name.equals('Duplicate Name')],
        pagination: const PaginationParams(limit: 5, offset: 2),
      );

      final results = await repository.findAll(queryParams: queryParams);

      expect(results, hasLength(5)); // Limited to 5 items
      // With 10 "Duplicate Name" items, skip first 2, get next 5
    });

    test(
      'should combine filter, sort, and pagination with TypedQueryParams',
      () async {
        final queryParams = QueryParams(
          filters: [PlainModelFields.value.greaterThan(200)],
          sorts: [
            const SortCondition(
              field: PlainModelFields.value,
              direction: SortDirection.ascending,
            ),
          ],
          pagination: const PaginationParams(limit: 3, offset: 1),
        );

        final results = await repository.findAll(queryParams: queryParams);

        expect(results, hasLength(3)); // Limited to 3 items
        // Should be sorted by value ascending, skipping the first
        expect(results[0].value, greaterThan(200));
        expect(results[1].value, greaterThanOrEqualTo(results[0].value));
        expect(results[2].value, greaterThanOrEqualTo(results[1].value));
      },
    );

    test('should handle edge cases with special values', () async {
      final queryParams = QueryParams(
        filters: [PlainModelFields.name.startsWith('Product')],
      );

      final results = await repository.findAll(queryParams: queryParams);

      expect(results, hasLength(5)); // Product A, B, C, D, E
      expect(results.every((item) => item.name.startsWith('Product')), isTrue);
    });

    test('should watch PlainModel with TypedQueryParams', () async {
      final queryParams = QueryParams(
        filters: [PlainModelFields.name.contains('Test')],
      );

      final stream = repository.watchAll(queryParams: queryParams);
      final results = await stream.first;

      expect(results, hasLength(5)); // 5 models with "Test" in name
      expect(results.every((item) => item.name.contains('Test')), isTrue);
    });

    test('should create TypedFilterCondition via extension methods', () {
      // Test different filter condition types
      final condition = PlainModelFields.name.equals('Test Value');
      expect(condition.field, equals(PlainModelFields.name));
      expect(condition.operator, equals(FilterOperator.equals));

      final condition2 = PlainModelFields.value.notEquals(100);
      expect(condition2.field, equals(PlainModelFields.value));
      expect(condition2.operator, equals(FilterOperator.notEquals));

      final gteCondition = PlainModelFields.value.greaterThanOrEqual(50);
      expect(gteCondition.field, equals(PlainModelFields.value));
      expect(gteCondition.operator, equals(FilterOperator.greaterThanOrEqual));

      final ltCondition = PlainModelFields.value.lessThan(1000);
      expect(ltCondition.field, equals(PlainModelFields.value));
      expect(ltCondition.operator, equals(FilterOperator.lessThan));

      final lteCondition = PlainModelFields.value.lessThanOrEqual(500);
      expect(lteCondition.field, equals(PlainModelFields.value));
      expect(lteCondition.operator, equals(FilterOperator.lessThanOrEqual));

      final containsCondition = PlainModelFields.name.contains('Model');
      expect(containsCondition.field, equals(PlainModelFields.name));
      expect(containsCondition.operator, equals(FilterOperator.contains));

      final startsWithCondition = PlainModelFields.name.startsWith('Test');
      expect(startsWithCondition.field, equals(PlainModelFields.name));
      expect(startsWithCondition.operator, equals(FilterOperator.startsWith));

      final endsWithCondition = PlainModelFields.name.endsWith('Model');
      expect(endsWithCondition.field, equals(PlainModelFields.name));
      expect(endsWithCondition.operator, equals(FilterOperator.endsWith));

      final inListCondition = PlainModelFields.value.inList([100, 200, 300]);
      expect(inListCondition.field, equals(PlainModelFields.value));
      expect(inListCondition.operator, equals(FilterOperator.inList));

      final isNullCondition = PlainModelFields.lastSyncedAt.isNull();
      expect(isNullCondition.field, equals(PlainModelFields.lastSyncedAt));
      expect(isNullCondition.operator, equals(FilterOperator.isNull));

      final isNotNullCondition = PlainModelFields.lastSyncedAt.isNotNull();
      expect(isNotNullCondition.field, equals(PlainModelFields.lastSyncedAt));
      expect(isNotNullCondition.operator, equals(FilterOperator.isNotNull));
    });

    test('should create similar conditions with different approaches', () {
      // Pattern 1: Using extension method
      final condition1 = PlainModelFields.name.contains('Test');

      // Pattern 2: Using same static factory method
      final condition2 = PlainModelFields.name.contains('Test');

      expect(condition1, equals(condition2));

      // Type safety test: this should be detected by the type system
      final nullCondition = PlainModelFields.lastSyncedAt.isNull();
      expect(nullCondition.field.fieldType, equals(DateTime));

      final intCondition = PlainModelFields.value.greaterThan(42);
      expect(intCondition.field.fieldType, equals(int));
    });

    test('should create TypedSortCondition with constructor', () {
      const typedCondition = SortCondition.descending(PlainModelFields.value);

      expect(typedCondition.field, equals(PlainModelFields.value));
      expect(typedCondition.direction, equals(SortDirection.descending));
    });

    test('should handle edge case with list filtering', () async {
      final queryParams = QueryParams(
        filters: [
          PlainModelFields.value.inList([100, 300, 500]),
        ],
      );

      final results = await repository.findAll(queryParams: queryParams);

      expect(results, hasLength(8)); // Models with values 100, 300, 500
      expect(
        results.every((item) => [100, 300, 500].contains(item.value)),
        isTrue,
      );
    });
  });
}

/// Helper function to insert test data
Future<void> _insertTestData(PlainModelRepository repository) async {
  final models = <PlainModel>[
    // 5 models with "Test" in the name
    PlainModel(id: '1', name: 'Test Model A', value: 100),
    PlainModel(id: '2', name: 'Test Model B', value: 200),
    PlainModel(id: '3', name: 'Test Model C', value: 300),
    PlainModel(id: '4', name: 'Test Model D', value: 400),
    PlainModel(id: '5', name: 'Test Model E', value: 500),

    // 5 models with "Product" in the name
    PlainModel(id: '6', name: 'Product A', value: 150),
    PlainModel(id: '7', name: 'Product B', value: 250),
    PlainModel(id: '8', name: 'Product C', value: 350),
    PlainModel(id: '9', name: 'Product D', value: 450),
    PlainModel(id: '10', name: 'Product E', value: 550),

    // 10 models with identical names "Duplicate Name"
    PlainModel(id: '11', name: 'Duplicate Name', value: 100),
    PlainModel(id: '12', name: 'Duplicate Name', value: 200),
    PlainModel(id: '13', name: 'Duplicate Name', value: 300),
    PlainModel(id: '14', name: 'Duplicate Name', value: 300),
    PlainModel(id: '15', name: 'Duplicate Name', value: 300),
    PlainModel(id: '16', name: 'Duplicate Name', value: 400),
    PlainModel(id: '17', name: 'Duplicate Name', value: 500),
    PlainModel(id: '18', name: 'Duplicate Name', value: 600),
    PlainModel(id: '19', name: 'Duplicate Name', value: 700),
    PlainModel(id: '20', name: 'Duplicate Name', value: 800),
  ];

  for (final model in models) {
    await repository.save(model, savePolicy: DataSavePolicy.localFirst);
  }
}
