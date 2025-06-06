# Synquill Example App

This is a comprehensive Flutter example app that demonstrates how to use the `synquill` package for offline-first data synchronization.

## Overview

This example implements a multi-model app featuring users, todos, and posts that showcases:

- **Model Definition**: How to create models with `@SynquillRepository` annotation
- **Data Synchronization**: Demonstrating `localFirst` and `remoteFirst` policies
- **Relationship Management**: One-to-many and many-to-one relationships between models
- **Background Sync**: Automatic background synchronization with WorkManager
- **Real-time Updates**: Stream-based reactive UI with BLoC pattern
- **Database Management**: Drift-powered local database with custom migrations

## Features

### Core Functionality
- ✅ **Multi-model support**: Users, Todos, and Posts
- ✅ **Relationship management**: Users have many todos and posts
- ✅ **Real-time UI updates**: Stream-based reactive interface with `watch...` methods
- ✅ **Advanced querying**: `findAll()`, `findOne()` with filtering, sorting, pagination
- ✅ **Offline-first operation**: Works without internet connection
- ✅ **Automatic synchronization**: Background sync with remote API
- ✅ **Data persistence**: Local SQLite database with Drift
- ✅ **Custom API adapters**: Model-specific REST API configurations

### Data Management
- ✅ **Add/edit/delete** todos and posts
- ✅ **Toggle todo completion** status
- ✅ **User-scoped data**: All todos and posts belong to users
- ✅ **Reactive queries**: Real-time data streams via `watchAll()`, `watchOne()`
- ✅ **Relationship loading**: Model-level `loadTodos()`, `watchPosts()` methods
- ✅ **Database viewer**: Built-in Drift database inspector
- ✅ **Custom migrations**: Database schema evolution support
- ✅ **Initial data setup**: Automatic demo data generation

### Synchronization Features
- ✅ **Background sync**: Periodic sync every 15 minutes via WorkManager
- ✅ **Connectivity monitoring**: Internet connection awareness
- ✅ **Foreground/background modes**: Optimized sync behavior
- ✅ **Queue management**: Configurable concurrency limits
- ✅ **Error handling**: Robust error recovery and logging

## Model Architecture

The app demonstrates three interconnected models:

### User Model
```dart
@SynquillRepository(
  adapters: [JsonApiAdapter, UserApiAdapter],
  relations: [
    OneToMany(target: Todo, mappedBy: 'userId'),
    OneToMany(target: Post, mappedBy: 'userId'),
  ],
)
class User extends SynquillDataModel<User> {
  final String id;
  final String name;
  // ... implementation
}
```

### Todo Model
```dart
@SynquillRepository(
  adapters: [JsonApiAdapter, TodoApiAdapter],
  relations: [
    ManyToOne(target: User, foreignKeyColumn: 'userId'),
  ],
)
class Todo extends ContactBase<Todo> {
  final String title;
  final bool isCompleted;
  final String userId;
  // ... implementation
}
```

### Post Model
```dart
@SynquillRepository(
  adapters: [JsonApiAdapter, PostApiAdapter],
  relations: [
    ManyToOne(target: User, foreignKeyColumn: 'userId'),
  ],
)
class Post extends SynquillDataModel<Post> {
  final String title;
  final String body;
  final String userId;
  // ... implementation
}
```

## Data Synchronization Policies

The app demonstrates different synchronization strategies:

### LocalFirst Policy
Used for new content creation - saves to local database first, then syncs to remote:
```dart
await todo.save(savePolicy: DataSavePolicy.localFirst);
```

### RemoteFirst Policy
Used for deletions - attempts remote deletion first, then updates local database:
```dart
await SynquillStorage.instance.todos.delete(
  todoId,
  savePolicy: DataSavePolicy.remoteFirst,
);
```

### Load Policies
- **LocalThenRemote**: Load from local database, then fetch fresh data from API
- **LocalOnly**: Load only from local database (offline mode)

## Data Query Methods

The app demonstrates comprehensive data query capabilities available on both repositories and models:

### Repository-level Queries
Access data through the global repository instances:

#### Find Methods
```dart
// Find all todos
final todos = await SynquillStorage.instance.todos.findAll(
  loadPolicy: DataLoadPolicy.localThenRemote,
  queryParams: QueryParams(
    sorts: [SortParam('createdAt', SortDirection.desc)],
    filters: [FilterParam('isCompleted', false)],
  ),
);

// Find todos by user ID
final userTodos = await SynquillStorage.instance.todos.findAll(
  queryParams: QueryParams(
    filters: [FilterParam('userId', '1')],
  ),
);

// Find single todo by ID
final todo = await SynquillStorage.instance.todos.findOne(
  'todo-id',
  loadPolicy: DataLoadPolicy.localOnly,
);
```

#### Watch Methods (Real-time Streams)
```dart
// Watch all todos with real-time updates
SynquillStorage.instance.todos.watchAll(
  queryParams: QueryParams(
    sorts: [SortParam('createdAt', SortDirection.desc)],
  ),
).listen((todos) {
  // UI automatically updates when data changes
  setState(() => _todos = todos);
});

// Watch single todo
SynquillStorage.instance.todos.watchOne('todo-id').listen((todo) {
  // React to specific todo changes
});
```

### Model-level Relationship Queries
Access related data directly through model instances:

#### User → Todos/Posts
```dart
final user = await SynquillStorage.instance.users.findOne('1');

// Load user's todos
final userTodos = await user.loadTodos(
  loadPolicy: DataLoadPolicy.localThenRemote,
  queryParams: QueryParams(
    filters: [FilterParam('isCompleted', false)],
  ),
);

// Watch user's posts with real-time updates
user.watchPosts(
  queryParams: QueryParams(
    sorts: [SortParam('createdAt', SortDirection.desc)],
  ),
).listen((posts) {
  // UI updates when user's posts change
});
```

#### Advanced Query Parameters
```dart
// Complex filtering and sorting
final queryParams = QueryParams(
  filters: [
    FilterParam('isCompleted', false),
    FilterParam('createdAt', DateTime.now().subtract(Duration(days: 7)), 
                operator: FilterOperator.greaterThan),
  ],
  sorts: [
    SortParam('priority', SortDirection.desc),
    SortParam('createdAt', SortDirection.asc),
  ],
  limit: 20,
  offset: 0,
);

final recentTodos = await SynquillStorage.instance.todos.findAll(
  queryParams: queryParams,
  loadPolicy: DataLoadPolicy.localThenRemote,
);
```

### Stream-based UI Updates
The example demonstrates reactive UI using watch methods:

```dart
// In BLoC or StatefulWidget
StreamSubscription<List<Todo>>? _todosSubscription;

void _startWatching() {
  _todosSubscription = SynquillStorage.instance.todos
      .watchAll(
        queryParams: QueryParams(
          sorts: [SortParam('createdAt', SortDirection.desc)],
        ),
      )
      .listen((todos) {
    // Automatic UI updates
    add(TodosUpdated(todos));
  });
}
```

## Background Synchronization

The app demonstrates robust background sync capabilities:

### WorkManager Integration
```dart
// Periodic background sync every 15 minutes
Workmanager().registerPeriodicTask(
  'synquill_periodic_sync_task',
  'sync_task',
  frequency: const Duration(minutes: 15),
  constraints: Constraints(
    networkType: NetworkType.connected,
    requiresBatteryNotLow: true,
  ),
);
```

### Background Isolate Handling
```dart
@pragma('vm:entry-point')
void callbackDispatcher() {
  // Initialize SynquillStorage for background isolate
  // Process pending sync operations
  // Handle cross-isolate database sharing
}
```

## Running the Example

1. **Navigate to the example directory:**
   ```bash
   cd synquill/example
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Generate code (if needed):**
   ```bash
   dart run build_runner build
   ```

4. **Run the app:**
   ```bash
   flutter run
   ```

## Code Generation

The example demonstrates the complete code generation workflow:

1. **Model Definitions**: Models with `@SynquillRepository()` annotations
2. **Generated Files**: Build runner generates:
   - `*.g.dart` - JSON serialization with json_annotation
   - `generated/*.g.dart` - Library-generated files
   - `synquill.generated.dart` - Database tables and repositories
3. **Database Setup**: Drift-powered SQLite with custom migrations
4. **API Adapters**: Custom REST API configurations per model

## Project Structure

```
lib/
├── main.dart                    # App entry point with WorkManager setup
├── synquill.generated.dart      # Generated database and repositories
├── adapters/
│   └── base_json_api_adapter.dart # Shared API configuration
├── blocs/                       # BLoC state management
│   ├── home/                    # Home screen state
│   ├── todos/                   # Todos management state
│   └── posts/                   # Posts management state
├── models/                      # Data models
│   ├── user.dart               # User model with relationships
│   ├── todo.dart               # Todo model with custom adapter
│   ├── post.dart               # Post model with custom adapter
│   └── *.g.dart                # Generated JSON serialization
├── screens/                     # UI screens
│   ├── home_screen.dart        # Main dashboard
│   ├── todos_screen.dart       # Todo management
│   └── posts_screen.dart       # Post management
└── generated/                   # Additional generated files
```

## Key Features Demonstrated

### Database Features
- **Drift Integration**: Full-featured SQLite database
- **Custom Migrations**: Schema evolution with `_performMigration`
- **Initial Data Setup**: Demo data creation with `_setupInitialData`
- **Database Inspector**: Built-in viewer with `drift_db_viewer`
- **Cross-Isolate Sharing**: Background sync with shared database

### Data Query & Reactive Updates
- **Repository Queries**: `findAll()`, `findOne()` with advanced filtering and sorting
- **Real-time Streams**: `watchAll()`, `watchOne()` for reactive UI updates
- **Relationship Queries**: Model-level `loadTodos()`, `watchPosts()` methods
- **Query Parameters**: Complex filtering, sorting, pagination support
- **Load Policies**: `localThenRemote`, `localOnly` data loading strategies

### API Integration
- **Custom Adapters**: Model-specific REST API configurations
- **Base Adapter**: Shared configuration with `BaseJsonApiAdapter`
- **Dynamic URLs**: Context-aware endpoint generation
- **Custom Headers**: Model-specific HTTP headers
- **Request/Response Logging**: Debug-friendly API monitoring

### State Management
- **BLoC Pattern**: Reactive state management with `flutter_bloc`
- **Stream Subscriptions**: Real-time UI updates from database changes
- **Error Handling**: Comprehensive error states and recovery
- **Loading States**: User-friendly loading indicators

### Connectivity & Sync
- **Internet Monitoring**: Real-time connectivity detection
- **Foreground/Background Modes**: Optimized sync behavior
- **Queue Management**: Configurable concurrency controls
- **Retry Logic**: Automatic retry for failed operations

## Configuration Examples

### SynquillStorage Initialization
```dart
await SynquillStorage.init(
  connectivityChecker: () async => await InternetConnection().hasInternetAccess,
  connectivityStream: InternetConnection().onStatusChange
      .map((status) => status == InternetStatus.connected),
  enableInternetMonitoring: true,
  database: database,
  config: const SynquillStorageConfig(
    defaultSavePolicy: DataSavePolicy.localFirst,
    defaultLoadPolicy: DataLoadPolicy.localThenRemote,
    foregroundQueueConcurrency: 1,
  ),
  initializeFn: initializeSynquillStorage,
);
```

### Database Version Management
```dart
@SynqillDatabaseVersion(1)
final database = SynquillDatabase(
  LazyDatabase(() => driftDatabase(
    name: 'synced_storage.db',
    native: DriftNativeOptions(
      shareAcrossIsolates: true,
      databaseDirectory: getApplicationSupportDirectory,
    ),
  )),
  onCustomMigration: _performMigration,
  onDatabaseCreated: _setupInitialData,
);
```

## Testing & Development

### Database Inspection
The app includes a built-in database viewer accessible via the storage icon in the app bar. This allows real-time inspection of:
- Table structures and data
- Sync queue status
- Relationship data
- Generated schema

### Logging
Comprehensive logging is enabled for debugging:
- Database operations
- API requests/responses
- Sync queue processing
- Background task execution

## API Documentation

For complete API documentation and advanced usage patterns, see the main `synquill` package documentation.
