import 'package:drift_flutter/drift_flutter.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synquill/synquill_core.dart';
import 'package:synquill_example/synquill.generated.dart';
import 'package:workmanager/workmanager.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Logger.root.level = Level.ALL; // Set global logging level
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

  // Initialize the SynquillStorage system
  @SynqillDatabaseVersion(1)
  final database = SynquillDatabase(
    LazyDatabase(
      () => driftDatabase(
        name: 'synced_storage.db',
        native: DriftNativeOptions(
          shareAcrossIsolates: true,
          databaseDirectory: getApplicationSupportDirectory,
        ),
      ),
    ),
    onCustomMigration: _performMigration,
    onDatabaseCreated: _setupInitialData,
  );

  // If uncommented, this should cause a build error due to conflicting versions
  // @SynqillDatabaseVersion(2)
  // final conflictingVersion = 'test';

  // Initialize the synced storage system
  await SynquillStorage.init(
    connectivityChecker: () async =>
        await InternetConnection().hasInternetAccess,
    connectivityStream: InternetConnection()
        .onStatusChange
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

  await InternetConnection().hasInternetAccess;

  runApp(const TodoApp());
}

/// Sets up initial demo data in the database
Future<void> _setupInitialData(Migrator migrator) async {
  final log = Logger('DatabaseSetup');
  log.info('Setting up initial user and todo data...');

  try {
    // First, create a sample user
    await migrator.database.customStatement('''
      INSERT INTO users (id, name, created_at, updated_at) 
      VALUES 
        ('1', 'Leanne Graham', strftime('%s', 'now'), strftime('%s', 'now'))
    ''');

    // Then, create todos and posts that belong to this user
    await migrator.database.customStatement('''
      INSERT INTO todos (id, title, user_id, is_completed, created_at, updated_at) 
      VALUES 
        ('welcome-todo', 'Welcome to Synced Storage!', '1', 0, strftime('%s', 'now'), strftime('%s', 'now')),
        ('getting-started', 'Try adding your own todos', '1', 0, strftime('%s', 'now'), strftime('%s', 'now'))
    ''');

    await migrator.database.customStatement('''
      INSERT INTO posts (id, title, body, user_id, created_at, updated_at) 
      VALUES 
        ('welcome-post', 'Welcome to Synced Storage!', 'This is your first post. You can create, edit, and delete posts to test the synced storage functionality.', '1', strftime('%s', 'now'), strftime('%s', 'now')),
        ('getting-started-post', 'Getting Started with Posts', 'Try creating your own posts using the floating action button. Posts are automatically synced with the backend when connected to the internet.', '1', strftime('%s', 'now'), strftime('%s', 'now'))
    ''');

    log.info('Initial user, todos, and posts created successfully');
  } catch (e) {
    log.warning('Failed to create initial data: $e');
  }
}

/// Handles database schema migrations
Future<void> _performMigration(Migrator migrator, int from, int to) async {
  final log = Logger('DatabaseMigration');
  log.info('Performing custom migration from version $from to $to');

  // Example migration logic (currently no schema changes needed)
  if (from < 2) {
    log.info('Future migration logic would go here');
    // Example: await migrator.addColumn(todos, todos.someNewColumn);
  }

  log.info('Custom migration completed');
}

class TodoApp extends StatelessWidget {
  const TodoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Synced Data Storage Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

/// Background task dispatcher for WorkManager
///
/// This function demonstrates proper usage of SyncedStorage background sync
/// methods with required pragma annotation for isolate accessibility.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("Background task started: $task");

    try {
      // Create database instance for background isolate
      final database = SynquillDatabase(
        LazyDatabase(
          () => driftDatabase(
            name: 'synced_storage.db',
            native: DriftNativeOptions(
              shareAcrossIsolates: true,
              databaseDirectory: getApplicationSupportDirectory,
            ),
          ),
        ),
      );

      // Initialize SyncedStorage in background isolate
      await SynquillStorage.initForBackgroundIsolate(
        database: database,
        config: SynquillStorageConfig(
          defaultSavePolicy: DataSavePolicy.localFirst,
          defaultLoadPolicy: DataLoadPolicy.localThenRemote,
          backgroundQueueConcurrency: 1,
          recordRequestBody: true,
          recordResponseBody: true,
        ),
        initializeFn: initializeSynquillStorage,
      );

      // Process background sync tasks
      await SynquillStorage.processBackgroundSync();

      await SynquillStorage.close();

      print("Background sync completed successfully");
      return true;
    } catch (e, stackTrace) {
      print("Background sync failed: $e");
      print("Stack trace: $stackTrace");
      return false;
    }
  });
}
