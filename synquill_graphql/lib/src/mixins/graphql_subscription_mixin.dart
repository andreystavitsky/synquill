import 'dart:async';

import 'package:gql/ast.dart' as gql_ast;
import 'package:gql_exec/gql_exec.dart' as gql_exec;
import 'package:gql_link/gql_link.dart';
import 'package:gql_websocket_link/gql_websocket_link.dart';
import 'package:meta/meta.dart';
import 'package:synquill/synquill.dart';
import 'package:synquill_graphql/src/mixins/graphql_error_handling_mixin.dart';
import 'package:synquill_graphql/src/mixins/graphql_execution_mixin.dart';
import 'package:synquill_graphql/src/mixins/graphql_response_parsing_mixin.dart';

/// Mixin for executing GraphQL subscriptions over `graphql-transport-ws`.
mixin GraphQLSubscriptionMixin<TModel extends SynquillDataModel<TModel>>
    on
        ApiAdapterBase<TModel>,
        GraphQLErrorHandlingMixin<TModel>,
        GraphQLResponseParsingMixin<TModel>,
        GraphQLExecutionMixin<TModel> {
  final Set<StreamController<dynamic>> _activeSubscriptionControllers =
      <StreamController<dynamic>>{};
  final Set<Link> _activeSubscriptionLinks = <Link>{};
  bool _subscriptionsDisposed = false;

  /// WebSocket endpoint for GraphQL subscriptions.
  ///
  /// Defaults to the same host and path as [baseUrl], with `https` mapped to
  /// `wss` and `http` mapped to `ws`.
  Uri get graphqlSubscriptionEndpoint {
    final endpoint = baseUrl;
    final scheme = switch (endpoint.scheme) {
      'https' => 'wss',
      'http' => 'ws',
      _ => endpoint.scheme,
    };
    return endpoint.replace(scheme: scheme);
  }

  /// GraphQL subscription string for watching one model by ID.
  ///
  /// Return null to keep [subscribeOne] unsupported for this adapter.
  String? get subscribeOneSubscription => null;

  /// GraphQL subscription string for watching a collection of models.
  ///
  /// Return null to keep [subscribeAll] unsupported for this adapter.
  String? get subscribeAllSubscription => null;

  /// Response field used by [subscribeOne].
  String get subscribeOneResponseField => findOneResponseField;

  /// Response field used by [subscribeAll].
  String get subscribeAllResponseField => findAllResponseField;

  /// Response JSON key for findOne queries.
  String get findOneResponseField;

  /// Response JSON key for findAll queries.
  String get findAllResponseField;

  /// Subscribes to real-time updates for a single model by [id].
  Stream<TModel?> subscribeOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
    String? operationName,
  }) {
    final subscription = subscribeOneSubscription;
    if (subscription == null) {
      return Stream<TModel?>.error(
        ApiException('subscribeOneSubscription is not configured.'),
      );
    }

    return executeGraphQLSubscription<TModel?>(
      subscription: subscription,
      variables: {'id': id},
      headers: headers,
      extra: extra,
      operationName: operationName,
      parseData: (data) => parseSubscribeOneGraphQLResponse(
        data,
        subscribeOneResponseField,
      ),
    );
  }

  /// Subscribes to real-time updates for a list of models.
  Stream<List<TModel>> subscribeAll({
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
    String? operationName,
  }) {
    final subscription = subscribeAllSubscription;
    if (subscription == null) {
      return Stream<List<TModel>>.error(
        ApiException('subscribeAllSubscription is not configured.'),
      );
    }

    final variables = queryParamsToGraphQLVariables(queryParams);
    return executeGraphQLSubscription<List<TModel>>(
      subscription: subscription,
      variables: variables.isEmpty ? null : variables,
      headers: headers,
      extra: extra,
      operationName: operationName,
      parseData: (data) => parseSubscribeAllGraphQLResponse(
        data,
        subscribeAllResponseField,
      ),
    );
  }

  /// Creates the [Link] used for one subscription stream.
  ///
  /// Override in tests or for custom transports.
  @protected
  Link createSubscriptionLink({
    required Uri endpoint,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) {
    return TransportWebSocketLink(
      TransportWsClientOptions(
        socketMaker: WebSocketMaker.url(() => endpoint.toString()),
        connectionParams: () => buildSubscriptionInitialPayload(
          headers: headers,
          extra: extra,
        ),
        retryAttempts: 5,
      ),
    );
  }

  /// Builds the `connection_init` payload for the subscription transport.
  @protected
  FutureOr<Map<String, Object?>?> buildSubscriptionInitialPayload({
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final mergedHeaders = await mergeHeaders(headers, extra: extra);
    return mergedHeaders.isEmpty ? null : <String, Object?>{...mergedHeaders};
  }

  /// Builds the [gql_exec.Request] sent through the subscription [Link].
  @protected
  gql_exec.Request buildSubscriptionRequest({
    required gql_ast.DocumentNode document,
    Map<String, dynamic>? variables,
    String? operationName,
    Map<String, dynamic>? extra,
  }) {
    return gql_exec.Request(
      operation: gql_exec.Operation(
        document: document,
        operationName: operationName,
      ),
      variables: variables ?? const <String, dynamic>{},
    );
  }

  /// Parses a subscription payload that represents one model.
  @protected
  TModel? parseSubscribeOneGraphQLResponse(
    Map<String, dynamic> data,
    String fieldName,
  ) {
    return parseFindOneGraphQLResponse(data, fieldName);
  }

  /// Parses a subscription payload that represents a list of models.
  @protected
  List<TModel> parseSubscribeAllGraphQLResponse(
    Map<String, dynamic> data,
    String fieldName,
  ) {
    return parseFindAllGraphQLResponse(data, fieldName);
  }

  /// Executes [subscription] through a GraphQL subscription [Link].
  @protected
  Stream<TResult> executeGraphQLSubscription<TResult>({
    required String subscription,
    Map<String, dynamic>? variables,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
    String? operationName,
    required TResult Function(Map<String, dynamic> data) parseData,
  }) {
    late final StreamController<TResult> controller;
    StreamSubscription<gql_exec.Response>? linkSubscription;
    Link? link;
    var cleanedUp = false;

    Future<void> cleanup() async {
      if (cleanedUp) return;
      cleanedUp = true;
      _activeSubscriptionControllers.remove(controller);
      await linkSubscription?.cancel();
      final activeLink = link;
      if (activeLink != null) {
        final shouldDispose = _activeSubscriptionLinks.remove(activeLink);
        if (shouldDispose) {
          await activeLink.dispose();
        }
      }
    }

    controller = StreamController<TResult>(
      onListen: () {
        if (_subscriptionsDisposed) {
          controller
              .addError(ApiException('GraphQL adapter has been disposed.'));
          unawaited(controller.close());
          return;
        }

        _activeSubscriptionControllers.add(controller);
        try {
          final document = documentFromOperation(subscription);
          final operationDefinition = resolveGraphQLOperation(
            document,
            operationName: operationName,
          );
          if (operationDefinition.type != gql_ast.OperationType.subscription) {
            throw ApiException(
              'Invalid GraphQL document: expected a subscription operation.',
            );
          }

          final request = buildSubscriptionRequest(
            document: document,
            variables: variables,
            operationName: operationName,
            extra: extra,
          );
          link = createSubscriptionLink(
            endpoint: graphqlSubscriptionEndpoint,
            headers: headers,
            extra: extra,
          );
          _activeSubscriptionLinks.add(link!);

          linkSubscription = link!.request(request).listen(
            (response) {
              try {
                checkGraphQLSubscriptionResponse(response);
                controller.add(parseData(response.data ?? const {}));
              } catch (e, st) {
                controller.addError(mapSubscriptionError(e), st);
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              controller.addError(
                mapSubscriptionError(error),
                stackTrace,
              );
            },
            onDone: () {
              unawaited(cleanup());
              if (!controller.isClosed) {
                unawaited(controller.close());
              }
            },
          );
        } catch (e, st) {
          controller.addError(mapSubscriptionError(e), st);
          unawaited(cleanup());
          unawaited(controller.close());
        }
      },
      onCancel: cleanup,
    );

    return controller.stream;
  }

  /// Throws when a subscription [response] contains GraphQL errors.
  @protected
  void checkGraphQLSubscriptionResponse(gql_exec.Response response) {
    final errors = response.errors;
    if (errors == null || errors.isEmpty) {
      return;
    }

    checkGraphQLErrors(
      <String, dynamic>{
        'data': response.data,
        'errors': errors.map(graphQLErrorToJson).toList(),
      },
      null,
    );
  }

  /// Converts a `gql_exec` GraphQL error to a response-style JSON map.
  @protected
  Map<String, dynamic> graphQLErrorToJson(gql_exec.GraphQLError error) {
    return <String, dynamic>{
      'message': error.message,
      if (error.locations != null)
        'locations': error.locations!
            .map(
              (location) => <String, int>{
                'line': location.line,
                'column': location.column,
              },
            )
            .toList(),
      if (error.path != null) 'path': error.path,
      if (error.extensions != null) 'extensions': error.extensions,
    };
  }

  /// Maps subscription transport errors to Synquill exceptions.
  @protected
  Object mapSubscriptionError(Object error) {
    if (error is SynquillStorageException) {
      return error;
    }
    return ApiException('GraphQL subscription failed: $error');
  }

  /// Fails all active subscription streams and disposes their links.
  @protected
  void disposeGraphQLSubscriptions() {
    if (_subscriptionsDisposed) return;
    _subscriptionsDisposed = true;

    final exception = ApiException('GraphQL adapter has been disposed.');
    for (final controller in _activeSubscriptionControllers.toList()) {
      if (!controller.isClosed) {
        controller.addError(exception);
        unawaited(controller.close());
      }
    }
    _activeSubscriptionControllers.clear();

    for (final link in _activeSubscriptionLinks.toList()) {
      unawaited(link.dispose());
    }
    _activeSubscriptionLinks.clear();
  }
}
