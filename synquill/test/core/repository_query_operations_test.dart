import 'dart:async';

import 'package:synquill/synquill_core.dart';
import 'package:test/test.dart';

import '../common/mock_test_user_api_adapter.dart';
import '../common/test_models.dart';

void main() {
  test('exported findOneOrFail mixin forwards query arguments', () async {
    final db = TestDatabase(NativeDatabase.memory());
    final repository = _MixinQueryRepository(db, MockApiAdapter());
    const queryParams = QueryParams(
      pagination: PaginationParams(limit: 1, offset: 2),
    );
    const headers = {'Authorization': 'Bearer query'};
    const extra = {'traceId': 'query-forwarding'};

    try {
      final result = await repository.findOneOrFail(
        'query-user',
        loadPolicy: DataLoadPolicy.remoteFirst,
        queryParams: queryParams,
        headers: headers,
        extra: extra,
      );

      expect(result.id, 'query-user');
      expect(repository.capturedLoadPolicy, DataLoadPolicy.remoteFirst);
      expect(repository.capturedQueryParams, same(queryParams));
      expect(repository.capturedHeaders, same(headers));
      expect(repository.capturedExtra, same(extra));
    } finally {
      await repository.close();
      await db.close();
    }
  });
}

class _MixinQueryRepository
    with
        RepositoryLocalOperations<TestUser>,
        RepositoryRemoteOperations<TestUser>,
        RepositoryDeleteOperations<TestUser>,
        RepositoryRealtimeOperations<TestUser>,
        RepositoryQueryOperations<TestUser> {
  _MixinQueryRepository(this.db, this.apiAdapter);

  @override
  final GeneratedDatabase db;

  @override
  final ApiAdapterBase<TestUser> apiAdapter;

  @override
  final Logger log = Logger('MixinQueryRepositoryTest');

  @override
  final StreamController<RepositoryChange<TestUser>> changeController =
      StreamController<RepositoryChange<TestUser>>.broadcast();

  @override
  final RequestQueueManager queueManager = RequestQueueManager();

  @override
  DataLoadPolicy get defaultLoadPolicy => DataLoadPolicy.localOnly;

  @override
  DataSavePolicy get defaultSavePolicy => DataSavePolicy.localFirst;

  @override
  bool get localOnly => false;

  DataLoadPolicy? capturedLoadPolicy;
  QueryParams? capturedQueryParams;
  Map<String, String>? capturedHeaders;
  Map<String, dynamic>? capturedExtra;

  @override
  Future<TestUser?> findOne(
    String id, {
    DataLoadPolicy? loadPolicy,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    capturedLoadPolicy = loadPolicy;
    capturedQueryParams = queryParams;
    capturedHeaders = headers;
    capturedExtra = extra;

    return TestUser(
      id: id,
      name: 'Query User',
      email: 'query@example.test',
    );
  }

  Future<void> close() async {
    await changeController.close();
    await queueManager.dispose();
  }
}
