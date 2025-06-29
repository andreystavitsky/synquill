import 'package:test/test.dart';
import 'dart:io';

void main() {
  group('Code Generation Integration Tests', () {
    test(
      'generated code should not contain toCompanion method calls',
      () async {
        // Read the DAO generated file where saveModel methods are located
        final daoFile = File('lib/generated/dao.g.dart');

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
      final daoFile = File('lib/generated/dao.g.dart');

      expect(
        daoFile.existsSync(),
        isTrue,
        reason: 'DAO generated file should exist',
      );

      final content = await daoFile.readAsString();

      // Verify that manual companion creation is present for test models
      expect(
        content,
        contains('PlainModelTableCompanion(id: Value(model.id)'),
        reason: 'Should create PlainModel companion manually',
      );
      expect(
        content,
        contains('UserTableCompanion(id: Value(model.id)'),
        reason: 'Should create User companion manually',
      );
      // updatedAt field logic
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
        final daoFile = File('lib/generated/dao.g.dart');

        expect(
          daoFile.existsSync(),
          isTrue,
          reason: 'DAO generated file should exist',
        );

        final content = await daoFile.readAsString();

        // Check for proper saveModel method structure for test models
        expect(
          content,
          contains('Future<PlainModel> saveModel(PlainModel model)'),
          reason: 'Should have PlainModel saveModel method',
        );
        expect(
          content,
          contains('Future<User> saveModel(User model)'),
          reason: 'Should have User saveModel method',
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
  });
}
