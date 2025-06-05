import 'dart:async';
import 'package:dio/dio.dart';
import 'package:synquill/synquill.dart';
import 'test_models.dart';

/// Mock API adapter for testing queue system
class MockApiAdapter extends ApiAdapterBase<TestUser> {
  final Map<String, TestUser> _remoteData = {};
  final List<String> _operationLog = [];
  bool _shouldFailNext = false;
  String? _nextFailureReason;
  bool _networkError = false;

  // Specific failure flags for different operations
  bool shouldFailOnCreate = false;
  bool shouldFailOnUpdate = false;
  bool shouldFailOnDelete = false;
  String failureMessage = 'Mock operation failure';

  @override
  Uri get baseUrl => Uri.parse('https://test.example.com/api/v1/');

  @override
  String get type => 'user';

  @override
  String get pluralType => 'users';

  /// Get operation log for testing
  List<String> get operationLog => List.unmodifiable(_operationLog);

  /// Add remote data for testing
  void addRemoteUser(TestUser user) {
    _remoteData[user.id] = user;
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
  TestUser fromJson(Map<String, dynamic> json) {
    return TestUser(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson(TestUser model) {
    return model.toJson();
  }

  @override
  Future<TestUser?> findOne(
    String id, {
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('findOne($id)');
    _checkShouldFail();
    await Future.delayed(
      const Duration(milliseconds: 10),
    ); // Simulate API delay
    return _remoteData[id];
  }

  @override
  Future<List<TestUser>> findAll({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('findAll()');
    _checkShouldFail();
    await Future.delayed(
      const Duration(milliseconds: 10),
    ); // Simulate API delay
    return _remoteData.values.toList();
  }

  @override
  Future<TestUser?> createOne(
    TestUser model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('createOne(${model.id})');
    _checkShouldFail();
    if (shouldFailOnCreate) {
      throw SynquillStorageException(failureMessage);
    }
    await Future.delayed(
      const Duration(milliseconds: 10),
    ); // Simulate API delay
    _remoteData[model.id] = model;
    return model;
  }

  @override
  Future<TestUser?> updateOne(
    TestUser model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('updateOne(${model.id})');
    _checkShouldFail();
    if (shouldFailOnUpdate) {
      throw SynquillStorageException(failureMessage);
    }
    await Future.delayed(
      const Duration(milliseconds: 10),
    ); // Simulate API delay
    _remoteData[model.id] = model;
    return model;
  }

  @override
  Future<TestUser?> replaceOne(
    TestUser model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('replaceOne(${model.id})');
    _checkShouldFail();
    if (shouldFailOnUpdate) {
      // Use update flag for replace as well
      throw SynquillStorageException(failureMessage);
    }
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
    _operationLog.add('deleteOne($id)');
    _checkShouldFail();
    if (shouldFailOnDelete) {
      throw SynquillStorageException(failureMessage);
    }
    await Future.delayed(
      const Duration(milliseconds: 10),
    ); // Simulate API delay
    _remoteData.remove(id);
  }
}
