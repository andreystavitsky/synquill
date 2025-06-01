part of synquill;

/// {@template api_adapter}
/// Abstract interface for REST API adapters used by SyncedDataStorage.
///
/// Each adapter provides HTTP configuration, URL builders, and CRUD methods
/// for a specific model type. All HTTP-related configuration can be overridden
/// by subclasses to customize behavior per model.
///
/// {@endtemplate}
abstract class ApiAdapterBase<TModel extends SynquillDataModel<TModel>> {
  /// Base URL for the API.
  /// Must be provided by concrete implementations.
  /// Example: `Uri.parse('https://api.example.com/v1/')`
  Uri get baseUrl;

  /// HTTP headers applied to every request.
  /// Can be overridden in subclasses for model-specific headers.
  ///
  /// Default implementation provides standard JSON headers.
  /// Can be async to allow for dynamic header generation (e.g., auth tokens).
  FutureOr<Map<String, String>> get baseHeaders => const {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// Logical entity name, singular.
  ///
  /// Defaults to the lowercase string representation of type TModel.
  /// Override in subclasses for custom entity names.
  ///
  /// Example: if TModel is `UserEvent`, returns `userevent`.
  /// Example: if TModel is `TodoItem`, returns `todoitem`.
  String get type => TModel.toString().toLowerCase();

  /// Plural form of the entity name for collection endpoints.
  ///
  /// Defaults to adding 's' to the singular type.
  /// Override in subclasses for irregular plurals.
  ///
  /// Example: `events`, `todos`, `users`
  String get pluralType => '${type}s';

  // HTTP Method Configuration
  // These provide defaults but can be overridden per model

  /// HTTP method used by `findOne` / `findAll` operations.
  /// Default: 'GET'
  String methodForFind({Map<String, dynamic>? extra}) => 'GET';

  /// HTTP method for creating a new entity.
  /// Default: 'POST'
  String methodForCreate({Map<String, dynamic>? extra}) => 'POST';

  /// HTTP method for partial updates.
  /// Default: 'PATCH'
  String methodForUpdate({Map<String, dynamic>? extra}) => 'PATCH';

  /// HTTP method for deleting an entity.
  /// Default: 'DELETE'
  String methodForDelete({Map<String, dynamic>? extra}) => 'DELETE';

  /// HTTP method for full replacement.
  /// Default: 'PUT'
  String methodForReplace({Map<String, dynamic>? extra}) => 'PUT';

  // Following proper plural/singular conventions

  /// Constructs the URL for fetching/updating/deleting a single model instance.
  ///
  /// Uses singular entity name + ID.
  /// Example: `baseUrl.resolve('event/some-id')`
  FutureOr<Uri> urlForFindOne(String id, {Map<String, dynamic>? extra}) async =>
      baseUrl.resolve('$type/$id');

  /// Constructs the URL for fetching all model instances.
  ///
  /// Uses plural entity name as per REST conventions.
  /// Example: `baseUrl.resolve('events')`
  FutureOr<Uri> urlForFindAll({Map<String, dynamic>? extra}) async =>
      baseUrl.resolve(pluralType);

  /// Constructs the URL for creating a new model instance.
  ///
  /// Uses plural entity name for collection endpoint.
  /// Example: `baseUrl.resolve('events')`
  FutureOr<Uri> urlForCreate({Map<String, dynamic>? extra}) async =>
      baseUrl.resolve(pluralType);

  /// Constructs the URL for updating an existing model instance.
  ///
  /// Uses singular entity name + ID.
  /// Example: `baseUrl.resolve('event/some-id')`
  FutureOr<Uri> urlForUpdate(String id, {Map<String, dynamic>? extra}) async =>
      baseUrl.resolve('$type/$id');

  /// Constructs the URL for replacing an existing model instance.
  ///
  /// Uses singular entity name + ID.
  /// Example: `baseUrl.resolve('event/some-id')`
  FutureOr<Uri> urlForReplace(String id, {Map<String, dynamic>? extra}) async =>
      baseUrl.resolve('$type/$id');

  /// Constructs the URL for deleting a model instance.
  ///
  /// Uses singular entity name + ID.
  /// Example: `baseUrl.resolve('event/some-id')`
  FutureOr<Uri> urlForDelete(String id, {Map<String, dynamic>? extra}) async =>
      baseUrl.resolve('$type/$id');

  /// Converts a JSON map to an instance of the model [TModel].
  ///
  /// This method must be implemented by subclasses to handle the
  /// specific structure of their data.
  TModel fromJson(Map<String, dynamic> json);

  /// Converts a model instance to a JSON map for API requests.
  ///
  /// This method must be implemented by subclasses to handle the
  /// specific structure of their data.
  Map<String, dynamic> toJson(TModel model);

  /// Fetches a single item by its ID from the remote API.
  ///
  /// Uses [methodForFind] and [urlForFindOne] for the HTTP request.
  /// Throws a [NotFoundException] if no item is found with the given ID.
  ///
  /// [headers] can override default headers for this specific request.
  /// [queryParams] can be used to filter the results on the server side.
  Future<TModel?> findOne(
    String id, {
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic> extra,
  });

  /// Fetches all items from the remote API.
  ///
  /// Uses [methodForFind] and [urlForFindAll] for the HTTP request.
  /// [headers] can override default headers for this specific request.
  /// [queryParams] can be used to filter, sort, and paginate the results
  /// on the server side.
  Future<List<TModel>> findAll({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic> extra,
  });

  /// Creates a new item on the remote API.
  ///
  /// Uses [methodForCreate] and [urlForCreate] for the HTTP request.
  /// [headers] can override default headers for this specific request.
  Future<TModel?> createOne(
    TModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  });

  /// Updates an existing item on the remote API using partial update.
  ///
  /// Uses [methodForUpdate] and [urlForUpdate] for the HTTP request.
  /// [headers] can override default headers for this specific request.
  Future<TModel?> updateOne(
    TModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  });

  /// Replaces an existing item on the remote API with full replacement.
  ///
  /// Uses [methodForReplace] and [urlForReplace] for the HTTP request.
  /// [headers] can override default headers for this specific request.
  Future<TModel?> replaceOne(
    TModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  });

  /// Deletes an item by its ID from the remote API.
  ///
  /// Uses [methodForDelete] and [urlForDelete] for the HTTP request.
  /// Throws a [NotFoundException] if no item is found with the given ID.
  /// [headers] can override default headers for this specific request.
  Future<void> deleteOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  });

  /// Merges base headers with request-specific headers.
  ///
  /// Request-specific headers take precedence over base headers.
  /// Utility method for concrete implementations.
  FutureOr<Map<String, String>> mergeHeaders(
    Map<String, String>? requestHeaders, {
    Map<String, dynamic>? extra,
  }) async {
    final base = await baseHeaders;
    if (requestHeaders == null) return base;
    return {...base, ...requestHeaders};
  }

  /// Converts QueryParams to HTTP query parameters.
  ///
  /// This method provides a default implementation that can be overridden
  /// by subclasses to customize how query parameters are formatted for
  /// their specific API.
  ///
  /// Default format:
  /// - Filters: `filter[field][operator]=value`
  /// - Sorts: `sort=field:direction,field2:direction`
  /// - Pagination: `limit=X&offset=Y`
  ///
  /// Examples:
  /// - `filter[name][equals]=John`
  /// - `filter[age][greaterThan]=18`
  /// - `filter[tags][inList]=tag1,tag2,tag3`
  /// - `sort=name:asc,createdAt:desc`
  /// - `limit=20&offset=40`
  Map<String, String> queryParamsToHttpParams(QueryParams? queryParams) {
    if (queryParams == null) return {};

    final Map<String, String> httpParams = {};

    // Handle filters
    for (final filter in queryParams.filters) {
      final fieldName = filter.field.fieldName;
      final operator = _filterOperatorToString(filter.operator);
      final value = _filterValueToString(filter.value);

      // Always include null check operators and string comparison operators
      // even with empty values, as they may be meaningful for API queries
      final shouldIncludeEmptyValue =
          filter.operator == FilterOperator.isNull ||
          filter.operator == FilterOperator.isNotNull ||
          filter.operator == FilterOperator.equals ||
          filter.operator == FilterOperator.notEquals ||
          filter.operator == FilterOperator.contains ||
          filter.operator == FilterOperator.startsWith ||
          filter.operator == FilterOperator.endsWith;

      if (value.isNotEmpty || shouldIncludeEmptyValue) {
        httpParams['filter[$fieldName][$operator]'] = value;
      }
    }

    // Handle sorting
    if (queryParams.sorts.isNotEmpty) {
      final sortValues = queryParams.sorts
          .map((sort) {
            final fieldName = sort.field.fieldName;
            final direction =
                sort.direction == SortDirection.ascending ? 'asc' : 'desc';
            return '$fieldName:$direction';
          })
          .join(',');
      httpParams['sort'] = sortValues;
    }

    // Handle pagination
    if (queryParams.pagination != null) {
      final pagination = queryParams.pagination!;
      if (pagination.limit != null) {
        httpParams['limit'] = pagination.limit.toString();
      }
      if (pagination.offset != null) {
        httpParams['offset'] = pagination.offset.toString();
      }
    }

    return httpParams;
  }

  /// Converts FilterOperator to string representation for HTTP parameters.
  ///
  /// Can be overridden by subclasses to customize operator names.
  String _filterOperatorToString(FilterOperator operator) {
    switch (operator) {
      case FilterOperator.equals:
        return 'equals';
      case FilterOperator.notEquals:
        return 'notEquals';
      case FilterOperator.greaterThan:
        return 'greaterThan';
      case FilterOperator.greaterThanOrEqual:
        return 'greaterThanOrEqual';
      case FilterOperator.lessThan:
        return 'lessThan';
      case FilterOperator.lessThanOrEqual:
        return 'lessThanOrEqual';
      case FilterOperator.contains:
        return 'contains';
      case FilterOperator.startsWith:
        return 'startsWith';
      case FilterOperator.endsWith:
        return 'endsWith';
      case FilterOperator.inList:
        return 'inList';
      case FilterOperator.notInList:
        return 'notInList';
      case FilterOperator.isNull:
        return 'isNull';
      case FilterOperator.isNotNull:
        return 'isNotNull';
    }
  }

  /// Converts FilterValue to string representation for HTTP parameters.
  String _filterValueToString(FilterValue value) {
    switch (value) {
      case SingleValue<dynamic>():
        return _valueToString(value.value);
      case ListValue<dynamic>():
        return value.values.map(_valueToString).join(',');
      case NoValue<dynamic>():
        return '';
    }
  }

  /// Converts a single value to string representation.
  String _valueToString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is DateTime) return value.toIso8601String();
    return value.toString();
  }
}
