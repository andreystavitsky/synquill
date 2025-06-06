// ignore_for_file: deprecated_member_use, depend_on_referenced_packages
part of synquill_gen;

/// Generates the main SynquillDatabase class
class DatabaseGenerator {
  // TypeChecker for database version annotation
  static const _synqillDatabaseVersionChecker = TypeChecker.fromRuntime(
    SynqillDatabaseVersion,
  );

  /// Finds the database version from @SynqillDatabaseVersion annotation
  /// in the project. Returns 1 as default if no annotation is found.
  /// Throws an error if multiple different versions are found.
  static Future<int> _findDatabaseVersion(BuildStep buildStep) async {
    // Find all Dart files in lib/
    final dartFiles = <AssetId>[];
    await for (final input in buildStep.findAssets(Glob('lib/**.dart'))) {
      dartFiles.add(input);
    }

    final foundVersions = <int, List<String>>{};

    for (final asset in dartFiles) {
      // Skip part files - they can't be processed as libraries
      final content = await buildStep.readAsString(asset);
      if (content.trimLeft().startsWith('part of ')) {
        continue;
      }

      // Search for ALL @SynqillDatabaseVersion annotations in source code
      final versionPattern = RegExp(
        r'@SynqillDatabaseVersion\s*\(\s*(\d+)\s*\)',
        multiLine: true,
      );
      final matches = versionPattern.allMatches(content);

      for (final match in matches) {
        // Check if this match is in a comment
        if (_isAnnotationInComment(content, match.start)) {
          continue; // Skip commented-out annotations
        }

        final versionStr = match.group(1);
        if (versionStr != null) {
          final version = int.tryParse(versionStr);
          if (version != null) {
            foundVersions.putIfAbsent(version, () => []).add(asset.path);
          }
        }
      }

      // Fallback to element analysis for top-level elements
      try {
        final library = await buildStep.resolver.libraryFor(asset);

        // Check annotations on all library-level elements
        for (final element in library.topLevelElements) {
          final annotation = _synqillDatabaseVersionChecker.firstAnnotationOf(
            element,
          );
          if (annotation != null) {
            final reader = ConstantReader(annotation);
            final version = reader.read('version').intValue;
            foundVersions
                .putIfAbsent(version, () => [])
                .add('${asset.path} (${element.name})');
          }

          // Check annotations on top-level variables specifically
          if (element is TopLevelVariableElement) {
            final annotation = _synqillDatabaseVersionChecker.firstAnnotationOf(
              element,
            );
            if (annotation != null) {
              final reader = ConstantReader(annotation);
              final version = reader.read('version').intValue;
              foundVersions
                  .putIfAbsent(version, () => [])
                  .add('${asset.path} (variable ${element.name})');
            }
          }

          // Check annotations on functions (like main)
          if (element is FunctionElement) {
            final annotation = _synqillDatabaseVersionChecker.firstAnnotationOf(
              element,
            );
            if (annotation != null) {
              final reader = ConstantReader(annotation);
              final version = reader.read('version').intValue;
              foundVersions
                  .putIfAbsent(version, () => [])
                  .add('${asset.path} (function ${element.name})');
            }
          }
        }
      } catch (e) {
        // Skip files that can't be analyzed
        continue;
      }
    }

    // Validate that we don't have conflicting versions
    if (foundVersions.length > 1) {
      final buffer = StringBuffer();
      buffer.writeln(
        'ERROR: Multiple @SynqillDatabaseVersion annotations found with '
        'different versions:',
      );
      for (final entry in foundVersions.entries) {
        buffer.writeln('  Version ${entry.key} found in:');
        for (final location in entry.value) {
          buffer.writeln('    - $location');
        }
      }
      buffer.writeln('');
      buffer.writeln(
        'Please use only one @SynqillDatabaseVersion annotation in your '
        'entire project.',
      );
      buffer.writeln(
        'Remove duplicate annotations or ensure they all specify the same '
        'version.',
      );

      throw InvalidGenerationSourceError(buffer.toString(), element: null);
    }

    // Return the single version found, or default to 1
    if (foundVersions.isNotEmpty) {
      final version = foundVersions.keys.first;
      // Validate that version is positive
      if (version <= 0) {
        throw InvalidGenerationSourceError(
          'Database version must be a positive integer, found: $version',
          element: null,
        );
      }
      return version;
    }

    // Default version if no annotation found
    return 1;
  }

  /// Checks if the annotation at the given position is commented out
  static bool _isAnnotationInComment(String content, int position) {
    // First check if this is in a single-line comment
    int lineStart = content.lastIndexOf('\n', position - 1) + 1;
    if (lineStart == 0) lineStart = 0;

    final lineEnd = content.indexOf('\n', position);
    final endPos = lineEnd == -1 ? content.length : lineEnd;
    final line = content.substring(lineStart, endPos);

    // Get the position relative to the start of the line
    final positionInLine = position - lineStart;

    // Check if there's a // comment before the position in this line
    final commentIndex = line.indexOf('//');
    if (commentIndex != -1 && commentIndex < positionInLine) {
      return true;
    }

    // Check if we're inside a block comment /* ... */
    return _isInBlockComment(content, position);
  }

  /// Checks if the given position is inside a block comment /* ... */
  static bool _isInBlockComment(String content, int position) {
    // Find the last '/*' before our position
    int lastBlockStart = -1;
    int searchPos = 0;

    while (true) {
      final nextStart = content.indexOf('/*', searchPos);
      if (nextStart == -1 || nextStart >= position) {
        break;
      }
      lastBlockStart = nextStart;
      searchPos = nextStart + 2;
    }

    // If no block comment start found before our position, we're not in one
    if (lastBlockStart == -1) {
      return false;
    }

    // Find the next '*/' after the last '/*'
    final blockEnd = content.indexOf('*/', lastBlockStart + 2);

    // If no closing found, or closing is after our position, we're inside
    return blockEnd == -1 || blockEnd >= position;
  }

  /// Generate the main SynquillDatabase class
  static Future<String> generateDatabaseClass(
    List<ModelInfo> models,
    BuildStep buildStep,
  ) async {
    // Find database version from annotation
    final schemaVersion = await _findDatabaseVersion(buildStep);
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
    buffer.writeln('  int get schemaVersion => $schemaVersion;');
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
