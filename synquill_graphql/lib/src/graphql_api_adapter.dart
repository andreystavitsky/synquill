import 'package:synquill/synquill.dart';
import 'package:synquill_graphql/src/mixins/graphql_error_handling_mixin.dart';
import 'package:synquill_graphql/src/mixins/graphql_execution_mixin.dart';
import 'package:synquill_graphql/src/mixins/graphql_response_parsing_mixin.dart';
import 'package:synquill_graphql/src/mixins/graphql_subscription_mixin.dart';

/// Base class for implementing GraphQL API adapters in Synquill.
abstract class GraphQLApiAdapter<TModel extends SynquillDataModel<TModel>>
    extends ApiAdapterBase<TModel>
    with
        DioClientMixin<TModel>,
        GraphQLErrorHandlingMixin<TModel>,
        GraphQLResponseParsingMixin<TModel>,
        GraphQLExecutionMixin<TModel>,
        GraphQLSubscriptionMixin<TModel>
    implements RealtimeApiAdapter<TModel> {
  /// The GraphQL endpoint URL (e.g. `https://api.example.com/graphql`).
  Uri get graphqlEndpoint;

  @override
  Uri get baseUrl => graphqlEndpoint;

  @override
  Logger get logger => Logger('GraphQLApiAdapter');

  /// The GraphQL query string for finding a single record.
  String get findOneQuery;

  /// The GraphQL query string for finding all records.
  String get findAllQuery;

  /// The GraphQL mutation string for creating a record.
  String get createMutation;

  /// The GraphQL mutation string for updating a record.
  String get updateMutation;

  /// The GraphQL mutation string for deleting a record.
  String get deleteMutation;

  /// The GraphQL mutation string for replacing a record (defaults to
  /// [updateMutation]).
  String get replaceMutation => updateMutation;

  /// Response JSON key for findOne queries.
  @override
  String get findOneResponseField => type;

  /// Response JSON key for findAll queries.
  @override
  String get findAllResponseField => pluralType;

  /// Response JSON key for createOne mutations.
  String get createResponseField => 'create${_capitalize(type)}';

  /// Response JSON key for updateOne mutations.
  String get updateResponseField => 'update${_capitalize(type)}';

  /// Response JSON key for replaceOne mutations.
  String get replaceResponseField => updateResponseField;

  /// Response JSON key for deleteOne mutations.
  String get deleteResponseField => 'delete${_capitalize(type)}';

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Disposes resources owned by this adapter.
  ///
  /// Pending GraphQL batch operations are completed with an [ApiException].
  /// In-flight HTTP requests are allowed to finish, but their responses are
  /// ignored for operations already completed during disposal.
  void dispose() {
    disposeGraphQLBatching();
    disposeGraphQLSubscriptions();
  }

  @override
  Future<TModel?> findOne(
    String id, {
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) {
    return executeFindOneRequest(
      query: findOneQuery,
      responseField: findOneResponseField,
      id: id,
      headers: headers,
      extra: extra,
    );
  }

  @override
  Future<List<TModel>> findAll({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) {
    return executeFindAllRequest(
      query: findAllQuery,
      responseField: findAllResponseField,
      queryParams: queryParams,
      headers: headers,
      extra: extra,
    );
  }

  @override
  Future<TModel?> createOne(
    TModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) {
    return executeCreateRequest(
      mutation: createMutation,
      responseField: createResponseField,
      model: model,
      headers: headers,
      extra: extra,
    );
  }

  @override
  Future<TModel?> updateOne(
    TModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) {
    return executeUpdateRequest(
      mutation: updateMutation,
      responseField: updateResponseField,
      id: model.id,
      updateFields: toJson(model),
      headers: headers,
      extra: extra,
    );
  }

  @override
  Future<TModel?> replaceOne(
    TModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) {
    return executeReplaceRequest(
      mutation: replaceMutation,
      responseField: replaceResponseField,
      model: model,
      headers: headers,
      extra: extra,
    );
  }

  @override
  Future<void> deleteOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) {
    return executeDeleteRequest(
      mutation: deleteMutation,
      responseField: deleteResponseField,
      id: id,
      headers: headers,
      extra: extra,
    );
  }
}
