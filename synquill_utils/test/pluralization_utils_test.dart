import 'package:test/test.dart';
import 'package:synquill_utils/src/pluralization_utils.dart';

void main() {
  group('PluralizationUtils', () {
    group('capitalizedCamelCasePlural', () {
      test('returns empty string for empty input', () {
        expect(PluralizationUtils.toPascalCasePlural(''), '');
      });
      test('capitalizes and pluralizes simple class', () {
        expect(PluralizationUtils.toPascalCasePlural('Category'), 'Categories');
        expect(PluralizationUtils.toPascalCasePlural('Todo'), 'Todos');
      });
      test('handles PascalCase class', () {
        expect(PluralizationUtils.toPascalCasePlural('PlainModelJson'),
            'PlainModelJsons');
      });
      test('handles irregulars', () {
        expect(PluralizationUtils.toPascalCasePlural('Child'), 'Children');
        expect(PluralizationUtils.toPascalCasePlural('Foot'), 'Feet');
        expect(PluralizationUtils.toPascalCasePlural('Tooth'), 'Teeth');
        expect(PluralizationUtils.toPascalCasePlural('Mouse'), 'Mice');
        expect(PluralizationUtils.toPascalCasePlural('Man'), 'Men');
        expect(PluralizationUtils.toPascalCasePlural('Woman'), 'Women');
      });
    });

    group('toCamelCasePlural', () {
      test('returns empty string for empty input', () {
        expect(PluralizationUtils.toCamelCasePlural(''), '');
      });
      test('pluralizes camelCase', () {
        expect(PluralizationUtils.toCamelCasePlural('category'), 'categories');
        expect(PluralizationUtils.toCamelCasePlural('plainModelJson'),
            'plainModelJsons');
      });
      test('handles irregulars', () {
        expect(PluralizationUtils.toCamelCasePlural('child'), 'children');
        expect(PluralizationUtils.toCamelCasePlural('foot'), 'feet');
        expect(PluralizationUtils.toCamelCasePlural('tooth'), 'teeth');
        expect(PluralizationUtils.toCamelCasePlural('mouse'), 'mice');
        expect(PluralizationUtils.toCamelCasePlural('man'), 'men');
        expect(PluralizationUtils.toCamelCasePlural('woman'), 'women');
      });
    });

    group('toSnakeCasePlural', () {
      test('returns empty string for empty input', () {
        expect(PluralizationUtils.toSnakeCasePlural(''), '');
      });
      test('pluralizes snake_case', () {
        expect(PluralizationUtils.toSnakeCasePlural('Category'), 'categories');
        expect(PluralizationUtils.toSnakeCasePlural('PlainModelJson'),
            'plain_model_jsons');
      });
      test('handles irregulars', () {
        expect(PluralizationUtils.toSnakeCasePlural('Child'), 'children');
        expect(PluralizationUtils.toSnakeCasePlural('Foot'), 'feet');
        expect(PluralizationUtils.toSnakeCasePlural('Tooth'), 'teeth');
        expect(PluralizationUtils.toSnakeCasePlural('Mouse'), 'mice');
        expect(PluralizationUtils.toSnakeCasePlural('Man'), 'men');
        expect(PluralizationUtils.toSnakeCasePlural('Woman'), 'women');
      });
    });

    group('toSnakeCase', () {
      test('returns empty string for empty input', () {
        expect(PluralizationUtils.toSnakeCase(''), '');
      });
      test('converts PascalCase to snake_case', () {
        expect(PluralizationUtils.toSnakeCase('PlainModelJson'),
            'plain_model_json');
      });
      test('converts camelCase to snake_case', () {
        expect(PluralizationUtils.toSnakeCase('plainModelJson'),
            'plain_model_json');
      });
      test('handles single word', () {
        expect(PluralizationUtils.toSnakeCase('Category'), 'category');
      });
    });

    group('pluralize', () {
      test('returns empty string for empty input', () {
        expect(PluralizationUtils.pluralize(''), '');
      });
      test('handles y-ending', () {
        expect(PluralizationUtils.pluralize('category'), 'categories');
        expect(PluralizationUtils.pluralize('boy'), 'boys');
      });
      test('handles sh/ch/x/z/s endings', () {
        expect(PluralizationUtils.pluralize('box'), 'boxes');
        expect(PluralizationUtils.pluralize('brush'), 'brushes');
        expect(PluralizationUtils.pluralize('church'), 'churches');
        expect(PluralizationUtils.pluralize('gas'), 'gases');
      });
      test('handles f/fe to ves', () {
        expect(PluralizationUtils.pluralize('wolf'), 'wolves');
        expect(PluralizationUtils.pluralize('knife'), 'knives');
        expect(PluralizationUtils.pluralize('leaf'), 'leaves');
      });
      test('handles o-ending (traditional and modern)', () {
        expect(PluralizationUtils.pluralize('hero'), 'heroes');
        expect(PluralizationUtils.pluralize('photo'), 'photos');
        expect(PluralizationUtils.pluralize('piano'), 'pianos');
        expect(PluralizationUtils.pluralize('potato'), 'potatoes');
      });
      test('handles irregulars', () {
        expect(PluralizationUtils.pluralize('child'), 'children');
        expect(PluralizationUtils.pluralize('foot'), 'feet');
        expect(PluralizationUtils.pluralize('tooth'), 'teeth');
        expect(PluralizationUtils.pluralize('mouse'), 'mice');
        expect(PluralizationUtils.pluralize('man'), 'men');
        expect(PluralizationUtils.pluralize('woman'), 'women');
        expect(PluralizationUtils.pluralize('todo'), 'todos');
      });
      test('default: just adds s', () {
        expect(PluralizationUtils.pluralize('car'), 'cars');
        expect(PluralizationUtils.pluralize('apple'), 'apples');
      });
    });

    group('capitalize', () {
      test('capitalizes first letter', () {
        expect(PluralizationUtils.capitalize('test'), 'Test');
        expect(PluralizationUtils.capitalize('tEST'), 'TEST');
      });
    });
  });
}
