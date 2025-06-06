# Configuration

This guide covers storage configuration, background sync setup, and runtime controls for optimizing sync behavior.

## Table of Contents

- [Storage Configuration](#storage-configuration)
- [Background Sync](#background-sync)
- [Background Sync Manager Controls](#background-sync-manager-controls)
  - [App Lifecycle Integration](#app-lifecycle-integration)
  - [Manual Sync Mode Control](#manual-sync-mode-control)
  - [Sync Mode Behavior](#sync-mode-behavior)
  - [Background Isolate Support](#background-isolate-support)

## Storage Configuration

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
  
  // Connectivity related options are provided when calling
  // `SynquillStorage.init` (see below)
);
```

When initializing `SynquillStorage`, you can pass
`enableInternetMonitoring`, `connectivityStream`, or
`connectivityChecker` to control how connectivity is tracked.

## Background Sync

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

## Background Sync Manager Controls

Synquill provides runtime controls to adjust sync behavior based on your app's lifecycle state. These methods allow you to optimize battery usage and responsiveness by switching between foreground and background sync modes.

### App Lifecycle Integration

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

### Manual Sync Mode Control

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

### Sync Mode Behavior

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

### Background Isolate Support

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
