# Synquill

A powerful Flutter package for offline-first data management with automatic REST API synchronization. Built on top of Drift for robust local storage and featuring intelligent sync queues for seamless online/offline operation.

> **Note**: This package is inspired by [flutter_data](https://pub.dev/packages/flutter_data), a fantastic data layer solution for Flutter applications.

[![pub package](https://img.shields.io/pub/v/synquill.svg)](https://pub.dev/packages/synquill)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## 🚀 Why Synquill?

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
  json_annotation: ^4.9.0
  synquill: ^1.0.0

dev_dependencies:
  synquill_gen: ^1.0.0
  build_runner: ^2.4.14
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

  User.fromDb({
    required this.id,
    required this.name,
    required this.email,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSyncedAt,
  }) {
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
    this.lastSyncedAt = lastSyncedAt;
  }

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

  Todo.fromDb({
    required this.id,
    required this.title,
    required this.isCompleted,
    required this.userId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSyncedAt,
  }) {
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
    this.lastSyncedAt = lastSyncedAt;
  }

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

## 📚 Documentation

For comprehensive documentation, guides, and advanced features, please visit the [documentation directory](./doc/).

- **[Getting Started Guide](./doc/guide.md)** - Core concepts, querying, operations, and relationships
- **[API Adapters](./doc/api-adapters.md)** - Customizing HTTP methods, headers, and response parsing
- **[Configuration](./doc/configuration.md)** - Storage configuration and background sync setup
- **[Advanced Features](./doc/advanced-features.md)** - Queue management, dependency resolution, and more
- **[API Reference](./doc/api-reference.md)** - Complete API documentation

- **[Advanced Topics]** - Deep dive into complex features
  - [Queue Management](queues.md) - Sync queue system and task processing
  - [Dependency Resolution](dependency-resolver.md) - Hierarchical task dependencies

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


