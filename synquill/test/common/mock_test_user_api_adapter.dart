import 'package:synquill/synquill.dart';
import 'in_memory_api_adapter.dart';
import 'test_models.dart';

/// Mock API adapter for testing queue system
class MockApiAdapter extends InMemoryApiAdapter<TestUser> {
  // Specific failure flags for different operations
  bool shouldFailOnCreate = false;
  bool shouldFailOnUpdate = false;
  bool shouldFailOnDelete = false;
  String failureMessage = 'Mock operation failure';

  MockApiAdapter()
      : super(
          type: 'user',
          pluralType: 'users',
          fromJsonFactory: (json) => TestUser(
            id: json['id'] as String,
            name: json['name'] as String,
            email: json['email'] as String,
          ),
          toJsonFactory: (model) => model.toJson(),
        );

  /// Add remote data for testing
  void addRemoteUser(TestUser user) {
    addRemoteModel(user);
  }

  @override
  Future<void> beforeOperation(
    InMemoryApiOperation<TestUser> operation,
  ) async {
    await super.beforeOperation(operation);

    switch (operation.name) {
      case 'createOne' when shouldFailOnCreate:
      case 'updateOne' when shouldFailOnUpdate:
      case 'replaceOne' when shouldFailOnUpdate:
      case 'deleteOne' when shouldFailOnDelete:
        throw SynquillStorageException(failureMessage);
    }
  }
}
