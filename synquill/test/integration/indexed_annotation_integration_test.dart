import 'package:test/test.dart';

import 'package:synquill/synquill.generated.dart';

// Import the real Project model from the example that uses @Indexed
import 'package:synquill/src/test_models/index.dart';

void main() {
  group('Indexed annotation integration tests', () {
    test('Project model with @Indexed annotation can be instantiated', () {
      // Test that the Project model with @Indexed(name: 'project_name',
      // unique: true) can be instantiated correctly
      final project = Project(
        name: 'My Test Project',
        description: 'A project for testing indexed annotations',
        ownerId: 'user123',
        categoryId: 'cat456',
      );

      expect(project.id, isNotEmpty);
      expect(project.name, equals('My Test Project'));
      expect(
        project.description,
        equals('A project for testing indexed annotations'),
      );
      expect(project.ownerId, equals('user123'));
      expect(project.categoryId, equals('cat456'));
    });

    test('Project model can be serialized to/from JSON', () {
      final project = Project(
        name: 'JSON Test Project',
        description: 'Testing JSON serialization',
        ownerId: 'user789',
        categoryId: 'cat999',
      );

      final json = project.toJson();
      final fromJson = Project.fromJson(json);

      expect(fromJson.id, equals(project.id));
      expect(fromJson.name, equals(project.name));
      expect(fromJson.description, equals(project.description));
      expect(fromJson.ownerId, equals(project.ownerId));
      expect(fromJson.categoryId, equals(project.categoryId));
    });

    test('Project.fromDb constructor works correctly', () {
      final project = Project.fromDb(
        id: 'test-id-123',
        name: 'DB Test Project',
        description: 'Testing fromDb constructor',
        ownerId: 'user456',
        categoryId: 'cat789',
      );

      expect(project.id, equals('test-id-123'));
      expect(project.name, equals('DB Test Project'));
      expect(project.description, equals('Testing fromDb constructor'));
      expect(project.ownerId, equals('user456'));
      expect(project.categoryId, equals('cat789'));
    });

    test('annotations are accessible and work correctly', () {
      // Test that we can create the annotations used in Project model
      const indexedAnnotation = Indexed(name: 'project_name', unique: true);

      expect(indexedAnnotation.name, equals('project_name'));
      expect(indexedAnnotation.unique, isTrue);

      // Test other annotation variants
      const simpleIndex = Indexed();
      const namedIndex = Indexed(name: 'test_idx');
      const uniqueIndex = Indexed(unique: true);

      expect(simpleIndex.name, isNull);
      expect(simpleIndex.unique, isFalse);

      expect(namedIndex.name, equals('test_idx'));
      expect(namedIndex.unique, isFalse);

      expect(uniqueIndex.name, isNull);
      expect(uniqueIndex.unique, isTrue);
    });

    test(
      'saving two projects with identical names throws unique constraint error',
      () async {
        final db = SynquillDatabase(NativeDatabase.memory());
        await SynquillStorage.init(
          database: db,
          config: const SynquillStorageConfig(
            defaultSavePolicy: DataSavePolicy.localFirst,
            defaultLoadPolicy: DataLoadPolicy.localOnly,
            foregroundQueueConcurrency: 1,
            backgroundQueueConcurrency: 1,
          ),
          logger: Logger('IndexedAnnotationIntegrationTest'),
          initializeFn: initializeSynquillStorage,
          enableInternetMonitoring: false, // Disable for testing
        );
        final repo = ProjectRepository(db);

        final project1 = Project(
          name: 'Unique Name',
          description: 'First project',
          ownerId: 'user1',
          categoryId: 'cat1',
        );
        final project2 = Project(
          name: 'Unique Name', // Same name as project1
          description: 'Second project',
          ownerId: 'user2',
          categoryId: 'cat2',
        );

        // First insert should succeed
        await repo.save(project1);

        // Second insert should throw a unique constraint error
        Object? error;
        try {
          await repo.save(project2);
        } catch (e) {
          error = e;
        }
        expect(
          error,
          isNotNull,
          reason: 'Should throw on unique constraint violation',
        );
        expect(
          error.toString(),
          anyOf(
            contains('UNIQUE constraint failed'),
            contains('unique constraint'),
            contains('already exists'),
          ),
        );
        await SynquillStorage.reset();
      },
    );
  });
}
