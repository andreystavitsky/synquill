import 'dart:async';

import 'package:gql_exec/gql_exec.dart' as gql_exec;
import 'package:gql_link/gql_link.dart';
import 'package:synquill/synquill.dart';
import 'package:test/test.dart';

import 'helpers/test_graphql_adapter.dart';
import 'helpers/test_model.dart';

class TestLinkException extends LinkException {
  TestLinkException(Object? originalException) : super(originalException, null);
}

class FakeSubscriptionLink extends Link {
  StreamController<gql_exec.Response>? _controller;
  gql_exec.Request? capturedRequest;
  var cancelCount = 0;
  var disposeCount = 0;

  void add(gql_exec.Response response) {
    _controller!.add(response);
  }

  void addError(Object error) {
    _controller!.addError(error);
  }

  Future<void> close() async {
    await _controller!.close();
  }

  @override
  Stream<gql_exec.Response> request(
    gql_exec.Request request, [
    NextLink? forward,
  ]) {
    capturedRequest = request;
    _controller = StreamController<gql_exec.Response>(
      onCancel: () {
        cancelCount++;
      },
    );
    return _controller!.stream;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}

class SubscriptionTestAdapter extends TestGraphQLAdapter {
  SubscriptionTestAdapter(this.link);

  final FakeSubscriptionLink link;
  Uri? capturedEndpoint;
  Map<String, String>? capturedHeaders;
  Map<String, dynamic>? capturedExtra;

  @override
  String? get subscribeOneSubscription =>
      r'subscription WatchTestModel($id: ID!) { '
      r'test_model(id: $id) { id name value } }';

  @override
  String? get subscribeAllSubscription =>
      r'subscription WatchTestModels($filter: TestFilter) { '
      r'test_models(filter: $filter) { id name value } }';

  @override
  String? get subscribeEventsSubscription =>
      r'subscription WatchTestModelEvents($id: ID, $filter: TestFilter) { '
      r'test_model_events(id: $id, filter: $filter) { '
      r'type id item { id name value } metadata } }';

  @override
  String get subscribeEventsResponseField => 'test_model_events';

  @override
  Link createSubscriptionLink({
    required Uri endpoint,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) {
    capturedEndpoint = endpoint;
    capturedHeaders = headers;
    capturedExtra = extra;
    return link;
  }
}

void main() {
  group('GraphQL subscriptions', () {
    late FakeSubscriptionLink link;
    late SubscriptionTestAdapter adapter;

    setUp(() {
      link = FakeSubscriptionLink();
      adapter = SubscriptionTestAdapter(link);
    });

    test('subscribeOne builds a request with id variable', () async {
      final values = <TestModel?>[];
      final subscription = adapter
          .subscribeOne(
            '1',
            headers: {'Authorization': 'Bearer token'},
            extra: {'traceId': 'trace-1'},
            operationName: 'WatchTestModel',
          )
          .listen(values.add);

      await Future<void>.delayed(Duration.zero);

      expect(
        link.capturedRequest?.operation.operationName,
        equals('WatchTestModel'),
      );
      expect(link.capturedRequest?.variables, equals({'id': '1'}));
      expect(adapter.capturedEndpoint.toString(),
          equals('wss://api.test.com/graphql'));
      expect(
          adapter.capturedHeaders, equals({'Authorization': 'Bearer token'}));
      expect(adapter.capturedExtra, equals({'traceId': 'trace-1'}));

      await subscription.cancel();
    });

    test('subscribeAll converts QueryParams to GraphQL variables', () async {
      const nameField = FieldSelector<String>('name', String);
      final subscription = adapter
          .subscribeAll(
            queryParams: QueryParams(
              filters: [nameField.equals('A')],
            ),
            operationName: 'WatchTestModels',
          )
          .listen((_) {});

      await Future<void>.delayed(Duration.zero);

      expect(
        link.capturedRequest?.variables,
        equals({
          'filter': {
            'name': {'eq': 'A'},
          },
        }),
      );

      await subscription.cancel();
    });

    test('subscribeEvents builds a request with id and query variables',
        () async {
      const nameField = FieldSelector<String>('name', String);
      final subscription = adapter
          .subscribeEvents(
            id: '1',
            queryParams: QueryParams(
              filters: [nameField.equals('A')],
            ),
          )
          .listen((_) {});

      await Future<void>.delayed(Duration.zero);

      expect(
        link.capturedRequest?.variables,
        equals({
          'id': '1',
          'filter': {
            'name': {'eq': 'A'},
          },
        }),
      );

      await subscription.cancel();
    });

    test('subscribeEvents parses standard event envelope', () async {
      final values = <RealtimeEvent<TestModel>>[];
      final subscription = adapter.subscribeEvents().listen(values.add);
      await Future<void>.delayed(Duration.zero);

      link.add(
        const gql_exec.Response(
          data: {
            'test_model_events': {
              'type': 'updated',
              'id': '1',
              'item': {'id': '1', 'name': 'One', 'value': 1},
              'metadata': {'source': 'test'},
            },
          },
          response: {},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(values.single.type, RealtimeEventType.updated);
      expect(values.single.id, '1');
      expect(values.single.item, TestModel(id: '1', name: 'One', value: 1));
      expect(values.single.metadata, {'source': 'test'});

      await subscription.cancel();
    });

    test('subscribeEvents emits ApiException for malformed envelope', () async {
      final stream = adapter.subscribeEvents();
      final expectation = expectLater(stream, emitsError(isA<ApiException>()));
      await Future<void>.delayed(Duration.zero);

      link.add(
        const gql_exec.Response(
          data: {
            'test_model_events': {'type': 'not-real', 'id': '1'},
          },
          response: {},
        ),
      );

      await expectation;
    });

    test('subscribeEvents can parse a custom envelope shape', () async {
      final customAdapter = CustomEventSubscriptionAdapter(link);
      final values = <RealtimeEvent<TestModel>>[];
      final subscription = customAdapter.subscribeEvents().listen(values.add);
      await Future<void>.delayed(Duration.zero);

      link.add(
        const gql_exec.Response(
          data: {
            'customEvent': {
              'kind': 'created',
              'model': {'id': '1', 'name': 'Custom', 'value': 2},
            },
          },
          response: {},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(values.single.type, RealtimeEventType.created);
      expect(values.single.id, '1');
      expect(values.single.item, TestModel(id: '1', name: 'Custom', value: 2));

      await subscription.cancel();
    });

    test('subscribeEvents errors when subscription document is not configured',
        () async {
      final unsupported = TestGraphQLAdapter();

      await expectLater(
        unsupported.subscribeEvents(),
        emitsError(isA<ApiException>()),
      );
    });

    test('subscribeOne emits multiple payloads in order', () async {
      final values = <TestModel?>[];
      final subscription = adapter.subscribeOne('1').listen(values.add);
      await Future<void>.delayed(Duration.zero);

      link
        ..add(
          const gql_exec.Response(
            data: {
              'test_model': {'id': '1', 'name': 'One', 'value': 1},
            },
            response: {},
          ),
        )
        ..add(
          const gql_exec.Response(
            data: {
              'test_model': {'id': '1', 'name': 'Two', 'value': 2},
            },
            response: {},
          ),
        );
      await Future<void>.delayed(Duration.zero);

      expect(
        values,
        equals([
          TestModel(id: '1', name: 'One', value: 1),
          TestModel(id: '1', name: 'Two', value: 2),
        ]),
      );

      await subscription.cancel();
    });

    test('subscribeOne emits null for null one-item payload', () async {
      final values = <TestModel?>[];
      final subscription = adapter.subscribeOne('missing').listen(values.add);
      await Future<void>.delayed(Duration.zero);

      link.add(
        const gql_exec.Response(
          data: {'test_model': null},
          response: {},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(values, equals([null]));

      await subscription.cancel();
    });

    test('subscribeAll parses list, empty list, and null list payloads',
        () async {
      final values = <List<TestModel>>[];
      final subscription = adapter.subscribeAll().listen(values.add);
      await Future<void>.delayed(Duration.zero);

      link
        ..add(
          const gql_exec.Response(
            data: {
              'test_models': [
                {'id': '1', 'name': 'One', 'value': 1},
              ],
            },
            response: {},
          ),
        )
        ..add(
          const gql_exec.Response(
            data: {'test_models': <Object?>[]},
            response: {},
          ),
        )
        ..add(
          const gql_exec.Response(
            data: {'test_models': null},
            response: {},
          ),
        );
      await Future<void>.delayed(Duration.zero);

      expect(values[0], equals([TestModel(id: '1', name: 'One', value: 1)]));
      expect(values[1], isEmpty);
      expect(values[2], isEmpty);

      await subscription.cancel();
    });

    test('GraphQL errors become mapped stream errors', () async {
      final stream = adapter.subscribeOne('1');
      final expectation = expectLater(
        stream,
        emitsError(isA<AuthenticationException>()),
      );
      await Future<void>.delayed(Duration.zero);

      link.add(
        const gql_exec.Response(
          errors: [
            gql_exec.GraphQLError(
              message: 'No auth',
              extensions: {'code': 'UNAUTHENTICATED'},
            ),
          ],
          response: {},
        ),
      );

      await expectation;
    });

    test(
        'LinkException and socket failures map to NetworkException for '
        'autoreconnect', () async {
      final stream = adapter.subscribeOne('1');
      final expectation = expectLater(
        stream,
        emitsError(isA<NetworkException>()),
      );
      await Future<void>.delayed(Duration.zero);

      link.addError(TestLinkException('Connection refused'));

      await expectation;
    });

    test('malformed payload becomes ApiException stream error', () async {
      final stream = adapter.subscribeOne('1');
      final expectation = expectLater(
        stream,
        emitsError(isA<ApiException>()),
      );
      await Future<void>.delayed(Duration.zero);

      link.add(
        const gql_exec.Response(
          data: {'test_model': 'not an object'},
          response: {},
        ),
      );

      await expectation;
    });

    test('cancel closes upstream subscription and disposes link', () async {
      final subscription = adapter.subscribeOne('1').listen((_) {});
      await Future<void>.delayed(Duration.zero);

      await subscription.cancel();

      expect(link.cancelCount, equals(1));
      expect(link.disposeCount, equals(1));
    });

    test('dispose errors active streams and prevents new subscriptions',
        () async {
      Object? error;
      var done = false;
      adapter.subscribeOne('1').listen(
        (_) {},
        onError: (Object e) {
          error = e;
        },
        onDone: () {
          done = true;
        },
      );
      await Future<void>.delayed(Duration.zero);

      adapter.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(error, isA<ApiException>());
      expect(done, isTrue);
      expect(link.disposeCount, equals(1));

      await expectLater(
        adapter.subscribeOne('1'),
        emitsError(isA<ApiException>()),
      );
    });
  });
}

class CustomEventSubscriptionAdapter extends SubscriptionTestAdapter {
  CustomEventSubscriptionAdapter(super.link);

  @override
  String? get subscribeEventsSubscription => r'''
subscription CustomEvent {
  customEvent { kind model { id name value } }
}
''';

  @override
  String get subscribeEventsResponseField => 'customEvent';

  @override
  RealtimeEvent<TestModel> parseSubscribeEventGraphQLResponse(
    Map<String, dynamic> data,
    String fieldName,
  ) {
    final event = data[fieldName] as Map<String, dynamic>;
    final item = fromJson(event['model'] as Map<String, dynamic>);
    return RealtimeEvent(
      type: RealtimeEventType.created,
      id: item.id,
      item: item,
      raw: event,
    );
  }
}
