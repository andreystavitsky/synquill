import 'dart:async';

import 'package:supabase/supabase.dart';
import 'package:synquill/synquill_contracts.dart';
import 'package:synquill_supabase/synquill_supabase.dart';
import 'package:test/test.dart';

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
}
