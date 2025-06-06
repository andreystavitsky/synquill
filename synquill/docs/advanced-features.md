# Advanced Features

This section covers advanced Synquill features including field indexing, database migrations, error handling, and more.

## Table of Contents

- [Custom Field Indexing](#custom-field-indexing)
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

## Database Migrations

```dart
TODO: describe
```

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
