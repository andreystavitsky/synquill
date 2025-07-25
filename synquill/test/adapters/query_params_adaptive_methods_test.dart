import 'dart:async';

import 'package:synquill/src/test_models/index.dart';
import 'package:test/test.dart';
import 'package:mockito/mockito.dart';

// Simple mock for Dio
class MockDio extends Mock implements Dio {}

// Field selectors for testing - using Post model fields
const titleField = FieldSelector<String>('title', String);
const bodyField = FieldSelector<String>('body', String);

/// Smart adapter that changes URL and method based on QueryParams
class SmartPostAdapter extends BasicApiAdapter<Post> {
  final Dio? mockDio;

  SmartPostAdapter({this.mockDio});

  @override
  Dio get dio => mockDio ?? super.dio;

  @override
  Uri get baseUrl => Uri.parse('https://api.example.com/v1/');

  @override
  Post fromJson(Map<String, dynamic> json) {
    return Post.fromJson(json);
  }

  @override
  Map<String, dynamic> toJson(Post model) {
    return model.toJson();
  }

  /// Adaptive method selection based on query complexity
  @override
  String methodForFind({
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) {
    if (queryParams == null) return 'GET';

    // Use POST for text search operations (complex queries)
    final hasTextSearch = queryParams.filters.any((filter) =>
        (filter.field == titleField || filter.field == bodyField) &&
        (filter.operator == FilterOperator.contains ||
            filter.operator == FilterOperator.startsWith ||
            filter.operator == FilterOperator.endsWith));

    // Use POST for complex multi-field queries
    final hasComplexQuery = queryParams.filters.length > 3;

    return (hasTextSearch || hasComplexQuery) ? 'POST' : 'GET';
  }

  /// Adaptive URL selection based on query type
  @override
  FutureOr<Uri> urlForFindAll({
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    if (queryParams == null) {
      return baseUrl.resolve('posts');
    }

    // Use search endpoint for text search
    final hasTextSearch = queryParams.filters.any((filter) =>
        (filter.field == titleField || filter.field == bodyField) &&
        (filter.operator == FilterOperator.contains ||
            filter.operator == FilterOperator.startsWith ||
            filter.operator == FilterOperator.endsWith));

    if (hasTextSearch) {
      return baseUrl.resolve('posts/search');
    }

    // Use advanced query endpoint for complex filtering (but not text search)
    final hasComplexQuery = queryParams.filters.length > 3;
    if (hasComplexQuery) {
      return baseUrl.resolve('posts/advanced-query');
    }

    // Use standard endpoint for simple queries
    return baseUrl.resolve('posts');
  }

  /// Adaptive method and URL for single item queries
  @override
  FutureOr<Uri> urlForFindOne(
    String id, {
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    // If we have query params, treat it as a filtered search
    if (queryParams?.filters.isNotEmpty ?? false) {
      return baseUrl.resolve('posts/find-by-criteria');
    }

    // Otherwise use standard single item endpoint
    return baseUrl.resolve('posts/$id');
  }
}

void main() {
  group('QueryParams Adaptive Methods', () {
    late SmartPostAdapter adapter;

    setUp(() {
      adapter = SmartPostAdapter();
    });

    group('methodForFind adaptation', () {
      test('should use GET for simple queries', () {
        final queryParams = QueryParams(
          filters: [titleField.equals('simple')],
        );

        final method = adapter.methodForFind(queryParams: queryParams);
        expect(method, equals('GET'));
      });

      test('should use POST for text search queries', () {
        final queryParams = QueryParams(
          filters: [titleField.contains('search text')],
        );

        final method = adapter.methodForFind(queryParams: queryParams);
        expect(method, equals('POST'));
      });

      test('should use POST for complex multi-field queries', () {
        final queryParams = QueryParams(
          filters: [
            titleField.equals('title1'),
            bodyField.equals('body1'),
            titleField.notEquals('title2'),
            bodyField.notEquals('body2'),
          ],
        );

        final method = adapter.methodForFind(queryParams: queryParams);
        expect(method, equals('POST'));
      });

      test('should use GET for null queryParams', () {
        final method = adapter.methodForFind(queryParams: null);
        expect(method, equals('GET'));
      });
    });

    group('urlForFindAll adaptation', () {
      test('should use standard endpoint for simple queries', () async {
        final queryParams = QueryParams(
          filters: [titleField.equals('simple')],
        );

        final url = await adapter.urlForFindAll(queryParams: queryParams);
        expect(url.toString(), equals('https://api.example.com/v1/posts'));
      });

      test('should use search endpoint for text search queries', () async {
        final queryParams = QueryParams(
          filters: [titleField.contains('search text')],
        );

        final url = await adapter.urlForFindAll(queryParams: queryParams);
        expect(
            url.toString(), equals('https://api.example.com/v1/posts/search'));
      });

      test('should use advanced-query endpoint for complex queries', () async {
        final queryParams = QueryParams(
          filters: [
            titleField.equals('title1'),
            bodyField.equals('body1'),
            titleField.notEquals('title2'),
            bodyField.notEquals('body2'),
          ],
        );

        final url = await adapter.urlForFindAll(queryParams: queryParams);
        expect(url.toString(),
            equals('https://api.example.com/v1/posts/advanced-query'));
      });

      test('should use standard endpoint for null queryParams', () async {
        final url = await adapter.urlForFindAll(queryParams: null);
        expect(url.toString(), equals('https://api.example.com/v1/posts'));
      });
    });

    group('urlForFindOne adaptation', () {
      test('should use standard endpoint for simple ID lookup', () async {
        final url = await adapter.urlForFindOne('123', queryParams: null);
        expect(url.toString(), equals('https://api.example.com/v1/posts/123'));
      });

      test(
        'should use find-by-criteria endpoint when queryParams provided',
        () async {
          final queryParams = QueryParams(
            filters: [titleField.equals('specific title')],
          );

          final url = await adapter.urlForFindOne(
            '123',
            queryParams: queryParams,
          );
          expect(
            url.toString(),
            equals('https://api.example.com/v1/posts/find-by-criteria'),
          );
        },
      );
    });

    group('Integration tests', () {
      test('should combine method and URL adaptation correctly', () async {
        // Text search query
        final textSearchQuery = QueryParams(
          filters: [titleField.contains('search text')],
        );

        expect(
          adapter.methodForFind(queryParams: textSearchQuery),
          equals('POST'),
        );

        final textSearchUrl = await adapter.urlForFindAll(
          queryParams: textSearchQuery,
        );
        expect(
          textSearchUrl.toString(),
          equals('https://api.example.com/v1/posts/search'),
        );

        // Complex query (non-text search)
        final complexQuery = QueryParams(
          filters: [
            titleField.equals('title1'),
            bodyField.equals('body1'),
            titleField.notEquals('title2'),
            bodyField.notEquals('body2'),
          ],
        );

        expect(
          adapter.methodForFind(queryParams: complexQuery),
          equals('POST'),
        );

        final complexUrl = await adapter.urlForFindAll(
          queryParams: complexQuery,
        );
        expect(
          complexUrl.toString(),
          equals('https://api.example.com/v1/posts/advanced-query'),
        );

        // Simple query
        final simpleQuery = QueryParams(
          filters: [titleField.equals('simple title')],
        );

        expect(
          adapter.methodForFind(queryParams: simpleQuery),
          equals('GET'),
        );

        final simpleUrl = await adapter.urlForFindAll(
          queryParams: simpleQuery,
        );
        expect(
          simpleUrl.toString(),
          equals('https://api.example.com/v1/posts'),
        );
      });
    });
  });
}
