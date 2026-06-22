import 'dart:async';

import 'package:stream_channel/stream_channel.dart';
import 'package:supabase/supabase.dart';
import 'package:synquill/synquill_contracts.dart';
import 'package:synquill_supabase/synquill_supabase.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'helpers/test_model.dart';

class RealtimeAdapter extends SupabaseApiAdapter<TestModel> {
  RealtimeAdapter(this.transport);

  @override
  final RealtimeTransport transport;

  @override
  SupabaseClient get supabaseClient =>
      throw UnimplementedError('client is not used by realtime tests');

  @override
  TestModel fromJson(Map<String, dynamic> json) => TestModel.fromJsonData(json);

  @override
  Map<String, dynamic> toJson(TestModel model) => model.toJson();
}

class RealtimeTransport implements SupabaseTransport {
  final controllers = <StreamController<SupabaseRealtimePayload>>[];
  SupabaseRealtimeRequest? lastRealtimeRequest;
  var cancelCount = 0;

  void emit(SupabaseRealtimePayload payload) {
    for (final controller in controllers.toList()) {
      controller.add(payload);
    }
  }

  @override
  Future<Map<String, dynamic>?> selectOne(SupabaseSelectRequest request) async {
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> selectMany(
    SupabaseSelectRequest request,
  ) async {
    return const [];
  }

  @override
  Future<Map<String, dynamic>?> insert(SupabaseMutationRequest request) async {
    return null;
  }

  @override
  Future<Map<String, dynamic>?> update(SupabaseMutationRequest request) async {
    return null;
  }

  @override
  Future<void> delete(SupabaseDeleteRequest request) async {}

  @override
  Stream<SupabaseRealtimePayload> subscribeEvents(
    SupabaseRealtimeRequest request,
  ) {
    lastRealtimeRequest = request;
    late final StreamController<SupabaseRealtimePayload> controller;
    controller = StreamController<SupabaseRealtimePayload>(
      onCancel: () {
        cancelCount++;
        controllers.remove(controller);
      },
    );
    controllers.add(controller);
    return controller.stream;
  }
}

void main() {
  group('SupabaseApiAdapter realtime', () {
    test('maps insert, update, and delete payloads to realtime events',
        () async {
      final transport = RealtimeTransport();
      final adapter = RealtimeAdapter(transport);
      final events = <RealtimeEvent<TestModel>>[];
      final subscription = adapter.subscribeEvents().listen(events.add);

      transport.emit(
        const SupabaseRealtimePayload(
          eventType: 'INSERT',
          newRecord: {'id': '1', 'name': 'Created', 'value': 10},
        ),
      );
      transport.emit(
        const SupabaseRealtimePayload(
          eventType: 'UPDATE',
          newRecord: {'id': '1', 'name': 'Updated', 'value': 11},
          oldRecord: {'id': '1', 'name': 'Created', 'value': 10},
        ),
      );
      transport.emit(
        const SupabaseRealtimePayload(
          eventType: 'DELETE',
          oldRecord: {'id': '1', 'name': 'Updated', 'value': 11},
        ),
      );
      await pumpEventQueue();

      expect(events.map((event) => event.type), [
        RealtimeEventType.created,
        RealtimeEventType.updated,
        RealtimeEventType.deleted,
      ]);
      expect(events[0].item,
          equals(TestModel(id: '1', name: 'Created', value: 10)));
      expect(events[1].item,
          equals(TestModel(id: '1', name: 'Updated', value: 11)));
      expect(events[2].id, equals('1'));
      expect(events[2].item, isNull);

      await subscription.cancel();
    });

    test('maps a supported query filter to realtime request data', () async {
      const name = FieldSelector<String>('name', String);
      final transport = RealtimeTransport();
      final adapter = RealtimeAdapter(transport);

      final subscription = adapter
          .subscribeEvents(
            queryParams: QueryParams(filters: [
              name.inList(['active', 'pending']),
            ]),
          )
          .listen((_) {});
      await pumpEventQueue();

      expect(transport.lastRealtimeRequest?.schema, equals('public'));
      expect(transport.lastRealtimeRequest?.table, equals('test_models'));
      expect(transport.lastRealtimeRequest?.idColumn, equals('id'));
      expect(transport.lastRealtimeRequest?.id, isNull);
      expect(
        transport.lastRealtimeRequest?.filters
            .map((filter) => [filter.field, filter.operator, filter.value])
            .toList(),
        equals([
          [
            'name',
            'in',
            ['active', 'pending'],
          ],
        ]),
      );

      await subscription.cancel();
    });

    test('rejects realtime id subscriptions with extra query filters',
        () async {
      const name = FieldSelector<String>('name', String);
      final transport = RealtimeTransport();
      final adapter = RealtimeAdapter(transport);
      final errors = <Object>[];

      final subscription = adapter
          .subscribeEvents(
            id: '1',
            queryParams: QueryParams(filters: [name.equals('active')]),
          )
          .listen((_) {}, onError: errors.add);
      await pumpEventQueue();

      expect(errors, contains(isA<ApiException>()));
      expect(transport.lastRealtimeRequest, isNull);

      await subscription.cancel();
    });

    test('rejects multiple or unsupported realtime query filters', () async {
      const name = FieldSelector<String>('name', String);
      const value = FieldSelector<int>('value', int);
      final transport = RealtimeTransport();
      final adapter = RealtimeAdapter(transport);

      final multipleErrors = <Object>[];
      final multiple = adapter
          .subscribeEvents(
            queryParams: QueryParams(
              filters: [name.equals('active'), value.greaterThan(1)],
            ),
          )
          .listen((_) {}, onError: multipleErrors.add);
      await pumpEventQueue();
      expect(multipleErrors, contains(isA<ApiException>()));
      expect(transport.lastRealtimeRequest, isNull);
      await multiple.cancel();

      final unsupportedErrors = <Object>[];
      final unsupported = adapter
          .subscribeEvents(
            queryParams: QueryParams(filters: [name.contains('needle')]),
          )
          .listen((_) {}, onError: unsupportedErrors.add);
      await pumpEventQueue();
      expect(unsupportedErrors, contains(isA<ApiException>()));
      expect(transport.lastRealtimeRequest, isNull);
      await unsupported.cancel();
    });

    test(
        'emits ApiException for missing ids, malformed rows, and unknown events',
        () async {
      final transport = RealtimeTransport();
      final adapter = RealtimeAdapter(transport);
      final errors = <Object>[];
      final subscription =
          adapter.subscribeEvents().listen((_) {}, onError: errors.add);

      transport.emit(
        const SupabaseRealtimePayload(eventType: 'DELETE', oldRecord: {}),
      );
      transport.emit(
        const SupabaseRealtimePayload(
          eventType: 'INSERT',
          newRecord: {'id': '1', 'name': 'Broken'},
        ),
      );
      transport.emit(
        const SupabaseRealtimePayload(eventType: 'TRUNCATE'),
      );
      await pumpEventQueue();

      expect(errors, hasLength(3));
      expect(errors, everyElement(isA<ApiException>()));

      await subscription.cancel();
    });

    test('cancels upstream subscriptions and dispose closes active streams',
        () async {
      final transport = RealtimeTransport();
      final adapter = RealtimeAdapter(transport);
      final errors = <Object>[];

      final first = adapter.subscribeEvents().listen((_) {});
      await first.cancel();
      expect(transport.cancelCount, equals(1));

      final second =
          adapter.subscribeEvents().listen((_) {}, onError: errors.add);
      adapter.dispose();
      await pumpEventQueue();

      expect(errors, contains(isA<ApiException>()));
      await second.cancel();
    });
  });

  group('SupabaseSdkTransport realtime', () {
    test('keeps identical subscriptions as separate channels', () async {
      final socketFactory = _RecordingWebSocketFactory();
      final client = _clientWithRealtimeTransport(socketFactory);
      final transport = SupabaseSdkTransport(client);

      try {
        final first = transport
            .subscribeEvents(_testRealtimeRequest(id: '1'))
            .listen((_) {});
        final second = transport
            .subscribeEvents(_testRealtimeRequest(id: '1'))
            .listen((_) {});
        await pumpEventQueue();

        expect(client.getChannels(), hasLength(2));

        await first.cancel();
        await second.cancel();
      } finally {
        await client.dispose();
      }
    });

    test('emits a retryable timeout error when subscribe times out', () async {
      final socketFactory = _RecordingWebSocketFactory();
      final client = _clientWithRealtimeTransport(
        socketFactory,
        timeout: const Duration(milliseconds: 1),
      );
      final transport = SupabaseSdkTransport(client);
      final errors = <Object>[];

      try {
        final subscription = transport
            .subscribeEvents(_testRealtimeRequest(id: '1'))
            .listen((_) {}, onError: errors.add);

        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(
          errors,
          contains(
            isA<SupabaseTransportException>()
                .having((error) => error.isTimeout, 'isTimeout', isTrue)
                .having(
                  (error) => error.isNetworkError,
                  'isNetworkError',
                  isTrue,
                ),
          ),
        );

        await subscription.cancel();
      } finally {
        await client.dispose();
      }
    });

    test('does not emit a closed error for normal cancellation', () async {
      final socketFactory = _RecordingWebSocketFactory();
      final client = _clientWithRealtimeTransport(socketFactory);
      final transport = SupabaseSdkTransport(client);
      final errors = <Object>[];

      try {
        final subscription = transport
            .subscribeEvents(_testRealtimeRequest(id: '1'))
            .listen((_) {}, onError: errors.add);
        await pumpEventQueue();

        await subscription.cancel();
        await pumpEventQueue();

        expect(errors, isEmpty);
      } finally {
        await client.dispose();
      }
    });
  });
}

SupabaseRealtimeRequest _testRealtimeRequest({String? id}) {
  return SupabaseRealtimeRequest(
    schema: 'public',
    table: 'test_models',
    idColumn: 'id',
    id: id,
  );
}

SupabaseClient _clientWithRealtimeTransport(
  _RecordingWebSocketFactory socketFactory, {
  Duration timeout = const Duration(seconds: 30),
}) {
  return SupabaseClient(
    'https://example.supabase.co',
    'test-key',
    accessToken: () async => 'test-key',
    realtimeClientOptions: RealtimeClientOptions(
      timeout: timeout,
      transport: socketFactory.call,
    ),
  );
}

class _RecordingWebSocketFactory {
  final channels = <_FakeWebSocketChannel>[];

  WebSocketChannel call(String url, Map<String, String> headers) {
    final channel = _FakeWebSocketChannel();
    channels.add(channel);
    return channel;
  }
}

class _FakeWebSocketChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  final _incoming = StreamController<dynamic>();
  late final _RecordingWebSocketSink _sink = _RecordingWebSocketSink(
    onClose: _incoming.close,
  );

  @override
  int? get closeCode => _sink.closeCode;

  @override
  String? get closeReason => _sink.closeReason;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  WebSocketSink get sink => _sink;

  @override
  Stream<dynamic> get stream => _incoming.stream;
}

class _RecordingWebSocketSink implements WebSocketSink {
  _RecordingWebSocketSink({required this.onClose});

  final Future<void> Function() onClose;
  final sentMessages = <Object?>[];
  final _done = Completer<void>();
  int? closeCode;
  String? closeReason;

  @override
  Future<void> get done => _done.future;

  @override
  void add(Object? data) {
    sentMessages.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (!_done.isCompleted) {
      _done.completeError(error, stackTrace);
    }
  }

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final message in stream) {
      add(message);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    this.closeCode = closeCode;
    this.closeReason = closeReason;
    if (!_done.isCompleted) {
      _done.complete();
    }
    await onClose();
  }
}
