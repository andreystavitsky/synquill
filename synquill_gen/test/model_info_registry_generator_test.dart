import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:synquill_gen/synquill_gen.dart';
import 'package:test/test.dart';

void main() {
  group('ModelInfoRegistryGenerator custom id JSON keys', () {
    test('registers custom id JSON key metadata', () {
      final code = ModelInfoRegistryGenerator.generateModelInfoRegistry([
        ModelInfo(
          className: 'FavoritePlace',
          tableName: 'favorite_places',
          endpoint: '/favorite_places',
          importPath: 'package:example/favorite_place.dart',
          fields: [
            FieldInfo(name: 'id', dartType: _MockDartType('String')),
          ],
          idJsonKey: 'placeId',
        ),
      ]);

      expect(
        code,
        contains(
          'ModelInfoRegistryProvider.registerIdJsonKey('
          "'FavoritePlace', 'placeId');",
        ),
      );
    });

    test('does not register default id JSON key metadata', () {
      final code = ModelInfoRegistryGenerator.generateModelInfoRegistry([
        ModelInfo(
          className: 'User',
          tableName: 'users',
          endpoint: '/users',
          importPath: 'package:example/user.dart',
          fields: [
            FieldInfo(name: 'id', dartType: _MockDartType('String')),
          ],
        ),
      ]);

      expect(code, isNot(contains('registerIdJsonKey')));
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
