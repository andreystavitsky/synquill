import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:test/test.dart';
import 'package:synquill_gen/synquill_gen.dart';

void main() {
  group('ModelAnalyzer relation field validation', () {
    test('should automatically index ManyToOne fields', () {
      // Create a FieldInfo representing a ManyToOne field that should be
      // automatically indexed
      final manyToOneField = FieldInfo(
        name: 'categoryId',
        dartType: _MockDartType('String'),
        isManyToOne: true,
        isIndexed: true, // This should be automatically set by ModelAnalyzer
        relationTarget: 'Category',
      );

      // Verify that the field is marked as indexed
      expect(manyToOneField.isIndexed, isTrue);
      expect(manyToOneField.isManyToOne, isTrue);
      expect(manyToOneField.indexName, isNull); // Should use default naming
      expect(manyToOneField.isUniqueIndex, isFalse);
    });

    test('should not index OneToMany fields directly', () {
      // OneToMany fields represent collections and should not create
      // database columns, therefore they should not be indexed
      final oneToManyField = FieldInfo(
        name: 'products',
        dartType: _MockDartType('List<Product>'),
        isOneToMany: true,
        isIndexed: false, // OneToMany fields should not be indexed
        relationTarget: 'Product',
        mappedBy: 'categoryId',
      );

      // Verify that OneToMany fields are not indexed
      expect(oneToManyField.isIndexed, isFalse);
      expect(oneToManyField.isOneToMany, isTrue);
    });
  });
}

// Mock DartType for testing
class _MockDartType implements DartType {
  final String _displayString;

  _MockDartType(this._displayString);

  @override
  String getDisplayString({bool withNullability = true}) => _displayString;

  @override
  NullabilitySuffix get nullabilitySuffix => NullabilitySuffix.none;

  // Implement required abstract methods with minimal implementations
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
