// ignore_for_file: deprecated_member_use, depend_on_referenced_packages
part of synquill_gen;

/// Generates the main SynquillDatabase class
class DatabaseGenerator {
  /// Generate the main SynquillDatabase class
  static String generateDatabaseClass(List<ModelInfo> models) {
    final buffer = StringBuffer();

    buffer.writeln('@DriftDatabase(');
    buffer.writeln('  tables: [');
    buffer.writeln('    SyncQueueItems,');
    for (final model in models) {
      buffer.writeln('    ${model.className}Table,');
    }
    buffer.writeln('  ],');
    buffer.writeln('  daos: [');
    // Only include generated DAOs, not custom ones like SyncQueueDao
    for (final model in models) {
      buffer.writeln('    ${model.className}Dao,');
    }
    buffer.writeln('  ],');
    buffer.writeln(')');
    buffer.writeln('/// Main database class for synced data storage');
    buffer.writeln('/// ');
    buffer.writeln(
      '/// Provides Drift-powered offline storage with automatic sync capabilities.',
    );
    buffer.writeln(
      '/// Includes all generated tables and DAOs for the configured models.',
    );
    buffer.writeln('class SynquillDatabase extends _\$SynquillDatabase {');
    buffer.writeln('  static Logger get _log {');
    buffer.writeln('    try {');
    buffer.writeln('      return SynquillStorage.logger;');
    buffer.writeln('    } catch (_) {');
    buffer.writeln('      return Logger(\'SynquillDatabase\');');
    buffer.writeln('    }');
    buffer.writeln('  }');
    buffer.writeln();

    // Add callback fields
    buffer.writeln('  /// Optional callback for when database is created.');
    buffer.writeln(
      '  final Future<void> Function(Migrator)? _onDatabaseCreated;',
    );
    buffer.writeln();
    buffer.writeln('  /// Optional callback for custom migration logic.');
    buffer.writeln(
      '  final Future<void> Function(Migrator, int, int)? _onCustomMigration;',
    );
    buffer.writeln();

    // Enhanced constructor
    buffer.writeln('  /// Creates a new SynquillDatabase instance');
    buffer.writeln('  /// ');
    buffer.writeln(
      '  /// [executor] The database executor (usually a file-based connection)',
    );
    buffer.writeln(
      '  /// [onDatabaseCreated] Optional callback for initial database setup',
    );
    buffer.writeln(
      '  /// [onCustomMigration] Optional callback for handling database migrations',
    );
    buffer.writeln('  SynquillDatabase(');
    buffer.writeln('    super.executor, {');
    buffer.writeln('    Future<void> Function(Migrator)? onDatabaseCreated,');
    buffer.writeln(
      '    Future<void> Function(Migrator, int, int)? onCustomMigration,',
    );
    buffer.writeln('  }) : _onDatabaseCreated = onDatabaseCreated,');
    buffer.writeln('       _onCustomMigration = onCustomMigration;');
    buffer.writeln();

    // Add lazy-initialized syncQueueDao
    buffer.writeln(
      '  late final SyncQueueDao _syncQueueDao = SyncQueueDao(this);',
    );
    buffer.writeln();

    buffer.writeln('  @override');
    buffer.writeln('  int get schemaVersion => 1;');
    buffer.writeln();

    // Add migration strategy
    buffer.writeln('  /// Provides migration strategy for schema upgrades.');
    buffer.writeln('  ///');
    buffer.writeln(
      '  /// The default implementation handles basic table creation and '
      'provides',
    );
    buffer.writeln(
      '  /// a foundation for custom migration logic. Override '
      '[onCustomMigration]',
    );
    buffer.writeln('  /// to add application-specific migration steps.');
    buffer.writeln('  @override');
    buffer.writeln('  MigrationStrategy get migration {');
    buffer.writeln('    return MigrationStrategy(');
    buffer.writeln('      onCreate: (m) async {');
    buffer.writeln('        _log.info(\'Creating database schema\');');
    buffer.writeln('        await m.createAll();');
    buffer.writeln('        if (_onDatabaseCreated != null) {');
    buffer.writeln('          await _onDatabaseCreated!(m);');
    buffer.writeln('        } else {');
    buffer.writeln('          await onDatabaseCreated(m);');
    buffer.writeln('        }');
    buffer.writeln('      },');
    buffer.writeln('      onUpgrade: (m, from, to) async {');
    buffer.writeln(
      '        _log.info(\'Upgrading database from version \$from to \$to\');',
    );
    buffer.writeln('        if (_onCustomMigration != null) {');
    buffer.writeln('          await _onCustomMigration!(m, from, to);');
    buffer.writeln('        } else {');
    buffer.writeln('          await onCustomMigration(m, from, to);');
    buffer.writeln('        }');
    buffer.writeln('      },');
    buffer.writeln('    );');
    buffer.writeln('  }');
    buffer.writeln();

    // Add onDatabaseCreated method
    buffer.writeln(
      '  /// Called when the database is created for the first time.',
    );
    buffer.writeln(
      '  /// Override this to add initial data or perform setup tasks.',
    );
    buffer.writeln(
      '  Future<void> onDatabaseCreated(Migrator migrator) async {',
    );
    buffer.writeln('    _log.info(\'Database created successfully\');');
    buffer.writeln('    // Override in subclasses to add initial data');
    buffer.writeln('  }');
    buffer.writeln();

    // Add onCustomMigration method
    buffer.writeln(
      '  /// Called when the database needs to be upgraded to a new '
      'schema version.',
    );
    buffer.writeln('  /// Override this to handle custom migration logic.');
    buffer.writeln('  ///');
    buffer.writeln('  /// Example:');
    buffer.writeln('  /// ```dart');
    buffer.writeln('  /// @override');
    buffer.writeln(
      '  /// Future<void> onCustomMigration(Migrator m, int from, int to) '
      'async {',
    );
    buffer.writeln('  ///   if (from < 2) {');
    buffer.writeln('  ///     await m.addColumn(users, users.newColumn);');
    buffer.writeln('  ///   }');
    buffer.writeln('  ///   if (from < 3) {');
    buffer.writeln('  ///     await m.createTable(newTable);');
    buffer.writeln('  ///   }');
    buffer.writeln('  /// }');
    buffer.writeln('  /// ```');
    buffer.writeln(
      '  Future<void> onCustomMigration(Migrator migrator, int from, int to) '
      'async {',
    );
    buffer.writeln('    _log.info(\'No custom migration logic defined\');');
    buffer.writeln('    // Override in subclasses to handle migrations');
    buffer.writeln('  }');
    buffer.writeln();

    buffer.writeln('  /// Provides access to the core SyncQueueDao');
    buffer.writeln('  SyncQueueDao get syncQueueDao => _syncQueueDao;');
    buffer.writeln();

    buffer.writeln('  /// Returns user-defined table types');
    buffer.writeln('  List<Type> get userDefinedTables => [');
    for (final model in models) {
      buffer.writeln('    ${model.className}Table,');
    }
    buffer.writeln('  ];');
    buffer.writeln();

    buffer.writeln('  /// Returns user-defined DAO types');
    buffer.writeln('  List<Type> get userDefinedDaos => [');
    for (final model in models) {
      buffer.writeln('    ${model.className}Dao,');
    }
    buffer.writeln('  ];');
    buffer.writeln();

    // Add enhanced close method
    buffer.writeln('  /// Closes the database connection.');
    buffer.writeln('  ///');
    buffer.writeln(
      '  /// This method should be called when the database is no longer '
      'needed',
    );
    buffer.writeln('  /// to ensure proper cleanup of resources.');
    buffer.writeln('  @override');
    buffer.writeln('  Future<void> close() async {');
    buffer.writeln('    _log.info(\'Closing database connection\');');
    buffer.writeln('    await super.close();');
    buffer.writeln('  }');

    buffer.writeln('}');

    return buffer.toString();
  }
}
