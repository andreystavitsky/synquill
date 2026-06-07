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

  group('RepositoryGenerator.generateRepositoryClass', () {
    test('caches the generated adapter for adapter-backed repositories', () {
      final code = RepositoryGenerator.generateRepositoryClass(
        _modelWithAdapters([
          _adapter('RestTodoAdapter'),
        ]),
      );

      expect(
        code,
        contains(
          'late final ApiAdapterBase<Todo> _apiAdapter = _TodoAdapter();',
        ),
      );
      expect(
        code,
        contains('''
  ApiAdapterBase<Todo> get apiAdapter {
    return _apiAdapter;
  }'''),
      );
      expect(
        code,
        isNot(
          contains('''
  ApiAdapterBase<Todo> get apiAdapter {
    return _TodoAdapter();
  }'''),
        ),
      );
    });

    test('throws for sync repositories without adapters', () {
      final code = RepositoryGenerator.generateRepositoryClass(
        _modelWithAdapters([]),
      );

      expect(
        code,
        contains("throw UnimplementedError('No adapters specified for Todo');"),
      );
    });

    test('keeps local-only repository apiAdapter unsupported', () {
      final code = RepositoryGenerator.generateRepositoryClass(
        _modelWithAdapters(
          [
            _adapter('RestTodoAdapter'),
          ],
          localOnly: true,
        ),
      );

      expect(
        code,
        contains('API adapter not available for local-only repository Todo.'),
      );
    });

    test('forwards headers from generated remote fetch methods', () {
      final code = RepositoryGenerator.generateRepositoryClass(
        _modelWithAdapters([
          _adapter('RestTodoAdapter'),
        ]),
      );

      expect(
        code,
        contains('''
      final result = await apiAdapter.findOne(
        id,
        queryParams: queryParams,
        headers: headers,
        extra: extra
      );'''),
      );
      expect(
        code,
        contains('''
      final result = await apiAdapter.findAll(
        queryParams: queryParams,
        headers: headers,
        extra: extra
      );'''),
      );
    });

    test('passes custom id JSON key to ID negotiation service', () {
      final code = RepositoryGenerator.generateRepositoryClass(
        _modelWithAdapters(
          [
            _adapter('RestTodoAdapter'),
          ],
          idGeneration: 'server',
          idJsonKey: 'placeId',
        ),
      );

      expect(
        code,
        contains('''
    initializeIdNegotiationService(
      usesServerGeneratedId: true,
      idJsonKey: 'placeId',
    );'''),
      );
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

ModelInfo _modelWithAdapters(
  List<AdapterInfo> adapters, {
  bool localOnly = false,
  String idGeneration = 'client',
  String idJsonKey = 'id',
}) {
  return ModelInfo(
    className: 'Todo',
    tableName: 'todos',
    endpoint: 'todos',
    importPath: 'package:example/todo.dart',
    fields: const [],
    adapters: adapters,
    localOnly: localOnly,
    idGeneration: idGeneration,
    idJsonKey: idJsonKey,
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
