# Queue Management System

Synquill uses a sophisticated three-queue system to manage different types of operations efficiently. Each queue is optimized for specific use cases and provides intelligent capacity management, connectivity awareness, and error recovery.

## Table of Contents

- [Queue Types](#queue-types)
- [Queue Configuration](#queue-configuration)
- [Capacity Management](#capacity-management)
- [Idempotency Protection](#idempotency-protection)
- [Connectivity Handling](#connectivity-handling)
- [Queue Monitoring](#queue-monitoring)
- [Error Handling](#error-handling)
- [Background Processing](#background-processing)

## Queue Types

### Foreground Queue
- **Purpose**: Critical user operations requiring immediate feedback
- **Usage**: `remoteFirst` save operations (create, update, delete)
- **Configuration**: Single-threaded (parallelism: 1), 50ms delay
- **Priority**: Highest
- **Timeout**: 10 seconds capacity wait

```dart
// Operations routed to foreground queue
await repository.save(
  user, 
  savePolicy: DataSavePolicy.remoteFirst,
);
```

### Load Queue
- **Purpose**: Background data refreshes and `localThenRemote` operations  
- **Usage**: Data fetching that doesn't block user interactions
- **Configuration**: Multi-threaded (parallelism: 2), 50ms delay
- **Priority**: Medium
- **Timeout**: 5 seconds capacity wait

```dart
// Operations routed to load queue
final users = await repository.findAll(
  loadPolicy: DataLoadPolicy.localThenRemote,
);
```

### Background Queue
- **Purpose**: `localFirst` sync operations that can be deferred
- **Usage**: Offline-first saves, sync queue processing
- **Configuration**: Single-threaded (parallelism: 1), 100ms delay  
- **Priority**: Lowest
- **Timeout**: 2 seconds capacity wait

```dart
// Operations routed to background queue
await repository.save(
  user,
  savePolicy: DataSavePolicy.localFirst,
);
```

## Queue Configuration

### Basic Configuration

```dart
await SynquillStorage.init(
  // ...
  config: const SynquillStorageConfig(
    // Queue concurrency settings
    foregroundQueueConcurrency: 1,
    backgroundQueueConcurrency: 2,
    
    // Queue capacity limits
    maxForegroundQueueCapacity: 50,
    maxLoadQueueCapacity: 50,
    maxBackgroundQueueCapacity: 50,
    
    // Capacity timeout settings
    foregroundQueueCapacityTimeout: Duration(seconds: 10),
    loadQueueCapacityTimeout: Duration(seconds: 5),
    backgroundQueueCapacityTimeout: Duration(seconds: 2),
    queueCapacityCheckInterval: Duration(milliseconds: 100),
  ),
);
```

### Custom Queue Management

```dart
// Get queue manager instance
final queueManager = SynquillStorage.queueManager;

// Enqueue custom network tasks
final task = NetworkTask<String>(
  exec: () async {
    // Your custom operation
    return 'result';
  },
  idempotencyKey: 'unique-operation-key',
  operation: SyncOperation.update,
  modelType: 'User',
  modelId: 'user-123',
);

await queueManager.enqueueTask(task, queueType: QueueType.foreground);
```

## Capacity Management

### Automatic Capacity Control

Synquill automatically manages queue capacity to prevent memory issues:

```dart
// When queue reaches capacity, new tasks wait with timeouts
try {
  await queueManager.enqueueTask(task);
} on SynquillStorageException catch (e) {
  if (e.message.contains('capacity')) {
    // Handle capacity timeout
    print('Queue at capacity, try again later');
  }
}
```

### Capacity Monitoring

```dart
// Monitor queue statistics
final stats = queueManager.getQueueStats();

print('Foreground queue: ${stats[QueueType.foreground]!.activeAndPendingTasks} tasks');
print('Load queue: ${stats[QueueType.load]!.activeAndPendingTasks} tasks');  
print('Background queue: ${stats[QueueType.background]!.activeAndPendingTasks} tasks');
```

### Capacity Wait Strategy

When queues reach capacity, the system uses a polling strategy:

1. Check capacity immediately
2. If full, wait for configured interval (default: 100ms)
3. Recheck capacity until space becomes available
4. Throw `SynquillStorageException` if timeout exceeded

## Idempotency Protection

### Duplicate Task Prevention

```dart
// Tasks with same idempotency key are rejected
final task1 = NetworkTask<void>(
  exec: () => apiCall(),
  idempotencyKey: 'user-update-123', // Same key
  operation: SyncOperation.update,
  modelType: 'User',
  modelId: 'user-123',
);

final task2 = NetworkTask<void>(
  exec: () => apiCall(),
  idempotencyKey: 'user-update-123', // Same key - will be rejected
  operation: SyncOperation.update,
  modelType: 'User', 
  modelId: 'user-123',
);

await queueManager.enqueueTask(task1); // Succeeds
try {
  await queueManager.enqueueTask(task2); // Throws SynquillStorageException
} catch (e) {
  print('Duplicate task rejected: $e');
}
```

### Per-Queue Idempotency Tracking

- Each queue maintains its own set of active idempotency keys
- Keys are automatically removed when tasks complete
- Race condition protection through immediate key registration

## Connectivity Handling

### Offline Behavior

```dart
// Example: Remote operations are blocked when offline
try {
  await repository.save(user, savePolicy: DataSavePolicy.remoteFirst);
} on SynquillStorageException catch (e) {
  if (e.message.contains('offline')) {
    // Show user-friendly offline message
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('You are offline. Please try again when connectivity is restored.'),
              behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
```

### Queue Clearing on Disconnect

```dart
// Automatically called when connectivity is lost
await queueManager.clearQueuesOnDisconnect();

// All pending tasks are cancelled with QueueCancelledException
// Task data remains in sync_queue database for retry when online
```

### Queue Restoration on Connect

```dart
// Automatically called when connectivity returns
await queueManager.restoreQueuesOnConnect();

// Triggers RetryExecutor to process pending sync queue items
// Queues are recreated and ready for new operations
```

## Queue Monitoring

### Real-time Statistics

```dart
// Example queue monitoring class
class QueueMonitor {
  void startMonitoring() {
    Timer.periodic(Duration(seconds: 5), (timer) {
      final stats = SynquillStorage.queueManager.getQueueStats();
      
      for (final entry in stats.entries) {
        final queueType = entry.key;
        final queueStats = entry.value;
        
        print('${queueType.name}: ${queueStats.activeAndPendingTasks} active, '
              '${queueStats.pendingTasks} pending');
      }
    });
  }
}
```

### Queue Health Checks

```dart
bool isQueueHealthy(QueueType queueType) {
  final stats = SynquillStorage.queueManager.getQueueStats();
  final queueStats = stats[queueType]!;
  
  // Check if queue is not severely backed up
  return queueStats.activeAndPendingTasks < 40; // Below 80% capacity
}
```

## Error Handling

### Task Execution Errors

```dart
final task = NetworkTask<String>(
  exec: () async {
    // This might throw an exception
    final response = await apiClient.updateUser(user);
    return response.data;
  },
  idempotencyKey: 'user-update-${user.id}',
  operation: SyncOperation.update,
  modelType: 'User',
  modelId: user.id,
);

try {
  final result = await queueManager.enqueueTask(task);
  print('Task succeeded: $result');
} catch (e) {
  print('Task failed: $e');
  // Task failure doesn't affect queue health
  // Idempotency key is automatically cleaned up
}
```

### Queue Recovery

```dart
// Queues automatically recover from errors
// Failed tasks clean up their idempotency keys
// Queue capacity is restored when tasks complete
```

### Network Interruption Handling

```dart
// Tasks handle network interruptions gracefully
try {
  await queueManager.enqueueTask(networkTask);
} on QueueCancelledException {
  // Task was cancelled due to connectivity loss
  // Will be retried when connectivity returns
} catch (e) {
  // Other errors (API failures, etc.)
  print('Task failed with error: $e');
}
```

## Background Processing

### Background Queue Priority

The background queue processes tasks based on dependency levels:

1. **Level 0**: Independent models (Users, Categories)
2. **Level 1**: Models with single dependencies (Posts → Users)  
3. **Level 2**: Models with multiple dependencies (Comments → Posts → Users)

```dart
// Background sync automatically orders tasks by dependency level
// Ensures parent records are synced before children
await SynquillStorage.retryExecutor.processDueTasksNow();
```

### Queue Coordination

```dart
// Example background processing coordinates with foreground queues
class BackgroundProcessor {
  Future<void> processWhenQuiet() async {
    final stats = SynquillStorage.queueManager.getQueueStats();
    
    // Wait for foreground operations to complete
    if (stats[QueueType.foreground]!.activeAndPendingTasks == 0) {
      await SynquillStorage.retryExecutor.processDueTasksNow();
    }
  }
}
```

The queue system provides robust, scalable operation management that adapts to network conditions, prevents resource exhaustion, and ensures data consistency through intelligent task ordering and retry mechanisms.