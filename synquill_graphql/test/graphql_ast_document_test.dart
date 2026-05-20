import 'package:gql/ast.dart' as gql_ast;
import 'package:synquill/synquill.dart';
import 'package:test/test.dart';

import 'helpers/test_graphql_adapter.dart';

class AstTestingAdapter extends TestGraphQLAdapter {
  gql_ast.DocumentNode parseDocument(String operation) {
    return documentFromOperation(operation);
  }

  gql_ast.OperationDefinitionNode resolveOperation(
    gql_ast.DocumentNode document, {
    String? operationName,
  }) {
    return resolveGraphQLOperation(document, operationName: operationName);
  }
}

void main() {
  group('GraphQL AST document handling', () {
    late AstTestingAdapter adapter;

    setUp(() {
      adapter = AstTestingAdapter();
    });

    test('parses valid query, mutation, subscription, and anonymous query', () {
      final query = adapter.resolveOperation(
        adapter.parseDocument('query Ping { ping }'),
      );
      final mutation = adapter.resolveOperation(
        adapter.parseDocument('mutation Save { save }'),
      );
      final subscription = adapter.resolveOperation(
        adapter.parseDocument('subscription Watch { changed }'),
      );
      final anonymous = adapter.resolveOperation(
        adapter.parseDocument('{ viewer { id } }'),
      );

      expect(query.type, equals(gql_ast.OperationType.query));
      expect(mutation.type, equals(gql_ast.OperationType.mutation));
      expect(subscription.type, equals(gql_ast.OperationType.subscription));
      expect(anonymous.type, equals(gql_ast.OperationType.query));
    });

    test('wraps invalid GraphQL syntax in ApiException', () {
      expect(
        () => adapter.parseDocument('query Broken {'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('Invalid GraphQL document'),
          ),
        ),
      );
    });

    test('resolves named operation by operationName', () {
      final document = adapter.parseDocument('''
query First { first }
query Second { second }
''');

      final operation = adapter.resolveOperation(
        document,
        operationName: 'Second',
      );

      expect(operation.name?.value, equals('Second'));
      expect(operation.type, equals(gql_ast.OperationType.query));
    });

    test('throws for multiple operations without operationName', () {
      final document = adapter.parseDocument('''
query First { first }
query Second { second }
''');

      expect(
        () => adapter.resolveOperation(document),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('operationName is required'),
          ),
        ),
      );
    });

    test('throws for missing operationName', () {
      final document = adapter.parseDocument('query First { first }');

      expect(
        () => adapter.resolveOperation(document, operationName: 'Missing'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('operation "Missing" was not found'),
          ),
        ),
      );
    });

    test('throws for fragment-only document', () {
      final document = adapter.parseDocument(
        'fragment ModelFields on TestModel { id name value }',
      );

      expect(
        () => adapter.resolveOperation(document),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('expected an executable operation'),
          ),
        ),
      );
    });

    test('reuses cached parse result for exact operation strings', () {
      const operation = 'query Cached { cached }';

      final first = adapter.parseDocument(operation);
      final second = adapter.parseDocument(operation);

      expect(identical(first, second), isTrue);
    });
  });
}
