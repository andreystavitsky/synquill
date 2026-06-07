import 'package:test/test.dart';
import 'package:synquill/synquill.dart';
import '../support/synquill.generated.dart';
import '../support/test_models/test_server_id_model.dart';

/// Test for ID negotiation service and repository integration
void main() {
  group('ID Negotiation Service Tests', () {
    late IdNegotiationService<ServerTestModel> service;
    late ServerTestModel testModel;

    setUp(() {
      service = IdNegotiationService<ServerTestModel>(
        usesServerGeneratedId: true,
      );
      testModel = ServerTestModel(
        id: generateCuid(),
        name: 'Test Model',
        description: 'Test Description',
      );
    });

    test('service correctly identifies server-generated ID models', () {
      expect(service.modelUsesServerGeneratedId(testModel), isTrue);
    });

    test('initially models do not have temporary IDs', () {
      expect(service.hasTemporaryId(testModel), isFalse);
      expect(service.getTemporaryClientId(testModel), isNull);
    });

    test('can mark model as temporary and retrieve client ID', () {
      final tempClientId = generateCuid();
      service.markAsTemporary(testModel, tempClientId);

      expect(service.hasTemporaryId(testModel), isTrue);
      expect(service.getTemporaryClientId(testModel), equals(tempClientId));
    });

    test('replaceIdEverywhere creates new model with updated ID', () {
      final newId = generateCuid();
      final newModel = service.replaceIdEverywhere(testModel, newId);

      expect(newModel.id, equals(newId));
      expect(newModel.name, equals(testModel.name));
      expect(newModel.description, equals(testModel.description));
      expect(newModel.id != testModel.id, isTrue);
    });

    test('replaceIdEverywhere preserves temporary ID tracking', () {
      final tempClientId = generateCuid();
      final newId = generateCuid();

      // Mark as temporary
      service.markAsTemporary(testModel, tempClientId);
      expect(service.hasTemporaryId(testModel), isTrue);

      // Replace ID
      final newModel = service.replaceIdEverywhere(testModel, newId);

      // New model should not be marked as temporary
      expect(service.hasTemporaryId(newModel), isFalse);
      // But we should be able to get the original temporary client ID
      expect(service.getTemporaryClientId(newModel), equals(tempClientId));
    });

    test('replaceIdEverywhere honors custom id JSON key metadata', () {
      ModelInfoRegistryProvider.registerIdJsonKey(
        'CustomServerIdModel',
        'serverKey',
      );
      addTearDown(ModelInfoRegistryProvider.reset);

      final customService = IdNegotiationService<CustomServerIdModel>(
        usesServerGeneratedId: true,
      );
      final model = CustomServerIdModel(
        id: 'temporary-id',
        name: 'Custom Model',
      );

      final newModel = customService.replaceIdEverywhere(model, 'server-id');

      expect(newModel.id, equals('server-id'));
      expect(newModel.name, equals(model.name));
      expect(newModel.toJson(), isNot(containsPair('id', 'server-id')));
      expect(newModel.toJson(), containsPair('serverKey', 'server-id'));
    });
  });

  group('Repository Integration Tests', () {
    test('generated repository uses RepositoryServerIdMixin', () async {
      final database = SynquillDatabase(NativeDatabase.memory());
      addTearDown(database.close);

      final repository = ServerTestModelRepository(database);
      final model = ServerTestModel(
        id: generateCuid(),
        name: 'Repository Test',
        description: 'Generated repository mixin test',
      );
      const temporaryClientId = 'temporary-client-id';

      expect(
        repository,
        isA<RepositoryServerIdMixin<ServerTestModel>>(),
      );
      expect(repository.modelUsesServerGeneratedId(model), isTrue);
      expect(repository.hasTemporaryId(model), isFalse);

      repository.markAsTemporary(model, temporaryClientId);

      expect(repository.hasTemporaryId(model), isTrue);
      expect(
        repository.getTemporaryClientId(model),
        equals(temporaryClientId),
      );
    });

    test('Extension methods work correctly on models', () {
      final model = ServerTestModel(
        id: generateCuid(),
        name: 'Test',
        description: 'Test Description',
      );

      // Test that generated extension methods work
      expect(model.$usesServerGeneratedId, isTrue);
      expect(model.$hasTemporaryId, isFalse);
      expect(model.$temporaryClientId, isNull);

      // Test ID replacement through extension
      final newId = generateCuid();
      final newModel = model.$replaceIdEverywhere(newId);
      expect(newModel.id, equals(newId));
      expect(newModel.name, equals(model.name));
    });

    test('ClientTestModel has correct extension behavior', () {
      final model = ClientTestModel(name: 'Test');

      // Client-generated ID models should not use server ID features
      expect(model.$usesServerGeneratedId, isFalse);
      expect(model.$hasTemporaryId, isFalse);
      expect(model.$temporaryClientId, isNull);

      // ID replacement should still work for consistency
      final newId = generateCuid();
      final newModel = model.$replaceIdEverywhere(newId);
      expect(newModel.id, equals(newId));
      expect(newModel.name, equals(model.name));
    });
  });
}

class CustomServerIdModel extends SynquillDataModel<CustomServerIdModel> {
  @override
  final String id;
  final String name;

  CustomServerIdModel({
    required this.id,
    required this.name,
  });

  @override
  Map<String, dynamic> toJson() => {
        'serverKey': id,
        'name': name,
      };

  @override
  CustomServerIdModel fromJson(Map<String, dynamic> json) {
    return CustomServerIdModel(
      id: json['serverKey'] as String,
      name: json['name'] as String,
    );
  }
}
