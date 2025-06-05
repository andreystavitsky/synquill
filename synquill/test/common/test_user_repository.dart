import 'package:synquill/synquill.dart';
import 'test_models.dart';
import 'mock_test_user_api_adapter.dart';

/// Test repository for queue system integration testing
class TestUserRepository extends SynquillRepositoryBase<TestUser> {
  final MockApiAdapter _mockAdapter;
  static final Map<String, TestUser> _localData = {};

  TestUserRepository(super.db, this._mockAdapter);

  @override
  ApiAdapterBase<TestUser> get apiAdapter => _mockAdapter;

  // Use parent class implementations that include localThenRemote logic

  @override
  Stream<TestUser?> watchOne(
    String id, {
    DataLoadPolicy? loadPolicy,
    QueryParams? queryParams,
  }) {
    return watchFromLocal(id, queryParams: queryParams);
  }

  @override
  Stream<List<TestUser>> watchAll({QueryParams? queryParams}) {
    return watchAllFromLocal(queryParams: queryParams);
  }

  @override
  Future<TestUser> save(
    TestUser model, {
    DataSavePolicy? savePolicy,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    // Use the base class implementation which includes queue integration
    return await super.save(model, savePolicy: savePolicy);
  }

  @override
  Future<void> delete(
    String id, {
    DataSavePolicy? savePolicy,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    // Use the base class implementation which includes queue integration
    return await super.delete(id, savePolicy: savePolicy);
  }

  @override
  Future<void> removeFromLocalIfExists(String id) async {
    _localData.remove(id);
  }

  @override
  Future<TestUser?> fetchFromLocal(
    String id, {
    QueryParams? queryParams,
  }) async {
    return _localData[id];
  }

  @override
  Future<List<TestUser>> fetchAllFromLocal({QueryParams? queryParams}) async {
    return _localData.values.toList();
  }

  @override
  Stream<TestUser?> watchFromLocal(String id, {QueryParams? queryParams}) {
    return Stream.value(_localData[id]);
  }

  @override
  Stream<List<TestUser>> watchAllFromLocal({QueryParams? queryParams}) {
    return Stream.value(_localData.values.toList());
  }

  @override
  Future<TestUser?> fetchFromRemote(
    String id, {
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    try {
      final result = await apiAdapter.findOne(
        id,
        queryParams: queryParams,
        extra: extra,
        headers: headers,
      );
      return result;
    } on ApiExceptionNotFound {
      // Rethrow so the caller can handle
      rethrow;
    } on ApiExceptionGone {
      // Rethrow so the caller can handle
      rethrow;
    } catch (e) {
      // Log and rethrow other errors
      rethrow;
    }
  }

  @override
  Future<List<TestUser>> fetchAllFromRemote({
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
    Map<String, String>? headers,
  }) async {
    try {
      final result = await apiAdapter.findAll(
        queryParams: queryParams,
        extra: extra,
        headers: headers,
      );
      return result;
    } catch (e) {
      // Log and rethrow errors
      rethrow;
    }
  }

  @override
  Future<void> saveToLocal(TestUser item, {Map<String, dynamic>? extra}) async {
    _localData[item.id] = item;
  }

  /// Add a user to local storage for testing
  void addLocalUser(TestUser user) {
    _localData[user.id] = user;
  }

  /// Clear all local data
  static void clearLocal() {
    _localData.clear();
  }

  /// Get local data count
  int get localCount => _localData.length;
}
