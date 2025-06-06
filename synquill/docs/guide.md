# Synquill Guide

This comprehensive guide covers all core concepts and features of Synquill, a powerful Flutter package for offline-first data management with automatic REST API synchronization.

## Table of Contents

- [Core Concepts](#core-concepts)
  - [Data Save Policies](#data-save-policies)
  - [Data Load Policies](#data-load-policies)
  - [Dependency-Based Sync Ordering](#dependency-based-sync-ordering)
- [Querying Data](#querying-data)
  - [Repository-Level Queries](#repository-level-queries)
  - [Model-Level Relationship Queries](#model-level-relationship-queries)
- [Reactive Data Streams](#reactive-data-streams)
  - [Watch for Real-time Updates](#watch-for-real-time-updates)
  - [Repository Change Events](#repository-change-events)
- [Model Operations](#model-operations)
  - [Instance Methods](#instance-methods)
  - [Bulk Operations](#bulk-operations)
- [Relationships](#relationships)
  - [OneToMany Relationships](#onetomany-relationships)
  - [ManyToOne Relationships](#manytoone-relationships)

## Core Concepts

### Data Save Policies

Control how data is saved to local and remote storage:

```dart
// Save locally first, then sync to remote in background
await user.save(savePolicy: DataSavePolicy.localFirst);

// Save to remote first, then update local on success
await user.save(savePolicy: DataSavePolicy.remoteFirst);
```

### Data Load Policies

Control how data is fetched from local and remote sources:

```dart
// Get from local storage only
final users = await repository.findAll(
  loadPolicy: DataLoadPolicy.localOnly,
);

// Get from local immediately, refresh from remote in background
final users = await repository.findAll(
  loadPolicy: DataLoadPolicy.localThenRemote,
);

// Fetch from remote first, fallback to local on failure
final users = await repository.findAll(
  loadPolicy: DataLoadPolicy.remoteFirst,
);
```

### Dependency-Based Sync Ordering

Synquill automatically ensures sync operations respect model relationships:

```dart
// Parent models (Users) are always synced before child models (Todos)
// This prevents foreign key constraint violations during sync operations
// See the "Dependency-Based Sync Ordering" section for detailed information
```

## Querying Data

### Repository-Level Queries

```dart
// Get repository instance
final userRepository = SynquillStorage.instance.users;
final todoRepository = SynquillStorage.instance.todos;

// Find all with filtering, sorting, and pagination
final completedTodos = await todoRepository.findAll(
  queryParams: QueryParams(
    filters: [
      TodoFields.isCompleted.equals(true),
      TodoFields.createdAt.greaterThan(DateTime.now().subtract(Duration(days: 7))),
    ],
    sorts: [
      SortCondition(
        field: TodoFields.createdAt, 
        direction: SortDirection.descending
      ),
    ],
    limit: 20,
    offset: 0,
  ),
  loadPolicy: DataLoadPolicy.localThenRemote,
);

// Find single item
final user = await userRepository.findOne('user-id');

// Find or throw exception
final user = await userRepository.findOneOrFail('user-id');
```

> **Note**: When using `DataLoadPolicy.localThenRemote` or `DataLoadPolicy.remoteFirst`, `QueryParams` are automatically translated to HTTP querystring parameters for API calls. The default format is:
> - Filters: `filter[field][operator]=value` (e.g., `filter[isCompleted][equals]=true`)
> - Sorts: `sort=field:direction,field2:direction` (e.g., `sort=createdAt:desc,name:asc`)
> - Pagination: `limit=X&offset=Y`
> 
> This behavior can be customized by overriding the `queryParamsToHttpParams` method in your API adapter mixins.

### Model-Level Relationship Queries

Generated extension methods provide convenient relationship access:

```dart
final user = await userRepository.findOne('user-id');

// Load related todos with filtering
final userTodos = await user.loadTodos(
  loadPolicy: DataLoadPolicy.localThenRemote,
  queryParams: QueryParams(
    filters: [TodoFields.isCompleted.equals(false)],
    sorts: [SortCondition(
      field: TodoFields.createdAt,
      direction: SortDirection.descending
    )],
  ),
);

// Load related user for a todo
final todo = await todoRepository.findOne('todo-id');
final todoOwner = await todo.loadUser();
```

## Reactive Data Streams

### Watch for Real-time Updates

```dart
// Watch all todos with real-time updates
StreamSubscription? subscription = todoRepository.watchAll(
  queryParams: QueryParams(
    filters: [TodoFields.isCompleted.equals(false)],
  ),
).listen((todos) {
  // UI automatically updates when data changes
  setState(() => _todos = todos);
});
// Remember to cancel the subscription when it is no longer needed to avoid memory leaks.

// Watch single item
todoRepository.watchOne('todo-id').listen((todo) {
  if (todo != null) {
    // React to specific todo changes
    updateUI(todo);
  }
});

// Watch relationship changes
user.watchTodos().listen((todos) {
  // Automatically updated when user's todos change
  print('User now has ${todos.length} todos');
});
```
> **Note**: Reactive streams currently only watch local database changes. Remote data changes are reflected in streams only after they've been synced to the local database. See [Current Limitations](advanced-features.md#current-limitations) for more details.

### Repository Change Events

Listen to fine-grained repository events:

```dart
todoRepository.changes.listen((change) {
  switch (change.type) {
    case RepositoryChangeType.created:
      print('New todo created: ${change.model?.title}');
      break;
    case RepositoryChangeType.updated:
      print('Todo updated: ${change.model?.title}');
      break;
    case RepositoryChangeType.deleted:
      print('Todo deleted');
      break;
    case RepositoryChangeType.error:
      print('Error: ${change.error}');
      break;
  }
});
```

## Model Operations

### Instance Methods

Every model instance has convenient methods:

```dart
// Create and save
final user = User(name: 'John Doe', email: 'john@example.com');
final savedUser = await user.save();

TODO: describe update

// Delete
await savedUser.delete();

// Refresh from remote - not implemented yet
// final refreshedUser = await savedUser.refresh();
```

### Bulk Operations

```dart
// bulk save/update is not supported yet

```

## Relationships

### OneToMany Relationships

```dart
@SynquillRepository(
  relations: [
    OneToMany(
      target: Todo, 
      mappedBy: 'userId',
      cascadeDelete: true, // Delete todos when user is deleted
    ),
  ],
)
class User extends SynquillDataModel<User> {
  // ... model definition
}
```

Generated methods:
```dart
// Load related todos
final todos = await user.loadTodos();

// Watch related todos
user.watchTodos().listen((todos) => updateUI(todos));
```

### ManyToOne Relationships

```dart
@SynquillRepository(
  relations: [
    ManyToOne(
      target: User, 
      foreignKeyColumn: 'userId',
      cascadeDelete: false,
    ),
  ],
)
class Todo extends SynquillDataModel<Todo> {
  final String userId;
  // ... model definition
}
```

Generated methods:
```dart
// Load related user
final user = await todo.loadUser();

// Watch related user
todo.watchUser().listen((user) => updateUI(user));

// Delete with cascade (automatically deletes related todos)
await userRepository.delete('user-id', savePolicy: DataSavePolicy.localFirst);
```
