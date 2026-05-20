import 'package:synquill_graphql/synquill_graphql.dart';
import 'test_model.dart';

/// A concrete implementation of [GraphQLApiAdapter] for unit testing.
class TestGraphQLAdapter extends GraphQLApiAdapter<TestModel> {
  @override
  Uri get graphqlEndpoint => Uri.parse('https://api.test.com/graphql');

  @override
  String get findOneQuery =>
      r'query GetTestModel($id: ID!) { testModel(id: $id) { id name value } }';

  @override
  String get findAllQuery =>
      r'query GetTestModels { testModels { id name value } }';

  @override
  String get createMutation =>
      r'mutation CreateTestModel($input: CreateInput!) { '
      r'createTestModel(input: $input) { id name value } }';

  @override
  String get updateMutation =>
      r'mutation UpdateTestModel($id: ID!, $input: UpdateInput!) { '
      r'updateTestModel(id: $id, input: $input) { id name value } }';

  @override
  String get deleteMutation =>
      r'mutation DeleteTestModel($id: ID!) { deleteTestModel(id: $id) { id } }';

  @override
  TestModel fromJson(Map<String, dynamic> json) => TestModel.fromJsonData(json);

  @override
  Map<String, dynamic> toJson(TestModel model) => model.toJson();
}
