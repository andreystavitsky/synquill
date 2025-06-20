part of synquill;

/// Mixin providing server ID negotiation capabilities to repositories.
///
/// This mixin adds functionality for managing server-generated IDs without
/// modifying user models directly. It uses an internal IdNegotiationService
/// to track temporary client IDs and handle ID replacement when the server
/// assigns different IDs.
mixin RepositoryServerIdMixin<T extends SynquillDataModel<T>>
    on RepositoryLocalOperations<T> {
  /// Internal service for managing ID negotiation
  late final IdNegotiationService<T> _idNegotiationService;

  /// Initialize the ID negotiation service
  /// This should be called in the repository constructor
  @protected
  void initializeIdNegotiationService({required bool usesServerGeneratedId}) {
    _idNegotiationService = IdNegotiationService<T>(
      usesServerGeneratedId: usesServerGeneratedId,
    );
  }

  /// Check if a model uses server-generated IDs
  bool modelUsesServerGeneratedId(T model) {
    return _idNegotiationService.modelUsesServerGeneratedId(model);
  }

  /// Check if a model has a temporary ID (awaiting server assignment)
  bool hasTemporaryId(T model) {
    return _idNegotiationService.hasTemporaryId(model);
  }

  /// Get the temporary client ID for a model (if any)
  String? getTemporaryClientId(T model) {
    return _idNegotiationService.getTemporaryClientId(model);
  }

  /// Mark a model as having a temporary ID before server assignment
  void markAsTemporary(T model, String temporaryClientId) {
    _idNegotiationService.markAsTemporary(model, temporaryClientId);
  }

  /// Create a new model instance with a different ID
  /// This is used during ID negotiation when server assigns a different ID
  T replaceIdEverywhere(T model, String newId) {
    return _idNegotiationService.replaceIdEverywhere(model, newId);
  }

  /// Update negotiation status for a model
  void updateNegotiationStatus(T model, IdNegotiationStatus status) {
    _idNegotiationService.updateNegotiationStatus(model, status);
  }

  /// Clean up completed or failed negotiations
  void cleanupNegotiation(T model) {
    _idNegotiationService.cleanupNegotiation(model);
  }

  /// Get all models currently undergoing ID negotiation
  Map<String, ServerIdMetadata> getPendingNegotiations() {
    return _idNegotiationService.getPendingNegotiations();
  }

  /// Check if there are any pending negotiations
  bool hasPendingNegotiations() {
    return _idNegotiationService.hasPendingNegotiations();
  }
}
