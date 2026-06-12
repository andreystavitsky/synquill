// ignore_for_file: implementation_imports

import 'package:analyzer/src/dart/element/type.dart';
import 'package:synquill_gen/synquill_gen.dart';
import 'package:test/test.dart';

void main() {
  group('FileAggregator.generateAggregateFile', () {
    test('imports synquill_graphql when adapter requires GraphQLApiAdapter',
        () {
      final content = FileAggregator.generateAggregateFile(
        [
          _modelWithAdapters([
            _adapter(
              'GraphqlPostApiAdapter',
              superclassConstraints: const ['GraphQLApiAdapter'],
            ),
          ]),
        ],
        'synquill_example',
      );

      expect(
        content,
        contains(
          "import 'package:synquill_graphql/synquill_graphql.dart';",
        ),
      );
    });

    test('does not import synquill_graphql for REST-only adapters', () {
      final content = FileAggregator.generateAggregateFile(
        [
          _modelWithAdapters([
            _adapter('JsonApiAdapter'),
          ]),
        ],
        'synquill_example',
      );

      expect(content, isNot(contains('package:synquill_graphql')));
    });

    test('imports narrow Synquill barrels for generated aggregate files', () {
      final content = FileAggregator.generateAggregateFile(
        [
          _modelWithAdapters([
            _adapter('JsonApiAdapter'),
          ]),
        ],
        'synquill_example',
      );

      expect(
        content,
        contains("import 'package:synquill/synquill_contracts.dart';"),
      );
      expect(
        content,
        contains("import 'package:synquill/synquill_rest.dart';"),
      );
      expect(
        content,
        contains("import 'package:synquill/synquill_drift.dart' show "),
      );
      expect(
        content,
        isNot(contains("import 'package:synquill/synquill.dart';")),
      );
    });

    test('imports drift barrel for generated database files', () {
      final content = FileAggregator.generateDatabaseFile([
        _modelWithAdapters([
          _adapter('JsonApiAdapter'),
        ]),
      ]);

      expect(
        content,
        contains("import 'package:synquill/synquill_drift.dart';"),
      );
      expect(
        content,
        isNot(contains("import 'package:synquill/synquill_core.dart';")),
      );
    });
  });
}

ModelInfo _modelWithAdapters(List<AdapterInfo> adapters) {
  return ModelInfo(
    className: 'GraphqlPost',
    tableName: 'graphql_posts',
    endpoint: '/graphql_posts',
    importPath: 'package:synquill_example/models/graphql_post.dart',
    fields: const [],
    adapters: adapters,
  );
}

AdapterInfo _adapter(
  String name, {
  List<String> superclassConstraints = const [],
}) {
  return AdapterInfo(
    adapterName: name,
    importPath: 'package:synquill_example/models/graphql_post.dart',
    dartType: DynamicTypeImpl.instance,
    isGeneric: false,
    superclassConstraints: superclassConstraints,
  );
}
