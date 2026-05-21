/// Utility functions to generate mock GraphQL responses for unit tests.
library mock_graphql_responses;

/// Generates a successful GraphQL response containing [data]
/// under the key [field].
Map<String, dynamic> graphqlSuccess(String field, dynamic data) {
  return {
    'data': {field: data},
  };
}

/// Generates a GraphQL response containing an error.
Map<String, dynamic> graphqlError(
  String message, {
  String? code,
  Map<String, dynamic>? extensions,
}) {
  return {
    'data': null,
    'errors': [
      {
        'message': message,
        if (code != null || extensions != null)
          'extensions': {
            if (code != null) 'code': code,
            if (extensions != null) ...extensions,
          },
      },
    ],
  };
}

/// Generates a partial GraphQL response containing both [data] and
/// an [errors] list.
Map<String, dynamic> graphqlPartialError(
  String field,
  dynamic data,
  String message, {
  String? code,
}) {
  return {
    'data': {field: data},
    'errors': [
      {
        'message': message,
        if (code != null) 'extensions': {'code': code},
      },
    ],
  };
}
