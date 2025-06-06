# API Adapter Customization

This guide covers how to customize API adapters for different REST API patterns, HTTP methods, headers, authentication, and response parsing.

## Table of Contents

- [HTTP Methods and URLs](#http-methods-and-urls)
- [Custom Headers and Authentication](#custom-headers-and-authentication)
- [Response Parsing](#response-parsing)

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
