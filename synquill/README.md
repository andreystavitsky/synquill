# Synquill

A powerful Flutter package for offline-first data management with automatic REST API synchronization. Built on top of Drift for robust local storage and featuring intelligent sync queues for seamless online/offline operation.

[![pub package](https://img.shields.io/pub/v/synquill.svg)](https://pub.dev/packages/synquill)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 🚀 Key Features

### 📱 Offline-First Architecture
- **Local-first operations** with Drift-powered SQLite database
- **Automatic background sync** with configurable retry mechanisms
- **Smart conflict resolution** and queue management
- **Works completely offline** - sync when connectivity returns

### 🔄 Intelligent Synchronization
- **Bidirectional sync** between local storage and REST APIs
- **Configurable sync policies**: `localFirst`, `remoteFirst`, `localThenRemote`
- **Background processing** with WorkManager integration
- **Retry logic** with exponential backoff for failed operations

### 🏗️ Model-Driven Development
- **Code generation** for repositories, DAOs, and database tables
- **Relationship support**: `OneToMany` and `ManyToOne` with cascade operations
- **JSON serialization** compatibility with `json_annotation`
- **Type-safe queries** with filtering, sorting, and pagination

### 🌐 Flexible API Integration
- **Pluggable API adapters** for different REST API patterns
- **Custom HTTP headers** and authentication support
- **Error handling** with comprehensive exception types
- **Request/response interceptors** for logging and debugging

### ⚡ Reactive Data Streams
- **Real-time UI updates** with `watchOne()` and `watchAll()` streams
- **Repository change events** for fine-grained reactivity
- **Automatic UI synchronization** when data changes locally or remotely

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  synquill: ^1.0.0
  drift: ^2.14.0
  json_annotation: ^4.8.1

dev_dependencies:
  synquill_gen: ^1.0.0
  build_runner: ^2.4.6
  drift_dev: ^2.14.0
  json_serializable: ^6.7.0
```

## 🏁 Quick Start

### 1. Define Your Models

```dart
import 'package:synquill/synquill.dart';
import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';

@JsonSerializable()
@SynquillRepository(
  adapters: [JsonApiAdapter, UserApiAdapter],
  relations: [
    OneToMany(target: Todo, mappedBy: 'userId'),
    OneToMany(target: Post, mappedBy: 'userId'),
  ],
)
class User extends SynquillDataModel<User> {
  @override
  final String id;
  final String name;
  final String email;

  User({
    String? id,
    required this.name,
    required this.email,
  }) : id = id ?? generateCuid();

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  
  @override
  Map<String, dynamic> toJson() => _$UserToJson(this);
}

@JsonSerializable()
@SynquillRepository(
  adapters: [JsonApiAdapter, TodoApiAdapter],
  relations: [
    ManyToOne(target: User, foreignKeyColumn: 'userId'),
  ],
)
class Todo extends SynquillDataModel<Todo> {
  @override
  final String id;
  final String title;
  final bool isCompleted;
  final String userId;

  Todo({
    String? id,
    required this.title,
    this.isCompleted = false,
    required this.userId,
  }) : id = id ?? generateCuid();

  factory Todo.fromJson(Map<String, dynamic> json) => _$TodoFromJson(json);
  
  @override
  Map<String, dynamic> toJson() => _$TodoToJson(this);
}
```

### 2. Create Custom API Adapters

```dart
// Base adapter with shared configuration
mixin JsonApiAdapter on BasicApiAdapter {
  @override
  Uri get baseUrl => Uri.parse('https://api.example.com');

  @override
  FutureOr<Map<String, String>> get baseHeaders async => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${await getAuthToken()}',
  };
}

// Model-specific adapter
mixin UserApiAdapter on BasicApiAdapter<User> {
  @override
  String get type => 'user';
  
  @override
  String get pluralType => 'users';

  @override
  FutureOr<Uri> urlForFindAll({Map<String, dynamic>? extra}) async {
    return baseUrl.resolve('api/v1/users');
  }
}

mixin TodoApiAdapter on BasicApiAdapter<Todo> {
  @override
  String get type => 'todo';
  
  @override
  String get pluralType => 'todos';

  @override
  FutureOr<Uri> urlForFindAll({Map<String, dynamic>? extra}) async {
    // Context-aware URLs - todos belong to users
    final users = await SynquillStorage.instance.users
        .findAll(loadPolicy: DataLoadPolicy.localOnly);
    
    if (users.isNotEmpty) {
      return baseUrl.resolve('api/v1/users/${users.first.id}/todos');
    }
    return baseUrl.resolve('api/v1/todos');
  }
}
```

### 3. Initialize the Storage System

```dart
import 'package:path_provider/path_provider.dart';
import 'package:synquill/synquill.generated.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize database
  final database = SynquillDatabase(
      LazyDatabase(
        () => driftDatabase(
          name: 'synquill.db',
          native: DriftNativeOptions(
            shareAcrossIsolates: true, // to sync between main thread and background isolate
            databaseDirectory: getApplicationSupportDirectory,
          ),
        ),
      ),
    );
  
  // Configure and initialize Synquill
  await SynquillStorage.init(
    database: database,
    config: const SynquillStorageConfig(
      defaultSavePolicy: DataSavePolicy.localFirst,
      defaultLoadPolicy: DataLoadPolicy.localThenRemote,
      foregroundQueueConcurrency: 3,
      backgroundQueueConcurrency: 1,
    ),
    logger: Logger('MyApp'),
    initializeFn: initializeSynquillStorage,
    // provide your own connectivity stream and check function
    connectivityChecker: () async =>
        await InternetConnection().hasInternetAccess,
    connectivityStream: InternetConnection()
        .onStatusChange
        .map((status) => status == InternetStatus.connected),
  );

  runApp(MyApp());
}
```

## 📚 Core Concepts

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

## 🔍 Querying Data

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
      field: TodoFields.createdAt, d
      irection: SortDirection.descending
    )],
  ),
);

// Load related user for a todo
final todo = await todoRepository.findOne('todo-id');
final todoOwner = await todo.loadUser();
```

## 📡 Reactive Data Streams

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

## 🔄 Model Operations

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
//final refreshedUser = await savedUser.refresh();
```

### Bulk Operations

```dart
// bulk save/update is not supported yet

```

## 🔗 Relationships

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

## 🌐 API Adapter Customization

### HTTP Methods and URLs

```dart
mixin CustomApiAdapter on BasicApiAdapter<MyModel> {
  @override
  String methodForCreate({Map<String, dynamic>? extra}) => 'POST';
  
  @override
  String methodForUpdate({Map<String, dynamic>? extra}) => 'PATCH';
  
  @override
  String methodForDelete({Map<String, dynamic>? extra}) => 'DELETE';

  @override
  FutureOr<Uri> urlForCreate({Map<String, dynamic>? extra}) async {
    return baseUrl.resolve('api/v2/models');
  }

  @override
  FutureOr<Uri> urlForUpdate(String id, {Map<String, dynamic>? extra}) async {
    return baseUrl.resolve('api/v2/models/$id');
  }
}
```

### Custom Headers and Authentication

```dart
mixin AuthenticatedAdapter on BasicApiAdapter {
  @override
  FutureOr<Map<String, String>> get baseHeaders async {
    final token = await getAuthToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'X-API-Version': '2.0',
    };
  }
}
```

### Response Parsing

```dart
mixin CustomResponseAdapter on BasicApiAdapter<MyModel> {
  @override
  MyModel? parseFindOneResponse(dynamic responseData, Response response) {
    if (responseData is Map<String, dynamic>) {
      // Handle wrapped responses
      final data = responseData['data'] ?? responseData;
      return fromJson(data);
    }
    return super.parseFindOneResponse(responseData, response);
  }

  @override
  List<MyModel> parseFindAllResponse(dynamic responseData, Response response) {
    if (responseData is Map<String, dynamic>) {
      // Handle paginated responses
      final items = responseData['items'] as List<dynamic>? ?? [];
      return items.map((item) => fromJson(item)).toList();
    }
    return super.parseFindAllResponse(responseData, response);
  }
}
```

## ⚙️ Configuration

### Storage Configuration

```dart
const config = SynquillStorageConfig(
  // Default policies
  defaultSavePolicy: DataSavePolicy.localFirst,
  defaultLoadPolicy: DataLoadPolicy.localThenRemote,
  
  // Concurrency limits
  foregroundQueueConcurrency: 3,
  backgroundQueueConcurrency: 1,
  
  // Retry configuration
  maxRetryAttempts: 5,
  initialRetryDelay: Duration(seconds: 1),
  maxRetryDelay: Duration(minutes: 5),
  
  // Connectivity
  enableInternetMonitoring: true,
  connectivityCheckInterval: Duration(seconds: 30),
);
```

### Background Sync

Configure automatic background synchronization:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Workmanager().initialize(
      callbackDispatcher, // The top level function, aka callbackDispatcher
      isInDebugMode: true // If enabled it will post a notification
      // whenever the task is running. Handy for debugging tasks
      );
  Workmanager().registerPeriodicTask(
    'synquill_periodic_sync_task',
    'sync_task',
    frequency: const Duration(minutes: 15), // Adjust as needed
    initialDelay: const Duration(seconds: 10), // Optional initial delay
    constraints: Constraints(
      networkType: NetworkType.connected, // Only run when connected to network
      requiresBatteryNotLow: true, // Avoid running on low battery
      requiresCharging: false, // Can run on battery power
    ),
  );
  // ... 
}

/// Background task dispatcher for WorkManager
///
/// This function demonstrates proper usage of SyncedStorage background sync
/// methods with required pragma annotation for isolate accessibility.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Create database instance for background isolate
      final database = SynquillDatabase(
        LazyDatabase(
          () => driftDatabase(
            name: 'synquill.db', // same database file
            native: DriftNativeOptions(
              shareAcrossIsolates: true, // same sync option
              databaseDirectory: getApplicationSupportDirectory,
            ),
          ),
        ),
      );

      // Initialize SyncedStorage in background isolate
      await SynquillStorage.initForBackgroundIsolate(
        database: database,
        config: SynquillStorageConfig(
          defaultSavePolicy: DataSavePolicy.localFirst,
          defaultLoadPolicy: DataLoadPolicy.localThenRemote,
          backgroundQueueConcurrency: 1,
        ),
        initializeFn: initializeSynquillStorage,
      );

      // Process background sync tasks
      await SynquillStorage.processBackgroundSync();

      // close the SynquillStorage instance to avoid resource leaks
      await SynquillStorage.close();
      return true;
    } catch (e, stackTrace) {
      //print("Background sync failed: $e");
      //print("Stack trace: $stackTrace");
      return false;
    }
  });
}
```

## 🛠️ Advanced Features

### Custom Field Indexing

```dart
class User extends SynquillDataModel<User> {
  @Indexed(name: 'user_email_idx', unique: true)
  final String email;
  
  @Indexed(name: 'user_name_idx')
  final String name;
}
```

### Database Migrations

```dart
TODO: describe
```

### Error Handling

```dart
try {
  final user = await userRepository.findOneOrFail('invalid-id');
} on NotFoundException catch (e) {
  print('User not found: ${e.message}');
} on ApiException catch (e) {
  print('API error: ${e.message}, Status: ${e.statusCode}');
} on SynquillStorageException catch (e) {
  print('Storage error: ${e.message}');
}
```

### Queue Management

```dart
// Get queue status
final stats = SynquillStorage.queueManager.getQueueStats();
print('Foreground pending tasks: '
    '${stats[QueueType.foreground]?.pendingTasks}');

```

## 📖 API Reference

### Core Classes

- **`SynquillDataModel<T>`** - Base class for all models
- **`SynquillRepository<T>`** - Generated repository for each model
- **`SynquillStorage`** - Main storage manager and entry point
- **`QueryParams`** - Query configuration for filtering, sorting, pagination

### Data Policies

- **`DataSavePolicy`** - `localFirst`, `remoteFirst`
- **`DataLoadPolicy`** - `localOnly`, `localThenRemote`, `remoteFirst`

### Relationship Annotations

- **`@OneToMany`** - One-to-many relationship
- **`@ManyToOne`** - Many-to-one relationship
- **`@Indexed`** - Database index configuration

### Repository Methods

```dart
// Query methods
Future<T?> findOne(String id, {DataLoadPolicy? loadPolicy, QueryParams? queryParams});
Future<T> findOneOrFail(String id, {DataLoadPolicy? loadPolicy, QueryParams? queryParams});
Future<List<T>> findAll({DataLoadPolicy? loadPolicy, QueryParams? queryParams});

// Watch methods (reactive streams)
Stream<T?> watchOne(String id, {DataLoadPolicy? loadPolicy, QueryParams? queryParams});
Stream<List<T>> watchAll({QueryParams? queryParams});

// Mutation methods
Future<T> save(T model, {DataSavePolicy? savePolicy});
Future<void> delete(String id, {DataSavePolicy? savePolicy});

// Repository events
Stream<RepositoryChange<T>> get changes;
```

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Related Packages

- **[drift](https://pub.dev/packages/drift)** - SQLite database toolkit
- **[json_annotation](https://pub.dev/packages/json_annotation)** - JSON serialization
- **[dio](https://pub.dev/packages/dio)** - HTTP client for API communication
- **[logging](https://pub.dev/packages/logging)** - Logging utilities

---

Built with ❤️ for the Flutter community


