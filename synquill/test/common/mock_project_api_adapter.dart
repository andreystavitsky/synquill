// ignore_for_file: avoid_relative_lib_imports

import '../support/test_models/index.dart';
import 'in_memory_api_adapter.dart';

/// Mock API adapter for Project testing
class MockProjectApiAdapter extends InMemoryApiAdapter<Project> {
  MockProjectApiAdapter()
      : super(
          type: 'project',
          pluralType: 'projects',
          fromJsonFactory: Project.fromJson,
          toJsonFactory: (model) => model.toJson(),
        );
}
