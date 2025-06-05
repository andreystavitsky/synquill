import 'package:synquill/synquill.dart';

import 'package:test/test.dart';

/// Test file to demonstrate compile-time type safety of TypedFilterCondition
void main() {
  group('TypedFilterCondition Type Safety', () {
    // Define test field selectors
    const intField = FieldSelector<int>('value', int);
    const stringField = FieldSelector<String>('name', String);
    const dateTimeField = FieldSelector<DateTime>('createdAt', DateTime);

    test('should enforce correct types for single value operations', () {
      // These should work fine - correct types
      final intEquals = intField.equals(123);
      final stringContains = stringField.contains('test');
      final dateLessThan = dateTimeField.lessThan(DateTime.now());

      expect(intEquals.field.fieldName, equals('value'));
      expect(stringContains.field.fieldName, equals('name'));
      expect(dateLessThan.field.fieldName, equals('createdAt'));
    });

    test('should enforce correct types for list operations', () {
      // These should work fine - correct types
      final intInList = intField.inList([1, 2, 3]);
      final stringNotInList = stringField.notInList(['a', 'b', 'c']);

      expect(intInList.operator, equals(FilterOperator.inList));
      expect(stringNotInList.operator, equals(FilterOperator.notInList));
    });

    test('should work with null operations', () {
      final intIsNull = intField.isNull();
      final stringIsNotNull = stringField.isNotNull();

      expect(intIsNull.operator, equals(FilterOperator.isNull));
      expect(stringIsNotNull.operator, equals(FilterOperator.isNotNull));
    });

    test('should correctly convert to FilterCondition', () {
      final typedCondition = intField.equals(42);
      final filterCondition = typedCondition;

      expect(filterCondition.field.fieldName, equals('value'));
      expect(filterCondition.operator, equals(FilterOperator.equals));
      expect((filterCondition.value as SingleValue).value, equals(42));
    });

    test('should correctly handle list values in conversion', () {
      final typedCondition = stringField.inList(['a', 'b']);
      final filterCondition = typedCondition;

      expect(filterCondition.field.fieldName, equals('name'));
      expect(filterCondition.operator, equals(FilterOperator.inList));
      expect((filterCondition.value as ListValue).values, equals(['a', 'b']));
    });

    test('should correctly handle null values in conversion', () {
      final typedCondition = intField.isNull();
      final filterCondition = typedCondition;

      expect(filterCondition.field.fieldName, equals('value'));
      expect(filterCondition.operator, equals(FilterOperator.isNull));
      //expect(filterCondition.value, isNull);
    });

    test('should have proper equality and hashCode', () {
      final condition1 = intField.equals(123);
      final condition2 = intField.equals(123);
      final condition3 = intField.equals(456);

      expect(condition1, equals(condition2));
      expect(condition1.hashCode, equals(condition2.hashCode));
      expect(condition1, isNot(equals(condition3)));
    });

    test('should have proper toString representation', () {
      final condition = intField.equals(123);
      final stringRepresentation = condition.toString();

      expect(stringRepresentation, contains('FilterCondition'));
      expect(stringRepresentation, contains('value'));
      expect(stringRepresentation, contains('equals'));
      expect(stringRepresentation, contains('123'));
    });
  });

  group('Compile-time Type Safety Demonstration', () {
    // This group contains examples that would cause compile-time errors
    // if type safety is properly implemented.
    //
    // The following code snippets are commented out because they should
    // NOT compile if type safety is working correctly:

    test('demonstrates type safety enforcement', () {
      const intField = FieldSelector<int>('value', int);
      const stringField = FieldSelector<String>('name', String);

      // These should work (correct types):
      final validIntCondition = intField.equals(123);
      final validStringCondition = stringField.equals('test');

      expect(validIntCondition.field.fieldName, equals('value'));
      expect(validStringCondition.field.fieldName, equals('name'));

      // The following would cause compile-time errors if uncommented:

      // ❌ This should NOT compile - passing string to int field:
      // intField.equals('invalid');

      // ❌ This should NOT compile - passing int to string field:
      // stringField.equals( 123);

      // ❌ This should NOT compile - wrong list type:
      // intField.inList( ['a', 'b', 'c']);

      // ❌ This should NOT compile - mixing types in list:
      // intField.inList( [1, 'mixed', 3]);
    });
  });
}
