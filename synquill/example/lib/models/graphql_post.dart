import 'package:json_annotation/json_annotation.dart';
import 'package:synquill_graphql/synquill_graphql.dart';
import 'index.dart';

part 'graphql_post.g.dart';

/// GraphQL placeholder post adapter.
mixin GraphqlPostApiAdapter on GraphQLApiAdapter<GraphqlPost> {
  @override
  Uri get graphqlEndpoint =>
      Uri.parse('https://graphqlplaceholder.vercel.app/graphql');

  @override
  Logger get logger => Logger('GraphqlPostApiAdapter');

  @override
  String get findOneQuery => r'''
    query GraphqlPost($postId: Int!) {
      posts(postId: $postId) {
        id
        title
        body
        user { id }
      }
    }
  ''';

  @override
  String get findAllQuery => r'''
    query GraphqlPosts($first: Int, $userId: Int, $postId: Int) {
      posts(first: $first, userId: $userId, postId: $postId) {
        id
        title
        body
        user { id }
      }
    }
  ''';

  @override
  String get createMutation => r'''
    mutation CreateGraphqlPost($input: CreatePostInput!) {
      createPost(post: $input) {
        id
        title
        body
        user { id }
      }
    }
  ''';

  @override
  String get updateMutation => r'''
    mutation UpdateGraphqlPost($postId: Int!, $input: UpdatePostInput!) {
      updatePost(postId: $postId, post: $input) {
        id
        title
        body
        user { id }
      }
    }
  ''';

  @override
  String get deleteMutation => r'''
    mutation DeleteGraphqlPost($postId: Int!) {
      deletePost(postId: $postId)
    }
  ''';

  @override
  String get findOneResponseField => 'posts';

  @override
  String get findAllResponseField => 'posts';

  @override
  String get createResponseField => 'createPost';

  @override
  String get updateResponseField => 'updatePost';

  @override
  String get replaceResponseField => 'updatePost';

  @override
  String get deleteResponseField => 'deletePost';

  @override
  Map<String, dynamic> queryParamsToGraphQLVariables(QueryParams? queryParams) {
    if (queryParams == null || !queryParams.hasParameters) {
      return const {};
    }

    final variables = <String, dynamic>{};
    final pagination = queryParams.pagination;
    if (pagination != null && pagination.limit != null) {
      variables['first'] = pagination.limit;
    }

    for (final filter in queryParams.filters) {
      if (filter.operator != FilterOperator.equals) continue;
      final value = filter.value;
      if (value is! SingleValue) continue;

      if (filter.field.fieldName == 'userId') {
        variables['userId'] = _toInt(value.value);
      } else if (filter.field.fieldName == 'id') {
        variables['postId'] = _toInt(value.value);
      }
    }

    return variables;
  }

  @override
  Future<GraphqlPost?> executeFindOneRequest({
    required String query,
    required String responseField,
    required String id,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final data = await executeGraphQLOperation(
      operation: query,
      variables: {'postId': _toInt(id)},
      headers: headers,
      extra: extra,
    );
    final posts = parseFindAllGraphQLResponse(data, responseField);
    return posts.isEmpty ? null : posts.first;
  }

  @override
  Future<GraphqlPost?> executeCreateRequest({
    required String mutation,
    required String responseField,
    required GraphqlPost model,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final data = await executeGraphQLOperation(
      operation: mutation,
      variables: {'input': _toGraphQLInput(model)},
      headers: headers,
      extra: extra,
    );
    return parseCreateGraphQLResponse(data, responseField);
  }

  @override
  Future<GraphqlPost?> executeUpdateRequest({
    required String mutation,
    required String responseField,
    required String id,
    required Map<String, dynamic> updateFields,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final data = await executeGraphQLOperation(
      operation: mutation,
      variables: {
        'postId': _toInt(id),
        'input': _inputFromJson(updateFields),
      },
      headers: headers,
      extra: extra,
    );
    return parseUpdateGraphQLResponse(data, responseField);
  }

  @override
  Future<GraphqlPost?> executeReplaceRequest({
    required String mutation,
    required String responseField,
    required GraphqlPost model,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) {
    return executeUpdateRequest(
      mutation: mutation,
      responseField: responseField,
      id: model.id,
      updateFields: toJson(model),
      headers: headers,
      extra: extra,
    );
  }

  @override
  Future<void> executeDeleteRequest({
    required String mutation,
    required String responseField,
    required String id,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    await executeGraphQLOperation(
      operation: mutation,
      variables: {'postId': _toInt(id)},
      headers: headers,
      extra: extra,
    );
  }

  Map<String, dynamic> _toGraphQLInput(GraphqlPost model) {
    return {
      'title': model.title,
      'body': model.body,
      'userId': model.userId,
    };
  }

  Map<String, dynamic> _inputFromJson(Map<String, dynamic> json) {
    return {
      'title': json['title'],
      'body': json['body'],
      'userId': _toInt(json['userId']),
    };
  }

  int _toInt(Object? value) {
    if (value is int) return value;
    return int.parse(value.toString());
  }
}

@JsonSerializable()
@SynquillRepository(adapters: [GraphqlPostApiAdapter])
class GraphqlPost extends SynquillDataModel<GraphqlPost> {
  @override
  @JsonKey(readValue: _readId)
  final String id;

  final String title;
  final String body;

  @JsonKey(readValue: _readUserId)
  final int userId;

  GraphqlPost({
    String? id,
    required this.title,
    required this.body,
    required this.userId,
  }) : id = id ?? generateCuid();

  GraphqlPost.fromDb({
    required this.id,
    required this.title,
    required this.body,
    required this.userId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSyncedAt,
    SyncStatus? syncStatus,
  }) {
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
    this.lastSyncedAt = lastSyncedAt;
    this.syncStatus = syncStatus ?? SyncStatus.synced;
  }

  factory GraphqlPost.fromJson(Map<String, dynamic> json) =>
      _$GraphqlPostFromJson(json);

  @override
  Map<String, dynamic> toJson() => _$GraphqlPostToJson(this);

  static Object? _readId(Map<dynamic, dynamic> json, String field) {
    final value = json[field];
    return value?.toString();
  }

  static Object? _readUserId(Map<dynamic, dynamic> json, String field) {
    final value = json[field];
    if (value is int) return value;
    if (value is String) return int.tryParse(value);

    final user = json['user'];
    if (user is Map) {
      final userId = user['id'];
      if (userId is int) return userId;
      if (userId is String) return int.tryParse(userId);
    }

    return null;
  }
}
