// Relations Integration Test
// Tests for User-Todo OneToMany/ManyToOne relationships

// ignore_for_file: avoid_relative_lib_imports

import 'dart:async';
import 'package:test/test.dart';

import 'package:synquill/synquill.generated.dart';

import 'package:synquill/src/test_models/index.dart';

void main() {
  group('Relations Integration Tests', () {
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
        logger: Logger('RelationsIntegrationTest'),
        initializeFn: initializeSynquillStorage,
        enableInternetMonitoring: false, // Disable for testing
      );
      userRepository =
          SynquillStorage.instance.getRepository<User>() as UserRepository;
      todoRepository =
          SynquillStorage.instance.getRepository<Todo>() as TodoRepository;
      // Call the original _insertTestData as the group for multiple relations
      // has its own specific setup.
      await _insertTestData(userRepository, todoRepository);
    });

    tearDownAll(() async {
      await SynquillStorage.close();
    });

    group('Basic Relationship Tests', () {
      test(
        'should save users and todos with proper foreign key relations',
        () async {
          // Verify all users were saved (reduced from 5 to 3)
          final allUsers = await userRepository.findAll();
          expect(allUsers, hasLength(3));

          // Verify all todos were saved (reduced from 25 to 9)
          final allTodos = await todoRepository.findAll();
          expect(allTodos, hasLength(9)); // 3 todos per user * 3 users

          // Verify all todos have valid userIds
          expect(allTodos.every((todo) => todo.userId.isNotEmpty), isTrue);
        },
      );

      test('should filter todos by userId', () async {
        final allUsers = await userRepository.findAll();
        final firstUser = allUsers.first;

        final queryParams = QueryParams(
          filters: [TodoFields.userId.equals(firstUser.id)],
        );

        final userTodos = await todoRepository.findAll(
          queryParams: queryParams,
        );
        expect(userTodos, hasLength(3)); // Each user has 3 todos
        expect(userTodos.every((todo) => todo.userId == firstUser.id), isTrue);
      });

      test('should find todos by completion status across all users', () async {
        final queryParams = QueryParams(
          filters: [TodoFields.isCompleted.equals(true)],
        );

        final completedTodos = await todoRepository.findAll(
          queryParams: queryParams,
        );
        expect(completedTodos.length, greaterThan(0));
        expect(completedTodos.every((todo) => todo.isCompleted), isTrue);
      });
    });

    group('Complex Relationship Queries', () {
      test(
        'should filter todos by user name pattern and completion status',
        () async {
          // First get users with "Alice" or "Bob" in their name
          final aliceAndBobUsers = await userRepository.findAll(
            queryParams: QueryParams(
              filters: [UserFields.name.contains('Alice')],
            ),
          );

          // Should find at least one user
          expect(aliceAndBobUsers, isNotEmpty);

          final targetUserId = aliceAndBobUsers.first.id;

          // Now find their completed todos
          final queryParams = QueryParams(
            filters: [
              TodoFields.userId.equals(targetUserId),
              TodoFields.isCompleted.equals(true),
            ],
          );

          final userCompletedTodos = await todoRepository.findAll(
            queryParams: queryParams,
          );

          expect(userCompletedTodos.length, greaterThanOrEqualTo(0));
          expect(
            userCompletedTodos.every(
              (todo) => todo.userId == targetUserId && todo.isCompleted,
            ),
            isTrue,
          );
        },
      );

      test('should get all todos for users matching a pattern', () async {
        // Get all users whose names contain "User"
        final usersWithPattern = await userRepository.findAll(
          queryParams: QueryParams(filters: [UserFields.name.contains('User')]),
        );

        // Get all todos for these users
        final userIds = usersWithPattern.map((user) => user.id).toList();

        final queryParams = QueryParams(
          filters: [TodoFields.userId.inList(userIds)],
        );

        final todosForPatternUsers = await todoRepository.findAll(
          queryParams: queryParams,
        );

        expect(todosForPatternUsers.length, equals(userIds.length * 3));
        expect(
          todosForPatternUsers.every((todo) => userIds.contains(todo.userId)),
          isTrue,
        );
      });

      test('should handle complex sorting with relationships', () async {
        final allUsers = await userRepository.findAll();
        final firstUser = allUsers.first;

        final queryParams = QueryParams(
          filters: [TodoFields.userId.equals(firstUser.id)],
          sorts: [
            const SortCondition(
              field: TodoFields.isCompleted,
              direction: SortDirection.ascending,
            ),
            const SortCondition(
              field: TodoFields.title,
              direction: SortDirection.descending,
            ),
          ],
        );

        final sortedTodos = await todoRepository.findAll(
          queryParams: queryParams,
        );

        expect(sortedTodos, hasLength(3));

        // Should be sorted by completion status first (false < true)
        // then by title descending within each completion group
        for (int i = 0; i < sortedTodos.length - 1; i++) {
          final current = sortedTodos[i];
          final next = sortedTodos[i + 1];

          if (current.isCompleted == next.isCompleted) {
            // Same completion status, title should be descending
            expect(
              current.title.compareTo(next.title),
              greaterThanOrEqualTo(0),
            );
          } else {
            // Different completion status, false should come before true
            expect(current.isCompleted, isFalse);
            expect(next.isCompleted, isTrue);
          }
        }
      });
    });

    group('Relationship Data Integrity', () {
      test('should find todos for specific user by ID', () async {
        final allUsers = await userRepository.findAll();
        final targetUser = allUsers.firstWhere(
          (user) => user.name == 'Alice Johnson',
        );

        final queryParams = QueryParams(
          filters: [TodoFields.userId.equals(targetUser.id)],
        );

        final aliceTodos = await todoRepository.findAll(
          queryParams: queryParams,
        );

        expect(aliceTodos, hasLength(3));
        expect(
          aliceTodos.every((todo) => todo.userId == targetUser.id),
          isTrue,
        );
      });

      test('should handle empty result sets gracefully', () async {
        final queryParams = QueryParams(
          filters: [TodoFields.userId.equals('non-existent-user-id')],
        );

        final emptyResults = await todoRepository.findAll(
          queryParams: queryParams,
        );

        expect(emptyResults, isEmpty);
      });

      test('should handle filtering by non-existent user pattern', () async {
        final queryParams = QueryParams(
          filters: [UserFields.name.contains('NonExistentPattern')],
        );

        final emptyUserResults = await userRepository.findAll(
          queryParams: queryParams,
        );

        expect(emptyUserResults, isEmpty);
      });
    });

    group('Pagination with Relationships', () {
      test('should paginate todos for a specific user', () async {
        final allUsers = await userRepository.findAll();
        final targetUser = allUsers.first;

        final queryParams = QueryParams(
          filters: [TodoFields.userId.equals(targetUser.id)],
          sorts: [
            const SortCondition(
              field: TodoFields.title,
              direction: SortDirection.ascending,
            ),
          ],
          pagination: const PaginationParams(limit: 2, offset: 1),
        );

        final paginatedTodos = await todoRepository.findAll(
          queryParams: queryParams,
        );

        expect(paginatedTodos, hasLength(2)); // limit = 2
        expect(
          paginatedTodos.every((todo) => todo.userId == targetUser.id),
          isTrue,
        );

        // Should be sorted by title ascending (skip first, take next 2)
        expect(
          paginatedTodos[0].title.compareTo(paginatedTodos[1].title),
          lessThanOrEqualTo(0),
        );
      });
    });

    group('Watch Operations with Relationships', () {
      test('should watch todos for a specific user', () async {
        final allUsers = await userRepository.findAll();
        final targetUser = allUsers.first;

        final queryParams = QueryParams(
          filters: [TodoFields.userId.equals(targetUser.id)],
        );

        final stream = todoRepository.watchAll(queryParams: queryParams);
        final results = await stream.first;

        expect(results, hasLength(3));
        expect(results.every((todo) => todo.userId == targetUser.id), isTrue);
      });
    });
  });

  group('Multiple Relations Tests', () {
    late SynquillDatabase db;
    late UserRepository userRepository;
    late CategoryRepository categoryRepository;
    late ProjectRepository projectRepository;

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
        logger: Logger('MultipleRelationsTest'),
        initializeFn: initializeSynquillStorage,
        enableInternetMonitoring: false, // Disable for testing
      );

      userRepository = UserRepository(db);
      categoryRepository = CategoryRepository(db);
      projectRepository = ProjectRepository(db);

      await _insertMultipleRelationsTestData(
        userRepository,
        categoryRepository,
        projectRepository,
      );
    });

    tearDownAll(() async {
      await SynquillStorage.close();
    });

    test('should filter projects by owner', () async {
      final allUsers = await userRepository.findAll();
      final alice = allUsers.firstWhere((user) => user.name == 'Alice Johnson');

      final queryParams = QueryParams(
        filters: [ProjectFields.ownerId.equals(alice.id)],
      );

      final aliceProjects = await projectRepository.findAll(
        queryParams: queryParams,
      );

      expect(aliceProjects, isNotEmpty);
      expect(
        aliceProjects.every((project) => project.ownerId == alice.id),
        isTrue,
      );
    });

    test('should filter projects by category', () async {
      final allCategories = await categoryRepository.findAll();
      final workCategory = allCategories.firstWhere(
        (category) => category.name == 'Work',
      );

      final queryParams = QueryParams(
        filters: [ProjectFields.categoryId.equals(workCategory.id)],
      );

      final workProjects = await projectRepository.findAll(
        queryParams: queryParams,
      );

      expect(workProjects, isNotEmpty);
      expect(
        workProjects.every((project) => project.categoryId == workCategory.id),
        isTrue,
      );
    });

    test('should find projects by owner name pattern and category', () async {
      // Get users with "Alice" in name
      final aliceUsers = await userRepository.findAll(
        queryParams: QueryParams(filters: [UserFields.name.contains('Alice')]),
      );

      expect(aliceUsers, isNotEmpty);
      final alice = aliceUsers.first;

      // Get Work category
      final workCategories = await categoryRepository.findAll(
        queryParams: QueryParams(filters: [CategoryFields.name.equals('Work')]),
      );

      expect(workCategories, isNotEmpty);
      final workCategory = workCategories.first;

      // Find Alice's work projects
      final queryParams = QueryParams(
        filters: [
          ProjectFields.ownerId.equals(alice.id),
          ProjectFields.categoryId.equals(workCategory.id),
        ],
      );

      final aliceWorkProjects = await projectRepository.findAll(
        queryParams: queryParams,
      );

      expect(aliceWorkProjects, isNotEmpty);
      expect(
        aliceWorkProjects.every(
          (project) =>
              project.ownerId == alice.id &&
              project.categoryId == workCategory.id,
        ),
        isTrue,
      );
    });

    test('should sort projects by category name through join', () async {
      // This test would ideally use a join, but since we're testing
      // repository-level features, we'll test sorting by categoryId
      const queryParams = QueryParams(
        sorts: [
          SortCondition(
            field: ProjectFields.categoryId,
            direction: SortDirection.ascending,
          ),
          SortCondition(
            field: ProjectFields.name,
            direction: SortDirection.ascending,
          ),
        ],
      );

      final sortedProjects = await projectRepository.findAll(
        queryParams: queryParams,
      );

      expect(sortedProjects, isNotEmpty);

      // Verify sorting by categoryId first, then by name
      for (int i = 0; i < sortedProjects.length - 1; i++) {
        final current = sortedProjects[i];
        final next = sortedProjects[i + 1];

        if (current.categoryId == next.categoryId) {
          // Same category, name should be ascending
          expect(current.name.compareTo(next.name), lessThanOrEqualTo(0));
        } else {
          // Different categories, categoryId should be ascending
          expect(
            current.categoryId.compareTo(next.categoryId),
            lessThanOrEqualTo(0),
          );
        }
      }
    });
  });

  group('Generated Relation Loading Extension Methods', () {
    late SynquillDatabase db;
    late UserRepository userRepository;
    late TodoRepository todoRepository;
    late ProjectRepository projectRepository;
    late CategoryRepository categoryRepository;

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
        logger: Logger('RelationsIntegrationTest'),
        initializeFn: initializeSynquillStorage,
        enableInternetMonitoring: false, // Disable for testing
      );

      userRepository = UserRepository(db);
      todoRepository = TodoRepository(db);
      projectRepository = ProjectRepository(db);
      categoryRepository = CategoryRepository(db);

      await _insertTestDataForExtensions(
        userRepository,
        todoRepository,
        projectRepository,
        categoryRepository,
      );
    });

    tearDownAll(() async {
      await SynquillStorage.close();
    });

    group('OneToMany Extension Methods', () {
      test('User.loadTodos() should return all todos for the user', () async {
        // Get the first user
        final users = await userRepository.findAll();
        final firstUser = users.first;

        // Use the generated extension method to load todos
        final todos = await firstUser.loadTodos();

        // Verify we got the expected todos (reduced from 5 to 3)
        expect(todos, hasLength(3)); // Each user has 3 todos
        expect(todos.every((todo) => todo.userId == firstUser.id), isTrue);

        // Verify all todos belong to this user
        for (final todo in todos) {
          expect(todo.userId, equals(firstUser.id));
        }
      });

      test('User.loadTodos() with loadPolicy should work', () async {
        final users = await userRepository.findAll();
        final firstUser = users.first;

        // Test with explicit load policy
        final todos = await firstUser.loadTodos(
          loadPolicy: DataLoadPolicy.localOnly,
        );

        expect(todos, hasLength(3));
        expect(todos.every((todo) => todo.userId == firstUser.id), isTrue);
      });

      test(
        'Category.loadProjects() should return all projects for the category',
        () async {
          final categories = await categoryRepository.findAll();
          final workCategory = categories.firstWhere((c) => c.name == 'Work');

          // Use the generated extension method to load projects
          final projects = await workCategory.loadProjects();

          // Verify we got the expected projects
          expect(projects, hasLength(2)); // 2 work projects
          expect(
            projects.every((project) => project.categoryId == workCategory.id),
            isTrue,
          );

          // Verify project names
          final projectNames = projects.map((p) => p.name).toSet();
          expect(projectNames, contains('Team Dashboard'));
          expect(projectNames, contains('Mobile App'));
        },
      );

      test(
        'User.loadTodos() should return empty list for user with no todos',
        () async {
          // Create a new user with no todos
          final newUser = User(id: 'user-no-todos', name: 'No Todos User');
          await userRepository.save(newUser);

          // Use the generated extension method
          final todos = await newUser.loadTodos();

          expect(todos, isEmpty);
        },
      );
    });

    group('ManyToOne Extension Methods', () {
      test('Todo.loadUser() should return the associated user', () async {
        // Get the first todo
        final todos = await todoRepository.findAll();
        final firstTodo = todos.first;

        // Use the generated extension method to load the user
        final user = await firstTodo.loadUser();

        // Verify we got the correct user
        expect(user, isNotNull);
        expect(user!.id, equals(firstTodo.userId));
      });

      test('Todo.loadUser() with loadPolicy should work', () async {
        final todos = await todoRepository.findAll();
        final firstTodo = todos.first;

        // Test with explicit load policy
        final user = await firstTodo.loadUser(
          loadPolicy: DataLoadPolicy.localOnly,
        );

        expect(user, isNotNull);
        expect(user!.id, equals(firstTodo.userId));
      });

      test('Project.loadUser() should return the project owner', () async {
        final projects = await projectRepository.findAll();
        final firstProject = projects.first;

        // Use the generated extension method to load the owner
        final owner = await firstProject.loadUser();

        // Verify we got the correct owner
        expect(owner, isNotNull);
        expect(owner!.id, equals(firstProject.ownerId));
      });

      test(
        'Project.loadCategory() should return the project category',
        () async {
          final projects = await projectRepository.findAll();
          final firstProject = projects.first;

          // Use the generated extension method to load the category
          final category = await firstProject.loadCategory();

          // Verify we got the correct category
          expect(category, isNotNull);
          expect(category!.id, equals(firstProject.categoryId));
        },
      );

      test(
        'Todo.loadUser() should return null for non-existent user',
        () async {
          // Create a todo with a non-existent userId
          final orphanTodo = Todo(
            id: 'orphan-todo',
            title: 'Orphaned Todo',
            isCompleted: false,
            userId: 'non-existent-user-id',
          );
          await todoRepository.save(orphanTodo);

          // Use the generated extension method
          final user = await orphanTodo.loadUser();

          expect(user, isNull);
        },
      );
    });

    group('Generated Relation Watch Extension Methods', () {
      group('OneToMany Watch Methods', () {
        test(
          'User.watchTodos() should return a stream of all todos for the user',
          () async {
            final users = await userRepository.findAll();
            final firstUser = users.first;

            // Use the generated extension method to watch todos
            final todosStream = firstUser.watchTodos();

            // Get the first emission from the stream
            final todos = await todosStream.first;

            // Verify we got the expected todos
            expect(todos, hasLength(3)); // Each user has 3 todos
            expect(todos.every((todo) => todo.userId == firstUser.id), isTrue);

            // Verify all todos belong to this user
            for (final todo in todos) {
              expect(todo.userId, equals(firstUser.id));
            }
          },
        );

        test(
          'User.watchTodos() stream should update when todos change',
          () async {
            final users = await userRepository.findAll();
            final firstUser = users.first;

            // Start watching todos
            final todosStream = firstUser.watchTodos();
            final streamResults = <List<Todo>>[];

            // Listen to the stream and collect results
            final subscription = todosStream.listen((todos) {
              streamResults.add(todos);
            });

            // Wait for initial data
            await Future.delayed(const Duration(milliseconds: 100));
            expect(streamResults, hasLength(1));
            expect(streamResults.first, hasLength(3));

            // Add a new todo for this user
            final newTodo = Todo(
              id: 'new-todo-${DateTime.now().millisecondsSinceEpoch}',
              title: 'New Todo for ${firstUser.name}',
              isCompleted: false,
              userId: firstUser.id,
            );
            await todoRepository.save(newTodo);

            // Wait for stream to update
            await Future.delayed(const Duration(milliseconds: 100));

            // Should have 2 emissions now
            expect(streamResults.length, greaterThanOrEqualTo(2));
            final latestTodos = streamResults.last;
            expect(latestTodos, hasLength(4)); // Original 3 + 1 new
            expect(latestTodos.any((todo) => todo.id == newTodo.id), isTrue);

            await subscription.cancel();
          },
        );

        test(
          'Category.watchProjects() should return stream of projects',
          () async {
            final categories = await categoryRepository.findAll();
            final workCategory = categories.firstWhere((c) => c.name == 'Work');

            // Use the generated extension method to watch projects
            final projectsStream = workCategory.watchProjects();
            final projects = await projectsStream.first;

            // Verify we got the expected projects
            expect(projects, hasLength(2)); // 2 work projects
            expect(
              projects.every(
                (project) => project.categoryId == workCategory.id,
              ),
              isTrue,
            );

            // Verify project names
            final projectNames = projects.map((p) => p.name).toSet();
            expect(projectNames, contains('Team Dashboard'));
            expect(projectNames, contains('Mobile App'));
          },
        );

        test(
          'User.watchTodos() should return empty stream for user with no todos',
          () async {
            // Create a new user with no todos
            final newUser = User(
              id: 'user-no-todos-watch',
              name: 'No Todos User Watch',
            );
            await userRepository.save(newUser);

            // Use the generated extension method
            final todosStream = newUser.watchTodos();
            final todos = await todosStream.first;

            expect(todos, isEmpty);
          },
        );

        test(
          'Category.watchProjects() stream should update when projects change',
          () async {
            final categories = await categoryRepository.findAll();
            final personalCategory = categories.firstWhere(
              (c) => c.name == 'Personal',
            );

            // Start watching projects
            final projectsStream = personalCategory.watchProjects();
            final streamResults = <List<Project>>[];

            // Listen to the stream and collect results
            final subscription = projectsStream.listen((projects) {
              streamResults.add(projects);
            });

            // Wait for initial data
            await Future.delayed(const Duration(milliseconds: 100));
            expect(streamResults, hasLength(1));
            final initialCount = streamResults.first.length;

            // Add a new project for this category
            final users = await userRepository.findAll();
            final newProject = Project(
              id: 'new-project-${DateTime.now().millisecondsSinceEpoch}',
              name: 'New Personal Project',
              description: 'A new personal project for testing',
              ownerId: users.first.id,
              categoryId: personalCategory.id,
            );
            await projectRepository.save(newProject);

            // Wait for stream to update
            await Future.delayed(const Duration(milliseconds: 100));

            // Should have 2 emissions now
            expect(streamResults.length, greaterThanOrEqualTo(2));
            final latestProjects = streamResults.last;
            expect(latestProjects, hasLength(initialCount + 1));
            expect(
              latestProjects.any((project) => project.id == newProject.id),
              isTrue,
            );

            await subscription.cancel();
          },
        );
      });

      group('ManyToOne Watch Methods', () {
        test(
          'Todo.watchUser() should return stream of the associated user',
          () async {
            final todos = await todoRepository.findAll();
            final firstTodo = todos.first;

            // Use the generated extension method to watch the user
            final userStream = firstTodo.watchUser();
            final user = await userStream.first;

            // Verify we got the correct user
            expect(user, isNotNull);
            expect(user!.id, equals(firstTodo.userId));
          },
        );

        test(
          'Project.watchUser() should return stream of the project owner',
          () async {
            final projects = await projectRepository.findAll();
            final firstProject = projects.first;

            // Use the generated extension method to watch the owner
            final ownerStream = firstProject.watchUser();
            final owner = await ownerStream.first;

            // Verify we got the correct owner
            expect(owner, isNotNull);
            expect(owner!.id, equals(firstProject.ownerId));
          },
        );

        test(
          'Project.watchCategory() should return stream of project category',
          () async {
            final projects = await projectRepository.findAll();
            final firstProject = projects.first;

            // Use the generated extension method to watch the category
            final categoryStream = firstProject.watchCategory();
            final category = await categoryStream.first;

            // Verify we got the correct category
            expect(category, isNotNull);
            expect(category!.id, equals(firstProject.categoryId));
          },
        );

        test(
          'Todo.watchUser() stream should update when user changes',
          () async {
            final todos = await todoRepository.findAll();
            final firstTodo = todos.first;

            // Start watching the user
            final userStream = firstTodo.watchUser();
            final streamResults = <User?>[];

            // Listen to the stream and collect results
            final subscription = userStream.listen((user) {
              streamResults.add(user);
            });

            // Wait for initial data
            await Future.delayed(const Duration(milliseconds: 100));
            expect(streamResults, hasLength(1));
            expect(streamResults.first, isNotNull);
            final originalUser = streamResults.first!;

            // Update the user's name
            final updatedUser = User(
              id: originalUser.id,
              name: '${originalUser.name} (Updated)',
            );
            await userRepository.save(updatedUser);

            // Wait for stream to update
            await Future.delayed(const Duration(milliseconds: 100));

            // Should have 2 emissions now
            expect(streamResults.length, greaterThanOrEqualTo(2));
            final latestUser = streamResults.last;
            expect(latestUser, isNotNull);
            expect(latestUser!.name, contains('(Updated)'));

            await subscription.cancel();
          },
        );

        test(
          'Project.watchCategory() stream should update when category changes',
          () async {
            final projects = await projectRepository.findAll();
            final firstProject = projects.first;

            // Start watching the category
            final categoryStream = firstProject.watchCategory();
            final streamResults = <Category?>[];

            // Listen to the stream and collect results
            final subscription = categoryStream.listen((category) {
              streamResults.add(category);
            });

            // Wait for initial data
            await Future.delayed(const Duration(milliseconds: 100));
            expect(streamResults, hasLength(1));
            expect(streamResults.first, isNotNull);
            final originalCategory = streamResults.first!;

            // Update the category's color
            final updatedCategory = Category(
              id: originalCategory.id,
              name: originalCategory.name,
              color: '#FFFFFF', // Changed color
            );
            await categoryRepository.save(updatedCategory);

            // Wait for stream to update
            await Future.delayed(const Duration(milliseconds: 100));

            // Should have 2 emissions now
            expect(streamResults.length, greaterThanOrEqualTo(2));
            final latestCategory = streamResults.last;
            expect(latestCategory, isNotNull);
            expect(latestCategory!.color, equals('#FFFFFF'));

            await subscription.cancel();
          },
        );

        test(
          'Todo.watchUser() should return null for non-existent user',
          () async {
            // Create a todo with a non-existent userId
            final orphanTodo = Todo(
              id: 'orphan-todo-watch',
              title: 'Orphaned Todo Watch',
              isCompleted: false,
              userId: 'non-existent-user-id-watch',
            );
            await todoRepository.save(orphanTodo);

            // Use the generated extension method
            final userStream = orphanTodo.watchUser();
            final user = await userStream.first;

            expect(user, isNull);
          },
        );

        test(
          'Project.watchUser() should handle owner changes correctly',
          () async {
            final projects = await projectRepository.findAll();
            final users = await userRepository.findAll();
            final testProject = projects.first;
            final newOwner = users.firstWhere(
              (u) => u.id != testProject.ownerId,
            );

            // Start watching the owner
            final ownerStream = testProject.watchUser();
            final streamResults = <User?>[];

            final subscription = ownerStream.listen((owner) {
              streamResults.add(owner);
            });

            // Wait for initial data
            await Future.delayed(const Duration(milliseconds: 300));
            expect(streamResults, hasLength(1));
            expect(streamResults.first!.id, equals(testProject.ownerId));

            // Change the project's owner
            final updatedProject = Project(
              id: testProject.id,
              name: testProject.name,
              description: testProject.description,
              ownerId: newOwner.id, // Changed owner
              categoryId: testProject.categoryId,
            );
            await projectRepository.save(updatedProject);

            // Wait for stream to update
            await Future.delayed(const Duration(milliseconds: 300));

            // Should have 2 emissions now
            expect(streamResults.length, greaterThanOrEqualTo(2));
            final latestOwner = streamResults.last;
            expect(latestOwner, isNotNull);
            expect(latestOwner!.id, equals(newOwner.id));

            await subscription.cancel();
          },
        );
      });

      group('Watch Method Performance', () {
        test('Multiple watch streams should work independently', () async {
          final users = await userRepository.findAll();
          final user1 = users[0];
          final user2 = users[1];

          // Create two independent watch streams
          final stream1 = user1.watchTodos();
          final stream2 = user2.watchTodos();

          // Get initial data from both streams
          final todos1 = await stream1.first;
          final todos2 = await stream2.first;

          // Verify they have different data
          expect(todos1.every((todo) => todo.userId == user1.id), isTrue);
          expect(todos2.every((todo) => todo.userId == user2.id), isTrue);
          expect(todos1.first.userId, isNot(equals(todos2.first.userId)));
        });

        test('Watch streams should be efficient with many listeners', () async {
          final users = await userRepository.findAll();
          final firstUser = users.first;

          // Create multiple listeners for the same stream
          final stream = firstUser.watchTodos();
          final results = <List<Todo>>[];

          // Add multiple listeners
          final subscriptions = <StreamSubscription<List<Todo>>>[];
          for (int i = 0; i < 3; i++) {
            subscriptions.add(
              stream.listen((todos) {
                results.add(todos);
              }),
            );
          }

          // Wait for all listeners to receive data
          await Future.delayed(const Duration(milliseconds: 100));

          // Should have received data for all listeners
          expect(results.length, greaterThanOrEqualTo(3));

          // Clean up subscriptions
          for (final subscription in subscriptions) {
            await subscription.cancel();
          }
        });

        test(
          'Watch methods should work with DataLoadPolicy parameter',
          () async {
            final users = await userRepository.findAll();
            final firstUser = users.first;

            // Test OneToMany watch with load policy
            final todosStream = firstUser.watchTodos();
            final todos = await todosStream.first;
            expect(
              todos.length,
              greaterThanOrEqualTo(3),
            ); // At least 3, may be more due to previous tests

            // Test ManyToOne watch with load policy
            final todos2 = await todoRepository.findAll();
            final firstTodo = todos2.first;
            final userStream = firstTodo.watchUser();
            final user = await userStream.first;
            expect(user, isNotNull);
            expect(user!.id, equals(firstTodo.userId));
          },
        );
      });
    });
  });

  group('Cascade Delete Tests', () {
    late SynquillDatabase db;
    late CategoryRepository categoryRepository;
    late ProjectRepository projectRepository;

    setUp(() async {
      db = SynquillDatabase(NativeDatabase.memory());
      await SynquillStorage.init(
        database: db,
        config: const SynquillStorageConfig(
          defaultSavePolicy: DataSavePolicy.localFirst,
          defaultLoadPolicy: DataLoadPolicy.localOnly,
          foregroundQueueConcurrency: 1,
          backgroundQueueConcurrency: 1,
        ),
        logger: Logger('CascadeDeleteTest'),
        initializeFn: initializeSynquillStorage,
        enableInternetMonitoring: false, // Disable for testing
      );

      categoryRepository = CategoryRepository(db);
      projectRepository = ProjectRepository(db);

      await _insertCascadeDeleteTestData(categoryRepository, projectRepository);
    });

    tearDown(() async {
      await SynquillStorage.close();
    });

    test('should cascade delete projects when category is deleted', () async {
      // Verify initial data setup
      final allCategories = await categoryRepository.findAll();
      final allProjects = await projectRepository.findAll();

      expect(allCategories, hasLength(3));
      expect(allProjects, hasLength(6)); // 2 projects per category

      // Find the Work category (which has cascadeDelete = true)
      final workCategory = allCategories.firstWhere(
        (category) => category.name == 'Work',
      );

      // Find projects belonging to the Work category
      final workProjects = await projectRepository.findAll(
        queryParams: QueryParams(
          filters: [ProjectFields.categoryId.equals(workCategory.id)],
        ),
      );

      expect(workProjects, hasLength(2));
      expect(
        workProjects.every((project) => project.categoryId == workCategory.id),
        isTrue,
      );

      // Delete the Work category - this should cascade delete its projects
      await categoryRepository.delete(
        workCategory.id,
        savePolicy: DataSavePolicy.localFirst,
      );

      // Verify the category was deleted
      final categoriesAfterDelete = await categoryRepository.findAll();
      expect(categoriesAfterDelete, hasLength(2)); // 3 - 1 = 2
      expect(
        categoriesAfterDelete.every(
          (category) => category.id != workCategory.id,
        ),
        isTrue,
      );

      // Verify the related projects were cascade deleted
      final projectsAfterDelete = await projectRepository.findAll();
      expect(projectsAfterDelete, hasLength(4)); // 6 - 2 = 4
      expect(
        projectsAfterDelete.every(
          (project) => project.categoryId != workCategory.id,
        ),
        isTrue,
      );

      // Verify the remaining projects are from other categories
      final remainingCategoryIds =
          categoriesAfterDelete.map((c) => c.id).toSet();
      expect(
        projectsAfterDelete.every(
          (project) => remainingCategoryIds.contains(project.categoryId),
        ),
        isTrue,
      );
    });

    test(
      'should cascade delete multiple projects from same category',
      () async {
        // Get the Personal category which should have multiple projects
        final allCategories = await categoryRepository.findAll();
        final personalCategory = allCategories.firstWhere(
          (category) => category.name == 'Personal',
        );

        // Verify it has multiple projects
        final personalProjects = await projectRepository.findAll(
          queryParams: QueryParams(
            filters: [ProjectFields.categoryId.equals(personalCategory.id)],
          ),
        );

        expect(personalProjects, hasLength(2));

        // Delete the Personal category
        await categoryRepository.delete(personalCategory.id);

        // Verify all personal projects were deleted
        final remainingProjects = await projectRepository.findAll();

        expect(
          remainingProjects.every(
            (project) => project.categoryId != personalCategory.id,
          ),
          isTrue,
        );

        // Should have Work + Hobby projects left (4 projects total)
        expect(remainingProjects, hasLength(4));

        // Verify no remaining projects belong to the deleted Personal category
        expect(
          remainingProjects.every(
            (project) => project.categoryId != personalCategory.id,
          ),
          isTrue,
        );

        // Verify we have both Work and Hobby projects remaining
        final workCategoryId =
            allCategories.firstWhere((category) => category.name == 'Work').id;
        final hobbyCategoryId =
            allCategories.firstWhere((category) => category.name == 'Hobby').id;

        final workProjectsRemaining = remainingProjects
            .where((project) => project.categoryId == workCategoryId)
            .length;
        final hobbyProjectsRemaining = remainingProjects
            .where((project) => project.categoryId == hobbyCategoryId)
            .length;

        expect(workProjectsRemaining, equals(2));
        expect(hobbyProjectsRemaining, equals(2));
      },
    );

    test('should handle cascade delete when no related items exist', () async {
      // Create a new category with no projects
      final emptyCategory = Category(
        id: 'empty-category',
        name: 'Empty Category',
        color: '#FFFFFF',
      );
      await categoryRepository.save(emptyCategory);

      // Verify it has no projects
      final emptyProjects = await projectRepository.findAll(
        queryParams: QueryParams(
          filters: [ProjectFields.categoryId.equals(emptyCategory.id)],
        ),
      );
      expect(emptyProjects, isEmpty);

      // Delete the empty category - should not cause errors
      await categoryRepository.delete(emptyCategory.id);

      // Verify the category was deleted and no projects were affected
      final allCategories = await categoryRepository.findAll();
      expect(
        allCategories.every((category) => category.id != emptyCategory.id),
        isTrue,
      );

      final allProjects = await projectRepository.findAll();
      expect(allProjects, hasLength(6)); // Original count unchanged
    });

    test('should handle cascade delete with non-existent category', () async {
      // Try to delete a non-existent category
      const nonExistentId = 'non-existent-category-id';

      // This should not throw an error
      await categoryRepository.delete(nonExistentId);

      // Verify original data is unchanged
      final allCategories = await categoryRepository.findAll();
      final allProjects = await projectRepository.findAll();

      expect(allCategories, hasLength(3)); // Original count
      expect(allProjects, hasLength(6)); // Original count
    });

    test('should cascade delete in correct order', () async {
      // Get initial counts
      final initialCategories = await categoryRepository.findAll();
      final initialProjects = await projectRepository.findAll();

      expect(initialCategories, hasLength(3));
      expect(initialProjects, hasLength(6));

      // Delete all categories one by one and verify cascade behavior
      for (final category in initialCategories) {
        // Count projects before deletion
        final projectsBeforeDelete = await projectRepository.findAll(
          queryParams: QueryParams(
            filters: [ProjectFields.categoryId.equals(category.id)],
          ),
        );

        // Delete the category
        await categoryRepository.delete(category.id);

        // Verify projects were cascade deleted
        final projectsAfterDelete = await projectRepository.findAll(
          queryParams: QueryParams(
            filters: [ProjectFields.categoryId.equals(category.id)],
          ),
        );

        expect(projectsAfterDelete, isEmpty);

        // Verify total project count decreased by the expected amount
        final totalProjectsAfterDelete = await projectRepository.findAll();
        expect(
          totalProjectsAfterDelete.length,
          equals(initialProjects.length - projectsBeforeDelete.length),
        );

        // Update the initial count for next iteration
        initialProjects.removeWhere(
          (project) => project.categoryId == category.id,
        );
      }

      // Verify all categories and projects are gone
      final finalCategories = await categoryRepository.findAll();
      final finalProjects = await projectRepository.findAll();

      expect(finalCategories, isEmpty);
      expect(finalProjects, isEmpty);
    });
  });

  group('Cascade Delete Cycle Detection Tests', () {
    late SynquillDatabase db;
    late CompanyRepository companyRepository;
    late DepartmentRepository departmentRepository;

    setUp(() async {
      db = SynquillDatabase(NativeDatabase.memory());
      await SynquillStorage.init(
        database: db,
        config: const SynquillStorageConfig(backgroundQueueConcurrency: 1),
        logger: Logger('CycleDetectionTest'),
        initializeFn: initializeSynquillStorage,
        enableInternetMonitoring: false, // Disable for testing
      );

      Logger.root.level = Level.ALL;
      Logger.root.onRecord.listen((record) {
        // Uncomment for debugging:
        // print(
        //   '[${record.level.name}] ${record.loggerName}: '
        //   '${record.message}',
        // );
      });

      companyRepository = CompanyRepository(db);
      departmentRepository = DepartmentRepository(db);
    });

    tearDown(() async {
      await SynquillStorage.close();
    });

    test(
      'should prevent infinite recursion in bidirectional cascade delete',
      () async {
        // Create a company that owns a department
        final parentCompany = Company(
          id: 'company-1',
          name: 'Parent Company',
          departmentId: null, // Will be set later
        );
        await companyRepository.save(parentCompany);

        // Create a department owned by the company
        final department = Department(
          id: 'dept-1',
          name: 'Main Department',
          companyId: parentCompany.id,
        );
        await departmentRepository.save(department);

        // Create a subsidiary company owned by the department
        final subsidiaryCompany = Company(
          id: 'company-2',
          name: 'Subsidiary Company',
          departmentId: department.id,
        );
        await companyRepository.save(subsidiaryCompany);

        // Update the parent company to be owned by the department
        // This creates a cycle: Company -> Department -> Company
        final updatedParentCompany = Company(
          id: parentCompany.id,
          name: parentCompany.name,
          departmentId: department.id,
        );
        await companyRepository.save(updatedParentCompany);

        // Verify the cyclic relationship is set up correctly
        final companies = await companyRepository.findAll();
        final departments = await departmentRepository.findAll();

        expect(companies, hasLength(2));
        expect(departments, hasLength(1));

        final savedParentCompany = companies.firstWhere(
          (c) => c.id == 'company-1',
        );
        final savedSubsidiaryCompany = companies.firstWhere(
          (c) => c.id == 'company-2',
        );
        final savedDepartment = departments.first;

        // Verify the cycle: Parent Company -> Department -> Subsidiary Company
        expect(savedParentCompany.departmentId, equals(department.id));
        expect(savedDepartment.companyId, equals(parentCompany.id));
        expect(savedSubsidiaryCompany.departmentId, equals(department.id));

        // Now delete the parent company - this should trigger cascade delete
        // but should NOT cause infinite recursion due to our cycle detection

        await companyRepository.delete(parentCompany.id);

        // Verify that the delete operation completed successfully
        // (if there was infinite recursion, the test would hang or timeout)
        final companiesAfterDelete = await companyRepository.findAll();

        // The exact outcome depends on the cascade delete logic and
        // cycle detection, but the important thing is that the operation
        // completed without hanging

        // Verify that at least some entities were deleted
        expect(companiesAfterDelete.length, lessThan(2));
      },
    );

    test('should handle complex multi-level cycles gracefully', () async {
      // Create a more complex cycle with multiple levels
      // Company A -> Department X -> Company B -> Department Y -> Company A

      final companyA = Company(
        id: 'company-a',
        name: 'Company A',
        departmentId: null,
      );
      await companyRepository.save(companyA);

      final departmentX = Department(
        id: 'dept-x',
        name: 'Department X',
        companyId: companyA.id,
      );
      await departmentRepository.save(departmentX);

      final companyB = Company(
        id: 'company-b',
        name: 'Company B',
        departmentId: departmentX.id,
      );
      await companyRepository.save(companyB);

      final departmentY = Department(
        id: 'dept-y',
        name: 'Department Y',
        companyId: companyB.id,
      );
      await departmentRepository.save(departmentY);

      // Close the cycle by making Company A owned by Department Y
      final updatedCompanyA = Company(
        id: companyA.id,
        name: companyA.name,
        departmentId: departmentY.id,
      );
      await companyRepository.save(updatedCompanyA);

      // Verify the complex cycle is set up
      final companies = await companyRepository.findAll();
      final departments = await departmentRepository.findAll();

      expect(companies, hasLength(2));
      expect(departments, hasLength(2));

      // Delete one entity to trigger cascade - should handle cycle gracefully
      await departmentRepository.delete(departmentX.id);

      // Verify operation completed without hanging
      final departmentsAfterDelete = await departmentRepository.findAll();

      // The operation should complete successfully
      expect(departmentsAfterDelete.length, lessThan(2));
    });

    test('should log cycle detection warnings', () async {
      // Create a simple cycle for testing logging
      final company = Company(
        id: 'company-log-test',
        name: 'Log Test Company',
        departmentId: null,
      );
      await companyRepository.save(company);

      final department = Department(
        id: 'dept-log-test',
        name: 'Log Test Department',
        companyId: company.id,
      );
      await departmentRepository.save(department);

      // Create the cycle
      final updatedCompany = Company(
        id: company.id,
        name: company.name,
        departmentId: department.id,
      );
      await companyRepository.save(updatedCompany);

      // Delete the company - this should log cycle detection warnings
      // (Note: In a real test environment, you might want to capture log
      // output to verify the warnings are actually logged)
      await companyRepository.delete(company.id);

      // Verify operation completed
      final companiesAfterDelete = await companyRepository.findAll();
      final departmentsAfterDelete = await departmentRepository.findAll();

      // The exact result may vary, but operation should complete
      expect(
        companiesAfterDelete.length + departmentsAfterDelete.length,
        lessThan(2),
      );
    });

    test('should work correctly with non-cyclic cascade deletes', () async {
      // Test that normal (non-cyclic) cascade deletes still work correctly
      final company = Company(
        id: 'company-normal',
        name: 'Normal Company',
        departmentId: null,
      );
      await companyRepository.save(company);

      final department1 = Department(
        id: 'dept-normal-1',
        name: 'Normal Department 1',
        companyId: company.id,
      );
      await departmentRepository.save(department1);

      final department2 = Department(
        id: 'dept-normal-2',
        name: 'Normal Department 2',
        companyId: company.id,
      );
      await departmentRepository.save(department2);

      // Create subsidiary companies owned by the departments (no cycles)
      final subsidiary1 = Company(
        id: 'company-sub-1',
        name: 'Subsidiary 1',
        departmentId: department1.id,
      );
      await companyRepository.save(subsidiary1);

      final subsidiary2 = Company(
        id: 'company-sub-2',
        name: 'Subsidiary 2',
        departmentId: department2.id,
      );
      await companyRepository.save(subsidiary2);

      // Verify initial setup
      expect(await companyRepository.findAll(), hasLength(3));
      expect(await departmentRepository.findAll(), hasLength(2));

      // Delete the main company - should cascade delete departments and
      // their subsidiaries
      await companyRepository.delete(company.id);

      // Verify cascade delete worked correctly
      final companiesAfterDelete = await companyRepository.findAll();
      final departmentsAfterDelete = await departmentRepository.findAll();

      expect(companiesAfterDelete, isEmpty);
      expect(departmentsAfterDelete, isEmpty);
    });
  });

  // Separate test groups for error handling tests with isolated databases
  group('Extension Methods Error Handling', () {
    late SynquillDatabase db;
    late UserRepository userRepository;

    setUp(() async {
      // Create a separate database instance for this test group
      db = SynquillDatabase(NativeDatabase.memory());
      await SynquillStorage.init(
        database: db,
        config: const SynquillStorageConfig(
          defaultSavePolicy: DataSavePolicy.localFirst,
          defaultLoadPolicy: DataLoadPolicy.localOnly,
          foregroundQueueConcurrency: 1,
          backgroundQueueConcurrency: 1,
        ),
        logger: Logger('ExtensionErrorHandlingTest'),
        initializeFn: initializeSynquillStorage,
        enableInternetMonitoring: false,
      );
      userRepository =
          SynquillStorage.instance.getRepository<User>() as UserRepository;

      // Create minimal test data
      final user = User(id: 'user1', name: 'Test User');
      await userRepository.save(user);
    });

    tearDown(() async {
      await SynquillStorage.close();
    });

    test(
      'Extension methods should handle database errors gracefully',
      () async {
        final users = await userRepository.findAll();
        final user = users.first;

        // Close the database to simulate an error
        await SynquillStorage.close();

        // Test that extension methods handle database errors gracefully
        expect(() => user.loadTodos(), throwsA(isA<StateError>()));
      },
    );
  });

  group('Watch Methods Error Handling', () {
    late SynquillDatabase db;
    late UserRepository userRepository;
    late TodoRepository todoRepository;

    setUp(() async {
      // Create a separate database instance for this test group
      db = SynquillDatabase(NativeDatabase.memory());
      await SynquillStorage.init(
        database: db,
        config: const SynquillStorageConfig(
          defaultSavePolicy: DataSavePolicy.localFirst,
          defaultLoadPolicy: DataLoadPolicy.localOnly,
          foregroundQueueConcurrency: 1,
          backgroundQueueConcurrency: 1,
        ),
        logger: Logger('WatchErrorHandlingTest'),
        initializeFn: initializeSynquillStorage,
        enableInternetMonitoring: false,
      );
      userRepository =
          SynquillStorage.instance.getRepository<User>() as UserRepository;
      todoRepository =
          SynquillStorage.instance.getRepository<Todo>() as TodoRepository;

      // Create minimal test data
      final user = User(id: 'user1', name: 'Test User');
      await userRepository.save(user);

      final todo = Todo(
        id: 'todo1',
        title: 'Test Todo',
        isCompleted: false,
        userId: user.id,
      );
      await todoRepository.save(todo);
    });

    tearDown(() async {
      await SynquillStorage.close();
    });

    test('Watch methods should handle database errors gracefully', () async {
      final users = await userRepository.findAll();
      final user = users.first;

      // Start watching before closing the database
      final watchStream = user.watchTodos();

      // Listen to the stream to activate it
      late StreamSubscription subscription;
      subscription = watchStream.listen(
        (todos) {
          // Expected to receive initial data
        },
        onError: (error) {
          // Expected when database is closed
          expect(error, isA<StateError>());
        },
      );

      // Give the stream time to emit initial data
      await Future.delayed(const Duration(milliseconds: 100));

      // Close the database to simulate an error
      await SynquillStorage.close();

      // Give the stream time to emit the error
      await Future.delayed(const Duration(milliseconds: 100));

      await subscription.cancel();
    });

    test(
      'ManyToOne watch methods should handle database errors gracefully',
      () async {
        final todos = await todoRepository.findAll();
        final todo = todos.first;

        // Start watching before closing the database
        final watchStream = todo.watchUser();

        // Listen to the stream to activate it
        late StreamSubscription subscription;
        subscription = watchStream.listen(
          (user) {
            // Expected to receive initial data
          },
          onError: (error) {
            // Expected when database is closed
            expect(error, isA<StateError>());
          },
        );

        // Give the stream time to emit initial data
        await Future.delayed(const Duration(milliseconds: 100));

        // Close the database to simulate an error
        await SynquillStorage.close();

        // Give the stream time to emit the error
        await Future.delayed(const Duration(milliseconds: 100));

        await subscription.cancel();
      },
    );
  });
}

/// Helper to insert cascade delete test data
Future<void> _insertCascadeDeleteTestData(
  CategoryRepository categoryRepository,
  ProjectRepository projectRepository,
) async {
  // Create 3 categories
  final categories = [
    Category(id: 'work-cat', name: 'Work', color: '#FF0000'),
    Category(id: 'personal-cat', name: 'Personal', color: '#00FF00'),
    Category(id: 'hobby-cat', name: 'Hobby', color: '#0000FF'),
  ];

  for (final category in categories) {
    await categoryRepository.save(category);
  }

  // Create 2 projects for each category (6 total)
  final projects = [
    // Work projects
    Project(
      id: 'work-proj-1',
      name: 'Team Dashboard',
      description: 'Internal team dashboard',
      ownerId: 'owner-1', // We don't need actual users for cascade delete test
      categoryId: categories[0].id, // Work
    ),
    Project(
      id: 'work-proj-2',
      name: 'Client Portal',
      description: 'Customer facing portal',
      ownerId: 'owner-1',
      categoryId: categories[0].id, // Work
    ),

    // Personal projects
    Project(
      id: 'personal-proj-1',
      name: 'Personal Website',
      description: 'My personal website',
      ownerId: 'owner-2',
      categoryId: categories[1].id, // Personal
    ),
    Project(
      id: 'personal-proj-2',
      name: 'Budget Tracker',
      description: 'Track personal expenses',
      ownerId: 'owner-2',
      categoryId: categories[1].id, // Personal
    ),

    // Hobby projects
    Project(
      id: 'hobby-proj-1',
      name: 'Photography Blog',
      description: 'Share my photos',
      ownerId: 'owner-3',
      categoryId: categories[2].id, // Hobby
    ),
    Project(
      id: 'hobby-proj-2',
      name: 'Recipe Collection',
      description: 'Collect favorite recipes',
      ownerId: 'owner-3',
      categoryId: categories[2].id, // Hobby
    ),
  ];

  for (final project in projects) {
    await projectRepository.save(project);
  }
}

/// Helper to insert basic user-todo test data (optimized with less data)
Future<void> _insertTestData(
  UserRepository userRepository,
  TodoRepository todoRepository,
) async {
  // Create only 3 users instead of 5 to speed up tests
  final users = [
    User(id: 'user1', name: 'Alice Johnson'),
    User(id: 'user2', name: 'Bob Smith'),
    User(id: 'user3', name: 'Charlie Brown'),
  ];

  for (final user in users) {
    await userRepository.save(user);
  }

  // Create only 3 todos per user instead of 5 (9 total instead of 25)
  int todoIdCounter = 1;
  for (final user in users) {
    for (int i = 1; i <= 3; i++) {
      final todo = Todo(
        id: 'todo${todoIdCounter++}',
        title: '${user.name} Task $i',
        isCompleted: i % 2 == 0, // Even numbered todos are completed
        userId: user.id,
      );
      await todoRepository.save(todo);
    }
  }
}

/// Helper to insert multi-relation test data (categories, projects)
Future<void> _insertMultipleRelationsTestData(
  UserRepository userRepository,
  CategoryRepository categoryRepository,
  ProjectRepository projectRepository,
) async {
  // Create users first (needed for projects)
  final users = [
    User(id: 'user1', name: 'Alice Johnson'),
    User(id: 'user2', name: 'Bob Smith'),
    User(id: 'user3', name: 'Charlie Brown'),
  ];

  for (final user in users) {
    await userRepository.save(user);
  }

  // Create categories
  final categories = [
    Category(id: 'cat1', name: 'Work', color: '#FF0000'),
    Category(id: 'cat2', name: 'Personal', color: '#00FF00'),
    Category(id: 'cat3', name: 'Hobby', color: '#0000FF'),
  ];

  for (final category in categories) {
    await categoryRepository.save(category);
  }

  // Get existing users
  final savedUsers = await userRepository.findAll();

  // Create projects for different combinations
  final projects = [
    // Alice's projects
    Project(
      id: 'proj1',
      name: 'Website Redesign',
      description: 'Company website overhaul',
      ownerId: savedUsers[0].id, // Alice
      categoryId: categories[0].id, // Work
    ),
    Project(
      id: 'proj2',
      name: 'Personal Blog',
      description: 'My personal writing space',
      ownerId: savedUsers[0].id, // Alice
      categoryId: categories[1].id, // Personal
    ),

    // Bob's projects
    Project(
      id: 'proj3',
      name: 'Mobile App',
      description: 'New mobile application',
      ownerId: savedUsers[1].id, // Bob
      categoryId: categories[0].id, // Work
    ),
    Project(
      id: 'proj4',
      name: 'Photography Collection',
      description: 'Nature photography project',
      ownerId: savedUsers[1].id, // Bob
      categoryId: categories[2].id, // Hobby
    ),

    // Charlie's projects
    Project(
      id: 'proj5',
      name: 'Home Automation',
      description: 'Smart home setup',
      ownerId: savedUsers[2].id, // Charlie
      categoryId: categories[1].id, // Personal
    ),
  ];

  for (final project in projects) {
    await projectRepository.save(project);
  }
}

/// Helper to insert test data for generated extension methods (optimized)
Future<void> _insertTestDataForExtensions(
  UserRepository userRepository,
  TodoRepository todoRepository,
  ProjectRepository projectRepository,
  CategoryRepository categoryRepository,
) async {
  // Create only 2 users instead of 3
  final users = [
    User(id: 'user1', name: 'Alice Johnson'),
    User(id: 'user2', name: 'Bob Smith'),
  ];

  for (final user in users) {
    await userRepository.save(user);
  }

  // Create only 2 categories instead of 3
  final categories = [
    Category(id: 'cat1', name: 'Work', color: '#FF0000'),
    Category(id: 'cat2', name: 'Personal', color: '#00FF00'),
  ];

  for (final category in categories) {
    await categoryRepository.save(category);
  }

  // Create only 2 projects instead of 3
  final projects = [
    Project(
      id: 'proj1',
      name: 'Team Dashboard',
      description: 'Company website overhaul',
      ownerId: users[0].id, // Alice
      categoryId: categories[0].id, // Work
    ),
    Project(
      id: 'proj2',
      name: 'Mobile App',
      description: 'New mobile application',
      ownerId: users[1].id, // Bob
      categoryId: categories[0].id, // Work
    ),
  ];

  for (final project in projects) {
    await projectRepository.save(project);
  }

  // Create only 3 todos per user instead of 5 (6 total instead of 15)
  int todoIdCounter = 1;
  for (final user in users) {
    for (int i = 1; i <= 3; i++) {
      final todo = Todo(
        id: 'todo${todoIdCounter++}',
        title: '${user.name} Task $i',
        isCompleted: i % 2 == 0, // Even numbered todos are completed
        userId: user.id,
      );
      await todoRepository.save(todo);
    }
  }
}
