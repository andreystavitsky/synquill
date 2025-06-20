# Dependency-Based Sync Ordering

Synquill automatically manages sync task ordering based on model relationships to ensure data integrity during synchronization. The `DependencyResolver` class analyzes `@ManyToOne` relationships to create a hierarchical sync order where parent models are always synced before their dependent children.

## Table of Contents

- [How It Works](#how-it-works)
- [Dependency Levels](#dependency-levels)
- [Automatic Sync Task Ordering](#automatic-sync-task-ordering)
- [Circular Dependency Detection](#circular-dependency-detection)
- [Complex Dependency Patterns](#complex-dependency-patterns)
- [Debug Information](#debug-information)

## How It Works

When models have `@ManyToOne` relationships, Synquill automatically registers dependencies during initialization:

```dart
// Generated during build - registers Todo's dependency on User
DependencyResolver.registerDependency('Todo', 'User');
DependencyResolver.registerDependency('Project', 'User');
DependencyResolver.registerDependency('Task', 'Project');
```

## Dependency Levels

The system assigns dependency levels to ensure proper ordering:

```dart
// Level 0: Root models (no dependencies)
DependencyResolver.getDependencyLevel('User');      // Returns 0

// Level 1: Models depending on level 0
DependencyResolver.getDependencyLevel('Project');   // Returns 1  
DependencyResolver.getDependencyLevel('Todo');      // Returns 1

// Level 2: Models depending on level 1 
DependencyResolver.getDependencyLevel('Task');      // Returns 2
```

## Automatic Sync Task Ordering

During sync operations, tasks are automatically ordered by dependency level:

```dart
// Sync queue tasks are processed in dependency order:
// 1. All User operations (level 0)
// 2. All Project and Todo operations (level 1) 
// 3. All Task operations (level 2)

// Within the same level, tasks maintain FIFO order by creation time
```

## Circular Dependency Detection

The system detects and prevents circular dependencies:

```dart
// This would be detected as a circular dependency:
DependencyResolver.registerDependency('A', 'B');
DependencyResolver.registerDependency('B', 'C'); 
DependencyResolver.registerDependency('C', 'A');

// Check for circular dependencies
if (DependencyResolver.hasCircularDependencies()) {
  // Handle circular dependency error
}
```

## Complex Dependency Patterns

Supports complex patterns like diamond dependencies:

```dart
@SynquillRepository(
  relations: [
    ManyToOne(target: User, foreignKeyColumn: 'userId'),
    ManyToOne(target: Category, foreignKeyColumn: 'categoryId'),
  ],
)
class Task extends SynquillDataModel<Task> {
  final String userId;
  final String categoryId;
  // ... model definition
}

// Results in dependency ordering:
// Level 0: User, Category (independent)
// Level 1: Task (depends on both User and Category)
```

## Debug Information

Access dependency information for debugging:

```dart
// Get dependency map
final dependencyResolver = SynquillStorage.dependencyResolver;
final dependencies = dependencyResolver.getDebugDependencyMap();
print('Task dependencies: ${dependencies['Task']}'); // [User, Category]

// Get dependency levels  
final levels = dependencyResolver.getDebugDependencyLevels();
print('All levels: $levels'); // {User: 0, Category: 0, Task: 1}

// Get comprehensive debug info
final debugInfo = dependencyResolver.getDebugInfo();
```

This ensures that during background sync operations, parent records (like Users) are always created or updated before child records (like Todos) that reference them, preventing foreign key constraint violations and maintaining data integrity.
