# synquill_graphql

GraphQL adapter integration for the **[Synquill](https://github.com/andreystavitsky/synquill)** offline-first persistent data synchronization engine. 

`synquill_graphql` provides a robust, production-ready GraphQL API adapter capable of executing queries, mutations, and real-time subscriptions, while mapping network data directly into the local SQLite store managed by Drift.

---

## Features

- **Flexible Query Compilation**: Supports both raw GraphQL query strings and fully structured AST-based `gql` Node definitions.
- **HTTP Query Batching**: Built-in DataLoader-style batching to group multiple concurrent individual GraphQL queries into a single HTTP POST request to minimize network overhead.
- **Real-Time Subscriptions**: Native implementation of the modern `graphql-transport-ws` protocol over WebSockets for robust stream events.
- **Unified Error Handling**: The `GraphQLErrorHandlingMixin` intercepts GraphQL response errors (inspecting `extensions.code`) and translates them into typed `SynquillStorageException` failures (e.g. `AuthenticationException`, `ValidationException`).
- **Partial Success Control**: Custom strategies to handle standard GraphQL hybrid responses containing both `data` and `errors`.
- **Automatic Persistence Mapping**: Automatically bridges incoming WebSocket stream events or HTTP query responses into SQLite transaction writes using Drift.

---

## Installation

Add both the core engine and the GraphQL adapter to your Flutter project's `pubspec.yaml`:

```yaml
dependencies:
  synquill: ^0.8.0
  synquill_graphql: ^0.8.0

dev_dependencies:
  synquill_gen: ^0.8.0
  build_runner: ^2.4.14
```

---

## Quick Start

### 1. Create your GraphQL API Adapter

Define your GraphQL endpoints, headers, and individual resource query maps:

```dart
import 'package:synquill_graphql/synquill_graphql.dart';

mixin TodoGraphQLAdapter on GraphQLApiAdapterMixin<Todo> {
  @override
  Uri get baseUrl => Uri.parse('https://api.example.com/graphql');

  @override
  Uri get wsUrl => Uri.parse('wss://api.example.com/graphql');

  @override
  String get type => 'todo';

  // GraphQL query string used to fetch a single item
  @override
  String get findOneQuery => r'''
    query GetTodo($id: ID!) {
      todo(id: $id) {
        id
        title
        isCompleted
      }
    }
  ''';

  // GraphQL query string used to fetch lists
  @override
  String get findAllQuery => r'''
    query GetTodos {
      todos {
        id
        title
        isCompleted
      }
    }
  ''';

  // GraphQL mutation used to create/update
  @override
  String get createOneMutation => r'''
    mutation CreateTodo($input: TodoInput!) {
      createTodo(input: $input) {
        id
        title
        isCompleted
      }
    }
  ''';
}
```

### 2. Configure model with `@SynquillRepository`

Attach your newly defined GraphQL adapter mixin directly to your model repository configuration:

```dart
@JsonSerializable()
@SynquillRepository(
  adapters: [GraphQLApiAdapter, TodoGraphQLAdapter],
)
class Todo extends SynquillDataModel<Todo> {
  @override
  final String id;
  final String title;
  final bool isCompleted;

  Todo({required this.id, required this.title, required this.isCompleted});

  // ... toJson, fromJson, and fromDb boilerplate
}
```

### 3. Consume with Reactive Watch Streams

Once code generation finishes, you can use high-level reactive streams which link local SQLite tables with remote GraphQL subscriptions seamlessly:

```dart
// Fetch database record instantly AND automatically open a WebSocket subscription to updates
final Stream<List<Todo>> activeTodos = todoRepository.watchAll(watchRemote: true);

activeTodos.listen((todos) {
  // Automatically reactive to both offline database updates and remote WebSocket notifications
  updateUI(todos);
});
```

---

## Documentation

For deep dives into advanced configurations, check out:
- **[GraphQL API Adapter Detailed Guide](https://github.com/andreystavitsky/synquill/blob/main/synquill/doc/graphql-adapter.md)**: Features, WebSocket subscriptions, HTTP batching tuning, custom query parameters, and error mapping configurations.
- **[Synquill Core Documentation](https://github.com/andreystavitsky/synquill/tree/main/synquill/doc)**: Architecture overview, SQLite persistence guides, custom headers, and database migrations.
