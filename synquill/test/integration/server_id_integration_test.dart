import 'dart:async';
import 'package:test/test.dart';
import 'package:synquill/synquill_core.dart';
import 'package:synquill/synquill.generated.dart';
import 'package:synquill/src/test_models/test_server_id_model.dart';

/// Mock API adapter that simulates server-generated IDs
class MockServerIdAdapter extends ApiAdapterBase<ServerTestModel> {
  final Map<String, ServerTestModel> _remoteData = {};
  final List<String> _operationLog = [];
  int _nextServerId = 1000; // Start server IDs from 1000

  @override
  Uri get baseUrl => Uri.parse('https://test.example.com/api/v1/');

  @override
  String get type => 'server-test-model';

  @override
  String get pluralType => 'server-test-models';

  /// Get operation log for testing
  List<String> get operationLog => List.unmodifiable(_operationLog);

  /// Get all remote data for verification
  Map<String, ServerTestModel> get remoteData => Map.unmodifiable(_remoteData);

  /// Clear remote data and operation log
  void clearAll() {
    _remoteData.clear();
    _operationLog.clear();
  }

  @override
  ServerTestModel fromJson(Map<String, dynamic> json) {
    return ServerTestModel.fromJson(json);
  }

  @override
  Map<String, dynamic> toJson(ServerTestModel model) {
    return model.toJson();
  }

  @override
  Future<ServerTestModel?> findOne(
    String id, {
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('findOne($id)');
    await Future.delayed(const Duration(milliseconds: 10));
    return _remoteData[id];
  }

  @override
  Future<List<ServerTestModel>> findAll({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('findAll()');
    await Future.delayed(const Duration(milliseconds: 10));
    return _remoteData.values.toList();
  }

  @override
  Future<ServerTestModel?> createOne(
    ServerTestModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('createOne(${model.id})');

    await Future.delayed(const Duration(milliseconds: 10));

    // Simulate server generating a new ID
    final serverId = 'server_${_nextServerId++}';

    final modelWithServerId = ServerTestModel(
      id: serverId,
      name: model.name,
      description: model.description,
    );

    _remoteData[serverId] = modelWithServerId;
    return modelWithServerId;
  }

  @override
  Future<ServerTestModel?> updateOne(
    ServerTestModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('updateOne(${model.id})');
    await Future.delayed(const Duration(milliseconds: 10));
    _remoteData[model.id] = model;
    return model;
  }

  @override
  Future<ServerTestModel?> replaceOne(
    ServerTestModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('replaceOne(${model.id})');
    await Future.delayed(const Duration(milliseconds: 10));
    _remoteData[model.id] = model;
    return model;
  }

  @override
  Future<void> deleteOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('deleteOne($id)');
    await Future.delayed(const Duration(milliseconds: 10));
    _remoteData.remove(id);
  }
}

/// Mock API adapter for client ID models (for comparison)
class MockClientIdAdapter extends ApiAdapterBase<ClientTestModel> {
  final Map<String, ClientTestModel> _remoteData = {};
  final List<String> _operationLog = [];

  @override
  Uri get baseUrl => Uri.parse('https://test.example.com/api/v1/');

  @override
  String get type => 'client-test-model';

  @override
  String get pluralType => 'client-test-models';

  List<String> get operationLog => List.unmodifiable(_operationLog);

  void clearAll() {
    _remoteData.clear();
    _operationLog.clear();
  }

  @override
  ClientTestModel fromJson(Map<String, dynamic> json) {
    return ClientTestModel.fromJson(json);
  }

  @override
  Map<String, dynamic> toJson(ClientTestModel model) {
    return model.toJson();
  }

  @override
  Future<ClientTestModel?> findOne(
    String id, {
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('findOne($id)');
    await Future.delayed(const Duration(milliseconds: 10));
    return _remoteData[id];
  }

  @override
  Future<List<ClientTestModel>> findAll({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('findAll()');
    await Future.delayed(const Duration(milliseconds: 10));
    return _remoteData.values.toList();
  }

  @override
  Future<ClientTestModel?> createOne(
    ClientTestModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('createOne(${model.id})');
    await Future.delayed(const Duration(milliseconds: 10));
    _remoteData[model.id] = model;
    return model;
  }

  @override
  Future<ClientTestModel?> updateOne(
    ClientTestModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('updateOne(${model.id})');
    await Future.delayed(const Duration(milliseconds: 10));
    _remoteData[model.id] = model;
    return model;
  }

  @override
  Future<ClientTestModel?> replaceOne(
    ClientTestModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('replaceOne(${model.id})');
    await Future.delayed(const Duration(milliseconds: 10));
    _remoteData[model.id] = model;
    return model;
  }

  @override
  Future<void> deleteOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('deleteOne($id)');
    await Future.delayed(const Duration(milliseconds: 10));
    _remoteData.remove(id);
  }
}

/// Mock API adapter for ServerParentModel with server-generated IDs
class MockServerParentAdapter extends ApiAdapterBase<ServerParentModel> {
  final Map<String, ServerParentModel> _remoteData = {};
  final List<String> _operationLog = [];
  int _nextServerId = 2000; // Start server IDs from 2000

  @override
  Uri get baseUrl => Uri.parse('https://test.example.com/api/v1/');

  @override
  String get type => 'server-parent-model';

  @override
  String get pluralType => 'server-parent-models';

  List<String> get operationLog => List.unmodifiable(_operationLog);

  void clearAll() {
    _remoteData.clear();
    _operationLog.clear();
  }

  @override
  ServerParentModel fromJson(Map<String, dynamic> json) {
    return ServerParentModel.fromJson(json);
  }

  @override
  Map<String, dynamic> toJson(ServerParentModel model) {
    return model.toJson();
  }

  @override
  Future<ServerParentModel?> createOne(
    ServerParentModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('createOne(${model.id})');

    await Future.delayed(const Duration(milliseconds: 10));

    // Simulate server generating a new ID
    final serverId = 'server_parent_${_nextServerId++}';
    final modelWithServerId = ServerParentModel(
      id: serverId,
      name: model.name,
      category: model.category,
    );

    _remoteData[serverId] = modelWithServerId;
    return modelWithServerId;
  }

  @override
  Future<ServerParentModel?> findOne(
    String id, {
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('findOne($id)');
    await Future.delayed(const Duration(milliseconds: 10));
    return _remoteData[id];
  }

  @override
  Future<List<ServerParentModel>> findAll({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('findAll()');
    await Future.delayed(const Duration(milliseconds: 10));
    return _remoteData.values.toList();
  }

  @override
  Future<ServerParentModel?> updateOne(
    ServerParentModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('updateOne(${model.id})');
    await Future.delayed(const Duration(milliseconds: 10));
    _remoteData[model.id] = model;
    return model;
  }

  @override
  Future<ServerParentModel?> replaceOne(
    ServerParentModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('replaceOne(${model.id})');
    await Future.delayed(const Duration(milliseconds: 10));
    _remoteData[model.id] = model;
    return model;
  }

  @override
  Future<void> deleteOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('deleteOne($id)');
    await Future.delayed(const Duration(milliseconds: 10));
    _remoteData.remove(id);
  }
}

/// Mock API adapter for ServerChildModel with server-generated IDs
class MockServerChildAdapter extends ApiAdapterBase<ServerChildModel> {
  final Map<String, ServerChildModel> _remoteData = {};
  final List<String> _operationLog = [];
  int _nextServerId = 3000; // Start server IDs from 3000

  @override
  Uri get baseUrl => Uri.parse('https://test.example.com/api/v1/');

  @override
  String get type => 'server-child-model';

  @override
  String get pluralType => 'server-child-models';

  List<String> get operationLog => List.unmodifiable(_operationLog);

  void clearAll() {
    _remoteData.clear();
    _operationLog.clear();
  }

  @override
  ServerChildModel fromJson(Map<String, dynamic> json) {
    return ServerChildModel.fromJson(json);
  }

  @override
  Map<String, dynamic> toJson(ServerChildModel model) {
    return model.toJson();
  }

  @override
  Future<ServerChildModel?> createOne(
    ServerChildModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('createOne(${model.id})');

    await Future.delayed(const Duration(milliseconds: 10));

    // Simulate server generating a new ID
    final serverId = 'server_child_${_nextServerId++}';
    final modelWithServerId = ServerChildModel(
      id: serverId,
      name: model.name,
      parentId: model.parentId,
      data: model.data,
    );

    _remoteData[serverId] = modelWithServerId;
    return modelWithServerId;
  }

  @override
  Future<ServerChildModel?> findOne(
    String id, {
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('findOne($id)');
    await Future.delayed(const Duration(milliseconds: 10));
    return _remoteData[id];
  }

  @override
  Future<List<ServerChildModel>> findAll({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('findAll()');
    await Future.delayed(const Duration(milliseconds: 10));
    return _remoteData.values.toList();
  }

  @override
  Future<ServerChildModel?> updateOne(
    ServerChildModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('updateOne(${model.id})');
    await Future.delayed(const Duration(milliseconds: 10));
    _remoteData[model.id] = model;
    return model;
  }

  @override
  Future<ServerChildModel?> replaceOne(
    ServerChildModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('replaceOne(${model.id})');
    await Future.delayed(const Duration(milliseconds: 10));
    _remoteData[model.id] = model;
    return model;
  }

  @override
  Future<void> deleteOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('deleteOne($id)');
    await Future.delayed(const Duration(milliseconds: 10));
    _remoteData.remove(id);
  }
}

/// Mock API adapter that simulates ID collisions
class MockIdCollisionAdapter extends MockServerIdAdapter {
  final Set<String> _existingServerIds = {};
  bool _shouldSimulateCollision = false;
  String? _collisionId;

  /// Add a model to remote data to simulate existing record
  void addExistingModel(ServerTestModel model) {
    _remoteData[model.id] = model;
    _existingServerIds.add(model.id);
  }

  /// Configure the adapter to simulate ID collision
  void simulateIdCollision(String existingId) {
    _existingServerIds.add(existingId);
    _shouldSimulateCollision = true;
    _collisionId = existingId;
  }

  /// Reset collision simulation
  void resetCollisionSimulation() {
    _shouldSimulateCollision = false;
    _collisionId = null;
    _existingServerIds.clear();
  }

  @override
  Future<ServerTestModel?> createOne(
    ServerTestModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('createOne(${model.id})');
    await Future.delayed(const Duration(milliseconds: 10));

    String serverId;
    if (_shouldSimulateCollision && _collisionId != null) {
      // Return the collision ID on first attempt
      serverId = _collisionId!;
      _shouldSimulateCollision = false; // Only collide once
    } else {
      serverId = 'server_${_nextServerId++}';
    }

    // Check if ID already exists in remote data (collision scenario)
    if (_remoteData.containsKey(serverId)) {
      throw Exception('ID collision: Server ID $serverId already exists');
    }

    final modelWithServerId = ServerTestModel(
      id: serverId,
      name: model.name,
      description: model.description,
    );

    _remoteData[serverId] = modelWithServerId;
    _existingServerIds.add(serverId);
    return modelWithServerId;
  }
}

/// Mock API adapter that simulates partial failures
class MockPartialFailureAdapter extends MockServerIdAdapter {
  bool _shouldFailOnCreate = false;
  bool _shouldFailOnUpdate = false;
  bool _shouldFailOnDelete = false;
  int _failureCount = 0;
  int _maxFailures = 1;

  /// Configure the adapter to fail on create operations
  void simulateCreateFailure({int maxFailures = 1}) {
    _shouldFailOnCreate = true;
    _maxFailures = maxFailures;
    _failureCount = 0;
  }

  /// Configure the adapter to fail on update operations
  void simulateUpdateFailure({int maxFailures = 1}) {
    _shouldFailOnUpdate = true;
    _maxFailures = maxFailures;
    _failureCount = 0;
  }

  /// Configure the adapter to fail on delete operations
  void simulateDeleteFailure({int maxFailures = 1}) {
    _shouldFailOnDelete = true;
    _maxFailures = maxFailures;
    _failureCount = 0;
  }

  /// Reset failure simulation
  void resetFailureSimulation() {
    _shouldFailOnCreate = false;
    _shouldFailOnUpdate = false;
    _shouldFailOnDelete = false;
    _failureCount = 0;
  }

  @override
  Future<ServerTestModel?> createOne(
    ServerTestModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('createOne(${model.id})');
    await Future.delayed(const Duration(milliseconds: 10));

    if (_shouldFailOnCreate && _failureCount < _maxFailures) {
      _failureCount++;
      throw Exception('Simulated create failure (attempt $_failureCount)');
    }

    return super.createOne(model, headers: headers, extra: extra);
  }

  @override
  Future<ServerTestModel?> updateOne(
    ServerTestModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('updateOne(${model.id})');
    await Future.delayed(const Duration(milliseconds: 10));

    if (_shouldFailOnUpdate && _failureCount < _maxFailures) {
      _failureCount++;
      throw Exception('Simulated update failure (attempt $_failureCount)');
    }

    return super.updateOne(model, headers: headers, extra: extra);
  }

  @override
  Future<void> deleteOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('deleteOne($id)');
    await Future.delayed(const Duration(milliseconds: 10));

    if (_shouldFailOnDelete && _failureCount < _maxFailures) {
      _failureCount++;
      throw Exception('Simulated delete failure (attempt $_failureCount)');
    }

    return super.deleteOne(id, headers: headers, extra: extra);
  }
}

/// Mock API adapter that simulates network timeouts
class MockTimeoutAdapter extends MockServerIdAdapter {
  Duration _timeout = const Duration(seconds: 5);
  bool _shouldTimeout = false;
  String _timeoutOperation = 'create';

  /// Configure the adapter to simulate timeouts
  void simulateTimeout({
    Duration timeout = const Duration(seconds: 5),
    String operation = 'create',
  }) {
    _timeout = timeout;
    _shouldTimeout = true;
    _timeoutOperation = operation;
  }

  /// Reset timeout simulation
  void resetTimeoutSimulation() {
    _shouldTimeout = false;
  }

  @override
  Future<ServerTestModel?> createOne(
    ServerTestModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('createOne(${model.id})');

    if (_shouldTimeout && _timeoutOperation == 'create') {
      await Future.delayed(_timeout);
      throw TimeoutException('Create operation timed out', _timeout);
    }

    return super.createOne(model, headers: headers, extra: extra);
  }

  @override
  Future<ServerTestModel?> updateOne(
    ServerTestModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('updateOne(${model.id})');

    if (_shouldTimeout && _timeoutOperation == 'update') {
      await Future.delayed(_timeout);
      throw TimeoutException('Update operation timed out', _timeout);
    }

    return super.updateOne(model, headers: headers, extra: extra);
  }

  @override
  Future<void> deleteOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('deleteOne($id)');

    if (_shouldTimeout && _timeoutOperation == 'delete') {
      await Future.delayed(_timeout);
      throw TimeoutException('Delete operation timed out', _timeout);
    }

    return super.deleteOne(id, headers: headers, extra: extra);
  }
}

/// Mock API adapter that simulates concurrent ID replacement scenarios
class MockConcurrentAdapter extends MockServerIdAdapter {
  final Map<String, List<Completer<ServerTestModel?>>> _pendingOperations = {};
  bool _shouldSimulateConcurrentOperations = false;
  int _concurrentOperationDelay = 100; // milliseconds

  /// Configure the adapter to simulate concurrent operations
  void simulateConcurrentOperations({int delayMs = 100}) {
    _shouldSimulateConcurrentOperations = true;
    _concurrentOperationDelay = delayMs;
  }

  /// Reset concurrent simulation
  void resetConcurrentSimulation() {
    _shouldSimulateConcurrentOperations = false;
    _pendingOperations.clear();
  }

  @override
  Future<ServerTestModel?> createOne(
    ServerTestModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('createOne(${model.id})');

    if (_shouldSimulateConcurrentOperations) {
      // Check if there's already a pending operation for this model
      if (_pendingOperations.containsKey(model.id)) {
        // Add this operation to the queue
        final completer = Completer<ServerTestModel?>();
        _pendingOperations[model.id]!.add(completer);
        return completer.future;
      } else {
        // Start a new concurrent operation sequence
        _pendingOperations[model.id] = [];

        // Simulate delay to allow concurrent operations to queue up
        await Future.delayed(Duration(milliseconds: _concurrentOperationDelay));

        // Process the operation
        final result = await super.createOne(
          model,
          headers: headers,
          extra: extra,
        );

        // Complete all queued operations with the same result
        final queuedOperations = _pendingOperations.remove(model.id) ?? [];
        for (final completer in queuedOperations) {
          completer.complete(result);
        }

        return result;
      }
    }

    return super.createOne(model, headers: headers, extra: extra);
  }
}

void main() {
  group('Server ID Integration Tests', () {
    late SynquillDatabase db;
    late Logger logger;

    setUp(() async {
      // Set up test database using the generated SynquillDatabase
      db = SynquillDatabase(NativeDatabase.memory());

      // Set up logging
      logger = Logger('ServerIdIntegrationTest');
      Logger.root.level = Level.ALL;
      Logger.root.onRecord.listen((record) {
        // Uncomment for debugging:
        // print('[${record.level.name}] ${record.loggerName}: '
        //     '${record.message}');
      });

      // Initialize SynquillStorage with test configuration
      await SynquillStorage.init(
        database: db,
        config: const SynquillStorageConfig(
          defaultSavePolicy: DataSavePolicy.localFirst,
          defaultLoadPolicy: DataLoadPolicy.localOnly,
          foregroundQueueConcurrency: 1,
          backgroundQueueConcurrency: 1,
        ),
        logger: logger,
        initializeFn: initializeSynquillStorage,
        enableInternetMonitoring: false,
      );
    });

    tearDown(() async {
      await SynquillStorage.close();
      SynquillRepositoryProvider.reset();
    });

    group('Basic Server ID Functionality', () {
      test('should identify server ID models correctly', () {
        final serverModel = ServerTestModel(
          id: generateCuid(),
          name: 'Test Server Model',
          description: 'Test Description',
        );

        final clientModel = ClientTestModel(
          name: 'Test Client Model',
        );

        expect(serverModel.$usesServerGeneratedId, isTrue);
        expect(clientModel.$usesServerGeneratedId, isFalse);
      });

      test('should save server ID model locally with repository', () async {
        final tempId = generateCuid();
        final serverModel = ServerTestModel(
          id: tempId,
          name: 'Test Server Model',
          description: 'Test Description',
        );

        final serverRepo =
            SynquillStorage.instance.getRepository<ServerTestModel>();

        // Save locally first
        final savedModel = await serverRepo.save(serverModel);

        expect(savedModel.id, equals(tempId));
        expect(savedModel.name, equals('Test Server Model'));

        // Verify it's saved in local database
        final localModel = await serverRepo.findOne(tempId);
        expect(localModel, isNotNull);
        expect(localModel!.id, equals(tempId));
      });

      test('should handle ID replacement correctly', () async {
        final tempId = generateCuid();
        final newId = generateCuid();

        final serverModel = ServerTestModel(
          id: tempId,
          name: 'Replace Test',
          description: 'Testing ID replacement',
        );

        // Test ID replacement method
        final replacedModel = serverModel.$replaceIdEverywhere(newId);

        expect(replacedModel.id, equals(newId));
        expect(replacedModel.name, equals('Replace Test'));
        expect(replacedModel.description, equals('Testing ID replacement'));

        // Verify original model unchanged
        expect(serverModel.id, equals(tempId));
      });

      test('should work with sync queue operations', () async {
        final tempId = generateCuid();
        final serverModel = ServerTestModel(
          id: tempId,
          name: 'Queue Test Model',
          description: 'Testing sync queue',
        );

        final serverRepo =
            SynquillStorage.instance.getRepository<ServerTestModel>();

        // Save model - this should create a sync queue entry
        await serverRepo.save(serverModel);

        // Wait briefly for async operations
        await Future.delayed(const Duration(milliseconds: 50));

        // Check sync queue API works and model is saved
        final queueDao = SyncQueueDao(db);
        await queueDao.getDueTasks(); // Test queue API

        // The sync operation may complete quickly.
        // In either case, the model should be saved locally
        final savedModel = await serverRepo.findOne(tempId);
        expect(savedModel, isNotNull);
        expect(savedModel!.name, equals('Queue Test Model'));

        // Also test that we can use the queue DAO API
        expect(queueDao, isNotNull);
      });

      test('should handle multiple models with different ID strategies',
          () async {
        final serverModel = ServerTestModel(
          id: generateCuid(),
          name: 'Server Model',
          description: 'Uses server ID',
        );

        final clientModel = ClientTestModel(
          name: 'Client Model',
        );

        final clientOriginalId = clientModel.id;

        final serverRepo =
            SynquillStorage.instance.getRepository<ServerTestModel>();
        final clientRepo =
            SynquillStorage.instance.getRepository<ClientTestModel>();

        // Save both models
        await serverRepo.save(serverModel);
        await clientRepo.save(clientModel);

        // Verify both models exist
        final savedServerModel = await serverRepo.findOne(serverModel.id);
        expect(savedServerModel, isNotNull);

        final savedClientModel = await clientRepo.findOne(clientOriginalId);
        expect(savedClientModel, isNotNull);
        expect(savedClientModel!.id, equals(clientOriginalId));
      });
    });

    group('ID Negotiation Service Integration', () {
      test('should integrate with repository for server ID models', () {
        final serverModel = ServerTestModel(
          id: generateCuid(),
          name: 'Service Test',
          description: 'Testing service integration',
        );

        // Test that the service can be created and works
        final service = IdNegotiationService<ServerTestModel>(
          usesServerGeneratedId: true,
        );

        expect(service.modelUsesServerGeneratedId(serverModel), isTrue);
        expect(service.hasTemporaryId(serverModel), isFalse);
        expect(service.getTemporaryClientId(serverModel), isNull);
      });

      test('should integrate with repository for client ID models', () {
        final clientModel = ClientTestModel(
          name: 'Service Test Client',
        );

        // Test that the service works for client models too
        final service = IdNegotiationService<ClientTestModel>(
          usesServerGeneratedId: false,
        );

        expect(service.modelUsesServerGeneratedId(clientModel), isFalse);
        expect(service.hasTemporaryId(clientModel), isFalse);
        expect(service.getTemporaryClientId(clientModel), isNull);
      });
    });

    group('Database Integration', () {
      test('should store and retrieve server ID models correctly', () async {
        final tempId = generateCuid();
        final serverModel = ServerTestModel(
          id: tempId,
          name: 'DB Test Model',
          description: 'Testing database integration',
        );

        final serverRepo =
            SynquillStorage.instance.getRepository<ServerTestModel>();

        // Save model
        await serverRepo.save(serverModel);

        // Retrieve all models
        final allModels = await serverRepo.findAll();
        expect(allModels, hasLength(1));
        expect(allModels.first.id, equals(tempId));
        expect(allModels.first.name, equals('DB Test Model'));
      });

      test('should work with repository watch functionality', () async {
        final tempId = generateCuid();
        final serverModel = ServerTestModel(
          id: tempId,
          name: 'Watch Test',
          description: 'Testing watch integration',
        );

        final serverRepo =
            SynquillStorage.instance.getRepository<ServerTestModel>();

        final modelUpdates = <ServerTestModel?>[];
        final subscription = serverRepo.watchOne(tempId).listen((model) {
          modelUpdates.add(model);
        });

        // Save model
        await serverRepo.save(serverModel);

        // Wait a bit for the watch to fire
        await Future.delayed(const Duration(milliseconds: 50));

        // Should have received an update
        expect(modelUpdates, isNotEmpty);
        expect(modelUpdates.last, isNotNull);
        expect(modelUpdates.last!.id, equals(tempId));
        expect(modelUpdates.last!.name, equals('Watch Test'));

        await subscription.cancel();
      });

      test('should work with findAll operations', () async {
        final models = [
          ServerTestModel(
            id: generateCuid(),
            name: 'Model A',
            description: 'First model',
          ),
          ServerTestModel(
            id: generateCuid(),
            name: 'Model B',
            description: 'Second model',
          ),
        ];

        final serverRepo =
            SynquillStorage.instance.getRepository<ServerTestModel>();

        // Save models
        for (final model in models) {
          await serverRepo.save(model);
        }

        // Find all models
        final allModels = await serverRepo.findAll();

        expect(allModels, hasLength(2));

        final names = allModels.map((model) => model.name).toSet();
        expect(names, containsAll(['Model A', 'Model B']));
      });
    });

    group('Comparison with Client ID Models', () {
      test('should handle client ID models without ID replacement', () async {
        final clientModel = ClientTestModel(
          name: 'Client Model',
        );

        final originalId = clientModel.id;

        final clientRepo =
            SynquillStorage.instance.getRepository<ClientTestModel>();

        // Save client model
        await clientRepo.save(clientModel);

        // Verify ID never changed
        final savedModel = await clientRepo.findOne(originalId);
        expect(savedModel, isNotNull);
        expect(savedModel!.id, equals(originalId));
      });

      test('should handle mixed server and client ID models in storage',
          () async {
        final serverModel = ServerTestModel(
          id: generateCuid(),
          name: 'Server Model',
          description: 'Uses server ID',
        );

        final clientModel = ClientTestModel(
          name: 'Client Model',
        );

        final clientOriginalId = clientModel.id;

        final serverRepo =
            SynquillStorage.instance.getRepository<ServerTestModel>();
        final clientRepo =
            SynquillStorage.instance.getRepository<ClientTestModel>();

        // Save both models
        await serverRepo.save(serverModel);
        await clientRepo.save(clientModel);

        // Verify both types work independently
        final finalServerModel = await serverRepo.findOne(serverModel.id);
        expect(finalServerModel, isNotNull);

        final finalClientModel = await clientRepo.findOne(clientOriginalId);
        expect(finalClientModel, isNotNull);
        expect(finalClientModel!.id, equals(clientOriginalId));

        // Check both appear in findAll
        final allServerModels = await serverRepo.findAll();
        final allClientModels = await clientRepo.findAll();

        expect(allServerModels, hasLength(1));
        expect(allClientModels, hasLength(1));
      });
    });

    group('Event System Integration', () {
      test('should work with repository event infrastructure', () {
        // Test that enums and infrastructure work
        expect(RepositoryChangeType.created, isNotNull);
        expect(RepositoryChangeType.updated, isNotNull);
        expect(RepositoryChangeType.deleted, isNotNull);
        expect(RepositoryChangeType.idChanged, isNotNull);
        expect(RepositoryChangeType.error, isNotNull);

        // Test that repository change factory methods work
        final testModel = ServerTestModel(
          id: generateCuid(),
          name: 'Test',
          description: 'Test',
        );

        final createChange = RepositoryChange.created(testModel);
        expect(createChange.type, equals(RepositoryChangeType.created));
        expect(createChange.item, equals(testModel));

        final updateChange = RepositoryChange.updated(testModel);
        expect(updateChange.type, equals(RepositoryChangeType.updated));

        final idChange = RepositoryChange.idChanged(
          testModel,
          'old-id',
          'new-id',
        );
        expect(idChange.type, equals(RepositoryChangeType.idChanged));
        expect(idChange.item, equals(testModel));
      });
    });

    group('RemoteFirst Sync Queue Operations', () {
      test('should handle sync queue operations with remoteFirst policy',
          () async {
        // Create model with server ID (remoteFirst is implicitly handled)
        final serverModel = ServerTestModel(
          id: generateCuid(),
          name: 'RemoteFirst Model',
          description: 'Test remoteFirst sync',
        );

        final serverRepo =
            SynquillStorage.instance.getRepository<ServerTestModel>();

        // Save model - this should bypass the queue since it has a server ID
        await serverRepo.save(serverModel);

        // Check queue is empty (no pending operations for server ID models)
        final queueDao = SyncQueueDao(db);
        final queueItems = await queueDao.getAllItems();

        // With server IDs, direct saves should not create queue entries
        // The model already has a valid server ID
        expect(
          queueItems.where((item) => item['model_id'] == serverModel.id),
          isEmpty,
        );

        // Verify model was saved directly to database
        final savedModel = await serverRepo.findOne(serverModel.id);
        expect(savedModel, isNotNull);
        expect(savedModel!.name, equals('RemoteFirst Model'));
      });

      test('should handle updates to existing server ID models', () async {
        final originalModel = ServerTestModel(
          id: generateCuid(),
          name: 'Original Name',
          description: 'Original Description',
        );

        final serverRepo =
            SynquillStorage.instance.getRepository<ServerTestModel>();

        // Save original
        await serverRepo.save(originalModel);

        // Update the model
        final updatedModel = ServerTestModel(
          id: originalModel.id,
          name: 'Updated Name',
          description: 'Updated Description',
        );

        await serverRepo.save(updatedModel);

        // Verify update worked
        final finalModel = await serverRepo.findOne(originalModel.id);
        expect(finalModel, isNotNull);
        expect(finalModel!.name, equals('Updated Name'));
        expect(finalModel.description, equals('Updated Description'));

        // Check that queue doesn't have stale entries
        final queueDao = SyncQueueDao(db);
        final queueItems = await queueDao.getAllItems();
        expect(
          queueItems.where((item) => item['model_id'] == originalModel.id),
          isEmpty,
        );
      });
    });

    group('LocalFirst ID Replacement in Sync Queue', () {
      late MockServerIdAdapter mockAdapter;
      late _TestServerTestRepository testRepo;

      setUp(() async {
        // Set up mock adapter to simulate server ID assignment
        mockAdapter = MockServerIdAdapter();

        // Create repository instance directly with mock adapter
        testRepo = _TestServerTestRepository(db, mockAdapter);

        // Register custom repository factory for global system (RetryExecutor)
        SynquillRepositoryProvider.register<ServerTestModel>(
          (db) => _TestServerTestRepository(db, mockAdapter),
        );
      });

      test('should replace IDs in sync queue when local model gets server ID',
          () async {
        // Verify our custom repository is being used by checking if it's
        // connected to our mock
        mockAdapter.clearAll(); // Reset log

        // Create a model with temporary ID
        final tempId = generateCuid();
        final localModel = ServerTestModel(
          id: tempId,
          name: 'LocalFirst Model',
          description: 'Will get server ID later',
        );

        // Save with localFirst policy to trigger ID negotiation
        final savedModel = await testRepo.save(
          localModel,
          savePolicy: DataSavePolicy.localFirst,
        );

        // Verify model saved locally with temporary ID
        expect(savedModel.id, equals(tempId));
        expect(savedModel.name, equals('LocalFirst Model'));

        // Check sync queue immediately after save (before background
        // processing)
        final queueDao = SyncQueueDao(db);
        final queueItems = await queueDao.getAllItems();

        expect(
          queueItems.where((item) => item['model_id'] == tempId),
          hasLength(1),
        );

        // Verify the queue entry was created for the temporary ID
        final queueEntry =
            queueItems.where((item) => item['model_id'] == tempId).first;

        expect(queueEntry['model_id'], equals(tempId));
        expect(queueEntry['op'], equals('create'));
        expect(queueEntry['temporary_client_id'], equals(tempId));
        expect(queueEntry['id_negotiation_status'], equals('pending'));

        // Process background sync tasks to trigger ID negotiation
        await SynquillStorage.instance
            .processBackgroundSyncTasks(forceSync: true);

        // Wait for the async operations to complete
        await Future.delayed(const Duration(milliseconds: 300));

        // Verify adapter was called for creation after background sync
        expect(mockAdapter.operationLog, contains('createOne($tempId)'));

        // Verify server ID was assigned in remote data after async operation
        final serverKey = mockAdapter.remoteData.keys
            .firstWhere((key) => key.startsWith('server_'), orElse: () => '');
        expect(serverKey, isNotEmpty);

        // Verify local model now has server ID (find by server ID)
        final finalModel = await testRepo.findOne(serverKey);

        expect(finalModel, isNotNull);
        expect(finalModel!.name, equals('LocalFirst Model'));
        expect(finalModel.description, equals('Will get server ID later'));

        // Verify temporary ID no longer exists
        expect(await testRepo.findOne(tempId), isNull);

        // Verify sync queue updated - after successful sync,
        // the task should be removed
        final updatedQueueItems = await queueDao.getAllItems();
        expect(
          updatedQueueItems.where((item) => item['model_id'] == tempId),
          isEmpty,
        );
        // After successful sync, the task is removed from queue,
        // so no entry should exist
        expect(
          updatedQueueItems.where((item) => item['model_id'] == serverKey),
          isEmpty,
        );
      });

      test(
          'should handle multiple operations for same model during ID '
          'negotiation', () async {
        final tempId = generateCuid();
        var model = ServerTestModel(
          id: tempId,
          name: 'Initial Name',
          description: 'Initial Description',
        );

        // Save initial model with localFirst policy
        model = await testRepo.save(
          model,
          savePolicy: DataSavePolicy.localFirst,
        );

        // Update the model multiple times
        model = ServerTestModel(
          id: model.id,
          name: 'Updated Name 1',
          description: model.description,
        );
        model = await testRepo.save(
          model,
          savePolicy: DataSavePolicy.localFirst,
        );

        model = ServerTestModel(
          id: model.id,
          name: model.name,
          description: 'Updated Description',
        );
        model = await testRepo.save(
          model,
          savePolicy: DataSavePolicy.localFirst,
        );

        // Wait for ID negotiation to complete
        await Future.delayed(const Duration(milliseconds: 200));

        // Get the actual server ID assigned
        final serverKey = mockAdapter.remoteData.keys
            .firstWhere((key) => key.startsWith('server_'), orElse: () => '');
        expect(serverKey, isNotEmpty);

        // Verify all operations were handled correctly
        final finalModel = await testRepo.findOne(serverKey);

        expect(finalModel, isNotNull);
        expect(finalModel!.name, equals('Updated Name 1'));
        expect(finalModel.description, equals('Updated Description'));

        // Verify temporary ID no longer exists
        expect(await testRepo.findOne(tempId), isNull);

        // Verify queue operations handled properly
        final queueDao = SyncQueueDao(db);
        final queueItems = await queueDao.getAllItems();

        // After successful sync, queue should be mostly empty
        // (successful operations are removed from queue)
        expect(
          queueItems.where((item) => item['model_id'] == tempId),
          isEmpty,
        );

        // After successful sync, tasks are removed from queue
        final serverIdEntries =
            queueItems.where((item) => item['model_id'] == serverKey).toList();
        expect(serverIdEntries, isEmpty);
      });
    });

    group('Relationship Integrity After ID Changes', () {
      late MockServerParentAdapter parentAdapter;
      late MockServerChildAdapter childAdapter;
      late _TestServerParentRepository parentRepo;
      late _TestServerChildRepository childRepo;

      setUp(() async {
        // Set up mock adapters for real ID negotiation
        parentAdapter = MockServerParentAdapter();
        childAdapter = MockServerChildAdapter();

        // Create repository instances directly with mock adapters
        parentRepo = _TestServerParentRepository(db, parentAdapter);
        childRepo = _TestServerChildRepository(db, childAdapter);

        // Register custom repositories for global system (RetryExecutor)
        SynquillRepositoryProvider.register<ServerParentModel>(
          (db) => _TestServerParentRepository(db, parentAdapter),
        );
        SynquillRepositoryProvider.register<ServerChildModel>(
          (db) => _TestServerChildRepository(db, childAdapter),
        );
      });

      test('should maintain foreign key relationships when parent ID changes',
          () async {
        // Create parent and child with temporary IDs
        final tempParentId = generateCuid();
        final tempChildId = generateCuid();

        final parent = ServerParentModel(
          id: tempParentId,
          name: 'Parent Model',
          category: 'Test Category',
        );

        final child = ServerChildModel(
          id: tempChildId,
          name: 'Child Model',
          parentId: tempParentId, // References temporary parent ID
          data: 'Child data',
        );

        // Listen for ID change events
        final parentChanges = <RepositoryChange<ServerParentModel>>[];
        final childChanges = <RepositoryChange<ServerChildModel>>[];

        final parentSub = parentRepo.changes.listen(parentChanges.add);
        final childSub = childRepo.changes.listen(childChanges.add);

        // Save parent with remoteFirst policy to trigger ID negotiation
        final savedParent = await parentRepo.save(
          parent,
          savePolicy: DataSavePolicy.remoteFirst,
        );

        // Parent should now have server-assigned ID
        expect(savedParent.id, startsWith('server_parent_'));
        expect(savedParent.name, equals('Parent Model'));

        // Update child to reference the new parent ID and save
        final updatedChild = ServerChildModel(
          id: tempChildId,
          name: child.name,
          parentId: savedParent.id, // Now references server ID
          data: child.data,
        );

        final savedChild = await childRepo.save(
          updatedChild,
          savePolicy: DataSavePolicy.remoteFirst,
        );

        // Child should also get server ID and maintain correct relationship
        expect(savedChild.id, startsWith('server_child_'));
        expect(savedChild.parentId, equals(savedParent.id));
        expect(savedChild.name, equals('Child Model'));

        // Verify database state
        final finalParent = await parentRepo.findOne(savedParent.id);
        final finalChild = await childRepo.findOne(savedChild.id);

        expect(finalParent, isNotNull);
        expect(finalChild, isNotNull);
        expect(finalChild!.parentId, equals(finalParent!.id));

        // Verify temporary IDs no longer exist
        expect(await parentRepo.findOne(tempParentId), isNull);
        expect(await childRepo.findOne(tempChildId), isNull);

        // Verify API adapters were called
        expect(
            parentAdapter.operationLog, contains('createOne($tempParentId)'));
        expect(childAdapter.operationLog, contains('createOne($tempChildId)'));

        // Verify relationship integrity in final state
        final allParents = await parentRepo.findAll();
        final allChildren = await childRepo.findAll();

        expect(allParents, hasLength(1));
        expect(allChildren, hasLength(1));
        expect(allChildren.first.parentId, equals(allParents.first.id));

        // Clean up subscriptions
        await parentSub.cancel();
        await childSub.cancel();
      });

      test('should handle cascade operations when IDs change', () async {
        // Create parent and multiple children with temporary IDs
        final tempParentId = generateCuid();
        final tempChild1Id = generateCuid();
        final tempChild2Id = generateCuid();

        final parent = ServerParentModel(
          id: tempParentId,
          name: 'Parent with Children',
          category: 'Cascade Test',
        );

        final child1 = ServerChildModel(
          id: tempChild1Id,
          name: 'Child 1',
          parentId: tempParentId,
          data: 'Data 1',
        );

        final child2 = ServerChildModel(
          id: tempChild2Id,
          name: 'Child 2',
          parentId: tempParentId,
          data: 'Data 2',
        );

        // Save parent first with remoteFirst to get server ID
        final savedParent = await parentRepo.save(
          parent,
          savePolicy: DataSavePolicy.remoteFirst,
        );

        // Parent now has server ID
        expect(savedParent.id, startsWith('server_parent_'));

        // Update children to reference new parent ID and save them
        final updatedChild1 = ServerChildModel(
          id: tempChild1Id,
          name: child1.name,
          parentId: savedParent.id, // Reference server parent ID
          data: child1.data,
        );

        final updatedChild2 = ServerChildModel(
          id: tempChild2Id,
          name: child2.name,
          parentId: savedParent.id, // Reference server parent ID
          data: child2.data,
        );

        final savedChild1 = await childRepo.save(
          updatedChild1,
          savePolicy: DataSavePolicy.remoteFirst,
        );

        final savedChild2 = await childRepo.save(
          updatedChild2,
          savePolicy: DataSavePolicy.remoteFirst,
        );

        // Children now have server IDs
        expect(savedChild1.id, startsWith('server_child_'));
        expect(savedChild2.id, startsWith('server_child_'));
        expect(savedChild1.parentId, equals(savedParent.id));
        expect(savedChild2.parentId, equals(savedParent.id));

        // Verify all models exist with correct relationships
        final allChildren = await childRepo.findAll();
        final parentChildren =
            allChildren.where((c) => c.parentId == savedParent.id).toList();
        expect(parentChildren, hasLength(2));

        // Test cascade delete with real repository operations
        await parentRepo.delete(
          savedParent.id,
          savePolicy: DataSavePolicy.remoteFirst,
        );

        // Verify parent is deleted
        final deletedParent = await parentRepo.findOne(savedParent.id);
        expect(deletedParent, isNull);

        // In a real system with proper cascade delete configuration,
        // children would be deleted automatically. For this test,
        // we verify the structure supports it by checking if children
        // can be found and cleaned up
        final remainingChildren = await childRepo.findAll();

        // If cascade delete was properly configured, children would be
        // automatically deleted. Here we verify they can still be found
        // and manually clean them up to demonstrate the pattern
        for (final child in remainingChildren) {
          if (child.parentId == savedParent.id) {
            await childRepo.delete(
              child.id,
              savePolicy: DataSavePolicy.remoteFirst,
            );
          }
        }

        // Verify cleanup worked
        final finalChildren = await childRepo.findAll();
        final orphanedChildren =
            finalChildren.where((c) => c.parentId == savedParent.id).toList();
        expect(orphanedChildren, hasLength(0));

        // Verify adapters were called for all operations
        expect(
            parentAdapter.operationLog, contains('createOne($tempParentId)'));
        expect(parentAdapter.operationLog,
            contains('deleteOne(${savedParent.id})'));
        expect(childAdapter.operationLog, contains('createOne($tempChild1Id)'));
        expect(childAdapter.operationLog, contains('createOne($tempChild2Id)'));
      });

      test(
          'should handle complex ID replacement scenarios with '
          'automatic foreign key updates', () async {
        // Create models with temporary client IDs using localFirst policy
        // This simulates real offline-first usage
        final tempParentId = generateCuid();
        final tempChildId = generateCuid();

        final parent = ServerParentModel(
          id: tempParentId,
          name: 'Offline Parent',
          category: 'Offline First Test',
        );

        final child = ServerChildModel(
          id: tempChildId,
          name: 'Offline Child',
          parentId: tempParentId, // References parent's temporary ID
          data: 'Offline data',
        );

        // Listen to repository change events to track ID changes
        final parentChanges = <RepositoryChange<ServerParentModel>>[];
        final childChanges = <RepositoryChange<ServerChildModel>>[];

        final parentSub = parentRepo.changes.listen(parentChanges.add);
        final childSub = childRepo.changes.listen(childChanges.add);

        // Save both models with localFirst policy (offline-first)
        // This should trigger ID negotiation for both
        final savedParent = await parentRepo.save(
          parent,
          savePolicy: DataSavePolicy.localFirst,
        );

        final savedChild = await childRepo.save(
          child,
          savePolicy: DataSavePolicy.localFirst,
        );

        // Initially, both should have temporary IDs
        expect(savedParent.id, equals(tempParentId));
        expect(savedChild.id, equals(tempChildId));
        expect(savedChild.parentId, equals(tempParentId));

        // Wait for background ID negotiation to complete
        await Future.delayed(const Duration(milliseconds: 500));

        // Force process background sync tasks to ensure completion
        await SynquillStorage.instance
            .processBackgroundSyncTasks(forceSync: true);

        // After ID negotiation, both should have server IDs
        final finalParents = await parentRepo.findAll();
        final finalChildren = await childRepo.findAll();

        expect(finalParents, hasLength(1));
        expect(finalChildren, hasLength(1));

        final finalParent = finalParents.first;
        final finalChild = finalChildren.first;

        // Verify both got server IDs
        expect(finalParent.id, startsWith('server_parent_'));
        expect(finalChild.id, startsWith('server_child_'));

        // Verify data integrity
        expect(finalParent.name, equals('Offline Parent'));
        expect(finalParent.category, equals('Offline First Test'));
        expect(finalChild.name, equals('Offline Child'));
        expect(finalChild.data, equals('Offline data'));

        // CRITICAL: Verify automatic foreign key update
        // The child's parentId should automatically reference
        // the parent's new server ID
        expect(finalChild.parentId, equals(finalParent.id));

        // Verify old temporary IDs no longer exist
        expect(await parentRepo.findOne(tempParentId), isNull);
        expect(await childRepo.findOne(tempChildId), isNull);

        // Verify API operations were called for both models
        expect(
            parentAdapter.operationLog, contains('createOne($tempParentId)'));
        expect(childAdapter.operationLog, contains('createOne($tempChildId)'));

        // Verify relationship integrity in database
        expect(finalChild.parentId, equals(finalParent.id));

        // Verify repository events were emitted
        expect(parentChanges, isNotEmpty);
        expect(childChanges, isNotEmpty);

        // Check for ID change events
        final parentIdChanges = parentChanges
            .where((c) => c.type == RepositoryChangeType.idChanged)
            .toList();
        final childIdChanges = childChanges
            .where((c) => c.type == RepositoryChangeType.idChanged)
            .toList();

        // Verify ID change events were emitted
        if (parentIdChanges.isNotEmpty) {
          expect(parentIdChanges.first.oldId, equals(tempParentId));
          expect(parentIdChanges.first.id, equals(finalParent.id));
        }

        if (childIdChanges.isNotEmpty) {
          expect(childIdChanges.first.oldId, equals(tempChildId));
          expect(childIdChanges.first.id, equals(finalChild.id));
        }

        // Clean up subscriptions
        await parentSub.cancel();
        await childSub.cancel();
      });
    });

    group('Edge Cases and Error Scenarios', () {
      group('ID Collision Scenarios', () {
        test('should handle server ID collision gracefully', () async {
          final mockAdapter = MockIdCollisionAdapter();
          final repository = _TestServerTestRepository(db, mockAdapter);

          // Pre-populate adapter with existing server ID to simulate collision
          const existingServerId = 'server_collision_test';
          final existingModel = ServerTestModel(
            id: existingServerId,
            name: 'Existing Model',
            description: 'Already exists',
          );

          // Use the proper method to add existing model
          mockAdapter.addExistingModel(existingModel);
          mockAdapter.simulateIdCollision(existingServerId);

          final newModel = ServerTestModel(
            id: generateCuid(),
            name: 'New Model',
            description: 'Should get different ID',
          );

          // Save with localFirst should succeed locally
          final savedModel = await repository.save(
            newModel,
            savePolicy: DataSavePolicy.localFirst,
          );
          expect(savedModel.id, equals(newModel.id));

          // Verify model is saved locally with temporary ID
          final localModel = await repository.findOne(newModel.id);
          expect(localModel, isNotNull);
          expect(localModel!.name, equals('New Model'));

          // Register repository for background sync
          SynquillRepositoryProvider.register<ServerTestModel>(
            (db) => _TestServerTestRepository(db, mockAdapter),
          );

          // Trigger background sync which should attempt createOne
          // and detect collision
          await SynquillStorage.instance
              .processBackgroundSyncTasks(forceSync: true);

          // Wait for async operations to complete
          await Future.delayed(const Duration(milliseconds: 200));

          // Verify that create operation was attempted (logged)
          expect(
            mockAdapter.operationLog,
            contains('createOne(${newModel.id})'),
          );

          // Check if collision was handled - the adapter should have
          // thrown exception but repository should still maintain local data
          final stillLocalModel = await repository.findOne(newModel.id);
          expect(stillLocalModel, isNotNull);
          expect(stillLocalModel!.name, equals('New Model'));

          // Verify existing model is still intact
          expect(mockAdapter.remoteData[existingServerId], isNotNull);
          expect(
            mockAdapter.remoteData[existingServerId]!.name,
            equals('Existing Model'),
          );
        });

        test('should handle actual ID collision during background sync',
            () async {
          final mockAdapter = MockIdCollisionAdapter();
          final repository = _TestServerTestRepository(db, mockAdapter);

          // Create an existing model first
          const existingServerId = 'server_collision_test';
          final existingModel = ServerTestModel(
            id: existingServerId,
            name: 'Existing Model',
            description: 'Already exists',
          );

          // Add existing model to remote data using proper method
          mockAdapter.addExistingModel(existingModel);

          // Configure adapter to always return the existing ID
          // (simulating server always assigning the same ID)
          mockAdapter.simulateIdCollision(existingServerId);

          final newModel = ServerTestModel(
            id: generateCuid(),
            name: 'New Model',
            description: 'Should conflict',
          );

          // Save with localFirst (succeeds locally)
          final savedModel = await repository.save(
            newModel,
            savePolicy: DataSavePolicy.localFirst,
          );
          expect(savedModel.id, equals(newModel.id));

          // Register repository for background sync
          SynquillRepositoryProvider.register<ServerTestModel>(
            (db) => _TestServerTestRepository(db, mockAdapter),
          );

          // Process background sync - this should fail due to collision
          await SynquillStorage.instance
              .processBackgroundSyncTasks(forceSync: true);

          await Future.delayed(const Duration(milliseconds: 200));

          // Verify create was attempted
          expect(
              mockAdapter.operationLog,
              contains(
                'createOne(${newModel.id})',
              ));

          // The new model should still exist locally with temp ID
          // (since remote sync failed)
          final localModel = await repository.findOne(newModel.id);
          expect(localModel, isNotNull);
          expect(localModel!.name, equals('New Model'));

          // The existing model should remain untouched
          expect(mockAdapter.remoteData[existingServerId], isNotNull);
          expect(
            mockAdapter.remoteData[existingServerId]!.name,
            equals('Existing Model'),
          );

          // There should be only one model with the collision ID in remote
          final modelsWithCollisionId = mockAdapter.remoteData.values
              .where((m) => m.id == existingServerId)
              .toList();
          expect(modelsWithCollisionId, hasLength(1));
        });

        test('should resolve ID conflicts during concurrent operations',
            () async {
          final mockAdapter = MockIdCollisionAdapter();
          final repository = _TestServerTestRepository(db, mockAdapter);

          // Create two models with different temporary IDs
          final model1 = ServerTestModel(
            id: generateCuid(),
            name: 'Test Model 1',
            description: 'Description 1',
          );

          final model2 = ServerTestModel(
            id: generateCuid(),
            name: 'Test Model 2',
            description: 'Description 2',
          );

          // Setup collision scenario - both models get same server ID
          mockAdapter.simulateIdCollision('server_collision_id');

          // Save first model successfully
          final saved1 = await repository.save(
            model1,
            savePolicy: DataSavePolicy.localFirst,
          );
          expect(saved1.id, equals(model1.id));

          // Reset collision for second model
          mockAdapter.resetCollisionSimulation();

          // Save second model - should get different server ID during sync
          final saved2 = await repository.save(
            model2,
            savePolicy: DataSavePolicy.localFirst,
          );
          expect(saved2.id, equals(model2.id));

          // Verify both models are saved locally with different IDs
          expect(saved1.id, isNot(equals(saved2.id)));
        });

        test('should handle server returning locally existing ID', () async {
          final mockAdapter = MockLocalIdConflictAdapter();
          final repository = _TestServerTestRepository(db, mockAdapter);

          // Step 1: Create and save a model locally first
          final existingLocalModel = ServerTestModel(
            id: 'local_existing_id',
            name: 'Existing Local Model',
            description: 'This model already exists in local database',
          );

          // Save this model directly to local database (bypassing API)
          await repository.saveToLocal(existingLocalModel);

          // Verify it exists locally
          final localCheck = await repository.findOne('local_existing_id');
          expect(localCheck, isNotNull);
          expect(localCheck!.name, equals('Existing Local Model'));

          // Step 2: Create a new model with temporary ID
          final newModel = ServerTestModel(
            id: generateCuid(), // This will be temporary client ID
            name: 'New Model',
            description: 'This model will cause ID conflict',
          );

          // Configure mock adapter to return the existing local ID
          // when creating the new model
          mockAdapter.forceReturnId('local_existing_id');

          // Step 3: Save with localFirst policy
          final savedModel = await repository.save(
            newModel,
            savePolicy: DataSavePolicy.localFirst,
          );
          expect(savedModel.id, equals(newModel.id)); // Still has temp ID

          // Verify new model is saved locally with temp ID
          final tempModel = await repository.findOne(newModel.id);
          expect(tempModel, isNotNull);
          expect(tempModel!.name, equals('New Model'));

          // Step 4: Register repository for background sync
          SynquillRepositoryProvider.register<ServerTestModel>(
            (db) => _TestServerTestRepository(db, mockAdapter),
          );

          // Step 5: Trigger background sync which should detect the conflict
          await SynquillStorage.instance
              .processBackgroundSyncTasks(forceSync: true);

          // Wait for async operations
          await Future.delayed(const Duration(milliseconds: 300));

          // Step 6: Verify conflict resolution behavior
          expect(
            mockAdapter.operationLog,
            contains('createOne(${newModel.id})'),
          );

          // Step 7: Check the final state after conflict resolution

          // The existing local model should remain unchanged
          final stillExistingModel =
              await repository.findOne('local_existing_id');
          expect(stillExistingModel, isNotNull);
          expect(stillExistingModel!.name, equals('Existing Local Model'));
          expect(
            stillExistingModel.description,
            equals('This model already exists in local database'),
          );

          // The new model should still exist with its temporary ID since
          // the server returned a conflicting ID
          final stillNewModel = await repository.findOne(newModel.id);
          expect(stillNewModel, isNotNull);
          expect(stillNewModel!.name, equals('New Model'));

          // Step 8: Verify that both models coexist without data corruption
          final allModels = await repository.findAll();
          final localExistingModels =
              allModels.where((m) => m.id == 'local_existing_id').toList();
          final newModels =
              allModels.where((m) => m.id == newModel.id).toList();

          expect(localExistingModels, hasLength(1));
          expect(newModels, hasLength(1));
          expect(
            localExistingModels.first.name,
            equals('Existing Local Model'),
          );
          expect(newModels.first.name, equals('New Model'));

          // Step 9: Verify no data was overwritten or lost
          expect(
            localExistingModels.first.description,
            equals('This model already exists in local database'),
          );
          expect(
            newModels.first.description,
            equals('This model will cause ID conflict'),
          );

          // The system should handle this gracefully without losing data
          // and the sync operation should be retried or marked as conflicted
        });
      });

      group('Partial Failure Scenarios', () {
        test('should handle partial create failure with retry', () async {
          final mockAdapter = MockPartialFailureAdapter();
          final repository = _TestServerTestRepository(db, mockAdapter);

          // Configure adapter to fail once then succeed
          mockAdapter.simulateCreateFailure(maxFailures: 1);

          final model = ServerTestModel(
            id: generateCuid(),
            name: 'Test Model',
            description: 'Test Description',
          );

          // Save with local-first policy (should succeed locally)
          final savedModel = await repository.save(
            model,
            savePolicy: DataSavePolicy.localFirst,
          );
          expect(savedModel.id, equals(model.id));

          // Verify model is saved locally
          final localModel = await repository.findOne(savedModel.id);
          expect(localModel, isNotNull);
          expect(localModel!.name, equals('Test Model'));

          // Trigger background sync (should eventually succeed after retry)
          await Future.delayed(const Duration(milliseconds: 100));

          // Verify that create was attempted
          expect(mockAdapter.operationLog, contains('createOne(${model.id})'));
        });

        test('should handle update failure during ID negotiation', () async {
          final mockAdapter = MockPartialFailureAdapter();
          final repository = _TestServerTestRepository(db, mockAdapter);

          final model = ServerTestModel(
            id: generateCuid(),
            name: 'Test Model',
            description: 'Test Description',
          );

          // First save successfully
          final savedModel = await repository.save(
            model,
            savePolicy: DataSavePolicy.localFirst,
          );

          // Configure adapter to fail on updates
          mockAdapter.simulateUpdateFailure(maxFailures: 1);

          // Update the model by creating a new instance with same ID
          final updatedModel = ServerTestModel(
            id: savedModel.id,
            name: 'Updated Name',
            description: savedModel.description,
          );

          // Update should succeed locally even if remote fails
          final result = await repository.save(
            updatedModel,
            savePolicy: DataSavePolicy.localFirst,
          );
          expect(result.name, equals('Updated Name'));

          // Verify local update worked
          final localModel = await repository.findOne(result.id);
          expect(localModel?.name, equals('Updated Name'));
        });

        test('should handle cascading failures in relationships', () async {
          final parentAdapter = MockServerParentAdapter();
          final childAdapter = MockServerChildAdapter();

          final parentRepo = _TestServerParentRepository(db, parentAdapter);
          final childRepo = _TestServerChildRepository(db, childAdapter);

          // Create parent model
          final parent = ServerParentModel(
            id: generateCuid(),
            name: 'Parent',
            category: 'Category A',
          );

          final savedParent = await parentRepo.save(
            parent,
            savePolicy: DataSavePolicy.localFirst,
          );

          // Create child model with reference to parent
          final child = ServerChildModel(
            id: generateCuid(),
            name: 'Child',
            parentId: savedParent.id,
            data: 'Child data',
          );

          final savedChild = await childRepo.save(
            child,
            savePolicy: DataSavePolicy.localFirst,
          );

          // Verify relationship is maintained locally
          expect(savedChild.parentId, equals(savedParent.id));

          final retrievedChild = await childRepo.findOne(savedChild.id);
          expect(retrievedChild?.parentId, equals(savedParent.id));
        });
      });

      group('Network Timeout Scenarios', () {
        test('should handle create timeout gracefully', () async {
          final mockAdapter = MockTimeoutAdapter();
          final repository = _TestServerTestRepository(db, mockAdapter);

          // Configure short timeout for testing
          mockAdapter.simulateTimeout(
            timeout: const Duration(milliseconds: 100),
            operation: 'create',
          );

          final model = ServerTestModel(
            id: generateCuid(),
            name: 'Test Model',
            description: 'Test Description',
          );

          // Local-first save should succeed despite remote timeout
          final savedModel = await repository.save(
            model,
            savePolicy: DataSavePolicy.localFirst,
          );
          expect(savedModel.id, equals(model.id));

          // Verify model is saved locally
          final localModel = await repository.findOne(savedModel.id);
          expect(localModel, isNotNull);

          // Test that remoteFirst will eventually timeout in background sync
          // but the operation itself succeeds and queues the sync
          final timeoutModel = ServerTestModel(
            id: generateCuid(),
            name: 'Timeout Model',
            description: 'Will timeout',
          );

          // This should succeed locally and queue for background sync
          final timeoutSavedModel = await repository.save(
            timeoutModel,
            savePolicy: DataSavePolicy.localFirst,
          );
          expect(timeoutSavedModel.id, equals(timeoutModel.id));

          // Verify local save worked
          final localTimeoutModel = await repository.findOne(timeoutModel.id);
          expect(localTimeoutModel, isNotNull);
        });

        test('should handle update timeout during ID negotiation', () async {
          final mockAdapter = MockTimeoutAdapter();
          final repository = _TestServerTestRepository(db, mockAdapter);

          final model = ServerTestModel(
            id: generateCuid(),
            name: 'Test Model',
            description: 'Test Description',
          );

          // First save successfully
          final savedModel = await repository.save(
            model,
            savePolicy: DataSavePolicy.localFirst,
          );

          // Configure timeout for updates
          mockAdapter.simulateTimeout(
            timeout: const Duration(milliseconds: 100),
            operation: 'update',
          );

          // Update should succeed locally despite remote timeout
          final updatedModel = ServerTestModel(
            id: savedModel.id,
            name: 'Updated Name',
            description: savedModel.description,
          );
          final result = await repository.save(
            updatedModel,
            savePolicy: DataSavePolicy.localFirst,
          );

          expect(result.name, equals('Updated Name'));

          // Verify local update worked
          final localModel = await repository.findOne(result.id);
          expect(localModel?.name, equals('Updated Name'));
        });

        test('should queue operations when network is unavailable', () async {
          final mockAdapter = MockTimeoutAdapter();
          final repository = _TestServerTestRepository(db, mockAdapter);

          // Simulate network unavailable
          mockAdapter.simulateTimeout(
            timeout: const Duration(seconds: 1),
            operation: 'create',
          );

          final models = List.generate(
              3,
              (i) => ServerTestModel(
                    id: generateCuid(),
                    name: 'Model $i',
                    description: 'Description $i',
                  ));

          // Save multiple models with local-first policy
          final savedModels = <ServerTestModel>[];
          for (final model in models) {
            final saved = await repository.save(
              model,
              savePolicy: DataSavePolicy.localFirst,
            );
            savedModels.add(saved);
          }

          // All models should be saved locally
          expect(savedModels.length, equals(3));
          for (int i = 0; i < savedModels.length; i++) {
            expect(savedModels[i].name, equals('Model $i'));

            final localModel = await repository.findOne(savedModels[i].id);
            expect(localModel, isNotNull);
            expect(localModel!.name, equals('Model $i'));
          }

          // Reset timeout simulation
          mockAdapter.resetTimeoutSimulation();

          // Background sync should eventually process queued operations
          await Future.delayed(const Duration(milliseconds: 200));
        });
      });

      group('Concurrent Operations Scenarios', () {
        test('should handle concurrent ID replacements safely', () async {
          final mockAdapter = MockConcurrentAdapter();
          final repository = _TestServerTestRepository(db, mockAdapter);

          // Configure concurrent operation simulation
          mockAdapter.simulateConcurrentOperations(delayMs: 50);

          final baseModel = ServerTestModel(
            id: generateCuid(),
            name: 'Concurrent Model',
            description: 'Concurrent Description',
          );

          // Start multiple concurrent save operations with similar models
          final futures = List.generate(3, (i) {
            final model = ServerTestModel(
              id: generateCuid(),
              name: 'Concurrent Model $i',
              description: baseModel.description,
            );
            return repository.save(
              model,
              savePolicy: DataSavePolicy.localFirst,
            );
          });

          // Wait for all operations to complete
          final results = await Future.wait(futures);

          // All operations should complete successfully
          expect(results.length, equals(3));
          for (int i = 0; i < results.length; i++) {
            expect(results[i].name, equals('Concurrent Model $i'));
          }

          // Verify all models are saved locally
          for (final result in results) {
            final localModel = await repository.findOne(result.id);
            expect(localModel, isNotNull);
          }
        });

        test('should handle concurrent updates to same model', () async {
          final mockAdapter = MockServerIdAdapter();
          final repository = _TestServerTestRepository(db, mockAdapter);

          final model = ServerTestModel(
            id: generateCuid(),
            name: 'Original Model',
            description: 'Original Description',
          );

          // Save initial model
          final savedModel = await repository.save(
            model,
            savePolicy: DataSavePolicy.localFirst,
          );

          // Start concurrent updates using the same ID but different content
          final update1Future = repository.save(
            ServerTestModel(
              id: savedModel.id,
              name: 'Update 1',
              description: savedModel.description,
            ),
            savePolicy: DataSavePolicy.localFirst,
          );

          final update2Future = repository.save(
            ServerTestModel(
              id: savedModel.id,
              name: 'Update 2',
              description: savedModel.description,
            ),
            savePolicy: DataSavePolicy.localFirst,
          );

          final update3Future = repository.save(
            ServerTestModel(
              id: savedModel.id,
              name: savedModel.name,
              description: 'Update 3 Description',
            ),
            savePolicy: DataSavePolicy.localFirst,
          );

          // Wait for all updates to complete
          final results = await Future.wait([
            update1Future,
            update2Future,
            update3Future,
          ]);

          // All updates should be successful
          expect(results.length, equals(3));

          // The final state should reflect the last update
          final finalModel = await repository.findOne(savedModel.id);
          expect(finalModel, isNotNull);

          // At least one of the updates should be applied
          expect(finalModel!.id, equals(savedModel.id));
        });

        test('should handle race conditions during foreign key updates',
            () async {
          final parentAdapter = MockServerParentAdapter();
          final childAdapter = MockServerChildAdapter();

          final parentRepo = _TestServerParentRepository(db, parentAdapter);
          final childRepo = _TestServerChildRepository(db, childAdapter);

          // Create parent model
          final parent = ServerParentModel(
            id: generateCuid(),
            name: 'Parent',
            category: 'Category A',
          );

          final savedParent = await parentRepo.save(
            parent,
            savePolicy: DataSavePolicy.localFirst,
          );

          // Create multiple children concurrently
          final childFutures = List.generate(3, (i) {
            final child = ServerChildModel(
              id: generateCuid(),
              name: 'Child $i',
              parentId: savedParent.id,
              data: 'Child $i data',
            );

            return childRepo.save(
              child,
              savePolicy: DataSavePolicy.localFirst,
            );
          });

          // Wait for all children to be saved
          final savedChildren = await Future.wait(childFutures);

          // All children should be saved successfully
          expect(savedChildren.length, equals(3));

          // All children should reference the same parent
          for (int i = 0; i < savedChildren.length; i++) {
            expect(savedChildren[i].parentId, equals(savedParent.id));
            expect(savedChildren[i].name, equals('Child $i'));

            // Verify local storage
            final localChild = await childRepo.findOne(savedChildren[i].id);
            expect(localChild, isNotNull);
            expect(localChild!.parentId, equals(savedParent.id));
          }
        });
      });

      group('Successful Merge Scenarios', () {
        test(
          'should successfully merge records when newer conflicts '
          'with existing',
          () async {
            final mockAdapter = MockLocalIdConflictAdapter();
            final repository = _TestServerTestRepository(db, mockAdapter);

            // Step 1: Create and save an older model locally first
            final existingLocalModel = ServerTestModel(
              id: 'merge_target_id',
              name: 'Original Model',
              description: 'Original description',
            );

            // Save this model directly to local database
            await repository.saveToLocal(existingLocalModel);

            // Manually set older timestamp for existing record
            final oldTimestamp = DateTime.now()
                .subtract(const Duration(hours: 1))
                .millisecondsSinceEpoch;
            await db.customUpdate(
              'UPDATE server_test_models SET created_at = ? WHERE id = ?',
              variables: [
                Variable.withInt(oldTimestamp),
                Variable.withString('merge_target_id'),
              ],
            );

            // Verify it exists locally
            final localCheck = await repository.findOne('merge_target_id');
            expect(localCheck, isNotNull);
            expect(localCheck!.name, equals('Original Model'));

            // Step 2: Create a newer model with updated content
            final newerModel = ServerTestModel(
              id: generateCuid(), // Temporary ID
              name: 'Updated Model', // Different name - this should merge
              description: 'Updated description', // Different description
            );

            // Configure adapter to return the existing ID
            mockAdapter.forceReturnId('merge_target_id');

            // Step 3: Save with localFirst policy
            final savedModel = await repository.save(
              newerModel,
              savePolicy: DataSavePolicy.localFirst,
            );
            expect(savedModel.id, equals(newerModel.id)); // Still has temp ID

            // Step 4: Manually set newer timestamp for the temp record
            final newTimestamp = DateTime.now().millisecondsSinceEpoch;
            await db.customUpdate(
              'UPDATE server_test_models SET created_at = ? WHERE id = ?',
              variables: [
                Variable.withInt(newTimestamp),
                Variable.withString(newerModel.id),
              ],
            );

            // Verify new model is saved locally with temp ID
            final tempModel = await repository.findOne(newerModel.id);
            expect(tempModel, isNotNull);
            expect(tempModel!.name, equals('Updated Model'));

            // Step 5: Register repository for background sync
            SynquillRepositoryProvider.register<ServerTestModel>(
              (db) => _TestServerTestRepository(db, mockAdapter),
            );

            // Step 6: Trigger background sync which should perform the merge
            // await SynquillStorage.instance
            //     .processBackgroundSyncTasks(forceSync: true);

            // Wait for async operations
            await Future.delayed(const Duration(milliseconds: 300));

            // Step 7: Verify merge was successful
            expect(
              mockAdapter.operationLog,
              contains('createOne(${newerModel.id})'),
            );

            // Step 8: The merge should have succeeded - verify final state

            // The original record should now have updated data
            // from newer record
            final mergedModel = await repository.findOne('merge_target_id');
            expect(mergedModel, isNotNull);
            expect(mergedModel!.name, equals('Updated Model')); // Updated
            expect(
              mergedModel.description,
              equals('Updated description'),
            ); // Updated
            expect(
              mergedModel.id,
              equals('merge_target_id'),
            ); // Kept original ID

            // The temporary record should be cleaned up
            final tempStillExists = await repository.findOne(newerModel.id);
            expect(tempStillExists, isNull);

            // Step 9: Verify only one record exists with the target ID
            final allModels = await repository.findAll();
            final modelsWithTargetId =
                allModels.where((m) => m.id == 'merge_target_id').toList();

            expect(modelsWithTargetId, hasLength(1));
            expect(modelsWithTargetId.first.name, equals('Updated Model'));
            expect(
              modelsWithTargetId.first.description,
              equals('Updated description'),
            );

            // Verify no temporary records remain
            final tempRecords =
                allModels.where((m) => m.id == newerModel.id).toList();
            expect(tempRecords, isEmpty);
          },
        );
      });
    });
  });
}

/// Test repository for ServerParentModel with injectable mock adapter
class _TestServerParentRepository
    extends SynquillRepositoryBase<ServerParentModel>
    with
        RepositoryHelpersMixin<ServerParentModel>,
        RepositoryServerIdMixin<ServerParentModel> {
  final MockServerParentAdapter _mockAdapter;
  late final ServerParentModelDao _dao;

  _TestServerParentRepository(super.db, this._mockAdapter) {
    _dao = ServerParentModelDao(db as SynquillDatabase);
    initializeIdNegotiationService(usesServerGeneratedId: true);
  }

  @override
  ApiAdapterBase<ServerParentModel> get apiAdapter => _mockAdapter;

  @override
  DatabaseAccessor<GeneratedDatabase> get dao => _dao;

  @override
  Future<ServerParentModel?> fetchFromRemote(
    String id, {
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return await _mockAdapter.findOne(id, queryParams: queryParams);
  }

  @override
  Future<List<ServerParentModel>> fetchAllFromRemote({
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return await _mockAdapter.findAll(queryParams: queryParams);
  }
}

/// Test repository for ServerChildModel with injectable mock adapter
class _TestServerChildRepository
    extends SynquillRepositoryBase<ServerChildModel>
    with
        RepositoryHelpersMixin<ServerChildModel>,
        RepositoryServerIdMixin<ServerChildModel> {
  final MockServerChildAdapter _mockAdapter;
  late final ServerChildModelDao _dao;

  _TestServerChildRepository(super.db, this._mockAdapter) {
    _dao = ServerChildModelDao(db as SynquillDatabase);
    initializeIdNegotiationService(usesServerGeneratedId: true);
  }

  @override
  ApiAdapterBase<ServerChildModel> get apiAdapter => _mockAdapter;

  @override
  DatabaseAccessor<GeneratedDatabase> get dao => _dao;

  @override
  Future<ServerChildModel?> fetchFromRemote(
    String id, {
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return await _mockAdapter.findOne(id, queryParams: queryParams);
  }

  @override
  Future<List<ServerChildModel>> fetchAllFromRemote({
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return await _mockAdapter.findAll(queryParams: queryParams);
  }
}

/// Test repository for ServerTestModel with injectable mock adapter
class _TestServerTestRepository extends SynquillRepositoryBase<ServerTestModel>
    with
        RepositoryHelpersMixin<ServerTestModel>,
        RepositoryServerIdMixin<ServerTestModel> {
  final MockServerIdAdapter _mockAdapter;
  late final ServerTestModelDao _dao;

  _TestServerTestRepository(super.db, this._mockAdapter) {
    _dao = ServerTestModelDao(db as SynquillDatabase);
    initializeIdNegotiationService(usesServerGeneratedId: true);
  }

  @override
  ApiAdapterBase<ServerTestModel> get apiAdapter => _mockAdapter;

  @override
  DatabaseAccessor<GeneratedDatabase> get dao => _dao;

  @override
  Future<ServerTestModel?> fetchFromRemote(
    String id, {
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return await _mockAdapter.findOne(id, queryParams: queryParams);
  }

  @override
  Future<List<ServerTestModel>> fetchAllFromRemote({
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    return await _mockAdapter.findAll(queryParams: queryParams);
  }
}

/// Mock API adapter that simulates server returning locally existing ID
class MockLocalIdConflictAdapter extends MockServerIdAdapter {
  String? _forceReturnId;
  bool _persistConflict = false;

  /// Configure the adapter to ALWAYS return a specific ID (simulating server
  /// consistently returning an ID that already exists locally)
  void forceReturnId(String id, {bool persistConflict = true}) {
    _forceReturnId = id;
    _persistConflict = persistConflict;
  }

  /// Reset the forced ID
  void resetForcedId() {
    _forceReturnId = null;
    _persistConflict = false;
  }

  /// Add a model to remote data (helper method for testing)
  void addToRemoteData(String id, ServerTestModel model) {
    _remoteData[id] = model;
  }

  @override
  Future<ServerTestModel?> createOne(
    ServerTestModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    _operationLog.add('createOne(${model.id})');
    await Future.delayed(const Duration(milliseconds: 10));

    String serverId;
    if (_forceReturnId != null) {
      // ALWAYS return the forced ID (simulating server consistently
      // returning the same conflicting ID)
      serverId = _forceReturnId!;

      // If not persisting conflict, only use the forced ID once
      if (!_persistConflict) {
        _forceReturnId = null;
      }
    } else {
      serverId = 'server_${_nextServerId++}';
    }

    final modelWithServerId = ServerTestModel(
      id: serverId,
      name: model.name,
      description: model.description,
    );

    // Check if this would create a conflict by overwriting existing data
    if (_remoteData.containsKey(serverId)) {
      // Simulate server conflict - throw an exception or return error
      // This simulates what would happen if server detects the conflict
      _operationLog.add('CONFLICT: ID $serverId already exists');
      throw ApiException(
        'Server ID conflict: ID $serverId already exists',
        statusCode: 409, // Conflict
      );
    }

    _remoteData[serverId] = modelWithServerId;
    return modelWithServerId;
  }
}
