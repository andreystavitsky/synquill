import 'package:test/test.dart' hide isNull, isNotNull;
import 'package:dio/dio.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:synquill/synquill.dart';

import 'basic_api_adapter_overrides_test.mocks.dart';

// Generate mocks
@GenerateMocks([Dio])
void main() {
  group('BasicApiAdapter Override Tests', () {
    late MockDio mockDio;
    late TestModel testModel;
    late Response<dynamic> mockResponse;

    setUp(() {
      mockDio = MockDio();
      testModel = TestModel(id: '123', name: 'Test Model', value: 42);
      
      // Configure SynquillStorage to use our mock Dio
      SynquillStorage.setConfigForTesting(
        SynquillStorageConfig(dio: mockDio),
      );

      mockResponse = Response<dynamic>(
        data: testModel.toJson(),
        statusCode: 200,
        requestOptions: RequestOptions(path: '/test'),
        headers: Headers.fromMap({
          'content-type': ['application/json'],
          'x-total-count': ['100'],
          'x-page-count': ['10'],
          'x-current-page': ['1'],
          'etag': ['"abc123"'],
          'last-modified': ['Wed, 21 Oct 2015 07:28:00 GMT'],
          'location': ['/testmodels/123'],
          'content-length': ['456'],
        }),
      );
    });

    tearDown(() {
      // Reset SynquillStorage configuration to prevent test pollution
      SynquillStorage.setConfigForTesting(const SynquillStorageConfig());
    });

    group('executeRequest Override Tests', () {
      test(
        'should allow custom authentication in executeRequest override',
        () async {
          final adapter = CustomExecuteRequestAdapter(
            customAuthToken: 'test-token-123',
            mockDio: mockDio,
          );

          when(
            mockDio.request<dynamic>(
              any,
              data: anyNamed('data'),
              queryParameters: anyNamed('queryParameters'),
              options: anyNamed('options'),
            ),
          ).thenAnswer((_) async => mockResponse);

          await adapter.findOne('123');

          expect(adapter.overrodeExecuteRequest, isTrue);
          expect(adapter.methodCalls, contains('executeRequest'));
          expect(
            adapter.capturedData['headers']['Authorization'],
            equals('Bearer test-token-123'),
          );
          expect(
            adapter.capturedData['headers']['X-Custom-Header'],
            equals('CustomValue'),
          );
        },
      );

      test(
        'should pass through all parameters in executeRequest override',
        () async {
          final adapter = CustomExecuteRequestAdapter(
            customAuthToken: 'test-token',
            mockDio: mockDio,
          );

          when(
            mockDio.request<dynamic>(
              any,
              data: anyNamed('data'),
              queryParameters: anyNamed('queryParameters'),
              options: anyNamed('options'),
            ),
          ).thenAnswer((_) async => mockResponse);

          await adapter.createOne(testModel);

          expect(adapter.capturedData['method'], equals('POST'));
          expect(adapter.capturedData['uri'], contains('/testmodels'));
          expect(adapter.capturedData['data'], equals(testModel.toJson()));
          verify(
            mockDio.request<dynamic>(
              any,
              data: testModel.toJson(),
              queryParameters: anyNamed('queryParameters'),
              options: anyNamed('options'),
            ),
          ).called(1);
        },
      );
    });

    group('executeFindOneRequest Override Tests', () {
      test(
        'should implement caching in executeFindOneRequest override',
        () async {
          final adapter = CustomFindOneAdapter(mockDio: mockDio);

          when(
            mockDio.request<dynamic>(
              any,
              data: anyNamed('data'),
              queryParameters: anyNamed('queryParameters'),
              options: anyNamed('options'),
            ),
          ).thenAnswer((_) async => mockResponse);

          // First call - should hit the API
          final result1 = await adapter.findOne('123');
          expect(adapter.overrodeExecuteFindOneRequest, isTrue);
          expect(adapter.capturedData['cacheHit'], isFalse);
          expect(result1?.id, equals('123'));

          // Second call - should hit the cache
          adapter.capturedData.clear();
          final result2 = await adapter.findOne('123');
          expect(adapter.capturedData['cacheHit'], isTrue);
          expect(result2?.id, equals('123'));

          // Verify API was only called once
          verify(
            mockDio.request<dynamic>(
              any,
              data: anyNamed('data'),
              queryParameters: anyNamed('queryParameters'),
              options: anyNamed('options'),
            ),
          ).called(1);
        },
      );
    });

    group('executeFindAllRequest Override Tests', () {
      test(
        'should implement automatic pagination in '
        'executeFindAllRequest override',
        () async {
          final adapter = CustomFindAllAdapter(
            maxPageSize: 50,
            mockDio: mockDio,
          );

          // Mock responses for pagination
          final page1Response = Response<dynamic>(
            data: List.generate(
              50,
              (i) => {'id': '$i', 'name': 'Item $i', 'value': i},
            ),
            statusCode: 200,
            requestOptions: RequestOptions(path: '/test'),
          );

          final page2Response = Response<dynamic>(
            data: List.generate(
              30,
              (i) => {
                'id': '${i + 50}',
                'name': 'Item ${i + 50}',
                'value': i + 50,
              },
            ),
            statusCode: 200,
            requestOptions: RequestOptions(path: '/test'),
          );

          when(
            mockDio.request<dynamic>(
              any,
              data: anyNamed('data'),
              queryParameters: anyNamed('queryParameters'),
              options: anyNamed('options'),
            ),
          ).thenAnswer((invocation) async {
            final queryParams =
                invocation.namedArguments[#queryParameters]
                    as Map<String, dynamic>?;
            final offset =
                int.tryParse(queryParams?['offset']?.toString() ?? '0') ?? 0;
            return offset == 0 ? page1Response : page2Response;
          });

          final results = await adapter.findAll();

          expect(adapter.overrodeExecuteFindAllRequest, isTrue);
          expect(adapter.capturedData['totalResults'], equals(80));
          expect(adapter.capturedData['totalPages'], equals(2));
          expect(
            adapter.capturedData['paginationCall_0'],
            isA<Map<String, dynamic>>(),
          );
          expect(
            adapter.capturedData['paginationCall_50'],
            isA<Map<String, dynamic>>(),
          );
          expect(results.length, equals(80));

          // Verify two API calls were made
          verify(
            mockDio.request<dynamic>(
              any,
              data: anyNamed('data'),
              queryParameters: anyNamed('queryParameters'),
              options: anyNamed('options'),
            ),
          ).called(2);
        },
      );
    });

    group('executeCreateRequest Override Tests', () {
      test(
        'should implement validation in executeCreateRequest override',
        () async {
          final adapter = CustomCreateAdapter(
            requiredFields: ['name', 'value'],
            mockDio: mockDio,
          );

          when(
            mockDio.request<dynamic>(
              any,
              data: anyNamed('data'),
              queryParameters: anyNamed('queryParameters'),
              options: anyNamed('options'),
            ),
          ).thenAnswer((_) async => mockResponse);

          // Valid model should pass validation
          await adapter.createOne(testModel);
          expect(adapter.overrodeExecuteCreateRequest, isTrue);
          expect(adapter.capturedData['validationPassed'], isTrue);

          // Invalid model should fail validation
          // Create adapter that will modify toJson to remove required field
          final invalidAdapter = CustomCreateAdapter(
            requiredFields: ['name', 'value'],
            mockDio: mockDio,
          );
          
          // Create a special test model that will fail validation
          final invalidModel = TestModelWithMissingFields(
            id: '456',
            name: 'test',
            value: 42,
            fieldsToOmit: ['name'],
          );

          expect(
            () async => await invalidAdapter.executeCreateRequest(
              model: invalidModel,
            ),
            throwsA(isA<ValidationException>()),
          );
        },
      );
    });

    group('executeUpdateRequest Override Tests', () {
      test(
        'should implement optimistic updates in executeUpdateRequest override',
        () async {
          final adapter = CustomUpdateAdapter(mockDio: mockDio);

          when(
            mockDio.request<dynamic>(
              any,
              data: anyNamed('data'),
              queryParameters: anyNamed('queryParameters'),
              options: anyNamed('options'),
            ),
          ).thenAnswer((_) async => mockResponse);

          // Successful update
          await adapter.updateOne(testModel);
          expect(adapter.overrodeExecuteUpdateRequest, isTrue);
          expect(
            adapter.capturedData['optimisticUpdate'],
            equals(testModel.toJson()),
          );
          expect(adapter.capturedData['updateSucceeded'], isTrue);
          expect(adapter.optimisticCache.containsKey('123'), isTrue);
        },
      );

      test('should revert optimistic updates on failure', () async {
        final adapter = CustomUpdateAdapter(mockDio: mockDio);

        when(
          mockDio.request<dynamic>(
            any,
            data: anyNamed('data'),
            queryParameters: anyNamed('queryParameters'),
            options: anyNamed('options'),
          ),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/test'),
            type: DioExceptionType.badResponse,
            response: Response(
              statusCode: 500,
              requestOptions: RequestOptions(path: '/test'),
            ),
          ),
        );

        bool exceptionThrown = false;
        try {
          await adapter.updateOne(testModel);
        } catch (e) {
          exceptionThrown = true;
          expect(e, isA<ServerException>());
        }

        expect(exceptionThrown, isTrue);
        expect(adapter.capturedData['updateFailed'], isTrue);
        expect(adapter.optimisticCache.containsKey('123'), isFalse);
      });
    });

    group('executeDeleteRequest Override Tests', () {
      test(
        'should implement soft delete in executeDeleteRequest override',
        () async {
          final adapter = CustomDeleteAdapter(mockDio: mockDio);

          await adapter.deleteOne('123');
          expect(adapter.overrodeExecuteDeleteRequest, isTrue);
          expect(adapter.softDeletedIds.contains('123'), isTrue);
          expect(adapter.capturedData['softDeletedIds'], contains('123'));

          // Verify no API call was made (soft delete)
          verifyNever(
            mockDio.request<dynamic>(
              any,
              data: anyNamed('data'),
              queryParameters: anyNamed('queryParameters'),
              options: anyNamed('options'),
            ),
          );
        },
      );
    });

    group('Response Parsing Override Tests', () {
      test(
        'should extract metadata in parseFindOneResponse override',
        () async {
          final adapter = CustomParsingAdapter(mockDio: mockDio);

          when(
            mockDio.request<dynamic>(
              any,
              data: anyNamed('data'),
              queryParameters: anyNamed('queryParameters'),
              options: anyNamed('options'),
            ),
          ).thenAnswer((_) async => mockResponse);

          await adapter.findOne('123');

          expect(adapter.overrodeParseFindOneResponse, isTrue);
          expect(
            adapter.extractedMetadata['findOne']['statusCode'],
            equals(200),
          );
          expect(
            adapter.extractedMetadata['findOne']['headers'],
            isA<Map<String, List<String>>>(),
          );
          expect(
            adapter.extractedMetadata['findOne']['timestamp'],
            isA<DateTime>(),
          );
        },
      );

      test(
        'should extract pagination metadata in parseFindAllResponse override',
        () async {
          final adapter = CustomParsingAdapter(mockDio: mockDio);

          final findAllResponse = Response<dynamic>(
            data: [testModel.toJson()],
            statusCode: 200,
            requestOptions: RequestOptions(path: '/test'),
            headers: Headers.fromMap({
              'x-total-count': ['100'],
              'x-page-count': ['10'],
              'x-current-page': ['1'],
            }),
          );

          when(
            mockDio.request<dynamic>(
              any,
              data: anyNamed('data'),
              queryParameters: anyNamed('queryParameters'),
              options: anyNamed('options'),
            ),
          ).thenAnswer((_) async => findAllResponse);

          await adapter.findAll();

          expect(adapter.overrodeParseFindAllResponse, isTrue);
          expect(
            adapter.extractedMetadata['findAll']['totalCount'],
            equals('100'),
          );
          expect(
            adapter.extractedMetadata['findAll']['pageCount'],
            equals('10'),
          );
          expect(
            adapter.extractedMetadata['findAll']['currentPage'],
            equals('1'),
          );
        },
      );

      test(
        'should extract creation metadata in parseCreateResponse override',
        () async {
          final adapter = CustomParsingAdapter(mockDio: mockDio);

          when(
            mockDio.request<dynamic>(
              any,
              data: anyNamed('data'),
              queryParameters: anyNamed('queryParameters'),
              options: anyNamed('options'),
            ),
          ).thenAnswer((_) async => mockResponse);

          await adapter.createOne(testModel);

          expect(adapter.overrodeParseCreateResponse, isTrue);
          expect(
            adapter.extractedMetadata['create']['statusCode'],
            equals(200),
          );
          expect(
            adapter.extractedMetadata['create']['location'],
            equals('/testmodels/123'),
          );
        },
      );

      test(
        'should extract update metadata in parseUpdateResponse override',
        () async {
          final adapter = CustomParsingAdapter(mockDio: mockDio);

          when(
            mockDio.request<dynamic>(
              any,
              data: anyNamed('data'),
              queryParameters: anyNamed('queryParameters'),
              options: anyNamed('options'),
            ),
          ).thenAnswer((_) async => mockResponse);

          await adapter.updateOne(testModel);

          expect(adapter.overrodeParseUpdateResponse, isTrue);
          expect(
            adapter.extractedMetadata['update']['etag'],
            equals('"abc123"'),
          );
          expect(
            adapter.extractedMetadata['update']['lastModified'],
            equals('Wed, 21 Oct 2015 07:28:00 GMT'),
          );
        },
      );

      test(
        'should extract replace metadata in parseReplaceResponse override',
        () async {
          final adapter = CustomParsingAdapter(mockDio: mockDio);

          when(
            mockDio.request<dynamic>(
              any,
              data: anyNamed('data'),
              queryParameters: anyNamed('queryParameters'),
              options: anyNamed('options'),
            ),
          ).thenAnswer((_) async => mockResponse);

          await adapter.replaceOne(testModel);

          expect(adapter.overrodeParseReplaceResponse, isTrue);
          expect(
            adapter.extractedMetadata['replace']['etag'],
            equals('"abc123"'),
          );
          expect(
            adapter.extractedMetadata['replace']['contentLength'],
            equals('456'),
          );
        },
      );
    });

    group('Error Handling Override Tests', () {
      test(
        'should handle 404 errors correctly in executeFindOneRequest',
        () async {
          final adapter = TestBasicApiAdapter(mockDio: mockDio);

          when(
            mockDio.request<dynamic>(
              any,
              data: anyNamed('data'),
              queryParameters: anyNamed('queryParameters'),
              options: anyNamed('options'),
            ),
          ).thenThrow(
            DioException(
              requestOptions: RequestOptions(path: '/testmodels/nonexistent'),
              type: DioExceptionType.badResponse,
              response: Response(
                statusCode: 404,
                requestOptions: RequestOptions(path: '/testmodels/nonexistent'),
              ),
            ),
          );

          // 404 should return null, not throw
          final result = await adapter.findOne('nonexistent');
          expect(result, equals(null));
        },
      );

      test(
        'should handle 410 errors correctly in executeFindOneRequest',
        () async {
          final adapter = TestBasicApiAdapter(mockDio: mockDio);

          when(
            mockDio.request<dynamic>(
              any,
              data: anyNamed('data'),
              queryParameters: anyNamed('queryParameters'),
              options: anyNamed('options'),
            ),
          ).thenThrow(
            DioException(
              requestOptions: RequestOptions(path: '/testmodels/gone'),
              type: DioExceptionType.badResponse,
              response: Response(
                statusCode: 410,
                requestOptions: RequestOptions(path: '/testmodels/gone'),
              ),
            ),
          );

          // 410 should return null, not throw
          final result = await adapter.findOne('gone');
          expect(result, equals(null));
        },
      );

      test('should throw other HTTP errors normally', () async {
        final adapter = TestBasicApiAdapter(mockDio: mockDio);

        when(
          mockDio.request<dynamic>(
            any,
            data: anyNamed('data'),
            queryParameters: anyNamed('queryParameters'),
            options: anyNamed('options'),
          ),
        ).thenThrow(
          DioException(
            requestOptions: RequestOptions(path: '/testmodels/123'),
            type: DioExceptionType.badResponse,
            response: Response(
              statusCode: 500,
              requestOptions: RequestOptions(path: '/testmodels/123'),
            ),
          ),
        );

        expect(
          () async => await adapter.findOne('123'),
          throwsA(isA<ServerException>()),
        );
      });
    });

    group('Method Call Tracking Tests', () {
      test('should track all override method calls correctly', () async {
        final adapter = CustomParsingAdapter(mockDio: mockDio);

        // Set up different responses for different operations
        when(
          mockDio.request<dynamic>(
            any,
            data: anyNamed('data'),
            queryParameters: anyNamed('queryParameters'),
            options: anyNamed('options'),
          ),
        ).thenAnswer((invocation) async {
          final options = invocation.namedArguments[#options] as Options;
          final method = options.method;
          final uri = invocation.positionalArguments[0] as String;
          
          if (method == 'GET') {
            if (uri.contains('/testmodel/123')) {
              // findOne request
              return mockResponse;
            } else {
              // findAll request - return array response
              return Response<dynamic>(
                data: [testModel.toJson()],
                statusCode: 200,
                requestOptions: RequestOptions(path: '/testmodels'),
                headers: mockResponse.headers,
              );
            }
          } else {
            // POST, PUT, PATCH, DELETE requests
            return mockResponse;
          }
        });

        // Test all CRUD operations
        await adapter.findOne('123');
        await adapter.findAll();
        await adapter.createOne(testModel);
        await adapter.updateOne(testModel);
        await adapter.replaceOne(testModel);
        await adapter.deleteOne('123');

        // Verify all parsing methods were called
        expect(adapter.methodCalls, contains('parseFindOneResponse'));
        expect(adapter.methodCalls, contains('parseFindAllResponse'));
        expect(adapter.methodCalls, contains('parseCreateResponse'));
        expect(adapter.methodCalls, contains('parseUpdateResponse'));
        expect(adapter.methodCalls, contains('parseReplaceResponse'));

        // Verify all override flags are set
        expect(adapter.overrodeParseFindOneResponse, isTrue);
        expect(adapter.overrodeParseFindAllResponse, isTrue);
        expect(adapter.overrodeParseCreateResponse, isTrue);
        expect(adapter.overrodeParseUpdateResponse, isTrue);
        expect(adapter.overrodeParseReplaceResponse, isTrue);
      });
    });

    group('Integration Tests', () {
      test('should allow combining multiple overrides', () async {
        // Custom adapter that combines multiple overrides
        final combinedAdapter = _CombinedOverrideAdapter(mockDio: mockDio);

        when(
          mockDio.request<dynamic>(
            any,
            data: anyNamed('data'),
            queryParameters: anyNamed('queryParameters'),
            options: anyNamed('options'),
          ),
        ).thenAnswer((_) async => mockResponse);

        await combinedAdapter.findOne('123');

        expect(combinedAdapter.overrideTracker['executeRequest'], isTrue);
        expect(
          combinedAdapter.overrideTracker['executeFindOneRequest'],
          isTrue,
        );
        expect(combinedAdapter.overrideTracker['parseFindOneResponse'], isTrue);
        expect(
          combinedAdapter.requestHeaders['Authorization'],
          equals('Bearer combined-token'),
        );
        expect(combinedAdapter.extractedMetadata, isNotEmpty);
      });
    });
  });
}

/// Test model for BasicApiAdapter override testing
class TestModel extends SynquillDataModel<TestModel> {
  @override
  final String id;
  final String name;
  final int value;

  TestModel({required this.id, required this.name, required this.value});

  TestModel copyWith({String? id, String? name, int? value}) {
    return TestModel(
      id: id ?? this.id,
      name: name ?? this.name,
      value: value ?? this.value,
    );
  }

  @override
  TestModel fromJson(Map<String, dynamic> json) {
    return TestModel(
      id: json['id'] as String,
      name: json['name'] as String,
      value: json['value'] as int,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'value': value};
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TestModel &&
        other.id == id &&
        other.name == name &&
        other.value == value;
  }

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ value.hashCode;
}

/// Test model that can omit specific fields from JSON serialization
class TestModelWithMissingFields extends TestModel {
  final List<String> fieldsToOmit;

  TestModelWithMissingFields({
    required super.id,
    required super.name,
    required super.value,
    this.fieldsToOmit = const [],
  });

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    for (final field in fieldsToOmit) {
      json.remove(field);
    }
    return json;
  }
}

/// Test implementation of BasicApiAdapter for testing overrides
class TestBasicApiAdapter extends BasicApiAdapter<TestModel> {
  final MockDio? mockDio;
  final List<String> methodCalls = [];
  final Map<String, dynamic> capturedData = {};

  // Override tracking
  bool overrodeExecuteRequest = false;
  bool overrodeExecuteFindOneRequest = false;
  bool overrodeExecuteFindAllRequest = false;
  bool overrodeExecuteCreateRequest = false;
  bool overrodeExecuteUpdateRequest = false;
  bool overrodeExecuteReplaceRequest = false;
  bool overrodeExecuteDeleteRequest = false;
  bool overrodeParseFindOneResponse = false;
  bool overrodeParseFindAllResponse = false;
  bool overrodeParseCreateResponse = false;
  bool overrodeParseUpdateResponse = false;
  bool overrodeParseReplaceResponse = false;

  TestBasicApiAdapter({this.mockDio});

  @override
  Uri get baseUrl => Uri.parse('https://api.test.com/v1/');

  @override
  String get type => 'testmodel';

  @override
  String get pluralType => 'testmodels';

  @override
  TestModel fromJson(Map<String, dynamic> json) {
    return TestModel(
      id: json['id'] as String,
      name: json['name'] as String,
      value: json['value'] as int,
    );
  }

  @override
  Map<String, dynamic> toJson(TestModel model) {
    return model.toJson();
  }
}

/// Custom adapter that overrides executeRequest method
class CustomExecuteRequestAdapter extends TestBasicApiAdapter {
  final String customAuthToken;

  CustomExecuteRequestAdapter({required this.customAuthToken, MockDio? mockDio})
    : super(mockDio: mockDio);

  @override
  Future<Response<T>> executeRequest<T>({
    required String method,
    required Uri uri,
    Object? data,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? extra,
  }) async {
    overrodeExecuteRequest = true;
    methodCalls.add('executeRequest');

    // Add custom authentication header
    final customHeaders = <String, String>{
      ...?headers,
      'Authorization': 'Bearer $customAuthToken',
      'X-Custom-Header': 'CustomValue',
    };

    capturedData['method'] = method;
    capturedData['uri'] = uri.toString();
    capturedData['headers'] = customHeaders;
    capturedData['data'] = data;
    capturedData['queryParameters'] = queryParameters;

    return super.executeRequest<T>(
      method: method,
      uri: uri,
      data: data,
      headers: customHeaders,
      queryParameters: queryParameters,
      extra: extra,
    );
  }
}

/// Custom adapter that overrides findOne request with caching
class CustomFindOneAdapter extends TestBasicApiAdapter {
  final Map<String, TestModel> cache = {};

  CustomFindOneAdapter({MockDio? mockDio}) : super(mockDio: mockDio);

  @override
  Future<TestModel?> executeFindOneRequest({
    required String id,
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    overrodeExecuteFindOneRequest = true;
    methodCalls.add('executeFindOneRequest');

    // Check cache first
    if (cache.containsKey(id)) {
      capturedData['cacheHit'] = true;
      return cache[id];
    }

    capturedData['cacheHit'] = false;
    final result = await super.executeFindOneRequest(
      id: id,
      headers: headers,
      queryParams: queryParams,
      extra: extra,
    );

    // Cache the result
    if (result != null) {
      cache[id] = result;
    }

    return result;
  }
}

/// Custom adapter that overrides findAll with automatic pagination
class CustomFindAllAdapter extends TestBasicApiAdapter {
  final int maxPageSize;

  CustomFindAllAdapter({required this.maxPageSize, MockDio? mockDio})
    : super(mockDio: mockDio);

  @override
  Future<List<TestModel>> executeFindAllRequest({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    overrodeExecuteFindAllRequest = true;
    methodCalls.add('executeFindAllRequest');

    // Implement automatic pagination
    final results = <TestModel>[];
    int offset = 0;
    bool hasMore = true;

    while (hasMore) {
      final paginatedParams = QueryParams(
        filters: queryParams?.filters ?? [],
        sorts: queryParams?.sorts ?? [],
        pagination: PaginationParams(limit: maxPageSize, offset: offset),
      );

      capturedData['paginationCall_$offset'] = {
        'limit': maxPageSize,
        'offset': offset,
      };

      final pageResults = await super.executeFindAllRequest(
        headers: headers,
        queryParams: paginatedParams,
        extra: extra,
      );

      results.addAll(pageResults);
      hasMore = pageResults.length == maxPageSize;
      offset += maxPageSize;
    }

    capturedData['totalResults'] = results.length;
    capturedData['totalPages'] = (offset / maxPageSize).ceil();

    return results;
  }
}

/// Custom adapter that overrides create with validation
class CustomCreateAdapter extends TestBasicApiAdapter {
  final List<String> requiredFields;

  CustomCreateAdapter({required this.requiredFields, MockDio? mockDio})
    : super(mockDio: mockDio);

  @override
  Future<TestModel?> executeCreateRequest({
    required TestModel model,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    overrodeExecuteCreateRequest = true;
    methodCalls.add('executeCreateRequest');

    // Custom validation
    final modelJson = toJson(model);
    final missingFields =
        requiredFields
            .where(
              (field) =>
                  !modelJson.containsKey(field) || modelJson[field] == null,
            )
            .toList();

    if (missingFields.isNotEmpty) {
      capturedData['validationErrors'] = missingFields;
      throw ValidationException('Missing required fields', {
        for (final field in missingFields) field: ['This field is required'],
      }, null);
    }

    capturedData['validationPassed'] = true;
    return super.executeCreateRequest(
      model: model,
      headers: headers,
      extra: extra,
    );
  }
}

/// Custom adapter that overrides update with optimistic updates
class CustomUpdateAdapter extends TestBasicApiAdapter {
  final Map<String, TestModel> optimisticCache = {};

  CustomUpdateAdapter({MockDio? mockDio}) : super(mockDio: mockDio);

  @override
  Future<TestModel?> executeUpdateRequest({
    required TestModel model,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    overrodeExecuteUpdateRequest = true;
    methodCalls.add('executeUpdateRequest');

    // Store optimistic update
    optimisticCache[model.id] = model;
    capturedData['optimisticUpdate'] = model.toJson();

    try {
      final result = await super.executeUpdateRequest(
        model: model,
        headers: headers,
        extra: extra,
      );

      // Update succeeded, keep the result
      if (result != null) {
        optimisticCache[model.id] = result;
      }

      capturedData['updateSucceeded'] = true;
      return result;
    } catch (e) {
      // Update failed, revert optimistic change
      optimisticCache.remove(model.id);
      capturedData['updateFailed'] = true;
      capturedData['updateError'] = e.toString();
      rethrow;
    }
  }
}

/// Custom adapter that overrides delete with soft delete
class CustomDeleteAdapter extends TestBasicApiAdapter {
  final Set<String> softDeletedIds = {};

  CustomDeleteAdapter({MockDio? mockDio}) : super(mockDio: mockDio);

  @override
  Future<void> executeDeleteRequest({
    required String id,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    overrodeExecuteDeleteRequest = true;
    methodCalls.add('executeDeleteRequest');

    // Implement soft delete
    softDeletedIds.add(id);
    capturedData['softDeletedIds'] = softDeletedIds.toList();

    // Don't call super - this is a soft delete, no API call needed
    // In real implementation, you might update a 'deleted' flag instead
  }
}

/// Custom adapter that overrides response parsing with metadata extraction
class CustomParsingAdapter extends TestBasicApiAdapter {
  final Map<String, dynamic> extractedMetadata = {};

  CustomParsingAdapter({MockDio? mockDio}) : super(mockDio: mockDio);

  @override
  TestModel? parseFindOneResponse(dynamic responseData, Response response) {
    overrodeParseFindOneResponse = true;
    methodCalls.add('parseFindOneResponse');

    // Extract metadata from response headers
    extractedMetadata['findOne'] = {
      'statusCode': response.statusCode,
      'headers': response.headers.map,
      'timestamp': DateTime.now(),
    };

    return super.parseFindOneResponse(responseData, response);
  }

  @override
  List<TestModel> parseFindAllResponse(
    dynamic responseData,
    Response response,
  ) {
    overrodeParseFindAllResponse = true;
    methodCalls.add('parseFindAllResponse');

    // Extract pagination metadata from headers
    final headers = response.headers;
    extractedMetadata['findAll'] = {
      'statusCode': response.statusCode,
      'totalCount': headers.value('x-total-count'),
      'pageCount': headers.value('x-page-count'),
      'currentPage': headers.value('x-current-page'),
      'timestamp': DateTime.now().toIso8601String(),
    };

    return super.parseFindAllResponse(responseData, response);
  }

  @override
  TestModel? parseCreateResponse(dynamic responseData, Response response) {
    overrodeParseCreateResponse = true;
    methodCalls.add('parseCreateResponse');

    // Extract creation metadata
    extractedMetadata['create'] = {
      'statusCode': response.statusCode,
      'location': response.headers.value('location'),
      'timestamp': DateTime.now().toIso8601String(),
    };

    return super.parseCreateResponse(responseData, response);
  }

  @override
  TestModel? parseUpdateResponse(dynamic responseData, Response response) {
    overrodeParseUpdateResponse = true;
    methodCalls.add('parseUpdateResponse');

    // Extract update metadata
    extractedMetadata['update'] = {
      'statusCode': response.statusCode,
      'etag': response.headers.value('etag'),
      'lastModified': response.headers.value('last-modified'),
      'timestamp': DateTime.now().toIso8601String(),
    };

    return super.parseUpdateResponse(responseData, response);
  }

  @override
  TestModel? parseReplaceResponse(dynamic responseData, Response response) {
    overrodeParseReplaceResponse = true;
    methodCalls.add('parseReplaceResponse');

    // Extract replace metadata
    extractedMetadata['replace'] = {
      'statusCode': response.statusCode,
      'etag': response.headers.value('etag'),
      'contentLength': response.headers.value('content-length'),
      'timestamp': DateTime.now().toIso8601String(),
    };

    return super.parseReplaceResponse(responseData, response);
  }
}

/// Test adapter that combines multiple overrides
class _CombinedOverrideAdapter extends TestBasicApiAdapter {
  final Map<String, bool> overrideTracker = {};
  final Map<String, String> requestHeaders = {};
  final Map<String, dynamic> extractedMetadata = {};

  _CombinedOverrideAdapter({MockDio? mockDio}) : super(mockDio: mockDio);

  @override
  Future<Response<T>> executeRequest<T>({
    required String method,
    required Uri uri,
    Object? data,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? extra,
  }) async {
    overrideTracker['executeRequest'] = true;

    final customHeaders = <String, String>{
      ...?headers,
      'Authorization': 'Bearer combined-token',
    };

    requestHeaders.addAll(customHeaders);

    return super.executeRequest<T>(
      method: method,
      uri: uri,
      data: data,
      headers: customHeaders,
      queryParameters: queryParameters,
      extra: extra,
    );
  }

  @override
  Future<TestModel?> executeFindOneRequest({
    required String id,
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    overrideTracker['executeFindOneRequest'] = true;

    return super.executeFindOneRequest(
      id: id,
      headers: headers,
      queryParams: queryParams,
      extra: extra,
    );
  }

  @override
  TestModel? parseFindOneResponse(dynamic responseData, Response response) {
    overrideTracker['parseFindOneResponse'] = true;

    extractedMetadata['statusCode'] = response.statusCode;
    extractedMetadata['headers'] = response.headers.map;

    return super.parseFindOneResponse(responseData, response);
  }
}
