# Synquill

A powerful Flutter package for offline-first data management with automatic REST API synchronization. Built on top of Drift for robust local storage and featuring intelligent sync queues for seamless online/offline operation.

> **Note**: This package is inspired by [flutter_data](https://pub.dev/packages/flutter_data), a fantastic data layer solution for Flutter applications.

[![pub package](https://img.shields.io/pub/v/synquill.svg)](https://pub.dev/packages/synquill)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 📋 Table of Contents

- [🚀 Key Features](#-key-features)
  - [📱 Offline-First Architecture](#-offline-first-architecture)
  - [🔄 Intelligent Synchronization](#-intelligent-synchronization)
  - [🏗️ Model-Driven Development](#️-model-driven-development)
  - [🌐 Flexible API Integration](#-flexible-api-integration)
  - [⚡ Reactive Data Streams](#-reactive-data-streams)
- [📦 Installation](#-installation)
- [🏁 Quick Start](#-quick-start)
  - [1. Define Your Models](#1-define-your-models)
  - [2. Create Custom API Adapters](#2-create-custom-api-adapters)
  - [3. Initialize the Storage System](#3-initialize-the-storage-system)
- [📚 Core Concepts](#-core-concepts)
  - [Data Save Policies](#data-save-policies)
  - [Data Load Policies](#data-load-policies)
  - [Dependency-Based Sync Ordering](#dependency-based-sync-ordering)
- [🔍 Querying Data](#-querying-data)
  - [Repository-Level Queries](#repository-level-queries)
  - [Model-Level Relationship Queries](#model-level-relationship-queries)
- [📡 Reactive Data Streams](#-reactive-data-streams)
  - [Watch for Real-time Updates](#watch-for-real-time-updates)
  - [Repository Change Events](#repository-change-events)
- [🔄 Model Operations](#-model-operations)
  - [Instance Methods](#instance-methods)
  - [Bulk Operations](#bulk-operations)
- [🔗 Relationships](#-relationships)
  - [OneToMany Relationships](#onetomany-relationships)
  - [ManyToOne Relationships](#manytoone-relationships)
- [🔗 Dependency-Based Sync Ordering](#-dependency-based-sync-ordering-1)
  - [How It Works](#how-it-works)
  - [Dependency Levels](#dependency-levels)
  - [Automatic Sync Task Ordering](#automatic-sync-task-ordering)
  - [Circular Dependency Detection](#circular-dependency-detection)
  - [Complex Dependency Patterns](#complex-dependency-patterns)
  - [Debug Information](#debug-information)
- [🌐 API Adapter Customization](#-api-adapter-customization)
  - [HTTP Methods and URLs](#http-methods-and-urls)
  - [Custom Headers and Authentication](#custom-headers-and-authentication)
  - [Response Parsing](#response-parsing)
- [⚙️ Configuration](#️-configuration)
  - [Storage Configuration](#storage-configuration)
  - [Background Sync](#background-sync)
  - [Background Sync Manager Controls](#background-sync-manager-controls)
    - [App Lifecycle Integration](#app-lifecycle-integration)
    - [Manual Sync Mode Control](#manual-sync-mode-control)
    - [Sync Mode Behavior](#sync-mode-behavior)
    - [Background Isolate Support](#background-isolate-support)
- [🛠️ Advanced Features](#️-advanced-features)
  - [Custom Field Indexing](#custom-field-indexing)
  - [Database Migrations](#database-migrations)
  - [Error Handling](#error-handling)
  - [Queue Management](#queue-management)
    - [Queue Types](#queue-types)
    - [Queue Statistics and Monitoring](#queue-statistics-and-monitoring)
    - [Capacity Management](#capacity-management)
    - [Connectivity-Responsive Queue Management](#connectivity-responsive-queue-management)
    - [Idempotency and Duplicate Prevention](#idempotency-and-duplicate-prevention)
    - [Queue Integration with RetryExecutor](#queue-integration-with-retryexecutor)
- [🔄 Offline Retry Mechanism](#-offline-retry-mechanism)
- [⚠️ Current Limitations](#️-current-limitations)
- [📖 API Reference](#-api-reference)
  - [Core Classes](#core-classes)
  - [Queue System Classes](#queue-system-classes)
  - [Data Policies](#data-policies)
  - [Relationship Annotations](#relationship-annotations)
  - [Repository Methods](#repository-methods)
- [🤝 Contributing](#-contributing)
- [📄 License](#-license)
- [🔗 Related Packages](#-related-packages)

## 🚀 Key Features

### 📱 Offline-First Architecture
- **Local-first operations** with Drift-powered SQLite database
- **Automatic background sync** with configurable retry mechanisms
- **Smart queue management** for operations with related data dependencies
- **Works completely offline** - sync when connectivity returns

### 🔄 Intelligent Synchronization
- **Bidirectional sync** between local storage and REST APIs
- **Configurable sync policies**: `localFirst`, `remoteFirst`, `localThenRemote`
- **Dependency-based sync ordering** with hierarchical task resolution
- **Background processing** capabilities, enabling integration with tools like WorkManager
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

### Dependency-Based Sync Ordering

Synquill automatically ensures sync operations respect model relationships:

```dart
// Parent models (Users) are always synced before child models (Todos)
// This prevents foreign key constraint violations during sync operations
// See the "Dependency-Based Sync Ordering" section for detailed information
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
// final refreshedUser = await savedUser.refresh();
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

## 🔗 Dependency-Based Sync Ordering

Synquill automatically manages sync task ordering based on model relationships to ensure data integrity during synchronization. The `DependencyResolver` class analyzes `@ManyToOne` relationships to create a hierarchical sync order where parent models are always synced before their dependent children.

### How It Works

When models have `@ManyToOne` relationships, Synquill automatically registers dependencies during initialization:

```dart
// Generated during build - registers Todo's dependency on User
DependencyResolver.registerDependency('Todo', 'User');
DependencyResolver.registerDependency('Project', 'User');
DependencyResolver.registerDependency('Task', 'Project');
```

### Dependency Levels

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

### Automatic Sync Task Ordering

During sync operations, tasks are automatically ordered by dependency level:

```dart
// Sync queue tasks are processed in dependency order:
// 1. All User operations (level 0)
// 2. All Project and Todo operations (level 1) 
// 3. All Task operations (level 2)

// Within the same level, tasks maintain FIFO order by creation time
```

### Circular Dependency Detection

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

### Complex Dependency Patterns

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

### Debug Information

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
/// This function demonstrates proper usage of SynquillStorage background sync
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

      // Initialize SynquillStorage in background isolate
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

**Note**: During background sync processing, Synquill automatically applies dependency-based task ordering to ensure parent records are synchronized before their dependent children. This prevents foreign key constraint violations and maintains data integrity across sync operations.

### Background Sync Manager Controls

Synquill provides runtime controls to adjust sync behavior based on your app's lifecycle state. These methods allow you to optimize battery usage and responsiveness by switching between foreground and background sync modes.

#### App Lifecycle Integration

The most common use case is integrating with Flutter's app lifecycle to automatically adjust sync behavior:

```dart
class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // App is active - enable foreground mode for faster sync
        SynquillStorage.enableForegroundMode(forceSync: true);
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // App is in background - switch to background mode to save battery
        SynquillStorage.enableBackgroundMode();
        break;
      default:
        break;
    }
  }
}
```

#### Manual Sync Mode Control

You can also manually control sync modes based on your app's specific needs:

```dart
// Switch to foreground mode for immediate responsiveness
// Optional forceSync parameter triggers immediate sync processing
SynquillStorage.enableForegroundMode(forceSync: true);

// Switch to background mode for battery optimization
SynquillStorage.enableBackgroundMode();

// Check if background sync manager is ready
final isReady = SynquillStorage.backgroundSyncManager.isReadyForBackgroundSync;
if (isReady) {
  // Manually trigger background sync processing
  await SynquillStorage.instance.processBackgroundSyncTasks();
}
```

#### Sync Mode Behavior

**Foreground Mode**:
- Higher polling frequency for immediate sync operations
- Shorter retry intervals for failed operations
- Optimized for responsiveness when app is active
- Optional immediate sync trigger with `forceSync: true`

**Background Mode**:
- Lower polling frequency to conserve battery
- Longer retry intervals to reduce CPU usage
- Optimized for battery life when app is inactive
- Automatic timeout (20 seconds) for background tasks

#### Background Isolate Support

These methods are also available in background isolates with proper pragma annotations:

```dart
@pragma('vm:entry-point')
void backgroundTaskHandler() {
  // Switch modes even in background isolates
  SynquillStorage.enableBackgroundMode();
  SynquillStorage.enableForegroundMode();
  
  // Process background sync tasks
  await SynquillStorage.processBackgroundSync();
}
```

The background sync manager automatically handles mode transitions and ensures optimal performance regardless of your app's state.

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

Synquill uses a sophisticated multi-queue system to handle different types of operations with optimized concurrency and reliability. The `RequestQueueManager` manages three specialized queues:

#### Queue Types

**Foreground Queue** (`QueueType.foreground`)
- **Purpose**: Immediate user operations (remoteFirst writes)
- **Concurrency**: 1 (sequential for data consistency)
- **Delay**: 50ms between tasks
- **Use Cases**: User-initiated saves, updates, deletes
- **Timeout**: 10 seconds when waiting for capacity

**Load Queue** (`QueueType.load`)
- **Purpose**: Background data fetching (localThenRemote reads)
- **Concurrency**: 2 (parallel for faster loading)
- **Delay**: 50ms between tasks
- **Use Cases**: UI refresh, background data synchronization
- **Timeout**: 5 seconds when waiting for capacity

**Background Queue** (`QueueType.background`)
- **Purpose**: Offline sync operations (localFirst writes)
- **Concurrency**: 1 (sequential for dependency ordering)
- **Delay**: 100ms between tasks
- **Use Cases**: Retry failed operations, offline-to-online sync
- **Timeout**: 2 seconds when waiting for capacity

#### Queue Statistics and Monitoring

```dart
// Get comprehensive queue statistics
final stats = SynquillStorage.queueManager.getQueueStats();

// Check each queue type
for (final queueType in QueueType.values) {
  final queueStats = stats[queueType]!;
  print('${queueType.name} Queue:');
  print('  Active + Pending: ${queueStats.activeAndPendingTasks}');
  print('  Pending: ${queueStats.pendingTasks}');
}

// Monitor specific queue
final foregroundStats = stats[QueueType.foreground]!;
if (foregroundStats.activeAndPendingTasks > 10) {
  print('Foreground queue is busy - consider deferring non-critical operations');
}
```

#### Capacity Management

Each queue has configurable capacity limits to prevent memory issues:

```dart
await SynquillStorage.init(
  database: database,
  config: const SynquillStorageConfig(
    // Queue capacity limits (default: 50 each)
    maxForegroundQueueCapacity: 30,
    maxLoadQueueCapacity: 40,
    maxBackgroundQueueCapacity: 100,
    
    // Capacity wait timeouts
    foregroundQueueCapacityTimeout: Duration(seconds: 15),
    loadQueueCapacityTimeout: Duration(seconds: 8),
    backgroundQueueCapacityTimeout: Duration(seconds: 5),
    
    // Capacity polling interval
    queueCapacityCheckInterval: Duration(milliseconds: 50),
  ),
);
```

#### Connectivity-Responsive Queue Management

The queue system automatically responds to connectivity changes:

```dart
// When connectivity is lost - queues are cleared to prevent timeouts
// Tasks remain in sync_queue database for later processing
await SynquillStorage.queueManager.clearQueuesOnDisconnect();

// When connectivity returns - processing resumes immediately
await SynquillStorage.queueManager.restoreQueuesOnConnect();

// Manual queue operations
await SynquillStorage.queueManager.joinAll(); // Wait for all tasks to complete
await SynquillStorage.queueManager.dispose(); // Clean shutdown
```

#### Idempotency and Duplicate Prevention

The queue system prevents duplicate operations using idempotency keys:

```dart
// Create a network task with idempotency key
final task = NetworkTask<User>(
  exec: () => apiAdapter.createUser(user),
  idempotencyKey: 'create-user-${user.id}-${cuid()}',
  operation: SyncOperation.create,
  modelType: 'User',
  modelId: user.id,
  taskName: 'Create User ${user.name}',
);

// Enqueue to specific queue type
try {
  final result = await SynquillStorage.queueManager.enqueueTask(
    task,
    queueType: QueueType.foreground,
  );
  print('User created: ${result.id}');
} catch (e) {
  if (e.toString().contains('Duplicate task')) {
    print('Task already in progress');
  } else if (e.toString().contains('capacity')) {
    print('Queue is full - try again later');
  }
}
```

#### Queue Integration with RetryExecutor

The queue system works seamlessly with the RetryExecutor for background sync:

```dart
// RetryExecutor processes sync queue and uses appropriate queues
final retryExecutor = SynquillStorage.retryExecutor;

// Start with adaptive polling (foreground/background modes)
retryExecutor.start(backgroundMode: false);

// Switch modes based on app state
retryExecutor.setBackgroundMode(true);  // Longer poll intervals

// Manual processing trigger
await retryExecutor.processDueTasksNow(forceSync: true);

// Network error tasks get priority in queue processing
// Dependency ordering ensures related tasks execute in correct sequence
```

## 🔄 Offline Retry Mechanism

**TBD** - Detailed explanation of the offline retry mechanism will be provided in a future update.

## ⚠️ Current Limitations

While Synquill provides a robust foundation for offline-first data management, there are several limitations to be aware of in the current version:

### Conflict Resolution
- **No automated conflict resolution yet:** Synquill currently lacks built-in mechanisms to resolve conflicts when data is modified simultaneously on the local device and the remote server. Developers are responsible for implementing their own conflict resolution strategies. If remote data differs from local data after a sync, local updates will not be automatically triggered.
- Future versions will include configurable conflict resolution strategies (last-write-wins, manual resolution, custom merge functions)

### Framework Support
- **Freezed support is not tested yet** - While the package may work with `freezed` models, compatibility has not been thoroughly tested
- **Desktop and web platform support not tested yet** - Development has focused on mobile platforms (iOS/Android), desktop and web compatibility needs validation

### Relationship Support
- **Relations support is currently limited**:
  - **No self-to-self relations** - Models cannot reference themselves (e.g., User with manager/subordinate relationships)
  - **No one-to-one relations** - Only `@OneToMany` and `@ManyToOne` relationships are currently supported
  - **No many-to-many relations** - Complex relationships requiring junction tables are not supported yet

### Database Indexing
- **Indexing support is limited**:
  - **No combined indexes yet** - Only single-field indexes are supported via `@Indexed` annotation
  - Composite indexes spanning multiple fields will be added in future versions

### Reactive Streams
- **Reactive streams are local-only**:
  - **`watchOne()` and `watchAll()` methods currently only watch local database changes** - These streams do not automatically react to remote data changes or sync operations
  - Remote data changes are only reflected in the streams after they have been synced to the local database
  - Future versions will include options to trigger remote data fetching when streams are subscribed to

These limitations are actively being addressed in the development roadmap. Contributions and feedback are welcome to help prioritize these features.

## 📖 API Reference

### Core Classes

- **`SynquillDataModel<T>`** - Base class for all models
- **`SynquillRepository<T>`** - Generated repository for each model
- **`SynquillStorage`** - Main storage manager and entry point
- **`QueryParams`** - Query configuration for filtering, sorting, pagination
- **`DependencyResolver`** - Manages hierarchical sync ordering based on model relationships
- **`RequestQueueManager`** - Multi-queue system for network operation management
- **`NetworkTask<T>`** - Encapsulates network operations with idempotency and error handling
- **`RetryExecutor`** - Background processor for failed sync operations

### Queue System Classes

- **`QueueType`** - Enum defining queue types (foreground, load, background)
- **`QueueStats`** - Queue statistics (active tasks, pending tasks)
- **`RequestQueue`** - Individual queue with configurable concurrency and delays

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

Contributions are welcome! Please feel free to submit pull requests, open issues, or ask questions on GitHub.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Related Packages

- **[drift](https://pub.dev/packages/drift)** - SQLite database toolkit
- **[json_annotation](https://pub.dev/packages/json_annotation)** - JSON serialization
- **[dio](https://pub.dev/packages/dio)** - HTTP client for API communication
- **[logging](https://pub.dev/packages/logging)** - Logging utilities

---

Built with ❤️ for the Flutter community


