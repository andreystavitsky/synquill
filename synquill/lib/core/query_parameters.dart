part of synquill;

/// Enum representing different comparison operators for filtering.
enum FilterOperator {
  /// Equals (=)
  equals,

  /// Not equals (!=)
  notEquals,

  /// Greater than (>)
  greaterThan,

  /// Greater than or equal (>=)
  greaterThanOrEqual,

  /// Less than (<)
  lessThan,

  /// Less than or equal (<=)
  lessThanOrEqual,

  /// Contains substring (for text fields)
  contains,

  /// Starts with (for text fields)
  startsWith,

  /// Ends with (for text fields)
  endsWith,

  /// Is in list of values
  inList,

  /// Is not in list of values
  notInList,

  /// Is null
  isNull,

  /// Is not null
  isNotNull,
}

/// Enum representing sort directions.
enum SortDirection {
  /// Ascending order (A-Z, 0-9, oldest first)
  ascending,

  /// Descending order (Z-A, 9-0, newest first)
  descending,
}

/// Base class for typed field selectors.
///
/// This provides compile-time safety for field access and type checking.
class FieldSelector<T> {
  /// The string name of the field as it appears in the database
  final String fieldName;

  /// The Dart type of the field for compile-time type checking
  final Type fieldType;

  /// Creates a new field selector
  const FieldSelector(this.fieldName, this.fieldType);

  @override
  String toString() => fieldName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FieldSelector &&
          runtimeType == other.runtimeType &&
          fieldName == other.fieldName &&
          fieldType == other.fieldType;

  @override
  int get hashCode => fieldName.hashCode ^ fieldType.hashCode;
}

/// Base class for typed filter condition values
sealed class FilterValue<T> {
  const FilterValue();
}

/// Single value for most filter operations
class SingleValue<T> extends FilterValue<T> {
  /// The single value to be used in filter comparison
  final T value;

  /// Creates a SingleValue with the given value
  const SingleValue(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SingleValue<T> && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '$value';
}

/// List value for inList/notInList operations
class ListValue<T> extends FilterValue<T> {
  /// The list of values to be used in list filter operations
  final List<T> values;

  /// Creates a ListValue with the given list of values
  const ListValue(this.values);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListValue<T> && _listEquals(values, other.values);

  @override
  int get hashCode => _listHashCode(values);

  @override
  String toString() => '$values';

  // Helper methods for list comparison
  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static int _listHashCode<T>(List<T> list) {
    int hash = 0;
    for (final item in list) {
      hash ^= item.hashCode;
    }
    return hash;
  }
}

/// No value for isNull/isNotNull operations
class NoValue<T> extends FilterValue<T> {
  /// Creates a NoValue instance for null check operations
  const NoValue();

  @override
  bool operator ==(Object other) => other is NoValue<T>;

  @override
  int get hashCode => 0;

  @override
  String toString() => '';
}

/// Typed version of FilterCondition that provides compile-time type safety.
class FilterCondition<T> {
  /// The field selector with type information
  final FieldSelector<T> field;

  /// The comparison operator
  final FilterOperator operator;

  /// The typed value to compare against
  final FilterValue<T> value;

  /// Private constructor that requires proper typed value
  const FilterCondition._({
    required this.field,
    required this.operator,
    required this.value,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilterCondition &&
          runtimeType == other.runtimeType &&
          field == other.field &&
          operator == other.operator &&
          value == other.value;

  @override
  int get hashCode => field.hashCode ^ operator.hashCode ^ value.hashCode;

  @override
  String toString() =>
      'FilterCondition(field: $field, operator: $operator, '
      'value: $value)';
}

/// Typed version of SortCondition that provides compile-time safety
/// for field names.
class SortCondition<T> {
  /// The field selector with type information
  final FieldSelector<T> field;

  /// The sort direction
  final SortDirection direction;

  /// Creates a new typed sort condition.
  const SortCondition({required this.field, required this.direction});

  /// Creates an ascending sort condition.
  const SortCondition.ascending(this.field)
    : direction = SortDirection.ascending;

  /// Creates a descending sort condition.
  const SortCondition.descending(this.field)
    : direction = SortDirection.descending;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SortCondition &&
          runtimeType == other.runtimeType &&
          field == other.field &&
          direction == other.direction;

  @override
  int get hashCode => field.hashCode ^ direction.hashCode;

  @override
  String toString() => 'SortCondition(field: $field, direction: $direction)';
}

/// Represents pagination parameters.
class PaginationParams {
  /// The maximum number of items to return
  final int? limit;

  /// The number of items to skip (offset-based pagination)
  final int? offset;

  /// Creates new pagination parameters.
  const PaginationParams({this.limit, this.offset});

  /// Creates pagination parameters for a specific page.
  ///
  /// [page] is 1-based (first page is page 1).
  /// [pageSize] is the number of items per page.
  const PaginationParams.page({required int page, required int pageSize})
    : limit = pageSize,
      offset = (page - 1) * pageSize;

  /// Creates pagination parameters with only a limit (no offset).
  const PaginationParams.limit(int this.limit) : offset = null;

  /// The page number (1-based) based on current offset and limit.
  int get page => limit != null && offset != null ? (offset! ~/ limit!) + 1 : 1;

  /// The page size (same as limit).
  int? get pageSize => limit;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaginationParams &&
          runtimeType == other.runtimeType &&
          limit == other.limit &&
          offset == other.offset;

  @override
  int get hashCode => limit.hashCode ^ offset.hashCode;

  @override
  String toString() => 'PaginationParams(limit: $limit, offset: $offset)';
}

/// Typed version of QueryParams that provides compile-time safety.
class QueryParams {
  /// List of typed filter conditions (AND logic applied between conditions)
  final List<FilterCondition> filters;

  /// List of typed sort conditions (applied in order)
  final List<SortCondition> sorts;

  /// Pagination parameters
  final PaginationParams? pagination;

  /// Creates new typed query parameters.
  const QueryParams({
    this.filters = const [],
    this.sorts = const [],
    this.pagination,
  });

  /// Creates typed query parameters with only filters.
  const QueryParams.filters(this.filters) : sorts = const [], pagination = null;

  /// Creates typed query parameters with only sorting.
  const QueryParams.sorts(this.sorts) : filters = const [], pagination = null;

  /// Creates typed query parameters with only pagination.
  const QueryParams.pagination(this.pagination)
    : filters = const [],
      sorts = const [];

  /// Creates an empty typed query parameters instance.
  static const QueryParams empty = QueryParams();

  /// Returns true if this query has any parameters.
  bool get hasParameters =>
      filters.isNotEmpty || sorts.isNotEmpty || pagination != null;

  /// Returns true if this query has filters.
  bool get hasFilters => filters.isNotEmpty;

  /// Returns true if this query has sorts.
  bool get hasSorts => sorts.isNotEmpty;

  /// Returns true if this query has pagination.
  bool get hasPagination => pagination != null;

  /// Creates a copy of this typed query parameters with the given changes.
  QueryParams copyWith({
    List<FilterCondition>? filters,
    List<SortCondition>? sorts,
    PaginationParams? pagination,
  }) {
    return QueryParams(
      filters: filters ?? this.filters,
      sorts: sorts ?? this.sorts,
      pagination: pagination ?? this.pagination,
    );
  }

  /// Creates a copy of this typed query parameters with additional filters.
  QueryParams addFilters(List<FilterCondition> additionalFilters) {
    return copyWith(filters: [...filters, ...additionalFilters]);
  }

  /// Creates a copy of this typed query parameters with additional filter.
  QueryParams addFilter(FilterCondition filter) {
    return addFilters([filter]);
  }

  /// Creates a copy of this typed query parameters with additional sorts.
  QueryParams addSorts(List<SortCondition> additionalSorts) {
    return copyWith(sorts: [...sorts, ...additionalSorts]);
  }

  /// Creates a copy of this typed query parameters with additional sort.
  QueryParams addSort(SortCondition sort) {
    return addSorts([sort]);
  }

  /// Merges this QueryParams with a required filter, removing any existing
  /// filter on the same field to prevent conflicts.
  ///
  /// This ensures that the required filter takes precedence over any
  /// user-provided filters on the same field.
  QueryParams mergeWithRequiredFilter(FilterCondition requiredFilter) {
    final filteredConditions =
        filters
            .where(
              (filter) =>
                  filter.field.fieldName != requiredFilter.field.fieldName,
            )
            .toList();

    return copyWith(filters: [...filteredConditions, requiredFilter]);
  }

  /// Creates QueryParams with a required filter, or merges with
  /// existing params.
  ///
  /// If [queryParams] is null, creates new QueryParams with just the required
  /// filter. Otherwise, merges the existing params with the required filter,
  /// removing any existing filter on the same field.
  static QueryParams withRequiredFilter(
    QueryParams? queryParams,
    FilterCondition requiredFilter,
  ) {
    if (queryParams == null) {
      return QueryParams(filters: [requiredFilter]);
    }
    return queryParams.mergeWithRequiredFilter(requiredFilter);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueryParams &&
          runtimeType == other.runtimeType &&
          _listEquals(filters, other.filters) &&
          _listEquals(sorts, other.sorts) &&
          pagination == other.pagination;

  @override
  int get hashCode =>
      _listHashCode(filters) ^ _listHashCode(sorts) ^ pagination.hashCode;

  @override
  String toString() =>
      'QueryParams('
      'filters: $filters, '
      'sorts: $sorts, '
      'pagination: $pagination)';

  // Helper methods for list comparison
  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static int _listHashCode<T>(List<T> list) {
    int hash = 0;
    for (final item in list) {
      hash ^= item.hashCode;
    }
    return hash;
  }
}

/// Extension methods for [FieldSelector] that provide compile-time type safety
/// for creating filter conditions.
extension FieldSelectorExtensions<T> on FieldSelector<T> {
  /// Creates an equals filter condition with compile-time type safety.
  FilterCondition<T> equals(T value) {
    return FilterCondition._(
      field: this,
      operator: FilterOperator.equals,
      value: SingleValue(value),
    );
  }

  /// Creates a not equals filter condition with compile-time type safety.
  FilterCondition<T> notEquals(T value) {
    return FilterCondition._(
      field: this,
      operator: FilterOperator.notEquals,
      value: SingleValue(value),
    );
  }

  /// Creates a greater than filter condition with compile-time type safety.
  FilterCondition<T> greaterThan(T value) {
    return FilterCondition._(
      field: this,
      operator: FilterOperator.greaterThan,
      value: SingleValue(value),
    );
  }

  /// Creates a greater than or equal filter condition with compile-time type
  /// safety.
  FilterCondition<T> greaterThanOrEqual(T value) {
    return FilterCondition._(
      field: this,
      operator: FilterOperator.greaterThanOrEqual,
      value: SingleValue(value),
    );
  }

  /// Creates a less than filter condition with compile-time type safety.
  FilterCondition<T> lessThan(T value) {
    return FilterCondition._(
      field: this,
      operator: FilterOperator.lessThan,
      value: SingleValue(value),
    );
  }

  /// Creates a less than or equal filter condition with compile-time type
  /// safety.
  FilterCondition<T> lessThanOrEqual(T value) {
    return FilterCondition._(
      field: this,
      operator: FilterOperator.lessThanOrEqual,
      value: SingleValue(value),
    );
  }

  /// Creates a contains filter condition with compile-time type safety.
  /// Typically used with String fields.
  FilterCondition<T> contains(T value) {
    return FilterCondition._(
      field: this,
      operator: FilterOperator.contains,
      value: SingleValue(value),
    );
  }

  /// Creates a starts with filter condition with compile-time type safety.
  /// Typically used with String fields.
  FilterCondition<T> startsWith(T value) {
    return FilterCondition._(
      field: this,
      operator: FilterOperator.startsWith,
      value: SingleValue(value),
    );
  }

  /// Creates an ends with filter condition with compile-time type safety.
  /// Typically used with String fields.
  FilterCondition<T> endsWith(T value) {
    return FilterCondition._(
      field: this,
      operator: FilterOperator.endsWith,
      value: SingleValue(value),
    );
  }

  /// Creates an in list filter condition with compile-time type safety.
  FilterCondition<T> inList(List<T> values) {
    return FilterCondition._(
      field: this,
      operator: FilterOperator.inList,
      value: ListValue(values),
    );
  }

  /// Creates a not in list filter condition with compile-time type safety.
  FilterCondition<T> notInList(List<T> values) {
    return FilterCondition._(
      field: this,
      operator: FilterOperator.notInList,
      value: ListValue(values),
    );
  }

  /// Creates an is null filter condition with compile-time type safety.
  FilterCondition<T> isNull() {
    return FilterCondition._(
      field: this,
      operator: FilterOperator.isNull,
      value: const NoValue(),
    );
  }

  /// Creates an is not null filter condition with compile-time type safety.
  FilterCondition<T> isNotNull() {
    return FilterCondition._(
      field: this,
      operator: FilterOperator.isNotNull,
      value: const NoValue(),
    );
  }
}
