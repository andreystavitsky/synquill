# API Adapter Customization

This guide covers how to customize API adapters for different REST API patterns, HTTP methods, headers, authentication, and response parsing.

## Table of Contents

- [HTTP Methods and URLs](#http-methods-and-urls)
- [Custom Headers and Authentication](#custom-headers-and-authentication)
- [Response Parsing](#response-parsing)
- [HTTP Status Code Handling](#http-status-code-handling)
- [Example: Overriding findAll for Full Synchronization](#example-overriding-findall-for-full-synchronization)

## HTTP Methods and URLs

```dart
mixin CustomApiAdapter on BasicApiAdapter<MyModel> {
  @override
  String methodForCreate({Map<String, dynamic>? extra}) => 'POST';
  
  @override
  String methodForUpdate({Map<String, dynamic>? extra}) => 'PATCH';
  
  @override
  String methodForDelete({Map<String, dynamic>? extra}) => 'DELETE';

  @override
  FutureOr<Uri> urlForCreate({Map<String, dynamic>? extra}) async {
    return baseUrl.resolve('api/v2/models');
  }

  // Other methods for defining URLs and HTTP methods can also be overridden.

  @override
  FutureOr<Uri> urlForUpdate(String id, {Map<String, dynamic>? extra}) async {
    return baseUrl.resolve('api/v2/models/$id');
  }
}
```

## Custom Headers and Authentication

```dart
mixin AuthenticatedAdapter on BasicApiAdapter {
  @override
  FutureOr<Map<String, String>> get baseHeaders async {
    final token = await getAuthToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'X-API-Version': '2.0',
    };
  }
}
```

## Response Parsing

```dart
mixin CustomResponseAdapter on BasicApiAdapter<MyModel> {
  @override
  MyModel? parseFindOneResponse(dynamic responseData, Response response) {
    if (responseData is Map<String, dynamic>) {
      // Handle wrapped responses
      final data = responseData['data'] ?? responseData;
      return fromJson(data);
    }
    return super.parseFindOneResponse(responseData, response);
  }

  @override
  List<MyModel> parseFindAllResponse(dynamic responseData, Response response) {
    if (responseData is Map<String, dynamic>) {
      // Handle paginated responses
      final items = responseData['items'] as List<dynamic>? ?? [];
      return items.map((item) => fromJson(item)).toList();
    }
    return super.parseFindAllResponse(responseData, response);
  }
}
```

## HTTP Status Code Handling

Synquill automatically handles certain HTTP status codes to maintain data consistency:

### HTTP 410 Gone Status

When your API returns an HTTP 410 Gone status for a specific resource, Synquill automatically removes the corresponding item from the local database:

```dart
// Example API response handling:
// GET /api/todos/123 returns 410 Gone
// → Synquill automatically deletes todo with ID '123' from local database

mixin TodoApiAdapter on BasicApiAdapter<Todo> {
  // No special handling needed - automatic 410 processing is built-in
  
  @override
  FutureOr<Uri> urlForFindOne(String id, {Map<String, dynamic>? extra}) async {
    return baseUrl.resolve('api/v1/$pluralType$/$id');
  }
}
```

This ensures that resources deleted on the server are properly cleaned up locally, maintaining consistency between remote and local data stores.

### Custom Status Code Handling

You can customize how other HTTP status codes are handled by overriding error handling methods:

```dart
mixin CustomErrorHandlingAdapter on BasicApiAdapter<MyModel> {
  @override
  Future<MyModel?> findOne(String id, {
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    try {
      return await super.findOne(id, extra: extra, headers: headers);
    } on ApiException catch (e) {
      // Custom handling for specific status codes
      switch (e.statusCode) {
        case 404:
          // Handle not found - return null instead of throwing
          return null;
        case 403:
          // Handle forbidden access
          throw UnauthorizedException('Access denied to resource $id');
        default:
          rethrow;
      }
    }
  }
}
```

## Example: Overriding findAll for Full Synchronization

```dart
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:synquill/synquill.dart';

class BasicLoadAllApiAdapter extends BasicApiAdapter<TModel> {
  /// Maximum batch size for data loading
  static const int maxBatchSize = 1000;

  @override
  Uri get baseUrl => Uri.parse('https://api.example.com/v1/');

  /// This adapter assumes the API provides the total count in the X-TOTAL-COUNT header.
  /// Override findAll for full synchronization with x-total-count
  @override
  Future<List<TModel>> findAll({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {

    final mergedHeaders = await mergeHeaders(headers, extra: extra);
    final baseHttpParams = queryParamsToHttpParams(queryParams);
    
    // Add limit=1 to save traffic when getting the count
    final countHttpParams = {
      ...baseHttpParams,
      'limit': '1',
      'offset': '0',
    };
    
    final uri = await urlForFindAll(extra: extra);
    final firstResponse = await executeRequest<dynamic>(
      method: methodForFind(extra: extra),
      uri: uri,
      headers: mergedHeaders,
      queryParameters: countHttpParams.isNotEmpty ? countHttpParams : null,
      extra: extra,
    );

    final totalCount = _extractTotalCountFromHeaders(firstResponse.headers);

    // If the total count is 0, return an empty list
    if (totalCount == 0) {
      return [];
    }

    // Load all data from the API
    final allItems = await _loadAllItemsFromApi(
      totalCount: totalCount,
      baseHttpParams: baseHttpParams,
      headers: mergedHeaders,
      extra: extra,
    );

    // Return the data loaded from the API
    return allItems;
  }

  /// Extracts the x-total-count value from response headers
  int _extractTotalCountFromHeaders(Headers headers) {
    final totalCountHeader = headers.value('x-total-count');
    if (totalCountHeader == null) {
      throw ApiException(
        'API response missing required x-total-count header',
        statusCode: null,
      );
    }

    final totalCount = int.tryParse(totalCountHeader);
    if (totalCount == null) {
      throw ApiException(
        'Invalid x-total-count header value: $totalCountHeader',
        statusCode: null,
      );
    }

    return totalCount;
  }

  /// Loads all items from the API, using pagination if necessary
  Future<List<TModel>> _loadAllItemsFromApi({
    required int totalCount,
    required Map<String, String> baseHttpParams,
    required Map<String, String> headers,
    Map<String, dynamic>? extra,
  }) async {
    final List<TModel> allItems = [];
    final uri = await urlForFindAll(extra: extra);

    if (totalCount <= maxBatchSize) {
      // Load all in one request
      final httpParams = {
        ...baseHttpParams,
        'limit': totalCount.toString(),
        'offset': '0',
      };

      final response = await executeRequest<dynamic>(
        method: methodForFind(extra: extra),
        uri: uri,
        headers: headers,
        queryParameters: httpParams.isNotEmpty ? httpParams : null,
        extra: extra,
      );

      allItems.addAll(parseFindAllResponse(response.data, response));
    } else {
      // Load with pagination
      for (int offset = 0; offset < totalCount; offset += maxBatchSize) {
        final batchSize = min(maxBatchSize, totalCount - offset);
        final httpParams = {
          ...baseHttpParams,
          'limit': batchSize.toString(),
          'offset': offset.toString(),
        };

        final response = await executeRequest<dynamic>(
          method: methodForFind(extra: extra),
          uri: uri,
          headers: headers,
          queryParameters: httpParams.isNotEmpty ? httpParams : null,
          extra: extra,
        );

        final batchItems = parseFindAllResponse(response.data, response);
        allItems.addAll(batchItems);
      }
    }

    return allItems;
  }
}
```
