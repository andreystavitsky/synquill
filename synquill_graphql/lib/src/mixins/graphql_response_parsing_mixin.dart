import 'package:meta/meta.dart';
import 'package:synquill/synquill.dart';

/// Mixin for parsing GraphQL responses into [SynquillDataModel] objects.
mixin GraphQLResponseParsingMixin<TModel extends SynquillDataModel<TModel>>
    on ApiAdapterBase<TModel> {
  /// Logger for parsing actions.
  Logger get logger;

  /// Extracts and parses a single model from a named GraphQL field.
  @protected
  TModel? parseFindOneGraphQLResponse(
    Map<String, dynamic> data,
    String fieldName,
  ) {
    return _parseSingle(data, fieldName, 'findOne');
  }

  /// Extracts and parses a list of models from a named GraphQL field.
  @protected
  List<TModel> parseFindAllGraphQLResponse(
    Map<String, dynamic> data,
    String fieldName,
  ) {
    try {
      if (!data.containsKey(fieldName)) {
        return [];
      }
      final value = data[fieldName];
      if (value == null) {
        return [];
      }
      if (value is! List) {
        throw ApiException(
          'Failed to parse findAll response: Expected List '
          'under key "$fieldName", got ${value.runtimeType}',
        );
      }
      return value.map((item) {
        if (item is! Map<String, dynamic>) {
          throw ApiException(
            'Failed to parse findAll response: Expected list item of type '
            'Map<String, dynamic>, got ${item.runtimeType}',
          );
        }
        return fromJson(item);
      }).toList();
    } catch (e, st) {
      if (e is SynquillStorageException) rethrow;
      logger.severe('Error parsing findAll response', e, st);
      throw ApiException('Failed to parse findAll response: $e');
    }
  }

  /// Extracts and parses a single model from a create mutation response field.
  @protected
  TModel? parseCreateGraphQLResponse(
    Map<String, dynamic> data,
    String fieldName,
  ) {
    return _parseSingle(data, fieldName, 'create');
  }

  /// Extracts and parses a single model from an update mutation response field.
  @protected
  TModel? parseUpdateGraphQLResponse(
    Map<String, dynamic> data,
    String fieldName,
  ) {
    return _parseSingle(data, fieldName, 'update');
  }

  /// Extracts and parses a single model from a replace mutation response field.
  @protected
  TModel? parseReplaceGraphQLResponse(
    Map<String, dynamic> data,
    String fieldName,
  ) {
    return _parseSingle(data, fieldName, 'replace');
  }

  TModel? _parseSingle(
    Map<String, dynamic> data,
    String fieldName,
    String opName,
  ) {
    try {
      if (!data.containsKey(fieldName)) {
        return null;
      }
      final value = data[fieldName];
      if (value == null) {
        return null;
      }
      if (value is! Map<String, dynamic>) {
        throw ApiException(
          'Failed to parse $opName response: Expected Map<String, dynamic> '
          'under key "$fieldName", got ${value.runtimeType}',
        );
      }
      return fromJson(value);
    } catch (e, st) {
      if (e is SynquillStorageException) rethrow;
      logger.severe('Error parsing $opName response', e, st);
      throw ApiException('Failed to parse $opName response: $e');
    }
  }
}
