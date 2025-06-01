# Synced Storage Todo Example

This is a minimal Flutter example app that demonstrates how to use the `synced_data_storage` package.

## Overview

This example implements a simple todo app that showcases:

- **Model Definition**: How to create models with `@SyncedDataRepository` annotation
- **Data Save Policies**: Demonstrating `localFirst` and `remoteFirst` data synchronization
- **Code Generation**: How the package generates Drift tables and repositories
- **Freezed Integration**: Using Freezed for immutable data models

## Features

- ✅ Add new todo items (saved with `localFirst` policy)
- ✅ Toggle todo completion (saved with `remoteFirst` policy)
- ✅ Delete todo items
- ✅ Automatic CUID generation for unique IDs
- ✅ JSON serialization with Freezed
- ✅ Local database persistence with Drift

## Model Structure

The `Todo` model demonstrates:

```dart
@freezed
@SyncedDataRepository()
class Todo extends SyncedDataModel<Todo> with _$Todo {
  const factory Todo({
    required String id,        // CUID for unique identification
    required String title,     // Todo description
    @Default(false) bool isCompleted,
    required String createdAt, // ISO 8601 timestamp
    String? updatedAt,
  }) = _Todo;

  factory Todo.fromJson(Map<String, dynamic> json) => _$TodoFromJson(json);
  
  factory Todo.create({required String title, bool isCompleted = false}) {
    final now = DateTime.now().toIso8601String();
    return Todo(
      id: generateCuid(),
      title: title,
      isCompleted: isCompleted,
      createdAt: now,
      updatedAt: now,
    );
  }
}
```

## Data Save Policies

The app demonstrates both data save policies:

### LocalFirst (Default)
Used for new todos - saves to local database first, then syncs to remote API:
```dart
await todo.save(policy: DataSavePolicy.localFirst);
```

### RemoteFirst
Used for todo updates - saves to remote API first, then updates local database:
```dart
await todo.save(policy: DataSavePolicy.remoteFirst);
```

## Running the Example

1. **Install dependencies:**
   ```bash
   flutter pub get
   ```

2. **Generate code:**
   ```bash
   flutter packages pub run build_runner build
   ```

3. **Run the app:**
   ```bash
   flutter run
   ```

## Code Generation

The example demonstrates the complete code generation workflow:

1. **Model Definition**: `lib/models/todo.dart` with `@SyncedDataRepository()`
2. **Generated Files**: Build runner generates:
   - `todo.g.dart` - JSON serialization
   - `todo.freezed.dart` - Freezed immutable classes
   - `todo.synced.g.dart` - Drift table and DAO
3. **Database Setup**: `AppDatabase` extends `SyncedDatabaseBase`

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── models/
│   └── todo.dart            # Todo model with annotations
├── screens/
│   └── todo_list_screen.dart # Main UI
└── database/
    └── app_database.dart    # Database configuration
```

## Next Steps

This example covers Stage 1 functionality. Future stages will add:

- **Stage 2**: Multi-device conflict resolution
- **Stage 3**: WebSocket real-time sync
- **Stage 4**: Advanced conflict handling strategies

## API Documentation

For more details about the `synced_data_storage` package, see the main package documentation.
