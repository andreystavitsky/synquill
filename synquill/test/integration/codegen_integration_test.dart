import 'package:test/test.dart';
import 'dart:io';

void main() {
  group('Code Generation Integration Tests', () {
    test(
      'generated code should not contain toCompanion method calls',
      () async {
        // Read the DAO generated file where saveModel methods are located
        final daoFile = File('example/lib/generated/dao.g.dart');

        expect(
          daoFile.existsSync(),
          isTrue,
          reason: 'DAO generated file should exist',
        );

        final content = await daoFile.readAsString();

        // Verify that toCompanion method calls are NOT present
        expect(
          content,
          isNot(contains('model.toCompanion(')),
          reason: 'Generated code should not call model.toCompanion()',
        );
        expect(
          content,
          isNot(contains('.toCompanion(true)')),
          reason: 'Generated code should not call .toCompanion(true)',
        );
      },
    );

    test('generated code should contain manual companion creation', () async {
      // Read the DAO generated file where saveModel methods are located
      final daoFile = File('example/lib/generated/dao.g.dart');

      expect(
        daoFile.existsSync(),
        isTrue,
        reason: 'DAO generated file should exist',
      );

      final content = await daoFile.readAsString();

      // Verify that manual companion creation is present
      expect(
        content,
        contains('PlainModelTableCompanion(id: Value(model.id)'),
        reason: 'Should create PlainModel companion manually',
      );
      expect(
        content,
        contains('PlainModelJsonTableCompanion(id: Value(model.id)'),
        reason: 'Should create PlainModelJson companion manually',
      );
      expect(
        content,
        contains('TodoTableCompanion(title: Value(model.title)'),
        reason: 'Should create Todo companion manually',
      );

      // Verify that updatedAt is always included with default timestamp logic
      expect(
        content,
        contains('updatedAt: Value(model.updatedAt ?? DateTime.now())'),
        reason: 'Should always include updatedAt field with default timestamp',
      );
    });

    test(
      'generated code should have proper saveModel method structure',
      () async {
        // Read the DAO generated file where saveModel methods are located
        final daoFile = File('example/lib/generated/dao.g.dart');

        expect(
          daoFile.existsSync(),
          isTrue,
          reason: 'DAO generated file should exist',
        );

        final content = await daoFile.readAsString();

        // Check for proper saveModel method structure
        expect(
          content,
          contains('Future<PlainModel> saveModel(PlainModel model)'),
          reason: 'Should have PlainModel saveModel method',
        );
        expect(
          content,
          contains('Future<PlainModelJson> saveModel(PlainModelJson model)'),
          reason: 'Should have PlainModelJson saveModel method',
        );
        expect(
          content,
          contains('Future<Todo> saveModel(Todo model)'),
          reason: 'Should have Todo saveModel method',
        );

        // Verify that companion is created and used correctly
        expect(
          content,
          contains('final companion = '),
          reason: 'Should create companion variable',
        );
        expect(
          content,
          contains('await insertOrUpdate(companion)'),
          reason: 'Should use companion for insertOrUpdate',
        );
      },
    );

    test('example project should compile without errors', () async {
      // Run dart analyze on the example project
      final result = await Process.run('dart', [
        'analyze',
      ], workingDirectory: 'example');

      // Check that there are no compilation errors
      // We allow warnings (like unused variables) but not errors
      expect(
        result.exitCode,
        lessThanOrEqualTo(2),
        reason: 'Example should compile without errors (warnings OK)',
      );

      // Specifically check that there are no toCompanion-related errors
      final stderr = result.stderr.toString();
      final stdout = result.stdout.toString();

      expect(
        stderr,
        isNot(contains('toCompanion')),
        reason: 'Should not have toCompanion errors',
      );
      expect(
        stdout,
        isNot(contains('toCompanion')),
        reason: 'Should not have toCompanion errors',
      );
    });
  });
}
