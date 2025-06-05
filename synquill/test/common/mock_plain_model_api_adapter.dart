// ignore_for_file: avoid_relative_lib_imports
import 'package:synquill/synquill.dart';

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:synquill/src/test_models/index.dart';

/// Mock API adapter for PlainModel testing
class MockPlainModelApiAdapter extends ApiAdapterBase<PlainModel> {
  final Map<String, PlainModel> _remoteData = {};
  final List<Map<String, dynamic>> _operationLog = [];
  bool _shouldFailNext = false;
  String? _nextFailureReason;
  bool _networkError = false;

  // New fields for 404 testing
  bool _updateReturns404 = false;
  bool _createReturns404 = false;

  @override
  Uri get baseUrl => Uri.parse('https://test.example.com/api/v1/');

  @override
  String get type => 'plainmodel';

  @override
  String get pluralType => 'plainmodels';

  /// Get operation log for testing
  List<Map<String, dynamic>> getOperationLog() =>
      List.unmodifiable(_operationLog);

  /// Get remote data for debugging
  Map<String, PlainModel> get remoteData => Map.unmodifiable(_remoteData);

  /// Add remote data for testing
  void addRemoteModel(PlainModel model) {
    _remoteData[model.id] = model;
  }

  /// Clear remote data
  void clearRemote() {
    _remoteData.clear();
  }

  /// Clear remote data (alias for clearRemote)
  void clearRemoteData() {
    _remoteData.clear();
  }

  /// Clear operation log
  void clearLog() {
    _operationLog.clear();
  }

  /// Clear operation log (alias for clearLog)
  void clearOperationLog() {
    _operationLog.clear();
  }

  /// Force next operation to fail
  void setNextOperationToFail([String? reason]) {
    _shouldFailNext = true;
    _nextFailureReason = reason ?? 'Mock failure';
  }

  /// Simulate network error
  void setNetworkError(bool error) {
    _networkError = error;
  }

  /// Set update operations to return 404
  void setUpdateToReturn404() {
    _updateReturns404 = true;
  }

  /// Set both update and create operations to return 404
  void setBothUpdateAndCreateToReturn404() {
    _updateReturns404 = true;
    _createReturns404 = true;
  }

  /// Reset 404 settings
  void reset404Settings() {
    _updateReturns404 = false;
    _createReturns404 = false;
  }

  void _checkShouldFail() {
    if (_networkError) {
      throw DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionError,
        message: 'Network error',
      );
    }
    if (_shouldFailNext) {
      _shouldFailNext = false;
      final reason = _nextFailureReason ?? 'Mock failure';
      _nextFailureReason = null;
      throw SynquillStorageException(reason);
    }
  }

  void _checkUpdate404() {
    if (_updateReturns404) {
      throw ApiExceptionNotFound(
        'test-model-id',
        stackTrace: StackTrace.current,
      );
    }
  }

  void _checkCreate404() {
    if (_createReturns404) {
      throw ApiExceptionNotFound(
        'test-model-id',
        stackTrace: StackTrace.current,
      );
    }
  }

  @override
  PlainModel fromJson(Map<String, dynamic> json) {
    return PlainModel.fromJson(json);
  }

  @override
  Map<String, dynamic> toJson(PlainModel model) {
    return model.toJson();
  }

  @override
  Future<PlainModel?> findOne(
    String id, {
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add({
      'operation': 'findOne',
      'id': id,
      'timestamp': DateTime.now().toIso8601String(),
    });
    _checkShouldFail();
    await Future.delayed(
      const Duration(milliseconds: 10),
    ); // Simulate API delay
    return _remoteData[id];
  }

  @override
  Future<List<PlainModel>> findAll({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add({
      'operation': 'findAll',
      'timestamp': DateTime.now().toIso8601String(),
    });
    _checkShouldFail();
    await Future.delayed(
      const Duration(milliseconds: 10),
    ); // Simulate API delay
    return _remoteData.values.toList();
  }

  @override
  Future<PlainModel?> createOne(
    PlainModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add({
      'operation': 'createOne',
      'id': model.id,
      'timestamp': DateTime.now().toIso8601String(),
    });
    _checkShouldFail();
    _checkCreate404();
    await Future.delayed(
      const Duration(milliseconds: 10),
    ); // Simulate API delay
    _remoteData[model.id] = model;
    return model;
  }

  @override
  Future<PlainModel?> updateOne(
    PlainModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add({
      'operation': 'updateOne',
      'id': model.id,
      'timestamp': DateTime.now().toIso8601String(),
    });
    _checkShouldFail();
    _checkUpdate404();
    await Future.delayed(
      const Duration(milliseconds: 10),
    ); // Simulate API delay
    _remoteData[model.id] = model;
    return model;
  }

  @override
  Future<PlainModel?> replaceOne(
    PlainModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add({
      'operation': 'replaceOne',
      'id': model.id,
      'timestamp': DateTime.now().toIso8601String(),
    });
    _checkShouldFail();
    await Future.delayed(
      const Duration(milliseconds: 10),
    ); // Simulate API delay
    _remoteData[model.id] = model;
    return model;
  }

  @override
  Future<void> deleteOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add({
      'operation': 'deleteOne',
      'id': id,
      'timestamp': DateTime.now().toIso8601String(),
    });
    _checkShouldFail();
    await Future.delayed(
      const Duration(milliseconds: 10),
    ); // Simulate API delay
    _remoteData.remove(id);
  }
}
