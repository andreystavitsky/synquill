// ignore_for_file: avoid_relative_lib_imports

import 'package:test/test.dart';
import 'package:synquill/synquill.dart';

import 'package:synquill/synquill.generated.dart';

// Import the generated code from the example
import 'package:synquill/src/test_models/index.dart';

void main() {
  group('QueryParams Merge Integration Tests', () {
    late SynquillDatabase db;
    late UserRepository userRepository;
    late TodoRepository todoRepository;

    setUpAll(() async {
      db = SynquillDatabase(NativeDatabase.memory());
      await SynquillStorage.init(
        database: db,
        config: const SynquillStorageConfig(
          defaultSavePolicy: DataSavePolicy.localFirst,
          defaultLoadPolicy: DataLoadPolicy.localOnly,
          foregroundQueueConcurrency: 1,
          backgroundQueueConcurrency: 1,
        ),
        logger: Logger('QueryParamsMergeTest'),
        initializeFn: initializeSynquillStorage,
        enableInternetMonitoring: false,
      );
      userRepository = SynquillStorage.instance.getRepository<User>();
      todoRepository = SynquillStorage.instance.getRepository<Todo>();

      // Create test data
      final testUser = User(id: 'user123', name: 'Test User');
      await userRepository.save(testUser);

      final todos = [
        Todo(
          id: 'todo1',
          title: 'Test Todo 1',
          isCompleted: false,
          userId: testUser.id,
        ),
        Todo(
          id: 'todo2',
          title: 'Important Task',
          isCompleted: true,
          userId: testUser.id,
        ),
        Todo(
          id: 'todo3',
          title: 'Test Todo 3',
          isCompleted: false,
          userId: testUser.id,
        ),
      ];

      for (final todo in todos) {
        await todoRepository.save(todo);
      }
    });

    tearDownAll(() async {
      await SynquillStorage.reset();
    });

    test('loadTodos with QueryParams merges correctly', () async {
      final allUsers = await userRepository.findAll();
      final testUser = allUsers.first;

      // Test with custom QueryParams
      final customQueryParams = QueryParams(
        filters: [
          TodoFields.title.contains('Test'),
          TodoFields.isCompleted.equals(false),
        ],
        sorts: [
          const SortCondition(
            field: TodoFields.title,
            direction: SortDirection.ascending,
          ),
        ],
      );

      // Load todos using relation method with QueryParams
      final todos = await testUser.loadTodos(
        queryParams: customQueryParams,
        loadPolicy: DataLoadPolicy.localOnly,
      );

      // Should return todos matching filters AND userId
      expect(todos.length, equals(2));

      // All should belong to the test user
      for (final todo in todos) {
        expect(todo.userId, equals(testUser.id));
      }

      // Should match custom filters
      for (final todo in todos) {
        expect(todo.title.contains('Test'), isTrue);
        expect(todo.isCompleted, isFalse);
      }

      // Should be sorted
      expect(todos[0].title, equals('Test Todo 1'));
      expect(todos[1].title, equals('Test Todo 3'));
    });

    test('loadTodos overwrites conflicting userId filter', () async {
      final allUsers = await userRepository.findAll();
      final testUser = allUsers.first;

      // QueryParams with conflicting userId filter
      final conflictingQueryParams = QueryParams(
        filters: [
          TodoFields.userId.equals('different-user-id'),
          TodoFields.isCompleted.equals(true),
        ],
      );

      final todos = await testUser.loadTodos(
        queryParams: conflictingQueryParams,
        loadPolicy: DataLoadPolicy.localOnly,
      );

      // Should return todos for testUser, not different-user-id
      expect(todos.length, equals(1));
      expect(todos[0].userId, equals(testUser.id));
      expect(todos[0].title, equals('Important Task'));
      expect(todos[0].isCompleted, isTrue);
    });
  });
}
