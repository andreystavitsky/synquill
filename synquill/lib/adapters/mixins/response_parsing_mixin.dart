part of synquill;

/// {@template response_parsing_mixin}
/// Mixin that provides response parsing functionality for API adapters.
///
/// Handles:
/// - Parsing responses for all CRUD operations
/// - Error handling during parsing
/// - Support for different response formats
/// {@endtemplate}
mixin ResponseParsingMixin<TModel extends SynquillDataModel<TModel>>
    on ApiAdapterBase<TModel> {
  /// Logger instance for response parsing.
  Logger get logger;

  // ==========================================================================
  // Protected Response Parsing Methods
  // ==========================================================================

  /// Parses a findOne response.
  ///
  /// Override this method to customize how single resource responses are parsed
  /// (e.g., handling different response formats, extracting metadata).
  @protected
  TModel? parseFindOneResponse(dynamic responseData, Response response) {
    try {
      if (responseData == null) {
        return null;
      }

      if (responseData is! Map<String, dynamic>) {
        throw ApiException(
          'Failed to parse findOne response: Expected Map<String, dynamic>, '
          'got ${responseData.runtimeType}',
          statusCode: response.statusCode,
        );
      }

      return fromJson(responseData);
    } catch (e, st) {
      if (e is SynquillStorageException) rethrow;

      logger.severe('Error parsing findOne response', e, st);
      throw ApiException(
        'Failed to parse findOne response: $e',
        statusCode: response.statusCode,
      );
    }
  }

  /// Parses a findAll response.
  ///
  /// Override this method to customize how collection responses are parsed
  /// (e.g., handling different response formats,
  /// extracting pagination metadata).
  @protected
  List<TModel> parseFindAllResponse(dynamic responseData, Response response) {
    try {
      if (responseData == null) {
        return [];
      }

      List<dynamic> items;
      if (responseData is List) {
        items = responseData;
      } else if (responseData is Map<String, dynamic>) {
        final dataMap = responseData;
        if (dataMap.containsKey('data') && dataMap['data'] is List) {
          items = dataMap['data'] as List<dynamic>;
        } else if (dataMap.containsKey(pluralType) &&
            dataMap[pluralType] is List) {
          items = dataMap[pluralType] as List<dynamic>;
        } else {
          throw ApiException(
            'Failed to parse findAll response: Expected a list or a map '
            'containing a list under "data" or "$pluralType" key.',
            statusCode: response.statusCode,
          );
        }
      } else {
        throw ApiException(
          'Failed to parse findAll response: Unexpected response type '
          '${responseData.runtimeType}. Expected List or Map.',
          statusCode: response.statusCode,
        );
      }

      return items
          .map((item) => fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      if (e is SynquillStorageException) rethrow;

      logger.severe('Error parsing findAll response', e, st);
      throw ApiException(
        'Failed to parse findAll response: $e',
        statusCode: response.statusCode,
      );
    }
  }

  /// Parses a create response.
  ///
  /// Override this method to customize how creation responses are parsed
  /// (e.g., handling different response formats, extracting metadata).
  @protected
  TModel? parseCreateResponse(dynamic responseData, Response response) {
    try {
      if (responseData == null) {
        // For 204 No Content, data will be null. This is a valid success.
        return null;
      }

      if (responseData is! Map<String, dynamic>) {
        throw ApiException(
          'Failed to parse create response: Expected Map<String, dynamic>, '
          'got ${responseData.runtimeType}',
          statusCode: response.statusCode,
        );
      }

      return fromJson(responseData);
    } catch (e, st) {
      if (e is SynquillStorageException) rethrow;

      logger.severe('Error parsing create response', e, st);
      throw ApiException(
        'Failed to parse create response: $e',
        statusCode: response.statusCode,
      );
    }
  }

  /// Parses an update response.
  ///
  /// Override this method to customize how update responses are parsed
  /// (e.g., handling different response formats, extracting metadata).
  @protected
  TModel? parseUpdateResponse(dynamic responseData, Response response) {
    try {
      if (responseData == null) {
        return null;
      }

      if (responseData is! Map<String, dynamic>) {
        throw ApiException(
          'Failed to parse update response: Expected Map<String, dynamic>, '
          'got ${responseData.runtimeType}',
          statusCode: response.statusCode,
        );
      }

      return fromJson(responseData);
    } catch (e, st) {
      if (e is SynquillStorageException) rethrow;

      logger.severe('Error parsing update response', e, st);
      throw ApiException(
        'Failed to parse update response: $e',
        statusCode: response.statusCode,
      );
    }
  }

  /// Parses a replace response.
  ///
  /// Override this method to customize how replace responses are parsed
  /// (e.g., handling different response formats, extracting metadata).
  @protected
  TModel? parseReplaceResponse(dynamic responseData, Response response) {
    try {
      if (responseData == null) {
        return null;
      }

      if (responseData is! Map<String, dynamic>) {
        throw ApiException(
          'Failed to parse replace response: Expected Map<String, dynamic>, '
          'got ${responseData.runtimeType}',
          statusCode: response.statusCode,
        );
      }

      return fromJson(responseData);
    } catch (e, st) {
      if (e is SynquillStorageException) rethrow;

      logger.severe('Error parsing replace response', e, st);
      throw ApiException(
        'Failed to parse replace response: $e',
        statusCode: response.statusCode,
      );
    }
  }
}
