# GraphQL API Adapter

The `synquill_graphql` package provides a robust GraphQL adapter for Synquill, allowing you to use GraphQL as the remote sync transport instead of the default REST-based HTTP transport. It is a plug-and-play replacement for `BasicApiAdapter`.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Defining Models and Adapters](#defining-models-and-adapters)
- [CRUD Operations & String-Based Queries](#crud-operations--string-based-queries)
- [Query Parameter Mapping](#query-parameter-mapping)
- [HTTP Query Batching (DataLoader)](#http-query-batching-dataloader)
- [Real-Time Subscriptions](#real-time-subscriptions)
- [Error Handling & Partial Success](#error-handling--partial-success)
- [Resource Disposal](#resource-disposal)

---

## Features

- **String-Based Queries**: Clean and flexible queries/mutations defined as strings.
- **AST Parsing & Validation**: Automatically parses operations into AST nodes for structural validation using the `gql` library, eliminating string scanner errors.
- **Direct Transport**: Uses `Dio` directly for HTTP communication, keeping runtime dependencies lightweight.
- **HTTP Query Batching**: Groups multiple queries into a single HTTP POST request within a small time window, resolving the N+1 query problem.
- **Real-Time Subscriptions**: Integrates with GraphQL WebSockets (`graphql-transport-ws` protocol) via `gql_websocket_link` for real-time model and repository cache updates.
- **Comprehensive Error Mapping**: Translates standard GraphQL extension codes (`UNAUTHENTICATED`, `FORBIDDEN`, etc.) and HTTP/Dio network failures into unified Synquill exceptions.

---

## Installation

Add both the core package and the GraphQL adapter package to your `pubspec.yaml`:

```yaml
dependencies:
  synquill: ^0.8.3
  synquill_graphql: ^0.8.2
```

---

## Defining Models and Adapters

To use the GraphQL adapter, your generated adapters must inherit from `GraphQLApiAdapter`. The code generator (`synquill_gen`) automatically detects this dependency through the superclass constraint on your adapter mixin.

### 1. Define the Model

```dart
@JsonSerializable()
@SynquillRepository(
  adapters: [TodoGraphQLAdapter],
)
class Todo extends SynquillDataModel<Todo> {
  @override
  final String id;
  final String title;
  final bool isCompleted;

  Todo({
    String? id,
    required this.title,
    this.isCompleted = false,
  }) : id = id ?? generateCuid();

  // ... fromJson and toJson ...
}
```

### 2. Implement the GraphQL Adapter

Create a mixin adapter that implements `GraphQLApiAdapter`:

```dart
mixin TodoGraphQLAdapter on GraphQLApiAdapter<Todo> {
  @override
  Uri get graphqlEndpoint => Uri.parse('https://api.example.com/graphql');

  @override
  String get type => 'todo';

  @override
  String get pluralType => 'todos';

  // Define string-based queries and mutations:
  @override
  String get findOneQuery => '''
    query GetTodo(\$id: ID!) {
      todo(id: \$id) {
        id
        title
        isCompleted
      }
    }
  ''';

  @override
  String get findAllQuery => '''
    query GetTodos(\$filter: Map, \$sort: [SortInput], \$pagination: PaginationInput) {
      todos(filter: \$filter, sort: \$sort, pagination: \$pagination) {
        id
        title
        isCompleted
      }
    }
  ''';

  @override
  String get createMutation => '''
    mutation CreateTodo(\$input: CreateTodoInput!) {
      createTodo(input: \$input) {
        id
        title
        isCompleted
      }
    }
  ''';

  @override
  String get updateMutation => '''
    mutation UpdateTodo(\$id: ID!, \$input: UpdateTodoInput!) {
      updateTodo(id: \$id, input: \$input) {
        id
        title
        isCompleted
      }
    }
  ''';

  @override
  String get deleteMutation => '''
    mutation DeleteTodo(\$id: ID!) {
      deleteTodo(id: \$id) {
        id
      }
    }
  ''';
}
```

Then run `build_runner` to generate the repository classes:
```sh
dart run build_runner build --delete-conflicting-outputs
```

---

## CRUD Operations & String-Based Queries

The `GraphQLApiAdapter` inherits from `ApiAdapterBase` and handles all core CRUD methods (`findOne`, `findAll`, `createOne`, `updateOne`, `replaceOne`, `deleteOne`) by delegating them to their respective GraphQL operations.

### Customizing Response Fields

By default, the adapter extracts return data using the following convention:
- **findOne**: `data[type]`
- **findAll**: `data[pluralType]`
- **createOne**: `data['create' + CapitalizedType]`
- **updateOne**: `data['update' + CapitalizedType]`
- **replaceOne**: `data['update' + CapitalizedType]`
- **deleteOne**: `data['delete' + CapitalizedType]`

If your GraphQL schema uses different field names in responses, you can override these getters in your adapter:

```dart
mixin TodoGraphQLAdapter on GraphQLApiAdapter<Todo> {
  @override
  String get findOneResponseField => 'getTodoItem';

  @override
  String get createResponseField => 'insertTodo';
}
```

---

## Query Parameter Mapping

When performing `findAll` operations with filtering, sorting, or pagination, the adapter automatically maps Synquill `QueryParams` to standard GraphQL variables.

### Default Mapping Structure

```json
{
  "filter": {
    "title": { "eq": "Buy Milk" },
    "isCompleted": { "eq": false }
  },
  "sort": [
    { "field": "title", "direction": "ASC" }
  ],
  "pagination": {
    "limit": 20,
    "offset": 0
  }
}
```

### Supported Filter Operators

Synquill filter operators are mapped as follows:
- `FilterOperator.equals` $\rightarrow$ `eq`
- `FilterOperator.notEquals` $\rightarrow$ `neq`
- `FilterOperator.greaterThan` $\rightarrow$ `gt` / `FilterOperator.greaterThanOrEqual` $\rightarrow$ `gte`
- `FilterOperator.lessThan` $\rightarrow$ `lt` / `FilterOperator.lessThanOrEqual` $\rightarrow$ `lte`
- `FilterOperator.contains` $\rightarrow$ `contains`
- `FilterOperator.startsWith` $\rightarrow$ `startsWith` / `FilterOperator.endsWith` $\rightarrow$ `endsWith`
- `FilterOperator.inList` $\rightarrow$ `in` / `FilterOperator.notInList` $\rightarrow$ `notIn`
- `FilterOperator.isNull` $\rightarrow$ `isNull` / `FilterOperator.isNotNull` $\rightarrow$ `isNotNull`

### Overriding Variable Mapping

If your backend schema (e.g., Hasura, Prisma, or custom) expects a different structure, you can override `queryParamsToGraphQLVariables`:

```dart
@override
Map<String, dynamic> queryParamsToGraphQLVariables(QueryParams? queryParams) {
  // Translate queryParams to your exact server-side syntax here
  // (e.g., changing "filter" nested format, or pagination parameter names)
  return customVariables;
}
```

---

## HTTP Query Batching (DataLoader)

Synquill supports automatic query batching for eligible GraphQL operations (read-only queries). Instead of triggering separate network requests immediately, they are collected in a brief timing window and sent as a single HTTP POST request containing a JSON list of operations.

### Configuration

Query batching is configured by overriding the `batchOptions` getter in your adapter:

```dart
mixin TodoGraphQLAdapter on GraphQLApiAdapter<Todo> {
  @override
  GraphQLBatchOptions get batchOptions => const GraphQLBatchOptions(
        enabled: true,
        window: Duration(milliseconds: 15), // Wait time before flushing a batch
        maxBatchSize: 20,                   // Maximum size to trigger immediate flush
      );
}
```

### Eligibility & Transport

- Only executable GraphQL `query` operations are batched.
- Mutations and subscriptions are never batched.
- Operations that pass custom `extra` parameters are executed immediately to preserve context.

---

## Real-Time Subscriptions

The `GraphQLApiAdapter` supports GraphQL subscriptions over WebSockets using the `graphql-transport-ws` protocol.

### 1. Configure Subscription Documents

To enable subscription support, define your subscription documents in the adapter:

```dart
mixin TodoGraphQLAdapter on GraphQLApiAdapter<Todo> {
  // Websocket endpoint defaults to wss:// or ws:// derived from graphqlEndpoint
  @override
  Uri get graphqlSubscriptionEndpoint => Uri.parse('wss://api.example.com/subscriptions');

  // String document to watch a single item
  @override
  String? get subscribeOneSubscription => '''
    subscription WatchTodo(\$id: ID!) {
      todoUpdated(id: \$id) {
        id
        title
        isCompleted
      }
    }
  ''';

  // String document to watch all items
  @override
  String? get subscribeAllSubscription => '''
    subscription WatchTodos {
      todosUpdated {
        id
        title
        isCompleted
      }
    }
  ''';
}
```

### 2. Stream Operations

You can listen to real-time updates directly via the streams. Since the repository's `apiAdapter` is statically typed as the base `ApiAdapterBase<T>`, you need to explicitly cast it to `GraphQLSubscriptionMixin<T>` (or your concrete adapter class) to access subscription methods:

```dart
// Stream updates for a single todo item
final Stream<Todo?> todoStream = 
    (todoRepository.apiAdapter as GraphQLSubscriptionMixin<Todo>).subscribeOne('123');

// Stream updates for all todos
final Stream<List<Todo>> todosStream = 
    (todoRepository.apiAdapter as GraphQLSubscriptionMixin<Todo>).subscribeAll();
```

### 3. Repository Watch Integration

When your adapter implements subscriptions, you can leverage transport-neutral remote watch operations seamlessly.

Using `watchRemote: true` inside repository methods (`watchAll`, `watchOne`) aggregates local Drift database streams and maps inbound server-sent events directly to your local persistent store. This ensures the local database remains the **Single Source of Truth** and updates the UI safely even while offline or processing background operations.

```dart
// Watch all todos from the local DB, and automatically listen to server updates
final Stream<List<Todo>> reactiveTodos = todoRepository.watchAll(watchRemote: true);

// Watch a single todo item reactively with server subscriptions enabled
final Stream<Todo?> reactiveTodo = todoRepository.watchOne('123', watchRemote: true);
```

#### Comparison: `watchAll(watchRemote: true)` vs `subscribeAll()`

| Feature | `watchAll(..., watchRemote: true)` | `subscribeAll()` |
| :--- | :--- | :--- |
| **Layer** | Repository (High-level) | Adapter (Low-level / raw connection) |
| **Source of Truth** | SQLite / Drift database | Memory-only Stream (direct from WebSocket) |
| **Offline Support** | Yes (returns cached data instantly) | No (requires active WebSocket connection) |
| **Data Persistence** | Yes (inbound remote events update local DB) | No (data bypasses local database completely) |
| **Typical Use Case** | Core offline-first application features and reactive UI screens | Lightweight, transient updates (e.g. typing indicators, active user counts, fast-moving tickers) |

---

## Error Handling & Partial Success

The `GraphQLErrorHandlingMixin` intercepts response bodies and translates GraphQL errors into clean, unified `SynquillStorageException` types.

### 1. Error Code Mapping

The adapter inspects the `extensions.code` of GraphQL errors and maps them as follows:

| GraphQL Error Code | Synquill Exception |
| :--- | :--- |
| `UNAUTHENTICATED` | `AuthenticationException` |
| `FORBIDDEN` | `AuthorizationException` |
| `NOT_FOUND` | `ApiExceptionNotFound` |
| `BAD_USER_INPUT` / `VALIDATION_ERROR` | `ValidationException` (with parsed `fieldErrors`) |
| `CONFLICT` | `ConflictException` |
| `INTERNAL_SERVER_ERROR` | `ServerException` |
| Unspecified / Unknown | `ApiException` |
| Network / Transport failures | `NetworkException` / `TimeoutException` |

### 2. Partial Success Strategy (Data + Errors)

In GraphQL, a response can contain both data and errors (`{"data": {...}, "errors": [...]}`). 

- **Default Strategy**: If the `errors` array in the response is present and non-empty, the adapter throws the mapped exception immediately, ignoring any partial data. This prevents storing incomplete or corrupted data states in the local offline-first database.
- **Customization**: You can customize this behavior by overriding `checkGraphQLErrors()` to support partial successes or log non-critical warnings instead of throwing.

---

## Resource Disposal

Always clean up active GraphQL adapter resources to prevent connection leaks. Calling the `dispose()` method:
- Cancels all pending HTTP batch timers and fails queued operations with an `ApiException`.
- Closes all active WebSocket subscription link connections and emits an error on remaining subscription streams.

The `dispose()` method is designed to be idempotent and can be safely called multiple times during lifecycle hooks.
