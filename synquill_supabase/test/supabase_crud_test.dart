import 'dart:async';

import 'package:supabase/supabase.dart';
import 'package:synquill/synquill_contracts.dart';
import 'package:synquill_supabase/synquill_supabase.dart';
import 'package:test/test.dart';

import 'helpers/test_model.dart';

class CrudAdapter extends SupabaseApiAdapter<TestModel> {
  CrudAdapter(this.transport);

  @override
  final CrudTransport transport;

  @override
  SupabaseClient get supabaseClient =>
      throw UnimplementedError('client is not used by CRUD tests');

  @override
  TestModel fromJson(Map<String, dynamic> json) => TestModel.fromJsonData(json);

  @override
  Map<String, dynamic> toJson(TestModel model) => model.toJson();
}

class CrudTransport implements SupabaseTransport {
  Map<String, dynamic>? selectOneResult;
  List<Map<String, dynamic>> selectManyResult = const [];
  Map<String, dynamic>? insertResult;
  Map<String, dynamic>? updateResult;

  SupabaseSelectRequest? lastSelectOne;
  SupabaseSelectRequest? lastSelectMany;
  SupabaseMutationRequest? lastInsert;
  SupabaseMutationRequest? lastUpdate;
  SupabaseDeleteRequest? lastDelete;

  @override
  Future<Map<String, dynamic>?> selectOne(SupabaseSelectRequest request) async {
    lastSelectOne = request;
    return selectOneResult;
  }

  @override
  Future<List<Map<String, dynamic>>> selectMany(
    SupabaseSelectRequest request,
  ) async {
    lastSelectMany = request;
    return selectManyResult;
  }

  @override
  Future<Map<String, dynamic>?> insert(SupabaseMutationRequest request) async {
    lastInsert = request;
    return insertResult;
  }

  @override
  Future<Map<String, dynamic>?> update(SupabaseMutationRequest request) async {
    lastUpdate = request;
    return updateResult;
  }

  @override
  Future<void> delete(SupabaseDeleteRequest request) async {
    lastDelete = request;
  }

  @override
  Stream<SupabaseRealtimePayload> subscribeEvents(
    SupabaseRealtimeRequest request,
  ) {
    return const Stream<SupabaseRealtimePayload>.empty();
  }
}

void main() {
  group('SupabaseApiAdapter CRUD', () {
    test('findOne parses a row and returns null when Supabase has no row',
        () async {
      final transport = CrudTransport()
        ..selectOneResult = {'id': '1', 'name': 'One', 'value': 10};
      final adapter = CrudAdapter(transport);

      expect(await adapter.findOne('1'),
          equals(TestModel(id: '1', name: 'One', value: 10)));
      expect(transport.lastSelectOne?.id, equals('1'));

      transport.selectOneResult = null;
      expect(await adapter.findOne('missing'), isNull);
    });

    test('findAll parses every row and returns an empty list for no rows',
        () async {
      final transport = CrudTransport()
        ..selectManyResult = [
          {'id': '1', 'name': 'One', 'value': 10},
          {'id': '2', 'name': 'Two', 'value': 20},
        ];
      final adapter = CrudAdapter(transport);

      expect(await adapter.findAll(), [
        TestModel(id: '1', name: 'One', value: 10),
        TestModel(id: '2', name: 'Two', value: 20),
      ]);

      transport.selectManyResult = const [];
      expect(await adapter.findAll(), isEmpty);
    });

    test('createOne sends model JSON and parses returned server row', () async {
      final transport = CrudTransport()
        ..insertResult = {'id': 'server-1', 'name': 'Created', 'value': 11};
      final adapter = CrudAdapter(transport);
      final model = TestModel(id: 'client-1', name: 'Created', value: 11);

      final result = await adapter.createOne(model);

      expect(result,
          equals(TestModel(id: 'server-1', name: 'Created', value: 11)));
      expect(transport.lastInsert?.values, equals(model.toJson()));
      expect(transport.lastInsert?.id, isNull);
    });

    test('updateOne sends id and model JSON, and null response stays null',
        () async {
      final transport = CrudTransport()
        ..updateResult = {'id': '1', 'name': 'Updated', 'value': 12};
      final adapter = CrudAdapter(transport);
      final model = TestModel(id: '1', name: 'Updated', value: 12);

      expect(await adapter.updateOne(model), equals(model));
      expect(transport.lastUpdate?.id, equals('1'));
      expect(transport.lastUpdate?.values, equals(model.toJson()));

      transport.updateResult = null;
      expect(await adapter.updateOne(model), isNull);
    });

    test('replaceOne defaults to the same update transport operation',
        () async {
      final transport = CrudTransport()
        ..updateResult = {'id': '1', 'name': 'Replaced', 'value': 13};
      final adapter = CrudAdapter(transport);
      final model = TestModel(id: '1', name: 'Replaced', value: 13);

      expect(await adapter.replaceOne(model), equals(model));
      expect(transport.lastUpdate?.id, equals('1'));
      expect(transport.lastUpdate?.values, equals(model.toJson()));
      expect(transport.lastInsert, isNull);
    });

    test('deleteOne sends a delete request and accepts no-content responses',
        () async {
      final transport = CrudTransport();
      final adapter = CrudAdapter(transport);

      await adapter.deleteOne('1');

      expect(transport.lastDelete?.schema, equals('public'));
      expect(transport.lastDelete?.table, equals('test_models'));
      expect(transport.lastDelete?.idColumn, equals('id'));
      expect(transport.lastDelete?.id, equals('1'));
    });

    test('malformed returned rows are reported as ApiException', () async {
      final transport = CrudTransport()
        ..selectOneResult = {'id': '1', 'name': 'Broken'};
      final adapter = CrudAdapter(transport);

      expect(
        () => adapter.findOne('1'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            contains('Failed to parse Supabase row'),
          ),
        ),
      );
    });

    test('merges headers for insert, update, replace, and delete requests',
        () async {
      final transport = CrudTransport()
        ..insertResult = {'id': '1', 'name': 'Created', 'value': 1}
        ..updateResult = {'id': '1', 'name': 'Updated', 'value': 2};
      final adapter = _HeaderCrudAdapter(transport);

      await adapter.createOne(
        TestModel(id: '1', name: 'Created', value: 1),
        headers: {'X-Base': 'request-create', 'X-Request': 'create'},
      );
      await adapter.updateOne(
        TestModel(id: '1', name: 'Updated', value: 2),
        headers: {'X-Base': 'request-update', 'X-Request': 'update'},
      );
      final updateHeaders = transport.lastUpdate?.headers;
      await adapter.replaceOne(
        TestModel(id: '1', name: 'Replaced', value: 3),
        headers: {'X-Base': 'request-replace', 'X-Request': 'replace'},
      );
      final replaceHeaders = transport.lastUpdate?.headers;
      await adapter.deleteOne(
        '1',
        headers: {'X-Base': 'request-delete', 'X-Request': 'delete'},
      );

      expect(
        transport.lastInsert?.headers,
        equals({
          'Accept': 'application/json',
          'X-Base': 'request-create',
          'X-Request': 'create',
        }),
      );
      expect(
        updateHeaders,
        equals({
          'Accept': 'application/json',
          'X-Base': 'request-update',
          'X-Request': 'update',
        }),
      );
      expect(
        replaceHeaders,
        equals({
          'Accept': 'application/json',
          'X-Base': 'request-replace',
          'X-Request': 'replace',
        }),
      );
      expect(
        transport.lastDelete?.headers,
        equals({
          'Accept': 'application/json',
          'X-Base': 'request-delete',
          'X-Request': 'delete',
        }),
      );
    });
  });
}

class _HeaderCrudAdapter extends CrudAdapter {
  _HeaderCrudAdapter(super.transport);

  @override
  Map<String, String> get baseHeaders => const {
        'Accept': 'application/json',
        'X-Base': 'base',
      };
}
