// ignore_for_file: avoid_relative_lib_imports
import '../support/test_models/index.dart';

import 'in_memory_api_adapter.dart';

/// Mock API adapter for Category testing
class MockCategoryApiAdapter extends InMemoryApiAdapter<Category> {
  MockCategoryApiAdapter()
      : super(
          type: 'category',
          pluralType: 'categories',
          fromJsonFactory: Category.fromJson,
          toJsonFactory: (model) => model.toJson(),
        );
}
