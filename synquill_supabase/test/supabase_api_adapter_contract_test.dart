import 'dart:async';

import 'package:supabase/supabase.dart';
import 'package:synquill_supabase/synquill_supabase.dart';
import 'package:test/test.dart';

import 'helpers/test_model.dart';

class ContractAdapter extends SupabaseApiAdapter<TestModel> {
  ContractAdapter(this.transport);

  @override
  final SupabaseTransport transport;

  @override
  SupabaseClient get supabaseClient =>
      throw UnimplementedError('client is not used by contract tests');

  @override
  TestModel fromJson(Map<String, dynamic> json) => TestModel.fromJsonData(json);

  @override
  Map<String, dynamic> toJson(TestModel model) => model.toJson();
}

class CustomContractAdapter extends ContractAdapter {
  CustomContractAdapter(super.transport);

  @override
  String get schema => 'private';

  @override
  String get tableName => 'custom_models';

  @override
  String get idColumn => 'model_id';

  @override
  String get selectColumns => 'model_id,name,value';
}

class RecordingTransport implements SupabaseTransport {
  SupabaseSelectRequest? lastSelectOne;
  SupabaseSelectRequest? lastSelectMany;

  @override
  Future<Map<String, dynamic>?> selectOne(SupabaseSelectRequest request) async {
    lastSelectOne = request;
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> selectMany(
    SupabaseSelectRequest request,
  ) async {
    lastSelectMany = request;
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
    return const Stream<SupabaseRealtimePayload>.empty();
  }
}

void main() {
  group('SupabaseApiAdapter contract', () {
    test(
        'uses public schema, plural table, id column, and wildcard select by default',
        () async {
      final transport = RecordingTransport();
      final adapter = ContractAdapter(transport);

      await adapter.findOne('model-1');
      await adapter.findAll();

      expect(transport.lastSelectOne?.schema, equals('public'));
      expect(transport.lastSelectOne?.table, equals('test_models'));
      expect(transport.lastSelectOne?.idColumn, equals('id'));
      expect(transport.lastSelectOne?.id, equals('model-1'));
      expect(transport.lastSelectOne?.selectColumns, equals('*'));
      expect(transport.lastSelectMany?.schema, equals('public'));
      expect(transport.lastSelectMany?.table, equals('test_models'));
      expect(transport.lastSelectMany?.selectColumns, equals('*'));
    });

    test(
        'allows schema, table, id column, and selected columns to be overridden',
        () async {
      final transport = RecordingTransport();
      final adapter = CustomContractAdapter(transport);

      await adapter.findOne('model-1');
      await adapter.findAll();

      expect(transport.lastSelectOne?.schema, equals('private'));
      expect(transport.lastSelectOne?.table, equals('custom_models'));
      expect(transport.lastSelectOne?.idColumn, equals('model_id'));
      expect(transport.lastSelectOne?.selectColumns,
          equals('model_id,name,value'));
      expect(transport.lastSelectMany?.schema, equals('private'));
      expect(transport.lastSelectMany?.table, equals('custom_models'));
    });

    test('merges base headers with per-call headers for select requests',
        () async {
      final transport = RecordingTransport();
      final adapter = _HeaderContractAdapter(transport);

      await adapter.findOne(
        'model-1',
        headers: {'X-Base': 'request-one', 'X-Request': 'one'},
      );
      await adapter.findAll(
        headers: {'X-Base': 'request-many', 'X-Request': 'many'},
      );

      expect(
        transport.lastSelectOne?.headers,
        equals({
          'Accept': 'application/json',
          'X-Base': 'request-one',
          'X-Request': 'one',
        }),
      );
      expect(
        transport.lastSelectMany?.headers,
        equals({
          'Accept': 'application/json',
          'X-Base': 'request-many',
          'X-Request': 'many',
        }),
      );
    });
  });
}

class _HeaderContractAdapter extends ContractAdapter {
  _HeaderContractAdapter(super.transport);

  @override
  Map<String, String> get baseHeaders => const {
        'Accept': 'application/json',
        'X-Base': 'base',
      };
}
