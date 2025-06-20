import 'package:test/test.dart';
import 'package:synquill/synquill.dart';
import 'package:synquill/synquill.generated.dart';
import 'package:synquill/src/test_models/test_server_id_model.dart';

/// Test for server-generated ID functionality
void main() {
  group('Server ID Generation Tests', () {
    test('ServerTestModel should use server-generated IDs', () {
      final model = ServerTestModel(
        id: generateCuid(),
        name: 'Test Model',
        description: 'Test Description',
      );

      // Test that the model reports using server-generated IDs through mixin
      expect(model.$usesServerGeneratedId, isTrue);
    });

    test('ClientTestModel should use client-generated IDs', () {
      final model = ClientTestModel(
        name: 'Test Model',
      );

      // Test that the model reports using client-generated IDs
      expect(model.$usesServerGeneratedId, isFalse);
    });

    test('ServerTestModel \$replaceIdEverywhere should work', () {
      final originalId = generateCuid();
      final newId = generateCuid();

      final model = ServerTestModel(
        id: originalId,
        name: 'Test Model',
        description: 'Test Description',
      );

      // Test ID replacement using mixin method
      final newModel = model.$replaceIdEverywhere(newId);
      expect(newModel.id, equals(newId));
      expect(newModel.name, equals('Test Model'));
      expect(newModel.description, equals('Test Description'));
    });

    test('ID negotiation infrastructure exists', () {
      // Test that enums and annotations work
      expect(IdGenerationStrategy.client, isNotNull);
      expect(IdGenerationStrategy.server, isNotNull);

      // Test that repository change types include idChanged
      expect(RepositoryChangeType.values,
          contains(RepositoryChangeType.idChanged));
    });

    test('IdNegotiationService exists and works', () {
      // Test that the service can be created
      final service = IdNegotiationService<ServerTestModel>(
        usesServerGeneratedId: true,
      );

      final model = ServerTestModel(
        id: generateCuid(),
        name: 'Test Model',
        description: 'Test Description',
      );

      expect(service.modelUsesServerGeneratedId(model), isTrue);
      expect(service.hasTemporaryId(model), isFalse);
      expect(service.getTemporaryClientId(model), isNull);
    });
  });
}
