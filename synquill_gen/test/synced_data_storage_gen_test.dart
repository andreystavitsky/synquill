import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:synquill_gen/synquill_gen.dart';
import 'package:test/test.dart';

void main() {
  group('synced_data_storage_gen library tests', () {
    test('exported generators produce repository and table code', () {
      final model = ModelInfo(
        className: 'Todo',
        tableName: 'todos',
        endpoint: '/todos',
        importPath: 'package:example/todo.dart',
        fields: [
          FieldInfo(
            name: 'title',
            dartType: _MockDartType('String'),
          ),
        ],
      );

      final tableCode = TableGenerator.generateTableClass(model);
      final repositoryCode = RepositoryGenerator.generateRepositoryClass(model);

      expect(tableCode, contains('class TodoTable extends Table'));
      expect(tableCode, contains('TextColumn get title => text()();'));
      expect(repositoryCode, contains('class TodoRepository'));
      expect(
        repositoryCode,
        contains("throw UnimplementedError('No adapters specified for Todo');"),
      );
    });
  });
}

class _MockDartType implements DartType {
  final String _displayString;

  _MockDartType(this._displayString);

  @override
  String getDisplayString({bool withNullability = true}) => _displayString;

  @override
  NullabilitySuffix get nullabilitySuffix => NullabilitySuffix.none;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
