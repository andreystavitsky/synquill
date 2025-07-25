# Advanced Features

This section covers advanced Synquill features including field indexing, database migrations, error handling, and more.

## Table of Contents

- [Custom Field Indexing](#custom-field-indexing)
- [Query Parameters Adaptive Methods](#query-parameters-adaptive-methods)
- [Database Migrations](#database-migrations)
- [Error Handling](#error-handling)
- [Offline Retry Mechanism](#offline-retry-mechanism)
- [Current Limitations](#current-limitations)

## Custom Field Indexing

```dart
class User extends SynquillDataModel<User> {
  @Indexed(name: 'user_email_idx', unique: true)
  final String email;
  
  @Indexed(name: 'user_name_idx')
  final String name;
}
```

## Query Parameters Adaptive Methods

Synquill supports adaptive QueryParams parameter in `methodForFind` and `urlForFind*` methods to create adaptive API adapters that change their behavior based on query parameters. This allows for efficient handling of different query types without requiring separate endpoint definitions.

### Smart Adapter Implementation

```dart
/// Smart adapter that adapts method and URL based on QueryParams
class SmartSearchAdapter extends BasicApiAdapter<SearchableModel> {
  @override
  Uri get baseUrl => Uri.parse('https://api.example.com/v1/');

  /// Adaptive method selection based on query complexity
  @override
  String methodForFind({
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) {
    if (queryParams == null) return 'GET';

    // Use POST for text search operations (complex queries)
    final hasTextSearch = queryParams.filters.any((filter) =>
        (filter.field == titleField || filter.field == contentField) &&
        (filter.operator == FilterOperator.contains ||
            filter.operator == FilterOperator.startsWith ||
            filter.operator == FilterOperator.endsWith));

    // Use POST for complex multi-field queries
    final hasComplexQuery = queryParams.filters.length > 3;

    return (hasTextSearch || hasComplexQuery) ? 'POST' : 'GET';
  }

  /// Adaptive URL selection based on query type
  @override
  FutureOr<Uri> urlForFindAll({
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    if (queryParams == null) {
      return baseUrl.resolve('searchable-models');
    }

    // Use search endpoint for text search
    final hasTextSearch = queryParams.filters.any((filter) =>
        (filter.field == titleField || filter.field == contentField) &&
        (filter.operator == FilterOperator.contains ||
            filter.operator == FilterOperator.startsWith ||
            filter.operator == FilterOperator.endsWith));

    if (hasTextSearch) {
      return baseUrl.resolve('searchable-models/search');
    }

    // Use advanced query endpoint for complex filtering
    final hasComplexQuery = queryParams.filters.length > 3;
    if (hasComplexQuery) {
      return baseUrl.resolve('searchable-models/advanced-query');
    }

    // Use standard endpoint for simple queries
    return baseUrl.resolve('searchable-models');
  }

  /// Adaptive method and URL for single item queries
  @override
  FutureOr<Uri> urlForFindOne(
    String id, {
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    // If we have query params, treat it as a filtered search
    if (queryParams?.filters.isNotEmpty ?? false) {
      return baseUrl.resolve('searchable-models/find-by-criteria');
    }

    // Otherwise use standard single item endpoint
    return baseUrl.resolve('searchable-models/$id');
  }
}
```

## Database Migrations
Database versioning in Synquill is set using the `@SynqillDatabaseVersion(1)` annotation above your database declaration, for example:

```dart
@SynqillDatabaseVersion(1)
final database = SynquillDatabase(
  ...,
  onCustomMigration: _performMigration, // Pass your migration function here
);
```

### Example: Custom Migration Function

You can provide a custom migration function to handle schema changes between versions. Pass it as the `onCustomMigration` parameter when creating your `SynquillDatabase` instance. The migration format is subject to change in future releases.
```dart
Future<void> _performMigration(Migrator migrator, int from, int to) async {
  final log = Logger('DatabaseMigration');
  log.info('Performing custom migration from version $from to $to');

  // Example migration logic
  if (from < 2) {
    log.info('Future migration logic would go here');
    // Example: await migrator.addColumn(todos, todos.someNewColumn);
  }

  log.info('Custom migration completed');
}
```

See also the official Drift documentation on migrations: [Drift - Manual Migrations](https://drift.simonbinder.eu/migrations/#manual-migrations)

> **Note:** The migration API and format are subject to change as Synquill evolves.

## Error Handling

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

## Offline Retry Mechanism

**TBD** - Detailed explanation of the offline retry mechanism will be provided in a future update.

## Current Limitations

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
