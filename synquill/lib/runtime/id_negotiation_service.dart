part of synquill;

/// Status of ID negotiation process for server-generated IDs.
enum IdNegotiationStatus {
  /// Negotiation is pending - waiting for server response
  pending,

  /// Negotiation is in progress - awaiting server assignment
  in_progress,

  /// Negotiation encountered a conflict - server and client IDs differ
  conflict,

  /// Negotiation completed successfully - server ID assigned
  completed,

  /// Negotiation failed - will retry or use fallback
  failed,

  /// Negotiation cancelled - operation aborted
  cancelled,
}

/// Metadata for tracking server ID negotiation process
class ServerIdMetadata {
  /// Temporary client-generated ID used before server assigns real ID
  final String temporaryClientId;

  /// Current negotiation status
  final IdNegotiationStatus status;

  /// When the negotiation was initiated
  final DateTime initiatedAt;

  /// Number of retry attempts
  final int retryCount;

  /// Creates a [ServerIdMetadata] instance to track the server ID
  /// negotiation process.
  const ServerIdMetadata({
    required this.temporaryClientId,
    required this.status,
    required this.initiatedAt,
    this.retryCount = 0,
  });

  /// Create a copy with updated fields
  ServerIdMetadata copyWith({
    String? temporaryClientId,
    IdNegotiationStatus? status,
    DateTime? initiatedAt,
    int? retryCount,
  }) {
    return ServerIdMetadata(
      temporaryClientId: temporaryClientId ?? this.temporaryClientId,
      status: status ?? this.status,
      initiatedAt: initiatedAt ?? this.initiatedAt,
      retryCount: retryCount ?? this.retryCount,
    );
  }
}

/// Service for managing server ID negotiation without modifying user models
class IdNegotiationService<T extends SynquillDataModel<T>> {
  /// Metadata for models undergoing ID negotiation
  final Map<String, ServerIdMetadata> _serverIdMetadata = {};

  /// Logger for this service
  static final Logger _log = Logger('IdNegotiationService');

  /// Whether this model type uses server-generated IDs
  final bool usesServerGeneratedId;

  /// Constructor
  IdNegotiationService({required this.usesServerGeneratedId});

  /// Check if a model uses server-generated IDs
  bool modelUsesServerGeneratedId(T model) {
    return usesServerGeneratedId;
  }

  /// Check if a model has a temporary ID (awaiting server assignment)
  bool hasTemporaryId(T model) {
    if (!usesServerGeneratedId) {
      return false;
    }
    final metadata = _serverIdMetadata[model.id];

    final result =
        metadata != null && metadata.status == IdNegotiationStatus.pending;

    return result;
  }

  /// Get the temporary client ID for a model (if any)
  String? getTemporaryClientId(T model) {
    if (!usesServerGeneratedId) return null;
    return _serverIdMetadata[model.id]?.temporaryClientId;
  }

  /// Mark a model as having a temporary ID before server assignment
  void markAsTemporary(T model, String temporaryClientId) {
    if (!usesServerGeneratedId) return;

    _serverIdMetadata[model.id] = ServerIdMetadata(
      temporaryClientId: temporaryClientId,
      status: IdNegotiationStatus.pending,
      initiatedAt: DateTime.now(),
    );

    _log.fine('Marked model ${model.id} as temporary with client ID: '
        '$temporaryClientId');
  }

  /// Create a new model instance with a different ID
  /// This is used during ID negotiation when server assigns a different ID
  T replaceIdEverywhere(T model, String newId) {
    if (!usesServerGeneratedId) {
      throw StateError('Cannot replace ID for client-generated ID model');
    }

    // Get the temporary client ID before creating new instance
    final tempClientId = getTemporaryClientId(model);

    // Create new instance with server-assigned ID
    final json = model.toJson();
    json['id'] = newId;
    final newModel = model.fromJson(json);

    // Transfer metadata to new ID if we had temporary metadata
    // Mark the negotiation as completed, so hasTemporaryId returns false
    if (tempClientId != null && _serverIdMetadata.containsKey(model.id)) {
      final metadata = _serverIdMetadata.remove(model.id)!;
      _serverIdMetadata[newId] = metadata.copyWith(
        status: IdNegotiationStatus.completed,
      );

      _log.info('Replaced ID everywhere: ${model.id} -> $newId '
          '(temp: $tempClientId)');
    }

    return newModel;
  }

  /// Update negotiation status for a model
  void updateNegotiationStatus(T model, IdNegotiationStatus status) {
    if (!usesServerGeneratedId) return;

    final metadata = _serverIdMetadata[model.id];
    if (metadata != null) {
      _serverIdMetadata[model.id] = metadata.copyWith(status: status);
    } else {
      // Create new metadata if it doesn't exist
      _serverIdMetadata[model.id] = ServerIdMetadata(
        temporaryClientId: model.id,
        status: status,
        initiatedAt: DateTime.now(),
      );
    }
    _log.fine('Updated negotiation status for ${model.id}: $status');
  }

  /// Clean up completed or failed negotiations
  void cleanupNegotiation(T model) {
    if (!usesServerGeneratedId) return;

    final removed = _serverIdMetadata.remove(model.id);
    if (removed != null) {
      _log.fine('Cleaned up negotiation for ${model.id}');
    }
  }

  /// Get all models currently undergoing ID negotiation
  Map<String, ServerIdMetadata> getPendingNegotiations() {
    return Map.unmodifiable(_serverIdMetadata);
  }

  /// Check if there are any pending negotiations
  bool hasPendingNegotiations() {
    return _serverIdMetadata.values
        .any((metadata) => metadata.status == IdNegotiationStatus.pending);
  }
}
