// ignore_for_file: avoid_relative_lib_imports

import 'dart:async';
import 'package:synquill/src/test_models/index.dart';

/// Mock API adapter for Project testing
class MockProjectApiAdapter extends ApiAdapterBase<Project> {
  final Map<String, Project> _remoteData = {};
  final List<String> _operationLog = [];
  bool _shouldFailNext = false;
  String? _nextFailureReason;
  bool _networkError = false;

  @override
  Uri get baseUrl => Uri.parse('https://test.example.com/api/v1/');

  @override
  String get type => 'project';

  @override
  String get pluralType => 'projects';

  /// Get operation log for testing
  List<String> get operationLog => List.unmodifiable(_operationLog);

  /// Add remote data for testing
  void addRemoteModel(Project model) {
    _remoteData[model.id] = model;
  }

  /// Clear remote data
  void clearRemote() {
    _remoteData.clear();
  }

  /// Clear operation log
  void clearLog() {
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

  @override
  Project fromJson(Map<String, dynamic> json) {
    return Project.fromJson(json);
  }

  @override
  Map<String, dynamic> toJson(Project model) {
    return model.toJson();
  }

  @override
  Future<Project?> findOne(
    String id, {
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('findOne($id)');
    _checkShouldFail();
    await Future.delayed(const Duration(milliseconds: 10));
    return _remoteData[id];
  }

  @override
  Future<List<Project>> findAll({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('findAll()');
    _checkShouldFail();
    await Future.delayed(const Duration(milliseconds: 10));
    return _remoteData.values.toList();
  }

  @override
  Future<Project?> createOne(
    Project model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('createOne(${model.id})');
    _checkShouldFail();
    await Future.delayed(const Duration(milliseconds: 10));
    _remoteData[model.id] = model;
    return model;
  }

  @override
  Future<Project?> updateOne(
    Project model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('updateOne(${model.id})');
    _checkShouldFail();
    await Future.delayed(const Duration(milliseconds: 10));
    _remoteData[model.id] = model;
    return model;
  }

  @override
  Future<Project?> replaceOne(
    Project model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('replaceOne(${model.id})');
    _checkShouldFail();
    await Future.delayed(const Duration(milliseconds: 10));
    _remoteData[model.id] = model;
    return model;
  }

  @override
  Future<void> deleteOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('deleteOne($id)');
    _checkShouldFail();
    await Future.delayed(const Duration(milliseconds: 10));
    _remoteData.remove(id);
  }
}
