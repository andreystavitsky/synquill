import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import 'package:synquill/synquill_contracts.dart';
import 'package:synquill_supabase/synquill_supabase.dart';
import 'package:test/test.dart';

import 'helpers/test_model.dart';

class QueryAdapter extends SupabaseApiAdapter<TestModel> {
  QueryAdapter(this.transport);

  @override
  final QueryTransport transport;

  @override
  SupabaseClient get supabaseClient =>
      throw UnimplementedError('client is not used by query tests');

  @override
  TestModel fromJson(Map<String, dynamic> json) => TestModel.fromJsonData(json);

  @override
  Map<String, dynamic> toJson(TestModel model) => model.toJson();
}

class SdkErrorAdapter extends SupabaseApiAdapter<TestModel> {
  SdkErrorAdapter(this.supabaseClient);

  @override
  final SupabaseClient supabaseClient;

  @override
  TestModel fromJson(Map<String, dynamic> json) => TestModel.fromJsonData(json);

  @override
  Map<String, dynamic> toJson(TestModel model) => model.toJson();
}

class QueryTransport implements SupabaseTransport {
  SupabaseSelectRequest? lastSelectOne;
  SupabaseSelectRequest? lastSelectMany;
  Object? error;

  @override
  Future<Map<String, dynamic>?> selectOne(SupabaseSelectRequest request) async {
    final thrown = error;
    if (thrown != null) throw thrown;
    lastSelectOne = request;
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> selectMany(
    SupabaseSelectRequest request,
  ) async {
    final thrown = error;
    if (thrown != null) throw thrown;
    lastSelectMany = request;
    return const [];
  }

  @override
  Future<Map<String, dynamic>?> insert(SupabaseMutationRequest request) async {
    final thrown = error;
    if (thrown != null) throw thrown;
    return null;
  }

  @override
  Future<Map<String, dynamic>?> update(SupabaseMutationRequest request) async {
    final thrown = error;
    if (thrown != null) throw thrown;
    return null;
  }

  @override
  Future<void> delete(SupabaseDeleteRequest request) async {
    final thrown = error;
    if (thrown != null) throw thrown;
  }

  @override
  Stream<SupabaseRealtimePayload> subscribeEvents(
    SupabaseRealtimeRequest request,
  ) {
    final thrown = error;
    if (thrown != null) throw thrown;
    return const Stream<SupabaseRealtimePayload>.empty();
  }
}

void main() {
  group('SupabaseApiAdapter query mapping', () {
    const name = FieldSelector<String>('name', String);
    const value = FieldSelector<int>('value', int);
    const deletedAt = FieldSelector<String?>('deleted_at', String);

    test('maps every supported filter operator in order', () async {
      final transport = QueryTransport();
      final adapter = QueryAdapter(transport);

      await adapter.findAll(
        queryParams: QueryParams(
          filters: [
            name.equals('one'),
            name.notEquals('two'),
            value.greaterThan(1),
            value.greaterThanOrEqual(2),
            value.lessThan(3),
            value.lessThanOrEqual(4),
            name.contains('needle'),
            name.startsWith('prefix'),
            name.endsWith('suffix'),
            name.inList(['a', 'b']),
            name.notInList(['c', 'd']),
            deletedAt.isNull(),
            deletedAt.isNotNull(),
          ],
        ),
      );

      expect(
        transport.lastSelectMany?.filters
            .map((filter) => [filter.field, filter.operator, filter.value])
            .toList(),
        equals([
          ['name', 'eq', 'one'],
          ['name', 'neq', 'two'],
          ['value', 'gt', 1],
          ['value', 'gte', 2],
          ['value', 'lt', 3],
          ['value', 'lte', 4],
          ['name', 'ilike', '%needle%'],
          ['name', 'ilike', 'prefix%'],
          ['name', 'ilike', '%suffix'],
          [
            'name',
            'in',
            ['a', 'b']
          ],
          [
            'name',
            'not.in',
            ['c', 'd']
          ],
          ['deleted_at', 'is', null],
          ['deleted_at', 'not.is', null],
        ]),
      );
    });

    test('maps multi-sort and limit-only pagination', () async {
      final transport = QueryTransport();
      final adapter = QueryAdapter(transport);

      await adapter.findAll(
        queryParams: const QueryParams(
          sorts: [
            SortCondition.ascending(name),
            SortCondition.descending(value),
          ],
          pagination: PaginationParams.limit(25),
        ),
      );

      expect(
        transport.lastSelectMany?.sorts
            .map((sort) => [sort.field, sort.ascending])
            .toList(),
        equals([
          ['name', true],
          ['value', false],
        ]),
      );
      expect(transport.lastSelectMany?.limit, equals(25));
      expect(transport.lastSelectMany?.rangeFrom, isNull);
      expect(transport.lastSelectMany?.rangeTo, isNull);
    });

    test('maps offset pagination to an inclusive Supabase range', () async {
      final transport = QueryTransport();
      final adapter = QueryAdapter(transport);

      await adapter.findAll(
        queryParams: const QueryParams(
          pagination: PaginationParams(limit: 10, offset: 20),
        ),
      );

      expect(transport.lastSelectMany?.limit, isNull);
      expect(transport.lastSelectMany?.rangeFrom, equals(20));
      expect(transport.lastSelectMany?.rangeTo, equals(29));
    });

    test('passes query filters into findOne requests', () async {
      final transport = QueryTransport();
      final adapter = QueryAdapter(transport);

      await adapter.findOne(
        'model-1',
        queryParams: QueryParams(filters: [name.equals('active')]),
      );

      expect(transport.lastSelectOne?.id, equals('model-1'));
      expect(
        transport.lastSelectOne?.filters
            .map((filter) => [filter.field, filter.operator, filter.value])
            .toList(),
        equals([
          ['name', 'eq', 'active'],
        ]),
      );
    });

    test('rejects offset pagination without a limit', () {
      final adapter = QueryAdapter(QueryTransport());

      expect(
        () => adapter.findAll(
          queryParams: const QueryParams(
            pagination: PaginationParams(offset: 20),
          ),
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('rejects empty list filters and non-positive pagination bounds', () {
      final adapter = QueryAdapter(QueryTransport());

      expect(
        () => adapter.findAll(
          queryParams: QueryParams(filters: [name.inList(const [])]),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => adapter.findAll(
          queryParams: const QueryParams(
            pagination: PaginationParams.limit(0),
          ),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => adapter.findAll(
          queryParams: const QueryParams(
            pagination: PaginationParams(limit: 10, offset: -1),
          ),
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('SupabaseApiAdapter error mapping', () {
    test('maps transport errors to Synquill exceptions', () async {
      final cases = <(SupabaseTransportException, Matcher)>[
        (
          SupabaseTransportException('auth', statusCode: 401),
          isA<AuthenticationException>(),
        ),
        (
          SupabaseTransportException('forbidden', statusCode: 403),
          isA<AuthorizationException>(),
        ),
        (
          SupabaseTransportException('missing', statusCode: 404),
          isA<ApiExceptionNotFound>(),
        ),
        (
          SupabaseTransportException('gone', statusCode: 410),
          isA<ApiExceptionGone>(),
        ),
        (
          SupabaseTransportException('conflict', statusCode: 409),
          isA<ConflictException>(),
        ),
        (
          SupabaseTransportException(
            'bad input',
            statusCode: 400,
            fieldErrors: {
              'name': ['is required'],
            },
          ),
          isA<ValidationException>().having(
            (error) => error.fieldErrors,
            'fieldErrors',
            {
              'name': ['is required'],
            },
          ),
        ),
        (
          SupabaseTransportException('server', statusCode: 500),
          isA<ServerException>(),
        ),
        (
          SupabaseTransportException('offline', isNetworkError: true),
          isA<NetworkException>(),
        ),
        (
          SupabaseTransportException('timeout', isTimeout: true),
          isA<NetworkException>(),
        ),
        (
          SupabaseTransportException('unknown', statusCode: 418),
          isA<ApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            418,
          ),
        ),
      ];

      for (final (exception, matcher) in cases) {
        final transport = QueryTransport()..error = exception;
        final adapter = QueryAdapter(transport);

        await expectLater(adapter.findAll(), throwsA(matcher));
      }
    });

    test('maps real SDK PostgREST errors to Synquill exceptions', () async {
      final cases = <(int, String, Matcher)>[
        (
          401,
          'status-401',
          isA<AuthenticationException>()
              .having((error) => error.message, 'message', 'status-401'),
        ),
        (
          403,
          'status-403',
          isA<AuthorizationException>()
              .having((error) => error.message, 'message', 'status-403'),
        ),
        (
          404,
          'status-404',
          isA<ApiExceptionNotFound>()
              .having((error) => error.message, 'message', 'status-404'),
        ),
        (
          409,
          'status-409',
          isA<ConflictException>()
              .having((error) => error.message, 'message', 'status-409'),
        ),
        (
          500,
          'status-500',
          isA<ServerException>()
              .having((error) => error.message, 'message', 'status-500'),
        ),
      ];

      for (final (statusCode, message, matcher) in cases) {
        final client = _clientWithHttpClient(
          _StatusCodeClient(statusCode, message: message),
        );
        final adapter = SdkErrorAdapter(client);

        try {
          await expectLater(adapter.findAll(), throwsA(matcher));
        } finally {
          await client.dispose();
        }
      }
    });

    test('preserves PostgREST message, code, and numeric status in transport',
        () async {
      final client = _clientWithHttpClient(
        _StatusCodeClient(409, message: 'unique key conflict'),
      );
      final transport = SupabaseSdkTransport(client);

      try {
        await expectLater(
          transport.selectMany(
            const SupabaseSelectRequest(
              schema: 'public',
              table: 'test_models',
              selectColumns: '*',
              idColumn: 'id',
            ),
          ),
          throwsA(
            isA<SupabaseTransportException>()
                .having(
                  (error) => error.message,
                  'message',
                  'unique key conflict',
                )
                .having((error) => error.code, 'code', '409')
                .having((error) => error.statusCode, 'statusCode', 409),
          ),
        );
      } finally {
        await client.dispose();
      }
    });

    test('maps PostgREST SQLSTATE unique violations to conflict status',
        () async {
      final client = _clientWithHttpClient(
        _StatusCodeClient(
          409,
          message: 'duplicate key value violates unique constraint',
          postgrestCode: '23505',
        ),
      );
      final transport = SupabaseSdkTransport(client);

      try {
        await expectLater(
          transport.selectMany(
            const SupabaseSelectRequest(
              schema: 'public',
              table: 'test_models',
              selectColumns: '*',
              idColumn: 'id',
            ),
          ),
          throwsA(
            isA<SupabaseTransportException>()
                .having(
                  (error) => error.message,
                  'message',
                  'duplicate key value violates unique constraint',
                )
                .having((error) => error.code, 'code', '23505')
                .having((error) => error.statusCode, 'statusCode', 409),
          ),
        );
      } finally {
        await client.dispose();
      }
    });

    test('maps real SDK network errors to NetworkException', () async {
      final cases = <(Object, String)>[
        (TimeoutException('request timed out'), 'request timed out'),
        (const SocketException('connection refused'), 'connection refused'),
        (http.ClientException('connection closed'), 'connection closed'),
      ];

      for (final (error, messagePart) in cases) {
        final client = _clientWithHttpClient(_ThrowingClient(error));
        final adapter = SdkErrorAdapter(client);

        try {
          await expectLater(
            adapter.createOne(TestModel(id: '1', name: 'Created', value: 1)),
            throwsA(
              isA<NetworkException>().having(
                (error) => error.message,
                'message',
                contains(messagePart),
              ),
            ),
          );
        } finally {
          await client.dispose();
        }
      }
    });

    test('applies request headers to real SDK CRUD and select requests',
        () async {
      final httpClient = _RecordingSuccessClient();
      final client = _clientWithHttpClient(httpClient);
      final transport = SupabaseSdkTransport(client);

      try {
        await transport.selectMany(
          const SupabaseSelectRequest(
            schema: 'public',
            table: 'test_models',
            selectColumns: '*',
            idColumn: 'id',
            headers: {'X-Synquill-Request': 'select'},
          ),
        );
        await transport.insert(
          const SupabaseMutationRequest(
            schema: 'public',
            table: 'test_models',
            selectColumns: '*',
            idColumn: 'id',
            values: {'id': '1', 'name': 'Created', 'value': 1},
            headers: {'X-Synquill-Request': 'insert'},
          ),
        );
        await transport.update(
          const SupabaseMutationRequest(
            schema: 'public',
            table: 'test_models',
            selectColumns: '*',
            idColumn: 'id',
            id: '1',
            values: {'name': 'Updated'},
            headers: {'X-Synquill-Request': 'update'},
          ),
        );
        await transport.delete(
          const SupabaseDeleteRequest(
            schema: 'public',
            table: 'test_models',
            idColumn: 'id',
            id: '1',
            headers: {'X-Synquill-Request': 'delete'},
          ),
        );

        expect(
          httpClient.requests
              .map((request) => _headerValue(
                    request.headers,
                    'X-Synquill-Request',
                  ))
              .toList(),
          equals(['select', 'insert', 'update', 'delete']),
        );
      } finally {
        await client.dispose();
      }
    });
  });
}

SupabaseClient _clientWithHttpClient(http.Client client) {
  return SupabaseClient(
    'https://example.supabase.co',
    'test-key',
    httpClient: client,
    accessToken: () async => 'test-key',
  );
}

class _StatusCodeClient extends http.BaseClient {
  _StatusCodeClient(
    this.statusCode, {
    required this.message,
    String? postgrestCode,
  }) : postgrestCode = postgrestCode ?? '$statusCode';

  final int statusCode;
  final String message;
  final String postgrestCode;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonEncode({
      'message': message,
      'code': postgrestCode,
      'details': 'details-$statusCode',
      'hint': null,
    });
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      statusCode,
      request: request,
      headers: {'content-type': 'application/json'},
      reasonPhrase: message,
    );
  }
}

class _ThrowingClient extends http.BaseClient {
  _ThrowingClient(this.error);

  final Object error;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw error;
  }
}

class _RecordingSuccessClient extends http.BaseClient {
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final body = switch (request.method) {
      'GET' => [
          {'id': '1', 'name': 'Selected', 'value': 1},
        ],
      'DELETE' => <Map<String, dynamic>>[],
      _ => {'id': '1', 'name': 'Written', 'value': 2},
    };
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

String? _headerValue(Map<String, String> headers, String name) {
  final expected = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == expected) {
      return entry.value;
    }
  }
  return null;
}
