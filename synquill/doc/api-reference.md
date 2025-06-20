# API Reference

This document provides comprehensive documentation for the Synquill library's public API.

## Core Classes

### SynquillStorage

The main entry point for the Synquill library, providing centralized access to the data storage system.

#### Initialization

```dart
static Future<void> init({
  required GeneratedDatabase database,
  SynquillStorageConfig? config,
  Logger? logger,
  void Function(GeneratedDatabase)? initializeFn,
  Stream<bool>? connectivityStream,
  Future<bool> Function()? connectivityChecker,
  bool enableInternetMonitoring = true,
})
```

Initializes the synced storage system. Must be called once before any other operations.

**Parameters:**
- `database`: The Drift database instance to use for local storage
- `config`: Optional configuration for the storage system
- `logger`: Optional custom logger implementation
- `initializeFn`: Optional function to call after database setup (typically the generated `initializeSynquillStorage` function)
- `connectivityStream`: Optional stream that emits connectivity status
- `connectivityChecker`: Optional function to check current connectivity
- `enableInternetMonitoring`: Whether to enable internet connection monitoring (defaults to true)

#### Properties

```dart
static SynquillStorage get instance
```
Returns the singleton instance. Throws `StateError` if not initialized.

```dart
static SynquillStorageConfig? get config
```
Returns the global configuration.

```dart
static GeneratedDatabase get database
```
Returns the global database instance.

```dart
static Logger get logger
```
Returns the global logger instance.

```dart
static RequestQueueManager get queueManager
```
Returns the global queue manager instance.

```dart
static RetryExecutor get retryExecutor
```
Returns the global retry executor instance.

```dart
static DependencyResolver get dependencyResolver
```
Returns the global dependency resolver instance.

#### Methods

```dart
T getRepository<T extends SynquillDataModel<T>>()
```
Retrieves a repository instance for the given model type.

```dart
SynquillRepositoryBase<SynquillDataModel<dynamic>>? getRepositoryByName(String modelTypeName)
```
Retrieves a repository instance by model type string name.

```dart
Future<void> processBackgroundSyncTasks()
```
Triggers background sync tasks to be processed immediately.

```dart
static Future<void> processBackgroundSync()
```
Static method to trigger background sync tasks without an instance.

```dart
static void enableBackgroundMode()
```
Switches the retry executor to background mode for battery optimization.

```dart
static void enableForegroundMode({bool forceSync = false})
```
Switches the retry executor to foreground mode for active use.

```dart
static Future<void> close()
```
Closes the synced storage system and releases all resources.

```dart
static Future<void> reset()
```
Resets the singleton instance and configuration (primarily for testing).

### SynquillStorageConfig

Configuration class for customizing the behavior of the SynquillStorage system.

#### Constructor

```dart
const SynquillStorageConfig({
  this.dio,
  this.keepConnectionAlive = true,
  this.foregroundQueueConcurrency = 1,
  this.backgroundQueueConcurrency = 2,
  this.defaultSavePolicy = DataSavePolicy.localFirst,
  this.defaultLoadPolicy = DataLoadPolicy.localThenRemote,
  this.initialRetryDelay = const Duration(seconds: 2),
  this.maxRetryDelay = const Duration(minutes: 5),
  this.backoffMultiplier = 2.0,
  this.jitterPercent = 0.2,
  this.maxRetryAttempts = 50,
  this.foregroundPollInterval = const Duration(seconds: 5),
  this.backgroundPollInterval = const Duration(minutes: 5),
  this.minRetryDelay = const Duration(seconds: 1),
  // ... additional configuration options
})
```

#### Key Properties

- `foregroundQueueConcurrency`: Concurrency level for foreground operations
- `backgroundQueueConcurrency`: Concurrency level for background operations
- `defaultSavePolicy`: Default save policy for all repositories
- `defaultLoadPolicy`: Default load policy for all repositories
- `initialRetryDelay`: Initial retry delay for failed sync operations
- `maxRetryDelay`: Maximum retry delay for failed sync operations
- `maxRetryAttempts`: Maximum number of retry attempts

### SynquillRepositoryBase<T>

Base class for synchronized repositories that handle data operations between local database and remote API.

#### Properties

```dart
Stream<RepositoryChange<T>> get changes
```
A broadcast stream of repository change events (created, updated, deleted, error).

#### Core Methods

**Find Operations:**
```dart
Future<T?> findOne(String id, {DataLoadPolicy? loadPolicy})
Future<List<T>> findAll({QueryParams? queryParams, DataLoadPolicy? loadPolicy})
```

**Watch Operations (Reactive Streams):**
```dart
Stream<T?> watchOne(String id, {bool fireImmediately = true})
Stream<List<T>> watchAll({QueryParams? queryParams, bool fireImmediately = true})
```
> **Note**: Reactive streams currently only watch local database changes. Remote data changes are reflected in streams only after they've been synced to the local database. See [Current Limitations](advanced-features.md#current-limitations) for more details.

**Save Operations:**
```dart
Future<T> save(T model, {DataSavePolicy? savePolicy})
```

**Delete Operations:**
```dart
Future<void> delete(String id, {DataSavePolicy? savePolicy})
```

**Relationship Operations:**
> **Note**: The method name identifies the relationship to load or watch. Generated model extensions provide type-safe methods for defined relationships (e.g., `todo.loadUser()`, `user.watchTodos()`).
```dart
Future<List<R>> loadUser<R extends SynquillDataModel<R>>(
  String id, {
  QueryParams? queryParams,
  DataLoadPolicy? loadPolicy,
  Map<String, dynamic>? extra
})

Stream<List<R>> watchTodos<R extends SynquillDataModel<R>>(
  String id, {
  QueryParams? queryParams,
})
```

## Data Model Classes

### SynquillDataModel<T>

Abstract base class for all data models in the Synquill system.

#### Required Properties

```dart
String get id
```
Unique identifier for the model instance.

#### Required Methods

```dart
Map<String, dynamic> toJson()
```
Converts the model instance to a JSON map.

```dart
T fromJson(Map<String, dynamic> json)
```
Creates a model instance from a JSON map.

```dart
T.fromDb({
  required String id,
  // ... other required fields
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? lastSyncedAt,
})
```
**Required named constructor** for deserializing from the database format. This constructor is used by Drift ORM to create model instances from database records.


#### Instance Methods

```dart
Future<T> save({DataSavePolicy? savePolicy})
```
Saves the current model instance.

```dart
Future<void> delete({DataSavePolicy? savePolicy})
```
Deletes the current model instance.

## API Adapter Classes

### ApiAdapterBase<TModel>

Abstract interface for REST API adapters used by SynquillStorage.

#### Required Properties

```dart
Uri get baseUrl
```
Base URL for the API.

```dart
String get type
```
Singular entity name (e.g., 'user').

```dart
String get pluralType
```
Plural entity name (e.g., 'users').

#### Optional Properties

```dart
FutureOr<Map<String, String>> get baseHeaders
```
HTTP headers applied to every request.

```dart
FutureOr<Map<String, String>> get headersWithContentType
```
HTTP headers for operations that send data.

#### HTTP Method Configuration

```dart
String methodForFind({Map<String, dynamic>? extra}) => 'GET'
String methodForCreate({Map<String, dynamic>? extra}) => 'POST'
String methodForUpdate({Map<String, dynamic>? extra}) => 'PATCH'
String methodForDelete({Map<String, dynamic>? extra}) => 'DELETE'
String methodForReplace({Map<String, dynamic>? extra}) => 'PUT'
```

#### URL Builder Methods

```dart
FutureOr<Uri> urlForFindOne(String id, {Map<String, dynamic>? extra})
FutureOr<Uri> urlForFindAll({Map<String, dynamic>? extra})
FutureOr<Uri> urlForCreate({Map<String, dynamic>? extra})
FutureOr<Uri> urlForUpdate(String id, {Map<String, dynamic>? extra})
FutureOr<Uri> urlForReplace(String id, {Map<String, dynamic>? extra})
FutureOr<Uri> urlForDelete(String id, {Map<String, dynamic>? extra})
```

#### CRUD Operations

```dart
Future<TModel?> findOne(String id, {
  Map<String, String>? headers,
  QueryParams? queryParams,
  Map<String, dynamic>? extra,
})

Future<List<TModel>> findAll({
  Map<String, String>? headers,
  QueryParams? queryParams,
  Map<String, dynamic>? extra,
})

Future<TModel?> createOne(TModel model, {
  Map<String, String>? headers,
  Map<String, dynamic>? extra,
})

Future<TModel?> updateOne(TModel model, {
  Map<String, String>? headers,
  Map<String, dynamic>? extra,
})

Future<TModel?> replaceOne(TModel model, {
  Map<String, String>? headers,
  Map<String, dynamic>? extra,
})

Future<void> deleteOne(String id, {
  Map<String, String>? headers,
  Map<String, dynamic>? extra,
})
```

#### Required Implementation Methods

```dart
TModel fromJson(Map<String, dynamic> json)
Map<String, dynamic> toJson(TModel model)
```

### BasicApiAdapter<TModel>

Concrete implementation of `ApiAdapterBase` using Dio for HTTP requests.

#### Features

- Complete HTTP implementation using Dio
- Automatic JSON serialization/deserialization
- Configurable timeouts and retry logic
- Proper error handling with typed exceptions
- Support for custom headers per request
- Request/response logging

#### Override Points

**HTTP Execution:**
```dart
Future<Response<T>> executeRequest<T>({
  required String method,
  required Uri uri,
  Object? data,
  Map<String, String>? headers,
  Map<String, dynamic>? queryParameters,
  Map<String, dynamic>? extra,
})
```

**Operation-Specific Execution:**
```dart
Future<TModel?> executeFindOneRequest({
  required String id,
  Map<String, String>? headers,
  QueryParams? queryParams,
  Map<String, dynamic>? extra,
})

Future<List<TModel>> executeFindAllRequest({
  Map<String, String>? headers,
  QueryParams? queryParams,
  Map<String, dynamic>? extra,
})

Future<TModel?> executeCreateRequest({
  required TModel model,
  Map<String, String>? headers,
  Map<String, dynamic>? extra,
})

Future<TModel?> executeUpdateRequest({
  required TModel model,
  Map<String, String>? headers,
  Map<String, dynamic>? extra,
})

Future<TModel?> executeReplaceRequest({
  required TModel model,
  Map<String, String>? headers,
  Map<String, dynamic>? extra,
})

Future<void> executeDeleteRequest({
  required String id,
  Map<String, String>? headers,
  Map<String, dynamic>? extra,
})
```

**Response Parsing:**
```dart
TModel? parseFindOneResponse(dynamic responseData, Response response)
List<TModel> parseFindAllResponse(dynamic responseData, Response response)
TModel? parseCreateResponse(dynamic responseData, Response response)
TModel? parseUpdateResponse(dynamic responseData, Response response)
TModel? parseReplaceResponse(dynamic responseData, Response response)
```

## Query System

### QueryParams

Class for building type-safe queries with filtering, sorting, and pagination.

#### Constructor

```dart
const QueryParams({
  this.filters = const [],
  this.sorts = const [],
  this.pagination,
})
```

#### Properties

```dart
List<FilterCondition> filters
List<SortCondition> sorts
PaginationParams? pagination
```

### FilterCondition

Represents a filter condition for queries.

#### Common Filter Methods

```dart
// Equality filters
field.equals(value)
field.notEquals(value)

// Comparison filters  
field.lessThan(value)
field.lessThanOrEqual(value)
field.greaterThan(value)
field.greaterThanOrEqual(value)

// String filters
field.contains(value)
field.startsWith(value)
field.endsWith(value)

// Null checks
field.isNull()
field.isNotNull()

// List operations
field.inList(values)
field.notInList(values)
```

### SortCondition

Represents a sort condition for queries.

#### Constructor

```dart
const SortCondition.ascending(FieldSelector field)
const SortCondition.descending(FieldSelector field)
```

### PaginationParams

Represents pagination parameters for queries.

#### Constructor

```dart
const PaginationParams({
  this.limit,
  this.offset,
})
```

## Enums

### DataSavePolicy

Defines how data should be saved.

```dart
enum DataSavePolicy {
  /// Save to local database first, then queue for remote sync
  localFirst,
  
  /// Save to remote API first, then save to local database on success
  remoteFirst,
}
```

### DataLoadPolicy

Defines how data should be loaded.

```dart
enum DataLoadPolicy {
  /// Look for data in local database only
  localOnly,
  
  /// Look for data in local database first, then load from remote API in the background
  localThenRemote,
  
  /// Load from remote API first, then save to local database on success
  remoteFirst,
}
```

### RepositoryChangeType

Types of repository change events.

```dart
enum RepositoryChangeType {
  created,
  updated,
  deleted,
  error,
}
```

## Exception Classes

### SynquillStorageException

Base class for all exceptions thrown by the synquill package.

```dart
class SynquillStorageException implements Exception {
  final String message;
  final StackTrace? stackTrace;
  
  SynquillStorageException(this.message, [this.stackTrace]);
}
```

### NotFoundException

Thrown when a repository can't find a requested item.

### ValidationException

Thrown when data validation fails.

### NetworkException

Thrown when network operations fail.

### ServerException

Thrown when the server returns an error response.

## Annotations

### @SynquillRepository

Annotation for marking data model classes for code generation.

```dart
@SynquillRepository(
  adapters: [MyApiAdapter],
  relations: [
    OneToMany(target: RelatedModel, mappedBy: 'parentId'),
    ManyToOne(target: ParentModel, foreignKeyColumn: 'parentId'),
  ],
)
class MyModel extends SynquillDataModel<MyModel> {
  // ...
}
```

#### Parameters

- `adapters`: List of API adapter mixins to apply
- `relations`: List of relationship definitions

### Relationship Annotations

#### @OneToMany

Defines a one-to-many relationship.

```dart
OneToMany(
  target: TargetModel,
  mappedBy: 'foreignKeyField',
)
```

#### @ManyToOne

Defines a many-to-one relationship.

```dart
ManyToOne(
  target: TargetModel,
  foreignKeyColumn: 'foreignKeyField',
)
```

## Generated Extensions

The code generator creates convenient extensions for accessing repositories:

```dart
extension SynquillStorageRepositories on SynquillStorage {
  UserRepository get users => getRepository<User>() as UserRepository;
  TodoRepository get todos => getRepository<Todo>() as TodoRepository;
  // ... additional repositories
}
```

## Utility Functions

### ID Generation

```dart
String generateCuid()
```
Generates a CUID (Collision-resistant Unique Identifier) for new model instances.

### Repository Provider

```dart
class SynquillRepositoryProvider {
  static void register<M extends SynquillDataModel<M>>(RepositoryFactory<M> factory)
  static SynquillRepositoryBase<M> get<M extends SynquillDataModel<M>>()
  static SynquillRepositoryBase<SynquillDataModel<dynamic>>? getByTypeName(String typeName)
  static void reset()
}
```

## Example Usage

### Basic Repository Operations

```dart
// Get repository instance
final userRepo = SynquillStorage.instance.users;

// Find operations
final user = await userRepo.findOne('user-id');
final users = await userRepo.findAll();

// Watch operations (reactive streams)
userRepo.watchOne('user-id').listen((user) {
  // React to user changes
});

// Save operations
final newUser = User(name: 'John', email: 'john@example.com');
await newUser.save();

// Delete operations
await userRepo.delete('user-id');
```

### Custom API Adapter

```dart
mixin UserApiAdapter on BasicApiAdapter<User> {
  @override
  Uri get baseUrl => Uri.parse('https://api.example.com/v1/');
  
  @override
  String get type => 'user';
  
  @override
  Future<Map<String, String>> get baseHeaders async => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${await getAuthToken()}',
  };
}
```

### Advanced Querying

```dart
final activeUsers = await userRepo.findAll(
  queryParams: QueryParams(
    filters: [
      isActiveField.equals(true),
      createdAtField.greaterThan(DateTime.now().subtract(Duration(days: 30))),
    ],
    sorts: [
      SortCondition.descending(createdAtField),
    ],
    pagination: PaginationParams(limit: 20, offset: 0),
  ),
);
```

---

For more examples and detailed guides, see:
- [Getting Started Guide](./guide.md)
- [API Adapters](./api-adapters.md)
- [Configuration](./configuration.md)
- [Advanced Features](./advanced-features.md)
