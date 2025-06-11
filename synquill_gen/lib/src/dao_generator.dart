// ignore_for_file: deprecated_member_use, depend_on_referenced_packages

part of synquill_gen;

/// Generates DAO classes for Drift database operations
class DaoGenerator {
  /// Generate Fields class for typed field selectors
  static String generateFieldsClass(ModelInfo model) {
    final buffer = StringBuffer();
    final fieldsClassName = '${model.className}Fields';

    buffer.writeln('/// Typed field selectors for ${model.className} model');
    buffer.writeln('class $fieldsClassName {');

    // Track which sync metadata fields we've already added
    final addedSyncFields = <String>{};

    // Generate field selectors for each field (skip OneToMany relations
    // and internal fields)
    for (final field in model.fields) {
      if (field.isOneToMany) continue;

      final fieldName = field.name;

      // Skip internal fields that start with $
      if (fieldName.startsWith('\$')) continue;

      // Track sync metadata fields to avoid duplication
      if ([
        'createdAt',
        'updatedAt',
        'lastSyncedAt',
        'syncStatus',
      ].contains(fieldName)) {
        addedSyncFields.add(fieldName);
      }

      final dartTypeName = field.dartType.getDisplayString(
        withNullability: false,
      );

      buffer.writeln('  /// Field selector for $fieldName');
      buffer.writeln(
        '  static const FieldSelector<$dartTypeName> $fieldName = ',
      );
      buffer.writeln(
        '      FieldSelector<$dartTypeName>(\'$fieldName\', $dartTypeName);',
      );
      buffer.writeln();
    }

    // Add sync metadata fields if not already present
    if (!addedSyncFields.contains('createdAt')) {
      buffer.writeln('  /// Field selector for createdAt');
      buffer.writeln('  static const FieldSelector<DateTime> createdAt = ');
      buffer.writeln('      FieldSelector<DateTime>(\'createdAt\', DateTime);');
      buffer.writeln();
    }

    if (!addedSyncFields.contains('updatedAt')) {
      buffer.writeln('  /// Field selector for updatedAt');
      buffer.writeln('  static const FieldSelector<DateTime> updatedAt = ');
      buffer.writeln('      FieldSelector<DateTime>(\'updatedAt\', DateTime);');
      buffer.writeln();
    }

    if (!addedSyncFields.contains('lastSyncedAt')) {
      buffer.writeln('  /// Field selector for lastSyncedAt');
      buffer.writeln('  static const FieldSelector<DateTime?> lastSyncedAt = ');
      buffer.writeln(
        '      FieldSelector<DateTime?>(\'lastSyncedAt\', DateTime);',
      );
      buffer.writeln();
    }

    if (!addedSyncFields.contains('syncStatus')) {
      buffer.writeln('  /// Field selector for syncStatus');
      buffer.writeln('  static const FieldSelector<SyncStatus> syncStatus = ');
      buffer.writeln(
        '      FieldSelector<SyncStatus>(\'syncStatus\', SyncStatus);',
      );
    }

    buffer.writeln('}');
    buffer.writeln();

    return buffer.toString();
  }

  /// Generate DAO class for a model
  static String generateDaoClass(ModelInfo model) {
    final buffer = StringBuffer();
    final daoName = '${model.className}Dao';
    final tableName = '${model.className}Table';
    final tableVariableName = '${BuilderUtils.camelCase(model.className)}Table';

    buffer.writeln('/// Data Access Object for ${model.className} operations');
    buffer.writeln('/// ');
    buffer.writeln(
      '/// Provides CRUD operations and query methods for ${model.className} entities',
    );
    buffer.writeln('/// in the SQLite database using Drift ORM.');
    buffer.writeln('@DriftAccessor(tables: [$tableName])');
    buffer.writeln('class $daoName extends DatabaseAccessor<SynquillDatabase>');
    buffer.writeln('    with _\$${model.className}DaoMixin,');
    buffer.writeln('       DaoHelpersMixin<$tableName, ${model.className}>, ');
    buffer.writeln('       BaseDaoMixin<${model.className}> {');
    buffer.writeln('  /// Creates a new ${model.className} DAO instance');
    buffer.writeln('  $daoName(super.attachedDatabase);');
    buffer.writeln();

    // Generate methods that work with Drift's generated data classes
    buffer.writeln(
      '  /// Get all ${model.className.toLowerCase()}s as Drift data',
    );
    buffer.writeln(
      '  Future<List<${model.className}>> getAllData() => '
      'select($tableVariableName).get();',
    );
    buffer.writeln();

    buffer.writeln('  /// Get ${model.className.toLowerCase()} data by ID');
    buffer.writeln('  Future<${model.className}?> getDataById(String id) =>');
    buffer.writeln('      (select($tableVariableName)..where((t) =>');
    buffer.writeln('        t.id.equals(id))).getSingleOrNull();');
    buffer.writeln();

    // High-level methods that work with model classes
    buffer.writeln(
      '  /// Get all ${model.className.toLowerCase()}s as model objects',
    );
    buffer.writeln(
      '  Future<List<${model.className}>> getAll('
      '{QueryParams? queryParams}) async {',
    );
    buffer.writeln('    queryParams ??= QueryParams.empty;');
    buffer.writeln('    final query = select($tableVariableName);');
    buffer.writeln('    applyQueryParams(query, queryParams);');
    buffer.writeln('    final dataList = await query.get();');
    buffer.writeln('    return dataList;');
    buffer.writeln('  }');
    buffer.writeln();

    buffer.writeln(
      '  /// Get ${model.className.toLowerCase()} by ID as model object',
    );
    buffer.writeln(
      '  Future<${model.className}?> getById(String id, '
      '{QueryParams? queryParams}) async {',
    );
    buffer.writeln('    queryParams ??= QueryParams.empty;');
    buffer.writeln(
      '    final query = select($tableVariableName)..'
      'where((t) => t.id.equals(id));',
    );
    buffer.writeln('    applyQueryParams(query, queryParams);');
    buffer.writeln('    final data = await query.getSingleOrNull();');
    buffer.writeln('    return data;');
    buffer.writeln('  }');
    buffer.writeln();

    buffer.writeln('  /// Insert or update ${model.className.toLowerCase()}');
    buffer.writeln(
      '  Future<int> insertOrUpdate(${tableName}Companion entry) =>',
    );
    buffer.writeln(
      '      into($tableVariableName).insertOnConflictUpdate(entry);',
    );
    buffer.writeln();

    buffer.writeln('  /// Save ${model.className.toLowerCase()} model');
    buffer.writeln(
      '  Future<${model.className}> saveModel(${model.className} model) '
      'async {',
    );
    buffer.writeln('    final companion = ');
    buffer.writeln('     ${_generateCompanionCreation(model)};');
    buffer.writeln('    await insertOrUpdate(companion);');
    buffer.writeln('    return model;');
    buffer.writeln('  }');
    buffer.writeln();

    buffer.writeln('  /// Delete ${model.className.toLowerCase()} by ID');
    buffer.writeln('  Future<int> deleteById(String id) =>');
    buffer.writeln(
      '      (delete($tableVariableName)..where((t) => t.id.equals(id))).go();',
    );
    buffer.writeln();

    // Add watch methods for reactive streams
    buffer.writeln(
      '  /// Watch all ${model.className.toLowerCase()}s as a stream',
    );
    buffer.writeln(
      '  Stream<List<${model.className}>> watchAll('
      '{QueryParams? queryParams}) {',
    );
    buffer.writeln('    queryParams ??= QueryParams.empty;');
    buffer.writeln('    final query = select($tableVariableName);');
    buffer.writeln('    applyQueryParams(query, queryParams);');
    buffer.writeln('    return query.watch();');
    buffer.writeln('  }');
    buffer.writeln();

    buffer.writeln(
      '  /// Watch ${model.className.toLowerCase()} by ID as a stream',
    );
    buffer.writeln(
      '  Stream<${model.className}?> watchById(String id, '
      '{QueryParams? queryParams}) {',
    );
    buffer.writeln('    queryParams ??= QueryParams.empty;');
    buffer.writeln(
      '    final query = select($tableVariableName)..'
      'where((t) => t.id.equals(id));',
    );
    buffer.writeln('    applyQueryParams(query, queryParams);');
    buffer.writeln('    return query.watchSingleOrNull();');
    buffer.writeln('  }');
    buffer.writeln();

    // Generate field mapping for more efficient filtering
    _generateFieldMapping(buffer, model, tableName, tableVariableName);

    _generateSortingMethod(buffer, model, tableName);

    // Add typed methods that repositories expect
    _generateTypedMethods(buffer, model, tableName, tableVariableName);

    buffer.writeln('}');
    return buffer.toString();
  }

  /// Generate companion object creation code
  static String _generateCompanionCreation(ModelInfo model) {
    final buffer = StringBuffer();
    final companionClass = '${model.className}TableCompanion';

    buffer.write('$companionClass(');

    // Collect existing field names to avoid duplicates
    final existingFieldNames = <String>{};

    // Add model fields (skip OneToMany fields and internal fields)
    bool hasFields = false;
    for (final field in model.fields) {
      if (field.isOneToMany) continue; // Skip OneToMany fields

      // Skip internal fields that start with $
      if (field.name.startsWith('\$')) continue;

      // Skip computed fields that shouldn't be stored in DB
      if (field.name == 'getSyncDetails') continue;

      existingFieldNames.add(field.name);

      if (hasFields) buffer.write(',\n        ');

      // Special handling for timestamp fields
      if (field.name == 'updatedAt') {
        buffer.write(
          '${field.name}: Value(model.${field.name} ?? '
          'DateTime.now())',
        );
      } else if (field.name == 'createdAt') {
        buffer.write(
          '${field.name}: Value(model.${field.name} ?? '
          'DateTime.now())',
        );
      } else if (field.name == 'syncStatus') {
        // syncStatus needs to be serialized to String
        buffer.write('${field.name}: Value(model.${field.name} ?? '
            'SyncStatus.synced)');
      } else {
        // Handle nullable fields properly
        if (field.dartType.nullabilitySuffix != NullabilitySuffix.none) {
          // Field is nullable, use appropriate handling
          buffer.write('${field.name}: Value(model.${field.name})');
        } else {
          // Field is non-nullable, use Value directly
          buffer.write('${field.name}: Value(model.${field.name})');
        }
      }
      hasFields = true;
    }

    // Add timestamp fields only if they don't exist in model
    // Set createdAt only for new records (if field doesn't exist)
    if (!existingFieldNames.contains('createdAt')) {
      if (hasFields) buffer.write(', ');
      buffer.write('createdAt: Value(DateTime.now())');
      hasFields = true;
    }

    // Set updatedAt only if it doesn't exist in model
    if (!existingFieldNames.contains('updatedAt')) {
      if (hasFields) buffer.write(', ');
      buffer.write('updatedAt: Value(DateTime.now())');
      hasFields = true;
    }

    // Set lastSyncedAt only if it doesn't exist in model
    if (!existingFieldNames.contains('lastSyncedAt')) {
      if (hasFields) buffer.write(', ');
      buffer.write('lastSyncedAt: Value(model.lastSyncedAt)');
      hasFields = true;
    }

    // Set syncStatus only if it doesn't exist in model
    if (!existingFieldNames.contains('syncStatus')) {
      if (hasFields) buffer.write(', ');
      buffer.write('syncStatus: Value(model.syncStatus ?? '
          'SyncStatus.synced)');
      hasFields = true;
    }

    buffer.write(')');
    return buffer.toString();
  }

  /// Generate field mapping for efficient filtering and sorting
  static void _generateFieldMapping(
    StringBuffer buffer,
    ModelInfo model,
    String tableName,
    String tableVariableName,
  ) {
    // Add table getter override
    buffer.writeln('  /// The primary table this DAO operates on.');
    buffer.writeln('  @override');
    buffer.writeln(
      '  TableInfo<$tableName, ${model.className}> get '
      'table => $tableVariableName;',
    );
    buffer.writeln();

    buffer.writeln('  /// Get column expression for a field name');
    buffer.writeln('  @override');
    buffer.writeln(
      '  Expression<Object>? getColumnForField(String fieldName) {',
    );
    buffer.writeln('    switch (fieldName) {');

    // Collect existing field names to avoid duplicates
    final existingFieldNames = <String>{};

    // Add model fields
    for (final field in model.fields) {
      if (field.isOneToMany) continue;
      // Skip internal fields that start with $
      if (field.name.startsWith('\$')) continue;

      existingFieldNames.add(field.name);
      buffer.writeln('      case \'${field.name}\':');
      buffer.writeln('        return $tableVariableName.${field.name};');
    }

    // Add sync metadata fields only if they don't already exist as model fields
    if (!existingFieldNames.contains('createdAt')) {
      buffer.writeln('      case \'createdAt\':');
      buffer.writeln('        return $tableVariableName.createdAt;');
    }
    if (!existingFieldNames.contains('updatedAt')) {
      buffer.writeln('      case \'updatedAt\':');
      buffer.writeln('        return $tableVariableName.updatedAt;');
    }
    if (!existingFieldNames.contains('lastSyncedAt')) {
      buffer.writeln('      case \'lastSyncedAt\':');
      buffer.writeln('        return $tableVariableName.lastSyncedAt;');
    }
    if (!existingFieldNames.contains('syncStatus')) {
      buffer.writeln('      case \'syncStatus\':');
      buffer.writeln('        return $tableVariableName.syncStatus;');
    }

    buffer.writeln('      default:');
    buffer.writeln('        return null;');
    buffer.writeln('    }');
    buffer.writeln('  }');
    buffer.writeln();

    // Generate field type mapping
    buffer.writeln('  /// Get the data type for a field name');
    buffer.writeln('  @override');
    buffer.writeln('  String? getFieldType(String fieldName) {');
    buffer.writeln('    switch (fieldName) {');

    for (final field in model.fields) {
      if (field.isOneToMany) continue;
      // Skip internal fields that start with $
      if (field.name.startsWith('\$')) continue;

      final dartTypeName = field.dartType.getDisplayString(
        withNullability: false,
      );
      buffer.writeln('      case \'${field.name}\':');
      buffer.writeln('        return \'$dartTypeName\';');
    }

    // Add sync metadata field types only if they don't already exist
    // as model fields
    final hasDateTimeFields = !existingFieldNames.contains('createdAt') ||
        !existingFieldNames.contains('updatedAt') ||
        !existingFieldNames.contains('lastSyncedAt');

    if (hasDateTimeFields) {
      if (!existingFieldNames.contains('createdAt')) {
        buffer.writeln('      case \'createdAt\':');
      }
      if (!existingFieldNames.contains('updatedAt')) {
        buffer.writeln('      case \'updatedAt\':');
      }
      if (!existingFieldNames.contains('lastSyncedAt')) {
        buffer.writeln('      case \'lastSyncedAt\':');
      }
      // Only write the return statement once for all DateTime fields
      buffer.writeln('        return \'DateTime\';');
    }
    if (!existingFieldNames.contains('syncStatus')) {
      buffer.writeln('      case \'syncStatus\':');
      buffer.writeln('        return \'SyncStatus\';');
    }

    buffer.writeln('      default:');
    buffer.writeln('        return null;');
    buffer.writeln('    }');
    buffer.writeln('  }');
    buffer.writeln();
  }

  /// Generate universal sorting method
  static void _generateSortingMethod(
    StringBuffer buffer,
    ModelInfo model,
    String tableName,
  ) {
    buffer.writeln('  /// Create ordering term for sorting');
    buffer.writeln('  @override');
    buffer.writeln(
      '  OrderingTerm createOrderingTerm(SortCondition sort, '
      '$tableName table) {',
    );
    buffer.writeln(
      '    final column = getColumnForField(sort.field.fieldName);',
    );
    buffer.writeln('    if (column == null) {');
    buffer.writeln(
      '      throw ArgumentError(\'Unknown field for sorting: '
      '\${sort.field.fieldName}\');',
    );
    buffer.writeln('    }');
    buffer.writeln();
    buffer.writeln('    return OrderingTerm(');
    buffer.writeln('      expression: column,');
    buffer.writeln('      mode: sort.direction == SortDirection.ascending');
    buffer.writeln('          ? OrderingMode.asc');
    buffer.writeln('          : OrderingMode.desc,');
    buffer.writeln('    );');
    buffer.writeln('  }');
    buffer.writeln();
  }

  /// Generate typed methods that repositories expect
  static void _generateTypedMethods(
    StringBuffer buffer,
    ModelInfo model,
    String tableName,
    String tableVariableName,
  ) {
    buffer.writeln('  // Implementation of BaseDaoMixin methods');
    buffer.writeln('  @override');
    buffer.writeln('  Future<${model.className}?> getByIdTyped(String id, ');
    buffer.writeln('   {QueryParams? queryParams}) async {');
    buffer.writeln('    return await getById(id, queryParams: queryParams);');
    buffer.writeln('  }');
    buffer.writeln();

    buffer.writeln('  @override');
    buffer.writeln(
      '  Future<List<${model.className}>> '
      'getAllTyped({QueryParams? queryParams}) async {',
    );
    buffer.writeln('    return await getAll(queryParams: queryParams);');
    buffer.writeln('  }');
    buffer.writeln();

    buffer.writeln('  @override');
    buffer.writeln(
      '  Stream<${model.className}?> watchByIdTyped(String id, '
      '{QueryParams? queryParams}) {',
    );
    buffer.writeln('    return watchById(id, queryParams: queryParams);');
    buffer.writeln('  }');
    buffer.writeln();

    buffer.writeln('  @override');
    buffer.writeln(
      '  Stream<List<${model.className}>> watchAllTyped('
      '{QueryParams? queryParams}) {',
    );
    buffer.writeln('    return watchAll(queryParams: queryParams);');
    buffer.writeln('  }');
    buffer.writeln();

    // Add deleteAll method for bulk deletion
    buffer.writeln(
      '  /// Delete all ${model.className.toLowerCase()}s from the table',
    );
    buffer.writeln('  Future<int> deleteAll() =>');
    buffer.writeln('      delete($tableVariableName).go();');
    buffer.writeln();
  }

  /// Generate all DAO related classes for a database
  static String generateAllDaoCode(List<ModelInfo> models) {
    final buffer = StringBuffer();

    // First, generate the DaoHelpersMixin
    buffer.writeln("""
/// Helper mixin for DAO classes to provide filtering and query operations
mixin DaoHelpersMixin<Tbl extends Table, D> 
  on DatabaseAccessor<SynquillDatabase> {
  /// Apply query parameters (filters, sorting, pagination) to a query
  void applyQueryParams(
    SimpleSelectStatement<Tbl, D> query,
    QueryParams queryParams,
  ) {
    // Apply filters
    for (final filter in queryParams.filters) {
      applyFilter(query, filter);
    }

    // Apply sorting
    if (queryParams.sorts.isNotEmpty) {
      query.orderBy([
        for (final sort in queryParams.sorts)
          (t) => createOrderingTerm(sort, t),
      ]);
    }

    // Apply pagination
    if (queryParams.pagination != null) {
      final pagination = queryParams.pagination!;
      final limit = pagination.limit;
      final offset = pagination.offset;
      if (limit != null && offset != null) {
        query.limit(limit, offset: offset);
      } else if (limit != null) {
        query.limit(limit);
      }
    }
  }

  /// Get column expression for a field name
  Expression<Object>? getColumnForField(String fieldName);

  /// Get the data type for a field name
  String? getFieldType(String fieldName);

  /// Apply a single filter to the query
  void applyFilter(
    SimpleSelectStatement<Tbl, D> query,
    FilterCondition filter,
  ) {
    final column = getColumnForField(filter.field.fieldName);
    if (column == null) {
      throw ArgumentError('Unknown field: \${filter.field.fieldName}');
    }

    final fieldType = getFieldType(filter.field.fieldName);
    applyFilterByType(query, column, filter, fieldType);
  }

  /// Apply filter based on field type
  void applyFilterByType(
    SimpleSelectStatement<Tbl, D> query,
    Expression<Object> column,
    FilterCondition filter,
    String? fieldType,
  ) {
    switch (filter.operator) {
      case FilterOperator.equals:
        _applySingleValueFilter(query, column, filter, fieldType, 
          (col, val) => col.equals(val));
        break;
      case FilterOperator.notEquals:
        _applySingleValueFilter(query, column, filter, fieldType, 
          (col, val) => col.equals(val).not());
        break;
      case FilterOperator.contains:
        if (fieldType == 'String' && filter.value is SingleValue) {
          final value = (filter.value as SingleValue).value as String;
          query.where((t) => (column as Expression<String>).contains(value));
        }
        break;
      case FilterOperator.startsWith:
        if (fieldType == 'String' && filter.value is SingleValue) {
          final value = (filter.value as SingleValue).value as String;
          query.where((t) => (column as Expression<String>).like('\$value%'));
        }
        break;
      case FilterOperator.endsWith:
        if (fieldType == 'String' && filter.value is SingleValue) {
          final value = (filter.value as SingleValue).value as String;
          query.where((t) => (column as Expression<String>).like('%\$value'));
        }
        break;
      case FilterOperator.greaterThan:
        _applyComparisonFilter(query, column, filter, fieldType, 
        _applyGreaterThan);
        break;
      case FilterOperator.greaterThanOrEqual:
        _applyComparisonFilter(query, column, filter, fieldType, 
        _applyGreaterThanOrEqual);
        break;
      case FilterOperator.lessThan:
        _applyComparisonFilter(query, column, filter, fieldType, 
        _applyLessThan);
        break;
      case FilterOperator.lessThanOrEqual:
        _applyComparisonFilter(query, column, filter, fieldType, 
        _applyLessThanOrEqual);
        break;
      case FilterOperator.isNull:
        query.where((t) => column.isNull());
        break;
      case FilterOperator.isNotNull:
        query.where((t) => column.isNotNull());
        break;
      case FilterOperator.inList:
        _applyListFilter(query, column, filter, fieldType, true);
        break;
      case FilterOperator.notInList:
        _applyListFilter(query, column, filter, fieldType, false);
        break;
    }
  }

  /// Apply filter for single value operations (equals, notEquals)
  void _applySingleValueFilter(
    SimpleSelectStatement<Tbl, D> query,
    Expression<Object> column,
    FilterCondition filter,
    String? fieldType,
    Expression<bool> Function(Expression<Object>, Object) operation,
  ) {
    if (filter.value is SingleValue) {
      if (fieldType == 'SyncStatus') {
        final value = (filter.value as SingleValue).value;
        final statusName = value is SyncStatus ? value.name : value;
        query.where((t) => operation(column, statusName));
      } else {
        final value = (filter.value as SingleValue).value;
        query.where((t) => operation(column, value));
      }
    }
  }

  /// Apply comparison filter for numeric and DateTime types
  void _applyComparisonFilter(
    SimpleSelectStatement<Tbl, D> query,
    Expression<Object> column,
    FilterCondition filter,
    String? fieldType,
    void Function(SimpleSelectStatement<Tbl, D>, 
    Expression<Object>, Object, String) operation,
  ) {
    if (filter.value is SingleValue) {
      final value = (filter.value as SingleValue).value;
      if (fieldType != null && (fieldType == 'int' 
        || fieldType == 'double' || fieldType == 'DateTime')) {
        operation(query, column, value, fieldType);
      }
    }
  }

  /// Apply greater than operation with type safety
  void _applyGreaterThan(
    SimpleSelectStatement<Tbl, D> query,
    Expression<Object> column,
    Object value,
    String fieldType,
  ) {
    switch (fieldType) {
      case 'int':
        query.where((t) => (column as Expression<int>)
          .isBiggerThan(Variable<int>(value as int)));
        break;
      case 'double':
        query.where((t) => (column as Expression<double>)
          .isBiggerThan(Variable<double>(value as double)));
        break;
      case 'DateTime':
        query.where((t) => (column as Expression<DateTime>)
          .isBiggerThan(Variable<DateTime>(value as DateTime)));
        break;
    }
  }

  /// Apply greater than or equal operation with type safety
  void _applyGreaterThanOrEqual(
    SimpleSelectStatement<Tbl, D> query,
    Expression<Object> column,
    Object value,
    String fieldType,
  ) {
    switch (fieldType) {
      case 'int':
        query.where((t) => (column as Expression<int>)
          .isBiggerOrEqual(Variable<int>(value as int)));
        break;
      case 'double':
        query.where((t) => (column as Expression<double>)
          .isBiggerOrEqual(Variable<double>(value as double)));
        break;
      case 'DateTime':
        query.where((t) => (column as Expression<DateTime>)
          .isBiggerOrEqual(Variable<DateTime>(value as DateTime)));
        break;
    }
  }

  /// Apply less than operation with type safety
  void _applyLessThan(
    SimpleSelectStatement<Tbl, D> query,
    Expression<Object> column,
    Object value,
    String fieldType,
  ) {
    switch (fieldType) {
      case 'int':
        query.where((t) => (column as Expression<int>)
          .isSmallerThan(Variable<int>(value as int)));
        break;
      case 'double':
        query.where((t) => (column as Expression<double>)
          .isSmallerThan(Variable<double>(value as double)));
        break;
      case 'DateTime':
        query.where((t) => (column as Expression<DateTime>)
          .isSmallerThan(Variable<DateTime>(value as DateTime)));
        break;
    }
  }

  /// Apply less than or equal operation with type safety
  void _applyLessThanOrEqual(
    SimpleSelectStatement<Tbl, D> query,
    Expression<Object> column,
    Object value,
    String fieldType,
  ) {
    switch (fieldType) {
      case 'int':
        query.where((t) => (column as Expression<int>)
          .isSmallerOrEqual(Variable<int>(value as int)));
        break;
      case 'double':
        query.where((t) => (column as Expression<double>)
          .isSmallerOrEqual(Variable<double>(value as double)));
        break;
      case 'DateTime':
        query.where((t) => (column as Expression<DateTime>)
          .isSmallerOrEqual(Variable<DateTime>(value as DateTime)));
        break;
    }
  }

  /// Apply list filter (inList, notInList)
  void _applyListFilter(
    SimpleSelectStatement<Tbl, D> query,
    Expression<Object> column,
    FilterCondition filter,
    String? fieldType,
    bool isInList,
  ) {
    if (filter.value is ListValue) {
      final listValues = (filter.value as ListValue).values;
      
      switch (fieldType) {
        case 'String':
          final values = listValues.cast<String>();
          query.where((t) => isInList 
            ? (column as Expression<String>).isIn(values)
            : (column as Expression<String>).isNotIn(values));
          break;
        case 'int':
          final values = listValues.cast<int>();
          query.where((t) => isInList
            ? (column as Expression<int>).isIn(values)
            : (column as Expression<int>).isNotIn(values));
          break;
        case 'double':
          final values = listValues.cast<double>();
          query.where((t) => isInList
            ? (column as Expression<double>).isIn(values)
            : (column as Expression<double>).isNotIn(values));
          break;
        case 'bool':
          final values = listValues.cast<bool>();
          query.where((t) => isInList
            ? (column as Expression<bool>).isIn(values)
            : (column as Expression<bool>).isNotIn(values));
          break;
        case 'DateTime':
          final values = listValues.cast<DateTime>();
          query.where((t) => isInList
            ? (column as Expression<DateTime>).isIn(values)
            : (column as Expression<DateTime>).isNotIn(values));
          break;
        case 'SyncStatus':
          final statusNames = listValues.map((e) => e is SyncStatus ?
            e.name : e.toString()).toList();
          query.where((t) => isInList
            ? (column as Expression<String>).isIn(statusNames)
            : (column as Expression<String>).isNotIn(statusNames));
          break;
        default:
          // Fallback for unhandled types
          final values = listValues.cast<Object>();
          query.where((t) => isInList
            ? column.isIn(values)
            : column.isNotIn(values));
          break;
      }
    } else {
      throw ArgumentError('\${isInList ? "inList" : "notInList"} '
      'operator requires a ListValue');
    }
  }

  /// Create ordering term for sorting
  OrderingTerm createOrderingTerm(SortCondition sort, Tbl table);

  /// The primary table this DAO operates on.
  TableInfo<Tbl, D> get table;
}
""");
    buffer.writeln();

    // Then generate all model-specific Fields classes and DAOs
    for (final model in models) {
      buffer.writeln(generateFieldsClass(model));
      buffer.writeln();
      buffer.writeln(generateDaoClass(model));
      buffer.writeln();
    }

    return buffer.toString();
  }
}
