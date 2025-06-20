part of synquill;

/// {@template server_id_handling_mixin}
/// Mixin that provides enhanced create response handling
/// for server-generated IDs.
///
/// This mixin extends the standard API adapter functionality to handle cases
/// where the server assigns IDs to newly created resources. It automatically
/// detects when a model uses server-generated IDs and triggers the ID
/// negotiation process when necessary.
///
/// Features:
/// - Automatic detection of server-generated ID models
/// - ID replacement when server assigns different ID
/// - Proper event emission for ID changes
/// - Integration with existing error handling
///
/// Usage:
/// ```dart
/// class MyApiAdapter extends BasicApiAdapter<MyModel>
///     with ServerIdHandlingMixin<MyModel> {
///   @override
///   Uri get baseUrl => Uri.parse('https://api.example.com/');
///
///   // The mixin automatically handles server ID responses
/// }
/// ```
/// {@endtemplate}
mixin ServerIdHandlingMixin<TModel extends SynquillDataModel<TModel>>
    on ApiAdapterBase<TModel>, ResponseParsingMixin<TModel> {
  /// Handles create operations with optional server ID negotiation.
  ///
  /// This method enhances the standard createOne operation to handle
  /// server-generated IDs. If the model uses server-generated IDs and
  /// the server response contains a different ID than the client-generated
  /// temporary ID, it triggers the ID replacement process.
  @override
  Future<TModel?> createOne(
    TModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    // Execute the standard create request
    final result = await super.createOne(
      model,
      headers: headers,
      extra: extra,
    );

    // Check if ID negotiation is needed (server assigned different ID)
    if (result != null && result.id != model.id) {
      // Server assigned a different ID - this triggers
      // the ID negotiation process
      // The actual ID replacement is handled by the repository layer
      logger.info(
        'Server assigned ID ${result.id} for model with temporary ID '
        '${model.id}',
      );

      // Return the model with the server-assigned ID
      // The repository layer will handle the ID replacement in database
      // and relationships
      return result;
    }

    // For client-generated IDs or when server uses the same ID, return as-is
    return result;
  }

  /// Extracts server-assigned ID from create response.
  ///
  /// This method can be overridden to handle custom response formats
  /// where the server ID might be in a different location or format.
  ///
  /// The default implementation assumes the ID is in the standard 'id' field
  /// of the response JSON.
  @protected
  String? extractServerAssignedId(
    Map<String, dynamic> responseData,
    TModel originalModel,
  ) {
    return responseData['id'] as String?;
  }

  /// Validates that a server-assigned ID is acceptable.
  ///
  /// Override this method to implement custom validation logic for
  /// server-assigned IDs (e.g., format validation, collision checking).
  ///
  /// The default implementation accepts any non-null, non-empty string.
  @protected
  bool isValidServerAssignedId(String serverId, TModel originalModel) {
    return serverId.isNotEmpty;
  }

  /// Handles server ID assignment errors.
  ///
  /// This method is called when the server response is invalid or
  /// the server-assigned ID is not acceptable. Override to implement
  /// custom error handling strategies.
  @protected
  void handleServerIdError(
    String error,
    TModel originalModel,
    dynamic responseData,
  ) {
    logger.severe(
      'Server ID assignment error for ${originalModel.id}: $error',
    );
    throw ApiException(
      'Server ID assignment failed: $error',
      statusCode: null,
    );
  }

  /// Enhanced create response parsing with server ID handling.
  ///
  /// This method extends the standard response parsing to handle
  /// server-generated IDs properly.
  @protected
  TModel? parseCreateResponseWithServerIdHandling(
    dynamic responseData,
    Response response,
    TModel originalModel,
  ) {
    try {
      if (responseData == null) {
        // For 204 No Content, data will be null. This is valid for some APIs.
        return null;
      }

      if (responseData is! Map<String, dynamic>) {
        throw ApiException(
          'Failed to parse create response: Expected Map<String, dynamic>, '
          'got ${responseData.runtimeType}',
          statusCode: response.statusCode,
        );
      }

      // Extract server-assigned ID if applicable
      // Note: We check if server assigned a different ID than the original
      final resultModel = fromJson(responseData);
      if (resultModel.id != originalModel.id) {
        final serverAssignedId = resultModel.id;

        if (!isValidServerAssignedId(serverAssignedId, originalModel)) {
          handleServerIdError(
            'Invalid server-assigned ID format: $serverAssignedId',
            originalModel,
            responseData,
          );
          return null;
        }

        // Server assigned a valid ID - update the response data
        final updatedResponseData = Map<String, dynamic>.from(responseData);
        updatedResponseData['id'] = serverAssignedId;

        logger.fine(
          'Server assigned ID $serverAssignedId for temporary ID '
          '${originalModel.id}',
        );

        return fromJson(updatedResponseData);
      } else {
        // Server didn't assign an ID - this might be an error
        // or expected behavior
        logger.warning(
          'Server did not assign ID for server-generated ID model '
          '${originalModel.id}',
        );
      }

      // Standard parsing for client-generated IDs or when server
      // doesn't assign ID
      return fromJson(responseData);
    } catch (e, st) {
      if (e is SynquillStorageException) rethrow;

      logger.severe(
          'Error parsing create response with server ID handling', e, st);
      throw ApiException(
        'Failed to parse create response: $e',
        statusCode: response.statusCode,
      );
    }
  }
}
