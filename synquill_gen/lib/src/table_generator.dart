// ignore_for_file: deprecated_member_use, depend_on_referenced_packages
part of synquill_gen;

/// Generates Drift table classes from model information
class TableGenerator {
  /// Generate Drift table class for a model
  static String generateTableClass(ModelInfo model) {
    final buffer = StringBuffer();
    buffer.writeln(
      '/// Drift table definition for ${model.className} entities',
    );
    buffer.writeln('/// ');
    buffer.writeln(
      '/// This table stores ${model.className} data '
      'with automatic sync metadata',
    );
    buffer.writeln(
      '/// and supports offline storage with eventual consistency.',
    );

    // Collect indexed fields for @TableIndex annotations
    final indexedFields =
        model.fields
            .where((field) => field.isIndexed && !field.isOneToMany)
            .toList();

    // Add @TableIndex annotations for indexed fields
    for (final field in indexedFields) {
      final indexName =
          field.indexName ?? 'idx_${model.tableName}_${field.name}';
      buffer.write('@TableIndex(name: \'$indexName\', ');
      buffer.write('columns: {#${field.name}}');
      if (field.isUniqueIndex) {
        buffer.write(', unique: true');
      }
      buffer.writeln(')');
    }

    // Add automatic index for createdAt sync metadata field
    // for better query performance
    final hasExplicitCreatedAtField = model.fields.any(
      (field) => field.name == 'createdAt',
    );
    if (!hasExplicitCreatedAtField) {
      buffer.writeln(
        '@TableIndex(name: \'idx_${model.tableName}_created_at\', '
        'columns: {#createdAt})',
      );
    }

    buffer.writeln('@UseRowClass(${model.className}, constructor: \'fromDb\')');
    buffer.writeln('class ${model.className}Table extends Table {');
    buffer.writeln('  @override');
    buffer.writeln('  String get tableName => \'${model.tableName}\';');
    buffer.writeln();

    // Generate columns based on model fields
    final existingFields = <String>{};
    for (final field in model.fields) {
      // Skip OneToMany fields - they don't create database columns
      if (field.isOneToMany) continue;

      // Skip internal fields that start with $ - these are runtime-only fields
      if (field.name.startsWith('\$')) continue;

      existingFields.add(field.name);
      final columnDefinition = _getDriftColumnDefinition(field);
      buffer.writeln('  /// ${field.name} column for ${model.className}');
      buffer.writeln('  $columnDefinition');
    }

    // Add sync metadata fields if not already present
    if (!existingFields.contains('createdAt')) {
      buffer.writeln('  // Sync metadata');
      buffer.writeln('  /// Timestamp when the record was created');
      buffer.writeln(
        '  DateTimeColumn get createdAt => '
        'dateTime().withDefault(currentDateAndTime)();',
      );
    }
    if (!existingFields.contains('updatedAt')) {
      buffer.writeln('  /// Timestamp when the record was last updated');
      buffer.writeln(
        '  DateTimeColumn get updatedAt => '
        'dateTime().withDefault(currentDateAndTime)();',
      );
    }
    if (!existingFields.contains('lastSyncedAt')) {
      buffer.writeln(
        '  /// Timestamp when the record was last synced with remote server',
      );
      buffer.writeln(
        '  DateTimeColumn get lastSyncedAt => dateTime().nullable()();',
      );
    }
    if (!existingFields.contains('syncStatus')) {
      buffer.writeln('  /// Current synchronization status');
      buffer.writeln(
        '  TextColumn get syncStatus => '
        'textEnum<SyncStatus>().withDefault(const Constant(\'pending\'))();',
      );
    }

    // Add primary key override if the table has an 'id' field
    if (existingFields.contains('id')) {
      buffer.writeln();
      buffer.writeln('  @override');
      buffer.writeln('  Set<Column> get primaryKey => {id};');
    }

    buffer.writeln('}');

    return buffer.toString();
  }

  /// Generate the core SyncQueueItems table definition
  static String generateSyncQueueItemsTable() {
    return '''
/// Defines the schema for an item in the synchronization queue.
///
/// Each row represents an operation (create, update, delete) on a data
/// model that needs to be synced with a remote server.
@DataClassName('SyncQueueItem')
@TableIndex(name: 'idx_model_id', columns: {#modelId})
@TableIndex(name: 'idx_model_type', columns: {#modelType})
@TableIndex(name: 'idx_operation', columns: {#operation})
@TableIndex(name: 'idx_status', columns: {#status})
@TableIndex(name: 'idx_next_retry_at', columns: {#nextRetryAt})
@TableIndex(name: 'idx_created_at', columns: {#createdAt})
class SyncQueueItems extends Table {
  /// Unique identifier for the queue item.
  IntColumn get id => integer().autoIncrement()();

  /// The type of the model being synced (e.g., "User", "Product").
  TextColumn get modelType => text().named('model_type')();

  /// The ID of the specific model instance being synced.
  TextColumn get modelId => text().named('model_id')();

  /// JSON string representation of the model data.
  /// For 'delete' operations, this might store the ID or key fields.
  TextColumn get payload => text()();

  /// The synchronization operation type (create, update, delete).
  TextColumn get operation => text().named('op')();

  /// Number of times a synchronization attempt has been made.
  IntColumn get attemptCount =>
      integer().named('attempt_count').withDefault(const Constant(0))();

  /// Stores the error message from the last failed sync attempt.
  TextColumn get lastError => text().named('last_error').nullable()();

  /// When the next synchronization attempt should occur.
  /// Null if ready for immediate processing or retries are exhausted.
  DateTimeColumn get nextRetryAt =>
      dateTime().named('next_retry_at').nullable()();

  /// Timestamp of when this item was added to the queue.
  DateTimeColumn get createdAt =>
      dateTime().named('created_at').withDefault(currentDateAndTime)();

  /// Optional idempotency key for ensuring network operations are not
  /// duplicated if a retry occurs after a successful but unconfirmed
  /// operation.
  TextColumn get idempotencyKey =>
      text().named('idempotency_key').nullable().unique()();

  /// Status of the sync queue item (pending, processing, completed, failed).
  TextColumn get status => text().withDefault(const Constant('pending'))();

  /// JSON string representation of HTTP headers for the sync operation.
  /// Stored as nullable text to preserve headers for retry operations.
  TextColumn get headers => text().nullable()();

  /// JSON string representation of extra parameters for the sync operation.
  /// Stored as nullable text to preserve extra data for retry operations.
  TextColumn get extra => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {modelId, operation}, // Ensure only one operation per model ID
  ];
}

''';
  }

  /// Get Drift column definition for a field
  static String _getDriftColumnDefinition(FieldInfo field) {
    final typeStr = field.dartType.getDisplayString(withNullability: false);
    final isNullable =
        field.dartType.nullabilitySuffix != NullabilitySuffix.none;

    // Handle ManyToOne relations - they create foreign key columns
    if (field.isManyToOne) {
      if (field.name == 'id') {
        final baseColumn = 'text().named(\'${field.name}\')';
        return 'TextColumn get ${field.name} => '
            '$baseColumn${isNullable ? '.nullable()' : ''}();';
      } else {
        // For foreign key fields, create references if possible
        const baseColumn = 'text()';
        return 'TextColumn get ${field.name} => '
            '$baseColumn${isNullable ? '.nullable()' : ''}();';
      }
    }

    switch (typeStr) {
      case 'String':
        if (field.name == 'id') {
          final baseColumn = 'text().named(\'${field.name}\')';
          return 'TextColumn get ${field.name} => '
              '$baseColumn${isNullable ? '.nullable()' : ''}();';
        }
        const baseColumn = 'text()';
        return 'TextColumn get ${field.name} => '
            '$baseColumn${isNullable ? '.nullable()' : ''}();';
      case 'int':
        const baseColumn = 'integer()';
        return 'IntColumn get ${field.name} => '
            '$baseColumn${isNullable ? '.nullable()' : ''}();';
      case 'double':
        const baseColumn = 'real()';
        return 'RealColumn get ${field.name} => '
            '$baseColumn${isNullable ? '.nullable()' : ''}();';
      case 'bool':
        const baseColumn = 'boolean()';
        return 'BoolColumn get ${field.name} => '
            '$baseColumn${isNullable ? '.nullable()' : ''}();';
      case 'DateTime':
        const baseColumn = 'dateTime()';
        return 'DateTimeColumn get ${field.name} => '
            '$baseColumn${isNullable ? '.nullable()' : ''}();';
      default:
        // For custom types, store as text with JSON serialization
        const baseColumn = 'text()';
        return 'TextColumn get ${field.name} => '
            '$baseColumn${isNullable ? '.nullable()' : ''}();';
    }
  }
}
