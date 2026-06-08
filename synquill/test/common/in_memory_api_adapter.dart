import 'dart:async';

import 'package:synquill/synquill.dart';

typedef InMemoryFromJson<TModel extends SynquillDataModel<TModel>> = TModel
    Function(Map<String, dynamic> json);

typedef InMemoryToJson<TModel extends SynquillDataModel<TModel>>
    = Map<String, dynamic> Function(TModel model);

typedef InMemoryOperationLabeler<TModel extends SynquillDataModel<TModel>>
    = String Function(InMemoryApiOperation<TModel> operation);

class InMemoryApiOperation<TModel extends SynquillDataModel<TModel>> {
  const InMemoryApiOperation({
    required this.name,
    this.id,
    this.model,
    this.headers,
    this.queryParams,
    this.extra,
  });

  final String name;
  final String? id;
  final TModel? model;
  final Map<String, String>? headers;
  final QueryParams? queryParams;
  final Map<String, dynamic>? extra;
}

class InMemoryApiAdapter<TModel extends SynquillDataModel<TModel>>
    extends ApiAdapterBase<TModel> {
  InMemoryApiAdapter({
    required String type,
    required String pluralType,
    required InMemoryFromJson<TModel> fromJsonFactory,
    required InMemoryToJson<TModel> toJsonFactory,
    Uri? baseUrl,
    Duration operationDelay = const Duration(milliseconds: 10),
    InMemoryOperationLabeler<TModel>? operationLabeler,
  })  : _type = type,
        _pluralType = pluralType,
        _fromJsonFactory = fromJsonFactory,
        _toJsonFactory = toJsonFactory,
        _baseUrl = baseUrl ?? Uri.parse('https://test.example.com/api/v1/'),
        _operationDelay = operationDelay,
        _operationLabeler = operationLabeler ?? _defaultOperationLabel;

  final Map<String, TModel> _remoteData = {};
  final List<String> _operationLog = [];
  final String _type;
  final String _pluralType;
  final InMemoryFromJson<TModel> _fromJsonFactory;
  final InMemoryToJson<TModel> _toJsonFactory;
  final Uri _baseUrl;
  final Duration _operationDelay;
  final InMemoryOperationLabeler<TModel> _operationLabeler;

  bool _shouldFailNext = false;
  String? _nextFailureReason;
  bool _networkError = false;

  @override
  Uri get baseUrl => _baseUrl;

  @override
  String get type => _type;

  @override
  String get pluralType => _pluralType;

  List<String> get operationLog => List.unmodifiable(_operationLog);

  Map<String, TModel> get remoteData => Map.unmodifiable(_remoteData);

  Map<String, TModel> get remoteDataStore => _remoteData;

  List<String> get operationLogStore => _operationLog;

  void addRemoteModel(TModel model) {
    _remoteData[model.id] = model;
  }

  void clearRemote() {
    _remoteData.clear();
  }

  void clearLog() {
    _operationLog.clear();
  }

  void clearAll() {
    clearRemote();
    clearLog();
  }

  void failNextOperation([String? reason]) {
    _shouldFailNext = true;
    _nextFailureReason = reason ?? 'Mock failure';
  }

  void setNextOperationToFail([String? reason]) {
    failNextOperation(reason);
  }

  void setNetworkError(bool error) {
    _networkError = error;
  }

  @override
  TModel fromJson(Map<String, dynamic> json) => _fromJsonFactory(json);

  @override
  Map<String, dynamic> toJson(TModel model) => _toJsonFactory(model);

  TModel? createRemoteModel(TModel model) => model;

  FutureOr<void> beforeOperation(InMemoryApiOperation<TModel> operation) {
    if (_networkError) {
      throw DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.connectionError,
        message: 'Network error',
      );
    }
    if (_shouldFailNext) {
      _shouldFailNext = false;
      final reason = _nextFailureReason ?? 'Mock failure';
      _nextFailureReason = null;
      throw SynquillStorageException(reason);
    }
  }

  @override
  Future<TModel?> findOne(
    String id, {
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    final operation = InMemoryApiOperation<TModel>(
      name: 'findOne',
      id: id,
      headers: headers,
      queryParams: queryParams,
      extra: extra,
    );
    await _runBeforeRemoteMutation(operation);
    return _remoteData[id];
  }

  @override
  Future<List<TModel>> findAll({
    Map<String, String>? headers,
    QueryParams? queryParams,
    Map<String, dynamic>? extra,
  }) async {
    final operation = InMemoryApiOperation<TModel>(
      name: 'findAll',
      headers: headers,
      queryParams: queryParams,
      extra: extra,
    );
    await _runBeforeRemoteMutation(operation);
    return _remoteData.values.toList();
  }

  @override
  Future<TModel?> createOne(
    TModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final operation = InMemoryApiOperation<TModel>(
      name: 'createOne',
      model: model,
      headers: headers,
      extra: extra,
    );
    await _runBeforeRemoteMutation(operation);
    final created = createRemoteModel(model);
    if (created != null) {
      _remoteData[created.id] = created;
    }
    return created;
  }

  @override
  Future<TModel?> updateOne(
    TModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final operation = InMemoryApiOperation<TModel>(
      name: 'updateOne',
      model: model,
      headers: headers,
      extra: extra,
    );
    await _runBeforeRemoteMutation(operation);
    _remoteData[model.id] = model;
    return model;
  }

  @override
  Future<TModel?> replaceOne(
    TModel model, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final operation = InMemoryApiOperation<TModel>(
      name: 'replaceOne',
      model: model,
      headers: headers,
      extra: extra,
    );
    await _runBeforeRemoteMutation(operation);
    _remoteData[model.id] = model;
    return model;
  }

  @override
  Future<void> deleteOne(
    String id, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    final operation = InMemoryApiOperation<TModel>(
      name: 'deleteOne',
      id: id,
      headers: headers,
      extra: extra,
    );
    await _runBeforeRemoteMutation(operation);
    _remoteData.remove(id);
  }

  Future<void> _runBeforeRemoteMutation(
    InMemoryApiOperation<TModel> operation,
  ) async {
    _operationLog.add(_operationLabeler(operation));
    await beforeOperation(operation);
    if (_operationDelay > Duration.zero) {
      await Future.delayed(_operationDelay);
    }
  }

  static String
      _defaultOperationLabel<TModel extends SynquillDataModel<TModel>>(
    InMemoryApiOperation<TModel> operation,
  ) {
    final model = operation.model;
    return switch (operation.name) {
      'findOne' => 'findOne(${operation.id})',
      'findAll' => 'findAll()',
      'createOne' => 'createOne(${model?.id})',
      'updateOne' => 'updateOne(${model?.id})',
      'replaceOne' => 'replaceOne(${model?.id})',
      'deleteOne' => 'deleteOne(${operation.id})',
      _ => operation.name,
    };
  }
}
