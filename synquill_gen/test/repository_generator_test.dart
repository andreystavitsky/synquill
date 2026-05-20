// ignore_for_file: implementation_imports

import 'package:analyzer/src/dart/element/type.dart';
import 'package:synquill_gen/synquill_gen.dart';
import 'package:test/test.dart';

void main() {
  group('RepositoryGenerator.generateAdapterClass', () {
    test('uses BasicApiAdapter when no GraphQL superclass constraint exists',
        () {
      final code = RepositoryGenerator.generateAdapterClass(
        _modelWithAdapters([
          _adapter('RestTodoAdapter'),
        ]),
      );

      expect(code, contains('extends BasicApiAdapter<Todo>'));
      expect(code, isNot(contains('extends GraphQLApiAdapter<Todo>')));
    });

    test('uses GraphQLApiAdapter when adapter has GraphQL constraint', () {
      final code = RepositoryGenerator.generateAdapterClass(
        _modelWithAdapters([
          _adapter(
            'TodoGraphQLAdapter',
            superclassConstraints: const ['GraphQLApiAdapter'],
          ),
        ]),
      );

      expect(code, contains('extends GraphQLApiAdapter<Todo>'));
      expect(code, contains('with TodoGraphQLAdapter'));
    });

    test('uses GraphQLApiAdapter when one of several adapters requires it', () {
      final code = RepositoryGenerator.generateAdapterClass(
        _modelWithAdapters([
          _adapter('AuditingAdapter'),
          _adapter(
            'TodoGraphQLAdapter',
            superclassConstraints: const ['GraphQLApiAdapter'],
          ),
        ]),
      );

      expect(code, contains('extends GraphQLApiAdapter<Todo>'));
      expect(code, contains('with AuditingAdapter, TodoGraphQLAdapter'));
    });

    test('preserves generic adapter type arguments', () {
      final code = RepositoryGenerator.generateAdapterClass(
        _modelWithAdapters([
          _adapter(
            'GenericGraphQLAdapter',
            isGeneric: true,
            superclassConstraints: const ['GraphQLApiAdapter'],
          ),
        ]),
      );

      expect(code, contains('extends GraphQLApiAdapter<Todo>'));
      expect(code, contains('with GenericGraphQLAdapter<Todo>'));
    });
  });

  group('AdapterInfo', () {
    test('defaults superclass constraints to empty list', () {
      final adapter = _adapter('RestTodoAdapter');

      expect(adapter.superclassConstraints, isEmpty);
    });

    test('equality includes superclass constraints', () {
      final rest = _adapter('TodoAdapter');
      final graphql = _adapter(
        'TodoAdapter',
        superclassConstraints: const ['GraphQLApiAdapter'],
      );

      expect(rest, isNot(equals(graphql)));
    });
  });
}

ModelInfo _modelWithAdapters(List<AdapterInfo> adapters) {
  return ModelInfo(
    className: 'Todo',
    tableName: 'todos',
    endpoint: 'todos',
    importPath: 'package:example/todo.dart',
    fields: const [],
    adapters: adapters,
  );
}

AdapterInfo _adapter(
  String name, {
  bool isGeneric = false,
  List<String> superclassConstraints = const [],
}) {
  return AdapterInfo(
    adapterName: name,
    importPath: 'package:example/$name.dart',
    dartType: DynamicTypeImpl.instance,
    isGeneric: isGeneric,
    superclassConstraints: superclassConstraints,
  );
}
