// ignore_for_file: avoid_relative_lib_imports, avoid_print

import 'dart:async';

import 'package:synquill/synquill.generated.dart';
import 'package:synquill/synquill_core.dart';

// Import generated models and repositories from example
import 'package:synquill/src/test_models/index.dart';

import '../common/mock_plain_model_api_adapter.dart';

/// Custom test repository that uses the mock API adapter
class TestPlainModelRepository extends SynquillRepositoryBase<PlainModel>
    with RepositoryHelpersMixin<PlainModel> {
  final MockPlainModelApiAdapter _mockAdapter;
  late final PlainModelDao _dao;

  /// Creates a new PlainModel repository instance
  ///
  /// [db] The database instance to use for data operations
  TestPlainModelRepository(super.db, this._mockAdapter) {
    _dao = PlainModelDao(db as SynquillDatabase);
  }

  @override
  ApiAdapterBase<PlainModel> get apiAdapter => _mockAdapter;

  @override
  Future<PlainModel?> fetchFromRemote(
    String id, {
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return await _mockAdapter.findOne(id, queryParams: queryParams);
  }

  @override
  Future<List<PlainModel>> fetchAllFromRemote({
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return await _mockAdapter.findAll(queryParams: queryParams);
  }

  @override
  DatabaseAccessor<GeneratedDatabase> get dao => _dao;
}
