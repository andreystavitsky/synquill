import 'package:synquill/synquill.dart';

import 'package:test/test.dart';

/// Tests runtime behavior for correctly typed TypedFilterCondition builders.
void main() {
  group('TypedFilterCondition Type Safety', () {
    // Define test field selectors
    const intField = FieldSelector<int>('value', int);
    const stringField = FieldSelector<String>('name', String);
    const dateTimeField = FieldSelector<DateTime>('createdAt', DateTime);

    test('builds single value operations with correctly typed values', () {
      final intEquals = intField.equals(123);
      final stringContains = stringField.contains('test');
      final dateLessThan = dateTimeField.lessThan(DateTime.now());

      expect(intEquals.field.fieldName, equals('value'));
      expect(stringContains.field.fieldName, equals('name'));
      expect(dateLessThan.field.fieldName, equals('createdAt'));
    });

    test('builds list operations with correctly typed values', () {
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

  // Negative compile-time type-safety cases need analyzer fixtures. Keeping
  // commented-out invalid Dart here would not exercise the test runner.
}
