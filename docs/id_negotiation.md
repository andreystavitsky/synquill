# ID Negotiation: Supporting Server-Generated IDs

## Executive Summary

Currently, Synquill exclusively uses client-generated CUIDs for all model instances. This document analyzes the existing architecture and proposes a comprehensive solution to support APIs that generate IDs server-side, while maintaining backward compatibility and preserving the existing offline-first synchronization capabilities.

## Current Architecture Analysis

### ID Generation System

**Current Implementation:**
- All models extend `SynquillDataModel<T>` with mandatory `id` field
- IDs are generated client-side using `generateCuid()` function
- Constructor pattern: `id = id ?? generateCuid()`
- IDs are immutable once assigned

**Key Components:**
```dart
// Base model enforces CUID usage
abstract class SynquillDataModel<T> {
  String get id; // Required, immutable
}

// Typical model constructor
Project({String? id, ...}) : id = id ?? generateCuid();
```

### Save Operations Flow

**Current Save Flow:**
1. `isExistingItem()` check determines CREATE vs UPDATE operation
2. Local save executes immediately 
3. Sync queue entry created for background API sync
4. API operation uses model's existing ID

**Critical Insight:** The system assumes ID stability throughout the entire save and sync pipeline.

### Sync Queue Architecture

**Current Behavior:**
- Queue entries use model ID as primary identifier
- Operations are: `create`, `update`, `delete`
- Retry mechanism relies on consistent ID mapping
- Background sync executes API calls with existing model IDs

### Relationship Management

**Foreign Key Dependencies:**
- Models reference each other via ID fields (e.g., `userId`, `categoryId`)
- Dependency resolver ensures parent models sync before children
- Relations use string IDs for cross-references
- Cascade operations depend on stable ID references

## Challenge Analysis

### Core Problems with Server-Generated IDs

1. **Temporal ID Mismatch**
   - Client needs immediate ID for local operations
   - Server provides "real" ID only after creation
   - Local relations may reference temporary IDs

2. **Sync Queue Complexity**
   - Queue entries indexed by model ID
   - ID changes require queue update logic
   - Retry scenarios become more complex

3. **Relationship Integrity**
   - Foreign key references may use temporary IDs
   - Related model sync must handle ID transitions
   - Cascade operations need ID mapping

4. **Offline Scenarios**
   - Models created offline cannot get server IDs immediately
   - Relations created offline use temporary IDs
   - Bulk sync requires careful ID negotiation

## Proposed Solution: Hybrid ID System

### Architecture Overview

**ID Replacement Strategy:**
- **Temporary Client ID:** Generated immediately for offline operations, used until server sync
- **Permanent Server ID:** Received from server after successful creation, replaces client ID everywhere
- **Single Active ID:** User always sees ONE consistent ID across local storage, API, and relationships

**Critical Principle:** The user sees the SAME ID that exists in local storage and the SAME ID that exists in the API. When server assigns an ID, it replaces the temporary client ID everywhere - in the model, database, and all relationship references.

### New Annotation Options

```dart
enum IdGenerationStrategy {
  /// Client-generated IDs (default, backward compatible)
  client,
  /// Server-generated IDs (replaces temporary client IDs after sync)
  server,
}

// Extended SynquillRepository annotation
@SynquillRepository(
  idGeneration: IdGenerationStrategy.server, // NEW parameter
  adapters: [MyApiAdapter],
  // ... existing parameters
)
```

### Implementation Strategy

#### Phase 1: Enhanced Model Base Class

```dart
abstract class SynquillDataModel<T> {
  // The single ID visible to user (same as in database and API)
  String get id;
  
  // INTERNAL fields for library use - HIDDEN from user
  // These getters will be overridden in generated mixins
  String? get $temporaryClientId => null;
  bool get $usesServerGeneratedId => false;
  bool get $hasTemporaryId => false;
  
  // Internal methods for library use
  T $replaceIdEverywhere(String newId);
}
```

#### Phase 2: Repository Annotation System

```dart
@SynquillRepository(
  idGeneration: IdGenerationStrategy.server, // NEW - configuration in annotation
  adapters: [MyApiAdapter],
)
class ServerModel extends SynquillDataModel<ServerModel> {
  @override
  final String id;
  final String name;
  
  // User does NOT create additional ID fields!
  // They will be added automatically by code generator
  
  ServerModel({
    String? id,
    required this.name,
  }) : id = id ?? generateCuid(); // User writes as usual
  
  // When server assigns ID, this same 'id' field will be updated
  // User always sees consistent ID across local storage and API
}
```

#### Phase 3: Enhanced Sync Queue

**Enhanced Sync Queue (Updated Drift Definition):**
```dart
class EnhancedSyncQueueDao extends SyncQueueDao {
  // Insert with temporary ID tracking
  Future<int> insertItem({
    required String modelId,
    String? temporaryClientId, // NEW: Track temporary client ID for replacement
    String idNegotiationStatus = 'complete', // NEW: Track negotiation status
    // ... existing parameters
  });
  
  // Update after server ID received - must update all references
  Future<void> replaceIdEverywhere({
    required int taskId,
    required String oldId,
    required String newId,
    required String modelType,
  });
}
```

#### Phase 4: ID Negotiation Process

**Save Operation Enhancement:**
```dart
class RepositorySaveOperations<T> {
  Future<T> save(T item, {
    DataSavePolicy savePolicy = DataSavePolicy.localFirst,
    // ... existing parameters
  }) async {
    // Automatic check for server ID negotiation need
    if (item.$usesServerGeneratedId && item.$hasTemporaryId) {
      return await _handleServerIdNegotiation(item, savePolicy);
    }
    return await _handleStandardSave(item, savePolicy);
  }
  
  Future<T> _handleServerIdNegotiation(T item, DataSavePolicy policy) async {
    switch (policy) {
      case DataSavePolicy.localFirst:
        // Save locally with temporary ID, sync in background
        final savedItem = await _saveWithTemporaryId(item);
        await _enqueueIdReplacement(savedItem);
        return savedItem;
        
      case DataSavePolicy.remoteFirst:
        // Create on server first to get permanent ID
        final serverItem = await _createOnServerForId(item);
        await _saveWithPermanentId(serverItem);
        return serverItem;
    }
  }
}
```

#### Phase 5: Relationship Resolution

**Enhanced Foreign Key Handling:**
```dart
class RelationshipResolver {
  // Resolve foreign keys during model loading
  Future<String?> resolveForeignKey(String foreignKey, String targetType) async {
    // Check if this references a model that had ID replacement
    final currentId = await _getCurrentIdForReference(foreignKey, targetType);
    return currentId ?? foreignKey;
  }
  
  // Update relations after ID replacement (automatic)
  Future<void> updateRelationshipsAfterIdReplacement({
    required String oldId,
    required String newId,
    required String modelType,
  }) async {
    // Find all models that reference the old ID
    final affectedModels = await _findModelsReferencingId(oldId);
    
    // Update each foreign key reference to use the new ID
    for (final model in affectedModels) {
      await _updateForeignKeyReferences(model, oldId, newId);
    }
    
    // Update cascade delete relationships
    await _updateCascadeDeleteReferences(oldId, newId, modelType);
  }
}
```

### Migration Strategy

#### Step 1: Backward Compatibility Layer

```dart
// Existing models continue to work unchanged
@SynquillRepository() // idGeneration defaults to client
class ExistingModel extends SynquillDataModel<ExistingModel> {
  @override
  final String id;
  final String name;
  
  ExistingModel({String? id, required this.name})
    : id = id ?? generateCuid();
  
  // No additional fields required!
  // ID never changes - same behavior as before
}
```

#### Step 2: Opt-in Server ID Models

```dart
// New models can enable server ID generation via annotation
@SynquillRepository(
  idGeneration: IdGenerationStrategy.server, // Only change needed!
)
class NewServerModel extends SynquillDataModel<NewServerModel> {
  @override
  final String id;
  final String name;
  
  NewServerModel({String? id, required this.name})
    : id = id ?? generateCuid();
  
  // Everything else is generated automatically!
  // After server sync, 'id' will be replaced with server ID
}
```

#### Step 3: Mixed Environment Support

```dart
// Some models use client IDs, others use server IDs
@SynquillRepository() // client ID (default)
class User extends SynquillDataModel<User> {
  @override
  final String id;
  final String name;
  
  User({String? id, required this.name})
    : id = id ?? generateCuid();
  // User ID never changes
}

@SynquillRepository(idGeneration: IdGenerationStrategy.server)
class Post extends SynquillDataModel<Post> {
  @override
  final String id;
  final String userId; // References stable client-generated User ID
  final String content;
  
  Post({String? id, required this.userId, required this.content})
    : id = id ?? generateCuid();
  
  // Post ID will be replaced by server ID automatically
  // User always sees the same ID that exists in database and API
}
```

## Technical Implementation Details

### Database Schema Updates


**Enhanced Sync Queue Table:**
```dart
class SyncQueueItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get modelId => text()();
  TextColumn get temporaryClientId => text().nullable()(); // Track temporary ID for replacement
  TextColumn get idNegotiationStatus => text().withDefault(const Constant('complete'))(); // 'pending', 'complete', 'failed'
  // ...existing columns...
}
```


**Generation of repository with ID management:**
```dart
class _$ServerModelRepository extends SynquillRepositoryBase<ServerModel> {
  @override
  Future<ServerModel> save(ServerModel item, {
    DataSavePolicy savePolicy = DataSavePolicy.localFirst,
  }) async {
    // Automatic handling of server IDs
    if (item.$usesServerGeneratedId && item.$hasTemporaryId) {
      return await _handleIdReplacement(item, savePolicy);
    }
    return await super.save(item, savePolicy: savePolicy);
  }
  
  Future<ServerModel> _handleIdReplacement(
    ServerModel item, 
    DataSavePolicy policy,
  ) async {
    switch (policy) {
      case DataSavePolicy.localFirst:
        // Save locally with temporary ID, sync in background
        final savedItem = await _saveLocally(item);
        await _enqueueIdReplacement(savedItem);
        return savedItem;
        
      case DataSavePolicy.remoteFirst:
        // Create on server first to get permanent ID
        final serverItem = await _createOnServerForId(item);
        await _saveWithPermanentId(serverItem);
        return serverItem;
    }
  }
}
```

### Conflict Resolution

**ID Collision Handling:**
```dart
class IdConflictResolver {
  Future<String> resolveIdConflict({
    required String temporaryId,
    required String proposedServerId,
    required String modelType,
  }) async {
    // Check if proposed server ID already exists locally
    if (await _existsLocally(proposedServerId, modelType)) {
      // Handle collision - may need to merge or use alternative ID
      return await _handleIdCollision(temporaryId, proposedServerId, modelType);
    }
    return proposedServerId;
  }
}
```

### Performance Considerations

**Caching Strategy:**
```dart
class IdReplacementCache {
  // Cache temporary-to-permanent ID mappings
  final Map<String, String> _temporaryToPermanentMap = {};
  final Map<String, String> _permanentToTemporaryMap = {};
  
  Future<String?> getPermanentId(String temporaryId) async {
    return _temporaryToPermanentMap[temporaryId] ?? 
           await _loadPermanentIdFromDatabase(temporaryId);
  }
  
  void recordIdReplacement(String temporaryId, String permanentId) {
    _temporaryToPermanentMap[temporaryId] = permanentId;
    _permanentToTemporaryMap[permanentId] = temporaryId;
  }
}
```

## Testing Strategy

### Unit Tests

1. **ID Generation Tests**
   - Temporary ID generation
   - Server ID assignment and replacement
   - ID consistency across operations

2. **Save Operation Tests**
   - Local-first with temporary ID
   - Remote-first with permanent ID
   - ID replacement scenarios

3. **Sync Queue Tests**
   - ID replacement tracking
   - Queue updates after server ID
   - Error recovery scenarios

4. **Relationship Tests**
   - Foreign key updates after ID replacement
   - Cascade operations with new IDs
   - Reference integrity maintenance

### Integration Tests

1. **End-to-End Flow Tests**
   - Complete save-sync-retrieve cycle with ID replacement
   - Offline creation with later ID replacement
   - Relationship integrity preservation after ID changes

2. **Migration Tests**
   - Existing client-ID models (unchanged behavior)
   - New server-ID models (with ID replacement)
   - Mixed environments

3. **Error Scenario Tests**
   - Server ID generation failure
   - Network interruption during ID replacement
   - ID collision resolution
   - Database transaction rollback scenarios

## Migration Path

### Phase 1: Foundation (Backward Compatible)
- Extend `SynquillDataModel` with optional server ID fields
- Update sync queue schema
- Implement basic ID negotiation infrastructure
- All existing functionality remains unchanged

### Phase 2: Opt-in Support
- Add `@IdGeneration` annotation support
- Implement server ID models
- Enhanced API adapters for server ID handling
- Documentation and examples

### Phase 3: Advanced Features
- Relationship resolution enhancements
- Bulk ID negotiation optimization
- Conflict resolution strategies
- Performance optimizations

### Phase 4: Ecosystem Integration
- Code generation updates
- Developer tools enhancement
- Migration utilities
- Best practices documentation

## Benefits

1. **Complete transparency for user**: User continues working with simple `id` field, unaware of internal ID replacement mechanics

2. **Backward Compatibility**: Existing client-generated ID models continue working without changes

3. **Simplicity of use**: Only need to change annotation `@SynquillRepository(idGeneration: IdGenerationStrategy.server)`

4. **ID Consistency**: User always sees the SAME ID that exists in local storage and API

5. **Flexible Integration**: Support for APIs that require server-generated IDs

6. **Offline Resilience**: Models can be created offline and have IDs replaced later

7. **Relationship Integrity**: Foreign key references are automatically updated when IDs change

8. **Performance**: Efficient ID replacement with caching and indexing

9. **Developer Experience**: Clean migration path without changes in user code

## Risks and Mitigation

### Risk: Complexity Increase
**Mitigation**: Phased rollout, comprehensive testing, clear documentation

### Risk: Performance Impact
**Mitigation**: Efficient caching, database indexing, lazy loading

### Risk: Sync Complexity
**Mitigation**: Robust error handling, retry mechanisms, fallback strategies

### Risk: Developer Confusion
**Mitigation**: Clear documentation, migration guides, examples

## Conclusion

The proposed hybrid ID system provides a robust foundation for supporting server-generated IDs while maintaining Synquill's core offline-first principles. The phased implementation approach ensures backward compatibility while enabling new use cases.

The solution addresses all major technical challenges:
- **ID Lifecycle Management**: Clear separation between client and server IDs
- **Sync Queue Evolution**: Enhanced tracking of ID negotiation status
- **Relationship Integrity**: Proper foreign key resolution and updates
- **API Integration**: Flexible adapter patterns for various server behaviors
- **Error Recovery**: Comprehensive fallback and retry mechanisms

This design positions Synquill to support a wider range of API patterns while preserving its fundamental strengths in offline-first data synchronization.

## Important Note: ID Change Event Emission

Whenever a model's ID is changed (for example, when a temporary client ID is replaced with a permanent server ID), the repository **must emit** a `RepositoryChangeType.idChanged` event. This ensures that all listeners and consumers of the repository are properly notified of the ID change, allowing for correct UI updates, cache invalidation, and relationship maintenance. Failing to emit this event may result in stale references or inconsistent application state.

