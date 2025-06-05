import 'package:synquill/synquill.dart';
import 'package:test/test.dart';

void main() {
  group('DependencyResolver', () {
    setUp(() {
      // Reset dependency resolver state before each test
      DependencyResolver.clearForTesting();
    });

    group('Basic Dependency Registration', () {
      test('should register simple parent-child dependency', () {
        DependencyResolver.registerDependency('Project', 'User');

        expect(DependencyResolver.getDependencies('Project'), contains('User'));
        expect(DependencyResolver.hasDependencies('Project'), isTrue);
        expect(DependencyResolver.hasDependencies('User'), isFalse);
      });

      test('should register multiple dependencies for one model', () {
        DependencyResolver.registerDependency('Project', 'User');
        DependencyResolver.registerDependency('Project', 'Category');

        final dependencies = DependencyResolver.getDependencies('Project');
        expect(dependencies, contains('User'));
        expect(dependencies, contains('Category'));
        expect(dependencies.length, equals(2));
      });

      test('should handle models with no dependencies', () {
        expect(DependencyResolver.getDependencies('User'), isEmpty);
        expect(DependencyResolver.hasDependencies('User'), isFalse);
        expect(DependencyResolver.getDependencyLevel('User'), equals(0));
      });
    });

    group('Dependency Level Calculation', () {
      test('should calculate correct levels for simple hierarchy', () {
        // User -> Project -> Task (User is root, Project depends on User,
        // Task depends on Project)
        DependencyResolver.registerDependency('Project', 'User');
        DependencyResolver.registerDependency('Task', 'Project');

        expect(DependencyResolver.getDependencyLevel('User'), equals(0));
        expect(DependencyResolver.getDependencyLevel('Project'), equals(1));
        expect(DependencyResolver.getDependencyLevel('Task'), equals(2));
      });

      test('should handle complex hierarchy with multiple parents', () {
        // User -> Project <- Category
        // Project -> Task
        DependencyResolver.registerDependency('Project', 'User');
        DependencyResolver.registerDependency('Project', 'Category');
        DependencyResolver.registerDependency('Task', 'Project');

        expect(DependencyResolver.getDependencyLevel('User'), equals(0));
        expect(DependencyResolver.getDependencyLevel('Category'), equals(0));
        expect(DependencyResolver.getDependencyLevel('Project'), equals(1));
        expect(DependencyResolver.getDependencyLevel('Task'), equals(2));
      });

      test('should handle diamond dependency pattern', () {
        // User -> Project -> Task
        // User -> Category -> Task
        DependencyResolver.registerDependency('Project', 'User');
        DependencyResolver.registerDependency('Category', 'User');
        DependencyResolver.registerDependency('Task', 'Project');
        DependencyResolver.registerDependency('Task', 'Category');

        expect(DependencyResolver.getDependencyLevel('User'), equals(0));
        expect(DependencyResolver.getDependencyLevel('Project'), equals(1));
        expect(DependencyResolver.getDependencyLevel('Category'), equals(1));
        expect(DependencyResolver.getDependencyLevel('Task'), equals(2));
      });
    });

    group('Circular Dependency Detection', () {
      test('should detect simple circular dependency', () {
        DependencyResolver.registerDependency('A', 'B');
        DependencyResolver.registerDependency('B', 'A');

        expect(DependencyResolver.hasCircularDependencies(), isTrue);
      });

      test('should detect complex circular dependency', () {
        DependencyResolver.registerDependency('A', 'B');
        DependencyResolver.registerDependency('B', 'C');
        DependencyResolver.registerDependency('C', 'A');

        expect(DependencyResolver.hasCircularDependencies(), isTrue);
      });

      test('should not report false positives for valid hierarchies', () {
        DependencyResolver.registerDependency('Project', 'User');
        DependencyResolver.registerDependency('Task', 'Project');
        DependencyResolver.registerDependency('Comment', 'Task');

        expect(DependencyResolver.hasCircularDependencies(), isFalse);
      });
    });

    group('Task Sorting', () {
      test('should sort tasks by dependency order', () {
        // Register dependencies: Project -> User, Task -> Project
        DependencyResolver.registerDependency('Project', 'User');
        DependencyResolver.registerDependency('Task', 'Project');

        final tasks = [
          {'model_type': 'Task', 'id': '1', 'created_at': DateTime(2024, 1, 1)},
          {
            'model_type': 'Project',
            'id': '2',
            'created_at': DateTime(2024, 1, 2),
          },
          {'model_type': 'User', 'id': '3', 'created_at': DateTime(2024, 1, 3)},
        ];

        final sortedTasks = DependencyResolver.sortTasksByDependencyOrder(
          tasks,
        );

        // Should be ordered: User, Project, Task
        expect(sortedTasks[0]['model_type'], equals('User'));
        expect(sortedTasks[1]['model_type'], equals('Project'));
        expect(sortedTasks[2]['model_type'], equals('Task'));
      });

      test('should maintain FIFO order within same model type', () {
        DependencyResolver.registerDependency('Project', 'User');

        final tasks = [
          {'model_type': 'User', 'id': '3', 'created_at': DateTime(2024, 1, 3)},
          {'model_type': 'User', 'id': '1', 'created_at': DateTime(2024, 1, 1)},
          {'model_type': 'User', 'id': '2', 'created_at': DateTime(2024, 1, 2)},
          {
            'model_type': 'Project',
            'id': '4',
            'created_at': DateTime(2024, 1, 4),
          },
        ];

        final sortedTasks = DependencyResolver.sortTasksByDependencyOrder(
          tasks,
        );

        // Users should be first (dependency level 0), ordered by creation time
        expect(sortedTasks[0]['model_type'], equals('User'));
        expect(sortedTasks[0]['id'], equals('1')); // Earliest created
        expect(sortedTasks[1]['model_type'], equals('User'));
        expect(sortedTasks[1]['id'], equals('2'));
        expect(sortedTasks[2]['model_type'], equals('User'));
        expect(sortedTasks[2]['id'], equals('3')); // Latest created
        expect(sortedTasks[3]['model_type'], equals('Project'));
      });

      test('should handle empty task list', () {
        final tasks = <Map<String, dynamic>>[];
        final sortedTasks = DependencyResolver.sortTasksByDependencyOrder(
          tasks,
        );
        expect(sortedTasks, isEmpty);
      });

      test('should handle tasks with no dependencies', () {
        final tasks = [
          {'model_type': 'User', 'id': '1', 'created_at': DateTime(2024, 1, 1)},
          {
            'model_type': 'Category',
            'id': '2',
            'created_at': DateTime(2024, 1, 2),
          },
        ];

        final sortedTasks = DependencyResolver.sortTasksByDependencyOrder(
          tasks,
        );

        // Should maintain creation time order when no dependencies
        expect(sortedTasks[0]['id'], equals('1'));
        expect(sortedTasks[1]['id'], equals('2'));
      });
    });

    group('Debug Information', () {
      test('should provide debug dependency map', () {
        DependencyResolver.registerDependency('Project', 'User');
        DependencyResolver.registerDependency('Project', 'Category');

        final debugInfo = DependencyResolver.getDebugDependencyMap();
        expect(debugInfo, contains('Project'));
        expect(debugInfo['Project'], contains('User'));
        expect(debugInfo['Project'], contains('Category'));
      });

      test('should provide debug dependency levels', () {
        DependencyResolver.registerDependency('Project', 'User');
        DependencyResolver.registerDependency('Task', 'Project');

        final debugLevels = DependencyResolver.getDebugDependencyLevels();
        expect(debugLevels['User'], equals(0));
        expect(debugLevels['Project'], equals(1));
        expect(debugLevels['Task'], equals(2));
      });
    });
  });
}
