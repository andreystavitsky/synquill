part of synquill;

/// Global database provider for the synced data storage system
class DatabaseProvider {
  static GeneratedDatabase? _instance;

  /// Sets the global database instance
  static void setInstance(GeneratedDatabase database) {
    _instance = database;
  }

  /// Gets the global database instance
  static GeneratedDatabase get instance {
    if (_instance == null) {
      throw StateError(
        'Database not initialized. Call DatabaseProvider.setInstance() or '
        'initializeSynquillStorage() first.',
      );
    }
    return _instance!;
  }

  /// Gets the global database instance without throwing
  static GeneratedDatabase? get instanceOrNull => _instance;

  /// Clears the database instance (primarily for testing)
  static void reset() {
    _instance = null;
  }
}
