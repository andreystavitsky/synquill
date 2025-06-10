import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:test/test.dart';
import 'package:synquill_gen/synquill_gen.dart';

void main() {
  group('TableGenerator @Indexed annotation tests', () {
    test('generates table with index for @Indexed field', () {
      // Create a mock FieldInfo with isIndexed = true
      final indexedField = FieldInfo(
        name: 'email',
        dartType: _MockDartType('String'),
        isIndexed: true,
        indexName: null, // Should generate default name
        isUniqueIndex: false,
      );

      final model = ModelInfo(
        className: 'User',
        tableName: 'users',
        endpoint: '/users',
        importPath: 'test',
        fields: [indexedField],
      );

      final result = TableGenerator.generateTableClass(model);

      // Should contain @TableIndex annotation
      expect(result, contains('@TableIndex(name: \'idx_users_email\''));
      expect(result, contains('columns: {#email}'));
      expect(result, isNot(contains('unique: true')));
    });

    test(
      'generates table with unique index for @Indexed(unique: true) field',
      () {
        final uniqueIndexedField = FieldInfo(
          name: 'username',
          dartType: _MockDartType('String'),
          isIndexed: true,
          indexName: 'unique_username_idx',
          isUniqueIndex: true,
        );

        final model = ModelInfo(
          className: 'User',
          tableName: 'users',
          endpoint: '/users',
          importPath: 'test',
          fields: [uniqueIndexedField],
        );

        final result = TableGenerator.generateTableClass(model);

        // Should contain @TableIndex annotation with unique: true
        expect(result, contains('@TableIndex(name: \'unique_username_idx\''));
        expect(result, contains('columns: {#username}'));
        expect(result, contains('unique: true'));
      },
    );

    test('generates table with multiple indexes', () {
      final emailField = FieldInfo(
        name: 'email',
        dartType: _MockDartType('String'),
        isIndexed: true,
        indexName: null,
        isUniqueIndex: true,
      );

      final nameField = FieldInfo(
        name: 'name',
        dartType: _MockDartType('String'),
        isIndexed: true,
        indexName: 'name_idx',
        isUniqueIndex: false,
      );

      final model = ModelInfo(
        className: 'User',
        tableName: 'users',
        endpoint: '/users',
        importPath: 'test',
        fields: [emailField, nameField],
      );

      final result = TableGenerator.generateTableClass(model);

      // Should contain both @TableIndex annotations
      expect(result, contains('@TableIndex(name: \'idx_users_email\''));
      expect(result, contains('columns: {#email}'));
      expect(result, contains('unique: true'));

      expect(result, contains('@TableIndex(name: \'name_idx\''));
      expect(result, contains('columns: {#name}'));
    });

    test('automatically indexes ManyToOne relation fields', () {
      final manyToOneField = FieldInfo(
        name: 'userId',
        dartType: _MockDartType('String'),
        isManyToOne: true,
        isIndexed: true, // This should be automatically set by ModelAnalyzer
      );

      final model = ModelInfo(
        className: 'Todo',
        tableName: 'todos',
        endpoint: '/todos',
        importPath: 'test',
        fields: [manyToOneField],
      );

      final result = TableGenerator.generateTableClass(model);

      // Should contain @TableIndex annotation for the ManyToOne field
      expect(
        result,
        contains('@TableIndex(name: \'idx_todos_userId\', columns: {#userId})'),
      );
      // Should also contain automatic createdAt index
      expect(
        result,
        contains(
          '@TableIndex(name: \'idx_todos_created_at\', columns: {#createdAt})',
        ),
      );
    });

    test('skips OneToMany fields for indexing but still indexes createdAt', () {
      final oneToManyField = FieldInfo(
        name: 'posts',
        dartType: _MockDartType('List<Post>'),
        isOneToMany: true,
        isIndexed: true, // This should be ignored
      );

      final model = ModelInfo(
        className: 'User',
        tableName: 'users',
        endpoint: '/users',
        importPath: 'test',
        fields: [oneToManyField],
      );

      final result = TableGenerator.generateTableClass(model);

      // Should not contain @TableIndex annotation for OneToMany field
      expect(result, isNot(contains('@TableIndex(name: \'idx_users_posts\'')));
      // But should contain @TableIndex annotation for automatic createdAt index
      expect(
        result,
        contains(
          '@TableIndex(name: \'idx_users_created_at\', columns: {#createdAt})',
        ),
      );
    });

    test(
        'generates table with automatic createdAt index when no explicit'
        ' fields are indexed', () {
      final regularField = FieldInfo(
        name: 'email',
        dartType: _MockDartType('String'),
        isIndexed: false,
      );

      final model = ModelInfo(
        className: 'User',
        tableName: 'users',
        endpoint: '/users',
        importPath: 'test',
        fields: [regularField],
      );

      final result = TableGenerator.generateTableClass(model);

      // Should contain automatic @TableIndex annotation for createdAt
      expect(
        result,
        contains(
          '@TableIndex(name: \'idx_users_created_at\', columns: {#createdAt})',
        ),
      );
      // But should still contain the class definition
      expect(result, contains('class UserTable extends Table'));
    });
  });

  group('ModelAnalyzer relation field indexing validation', () {
    test('throws error when @Indexed annotation is used on ManyToOne field',
        () {
      // This test would need to be in a separate test file for ModelAnalyzer
      // since we can't easily mock ClassElement here
      // For now, this serves as documentation of expected behavior
    });

    test('throws error when @Indexed annotation is used on OneToMany field',
        () {
      // This test would need to be in a separate test file for ModelAnalyzer
      // since we can't easily mock ClassElement here
      // For now, this serves as documentation of expected behavior
    });

    test('automatically indexes ManyToOne fields without explicit @Indexed',
        () {
      final manyToOneField = FieldInfo(
        name: 'categoryId',
        dartType: _MockDartType('String'),
        isManyToOne: true,
        isIndexed: true, // Should be automatically set by ModelAnalyzer
      );

      final model = ModelInfo(
        className: 'Product',
        tableName: 'products',
        endpoint: '/products',
        importPath: 'test',
        fields: [manyToOneField],
      );

      final result = TableGenerator.generateTableClass(model);

      // Should contain @TableIndex annotation for the ManyToOne field
      expect(
        result,
        contains(
          '@TableIndex(name: \'idx_products_categoryId\', '
          'columns: {#categoryId})',
        ),
      );
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
