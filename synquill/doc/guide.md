# Synquill Guide

This comprehensive guide covers all core concepts and features of Synquill, a powerful Flutter package for offline-first data management with automatic REST API synchronization.

## Table of Contents

- [Core Concepts](#core-concepts)
  - [Data Save Policies](#data-save-policies)
  - [Data Load Policies](#data-load-policies)
  - [Dependency-Based Sync Ordering](#dependency-based-sync-ordering)
  - [Synchronization Behavior](#synchronization-behavior)
  - [Server-Generated IDs](#server-generated-ids)
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

// Save to remote first, then save/update local on success
await user.save(savePolicy: DataSavePolicy.remoteFirst);
```
> **Note:** When using the `remoteFirst` save policy, if the remote operation fails (e.g., due to offline status or a server error), a `SynquillStorageException` or `OfflineException` will be thrown and the local model will **not** be saved.


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

### Synchronization Behavior

#### Data Overwriting Rules

When loading data from the API, Synquill follows specific rules to determine whether remote data should overwrite local data:

```dart
// Remote data overwrites local data by default
final users = await repository.findAll(
  loadPolicy: DataLoadPolicy.remoteFirst,
);
```

**Exception**: Local items with pending sync operations are **never overwritten** by remote data:

```dart
// Example scenario:
// 1. User updates a todo locally
final todo = await todoRepository.findOne('todo-123');
await todo.save(savePolicy: DataSavePolicy.localFirst); // API fails, queued for sync

// 2. Later, a full refresh is triggered
final allTodos = await todoRepository.findAll(
  loadPolicy: DataLoadPolicy.remoteFirst,
);
// The locally modified todo retains its pending changes
// even if the remote API has older data for the same todo
```

This protection ensures that user changes are never lost during background sync operations, maintaining data integrity in offline-first scenarios.

#### HTTP Gone (410) Status Handling

When the API returns an HTTP 410 Gone status for a specific item, Synquill automatically removes it from the local database:

```dart
// If API returns 410 Gone for a todo:
try {
  final todo = await todoRepository.findOne('deleted-todo-id');
  // todo will be null - automatically removed from local DB
} catch (e) {
  // Item was deleted both remotely and locally
}
```

This behavior ensures that items deleted on the server are properly cleaned up locally, maintaining consistency between remote and local data stores.

### Server-Generated IDs

Synquill supports server-generated IDs for models where the server needs to assign the final ID. This is useful when integrating with existing APIs that generate UUIDs, auto-incrementing IDs, or other server-specific ID formats.

#### Configuring Server-Generated IDs

To use server-generated IDs, add the `idGeneration` parameter to your model annotation:

```dart
@SynquillRepository(
  idGeneration: IdGenerationStrategy.server, // default: IdGenerationStrategy.client
  adapters: [MyApiAdapter],
)
class ServerManagedPost extends SynquillDataModel<ServerManagedPost> {
  @override
  final String id;
  final String title;
  final String content;

  ServerManagedPost({
    required this.id,
    required this.title, 
    required this.content,
  });

  // ... toJson, fromJson, fromDb methods
}
```

#### Creating Models with Server-Generated IDs

When creating new models, you still need to provide a temporary ID (using `generateCuid()`), but the server will replace it with a permanent ID during sync:

```dart
// Create with temporary client ID
final post = ServerManagedPost(
  id: generateCuid(), // Temporary ID
  title: 'My Post',
  content: 'Post content',
);

// Save the model - server will assign permanent ID
final savedPost = await post.save();
// savedPost.id will contain the server-assigned ID after sync
```

#### ID Negotiation Process

When you save a model with server-generated IDs:

1. **Local Save**: Model is saved locally with temporary client ID
2. **Background Sync**: API call creates the record on server
3. **ID Replacement**: Server returns permanent ID (e.g., `"server_1001"`)
4. **Local Update**: Temporary ID is replaced everywhere with permanent ID
5. **Relationship Updates**: All related models that reference this ID are automatically updated

```dart
// Before sync: model.id = "cuid_xyz123"
final post = await repository.save(post, savePolicy: DataSavePolicy.localFirst);

// After background sync completes: model.id = "server_1001"
// All relationships automatically updated to reference "server_1001"
```

#### Relationships with Server-Generated IDs

When models with server-generated IDs have relationships, Synquill automatically handles ID replacement across all related models:

```dart
@SynquillRepository(
  idGeneration: IdGenerationStrategy.server,
  relations: [
    OneToMany(target: Comment, mappedBy: 'postId'),
  ],
)
class Post extends SynquillDataModel<Post> {
  // ... model definition
}

@SynquillRepository(
  relations: [
    ManyToOne(target: Post, foreignKeyColumn: 'postId'),
  ],
)
class Comment extends SynquillDataModel<Comment> {
  final String postId; // Will be automatically updated when Post ID changes
  // ... model definition
}

// Create post and comment with temporary IDs
final post = Post(id: generateCuid(), title: 'My Post');
await post.save();

final comment = Comment(
  id: generateCuid(),
  postId: post.id, // Uses temporary post ID initially
  content: 'Great post!',
);
await comment.save();

// After sync: both post.id and comment.postId will have server-assigned values
// Relationship integrity is maintained automatically
```

#### Mixed ID Strategies

You can use both client and server-generated IDs in the same application:

```dart
// User uses client-generated IDs (stable across offline usage)
@SynquillRepository() // defaults to IdGenerationStrategy.client
class User extends SynquillDataModel<User> {
  // ID never changes, always client-generated
}

// Post uses server-generated IDs (integrates with existing blog system)
@SynquillRepository(idGeneration: IdGenerationStrategy.server)
class BlogPost extends SynquillDataModel<BlogPost> {
  final String userId; // References stable client-generated User ID
  // Post ID will be replaced with server ID after sync
}
```

This approach ensures that user-centric data remains stable for offline usage, while server-managed content integrates seamlessly with existing backend systems.

#### ID Conflict Resolution

When the server assigns an ID that already exists locally, Synquill automatically attempts to resolve the conflict using several strategies:

```dart
// Scenario: Server wants to assign ID "server_123" but it already exists locally
final post = ServerManagedPost(
  id: generateCuid(), // temporary: "cuid_abc"
  title: 'My Post',
  content: 'Content',
);

await post.save(); // Server responds with ID "server_123" but it already exists
```

**Strategy 1: Same Record Detection**
```dart
// If the existing local record is actually the same entity:
// - Compare all non-ID fields (name, content, etc.)
// - If records are identical, cleanup temporary record and use existing ID
// - Result: No conflict, existing record ID is used
```

**Strategy 2: Record Merging**
```dart
// If records represent the same entity but have different data:
// - Compare creation timestamps
// - If temporary record is newer, merge its data into existing record
// - Update existing record with newer field values
// - Cleanup temporary record
// - Result: Existing ID kept, data merged
```

**Strategy 3: Concurrent Operation Handling**
```dart
// If the existing record is from another ongoing operation:
// - Wait for other operation to complete
// - Retry conflict resolution after delay
// - Use exponential backoff (1s, 2s, 4s)
// - Result: Resolved after other operation completes
```

**Strategy 4: Conflict Marking**
```dart
// If conflict cannot be resolved automatically:
// - Keep temporary ID for the local record
// - Mark sync queue task as "conflict" status
// - Log detailed conflict information
// - Result: Manual resolution required

// Check for conflicts in sync queue:
final syncQueueDao = SyncQueueDao(database);
final allTasks = await syncQueueDao.getAllItems();
final conflicts = allTasks.where((task) => 
  task['id_negotiation_status'] == 'conflict'
).toList();

for (final conflict in conflicts) {
  print('Conflict: ${conflict['model_id']} vs server ID');
  print('Error: ${conflict['last_error']}');
  // Handle manually or implement custom resolution logic
}
```

**Foreign Key Integrity Protection**
```dart
// During ID conflict resolution, Synquill validates:
// - No foreign key constraints will be violated
// - Related models won't reference orphaned IDs
// - Cascade relationships remain intact

// Example: If Post references User, and Post ID changes:
// 1. Check all Comments that reference Post.id
// 2. Ensure Comment.postId updates are safe
// 3. Validate no circular dependencies exist
// 4. Update all references atomically
```

**Error Handling**
```dart
try {
  await post.save();
} on IdConflictException catch (e) {
  print('ID conflict: ${e.message}');
  print('Temporary ID: ${e.temporaryId}');
  print('Server ID: ${e.proposedServerId}');
  print('Model type: ${e.modelType}');
  
  // Handle conflict manually or retry later
}
```

The conflict resolution system ensures data integrity while maximizing automatic resolution success rates. Most conflicts are resolved transparently without user intervention.

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

// Remember to cancel the subscription when it is no longer needed to prevent memory leaks.
subscription?.cancel();
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

// Delete
await savedUser.delete();

// Force refresh from remote is not yet implemented; for now, use findOne with DataLoadPolicy.remoteFirst to fetch the latest data from the server.
// final refreshedUser = await savedUser.refresh();
```

### Bulk Operations

> **Note:** Bulk save, update, and delete operations are not yet supported. These features are planned for future releases.


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
