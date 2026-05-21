import 'dart:async';
import 'dart:convert' as convert;
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:synquill/src/adapters/api_adapter.dart';
import 'package:synquill/src/adapters/realtime_api_adapter.dart';
import 'package:synquill/src/core/exceptions.dart';
import 'package:synquill/src/core/query_parameters.dart';
import 'package:synquill/src/core/realtime_event.dart';
import 'package:synquill/src/core/repository_mixins/repository_delete_operations.dart';
import 'package:synquill/src/core/repository_mixins/repository_local_operations.dart';
import 'package:synquill/src/core/repository_mixins/repository_types.dart';
import 'package:synquill/src/core/synquill_data_model.dart';
import 'package:synquill/src/core/synquill_storage.dart';
import 'package:synquill/src/drift/sync_queue_dao.dart';

/// Adds transport-neutral realtime subscription handling to repositories.
mixin RepositoryRealtimeOperations<T extends SynquillDataModel<T>>
    on RepositoryLocalOperations<T>, RepositoryDeleteOperations<T> {
  final Map<_RealtimeSubscriptionKey, _ActiveRealtimeSubscription<T>>
      _activeRealtimeSubscriptions = {};
  final math.Random _realtimeJitterRandom = math.Random();

  /// The logger instance for this repository.
  @override
  Logger get log;

  /// The generated database instance for this repository.
  GeneratedDatabase get db;

  /// The API adapter used for remote operations.
  @override
  ApiAdapterBase<T> get apiAdapter;

  /// The stream controller for repository change events.
  @override
  StreamController<RepositoryChange<T>> get changeController;

  /// Wraps a local watch stream and ties a remote realtime subscription to
  /// the returned stream's lifecycle.
  @protected
  Stream<TResult> watchLocalWithRealtime<TResult>(
    Stream<TResult> localStream, {
    required String scope,
    String? id,
    QueryParams? queryParams,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
    bool retryOnFail = true,
  }) {
    _realtimeAdapterOrThrow();

    late final StreamController<TResult> controller;
    StreamSubscription<TResult>? localSubscription;
    _RealtimeSubscriptionKey? key;

    controller = StreamController<TResult>(
      onListen: () {
        key = _retainRealtimeSubscription(
          scope: scope,
          id: id,
          queryParams: queryParams,
          headers: headers,
          extra: extra,
          retryOnFail: retryOnFail,
        );

        localSubscription = localStream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onPause: () {
        localSubscription?.pause();
      },
      onResume: () {
        localSubscription?.resume();
      },
      onCancel: () async {
        await localSubscription?.cancel();
        final activeKey = key;
        if (activeKey != null) {
          await _releaseRealtimeSubscription(activeKey,
              retryOnFail: retryOnFail);
        }
      },
    );

    return controller.stream;
  }

  /// Applies one realtime event to the local cache.
  @protected
  Future<void> applyRealtimeEvent(
    RealtimeEvent<T> event, {
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) async {
    if (event.type == RealtimeEventType.deleted) {
      if (await hasPendingRealtimeSync(event.id)) {
        log.fine(
          'Skipping realtime deleted for $T ${event.id}: '
          'local sync is pending.',
        );
        return;
      }
      await applyRealtimeDelete(
        event.id,
        event: event,
        headers: headers,
        extra: extra,
      );
      return;
    }

    T? itemToEmit;
    await db.transaction(() async {
      if (await hasPendingRealtimeSync(event.id)) {
        log.fine(
          'Skipping realtime ${event.type.name} for $T ${event.id}: '
          'local sync is pending.',
        );
        return;
      }

      final item = _requireRealtimeItem(event);
      await saveToLocal(item, extra: extra);
      itemToEmit = item;
    });

    final committedItem = itemToEmit;
    if (committedItem != null && !changeController.isClosed) {
      if (event.type == RealtimeEventType.created) {
        changeController.add(RepositoryChange.created(committedItem));
      } else {
        changeController.add(RepositoryChange.updated(committedItem));
      }
    }
  }

  /// Applies a realtime delete event.
  ///
  /// Override this when a transport uses semantics other than hard server-side
  /// deletion, such as soft deletes.
  @protected
  Future<void> applyRealtimeDelete(
    String id, {
    RealtimeEvent<T>? event,
    Map<String, String>? headers,
    Map<String, dynamic>? extra,
  }) {
    return handleCascadeDeleteAfterGone(id, headers: headers, extra: extra);
  }

  /// Returns whether a local sync task is pending for [id].
  @protected
  Future<bool> hasPendingRealtimeSync(String id) async {
    final pendingTasks = await SyncQueueDao(db).getTasksForModelId(
      T.toString(),
      id,
    );
    return pendingTasks.isNotEmpty;
  }

  /// Whether [error] should retry the realtime subscription.
  @protected
  bool isRealtimeRetryableError(Object error) {
    if (error is TimeoutException) return true;
    if (error is OfflineException) return true;
    if (error is NetworkException) return true;
    if (error is ServerException) return true;
    if (error is ApiException) {
      final statusCode = error.statusCode;
      return statusCode != null && statusCode >= 500;
    }
    return false;
  }

  /// Calculates the next realtime retry delay.
  @protected
  Duration realtimeRetryDelay(int attemptNumber) {
    final config = SynquillStorage.config ?? const SynquillStorageConfig();
    final baseDelayMs = (config.initialRetryDelay.inMilliseconds *
            math.pow(config.backoffMultiplier, attemptNumber - 1))
        .round();
    final cappedMs = math.min(baseDelayMs, config.maxRetryDelay.inMilliseconds);
    final flooredMs = math.max(cappedMs, config.minRetryDelay.inMilliseconds);

    if (config.jitterPercent <= 0) {
      return Duration(milliseconds: flooredMs);
    }

    final jitterRange = flooredMs * config.jitterPercent;
    final jitterOffset =
        ((_realtimeJitterRandom.nextDouble() * 2) - 1) * jitterRange;
    final jitteredMs = (flooredMs + jitterOffset).round();
    final finalMs = math.max(jitteredMs, config.minRetryDelay.inMilliseconds);
    return Duration(milliseconds: finalMs);
  }

  /// Disposes all active realtime subscriptions owned by this repository.
  Future<void> disposeRealtimeSubscriptions() async {
    final activeSubscriptions = _activeRealtimeSubscriptions.values.toList();
    _activeRealtimeSubscriptions.clear();
    await Future.wait(
      activeSubscriptions.map((subscription) => subscription.dispose()),
    );
  }

  RealtimeApiAdapter<T> _realtimeAdapterOrThrow() {
    final adapter = apiAdapter;
    if (adapter is RealtimeApiAdapter<T>) {
      return adapter as RealtimeApiAdapter<T>;
    }
    throw SynquillStorageException(
      'watchRemote requires apiAdapter for $T to implement '
      'RealtimeApiAdapter<$T>.',
    );
  }

  _RealtimeSubscriptionKey _retainRealtimeSubscription({
    required String scope,
    required String? id,
    required QueryParams? queryParams,
    required Map<String, String>? headers,
    required Map<String, dynamic>? extra,
    required bool retryOnFail,
  }) {
    final key = _RealtimeSubscriptionKey(
      modelType: T.toString(),
      scope: scope,
      id: id,
      queryParamsKey: _canonicalQueryParamsKey(queryParams),
      headersKey: _canonicalMapKey(headers),
      extraKey: _canonicalMapKey(extra),
    );

    final existing = _activeRealtimeSubscriptions[key];
    if (existing != null) {
      existing.listenerCount++;
      if (retryOnFail) {
        existing.retryOnFailCount++;
      }
      return key;
    }

    final active = _ActiveRealtimeSubscription<T>(
      key: key,
      id: id,
      queryParams: queryParams,
      headers: headers,
      extra: extra,
      retryOnFail: retryOnFail,
    );
    _activeRealtimeSubscriptions[key] = active;
    _startRealtimeSubscription(active);
    return key;
  }

  Future<void> _releaseRealtimeSubscription(
    _RealtimeSubscriptionKey key, {
    required bool retryOnFail,
  }) async {
    final active = _activeRealtimeSubscriptions[key];
    if (active == null) return;

    active.listenerCount--;
    if (retryOnFail) {
      active.retryOnFailCount = math.max(0, active.retryOnFailCount - 1);
    }
    if (active.listenerCount > 0) return;

    _activeRealtimeSubscriptions.remove(key);
    await active.dispose();
  }

  void _startRealtimeSubscription(_ActiveRealtimeSubscription<T> active) {
    if (active.disposed) return;

    try {
      final adapter = _realtimeAdapterOrThrow();
      active.subscription = adapter
          .subscribeEvents(
        id: active.id,
        queryParams: active.queryParams,
        headers: active.headers,
        extra: active.extra,
      )
          .listen(
        (event) {
          unawaited(_handleRealtimeEvent(active, event));
        },
        onError: (Object error, StackTrace stackTrace) {
          _handleRealtimeFailure(active, error, stackTrace);
        },
        onDone: () {
          if (!active.disposed &&
              active.subscription != null &&
              active.retryTimer == null) {
            _handleRealtimeFailure(
              active,
              NetworkException('Realtime subscription ended.'),
              StackTrace.current,
            );
          }
        },
      );
    } catch (error, stackTrace) {
      _handleRealtimeFailure(active, error, stackTrace);
    }
  }

  Future<void> _handleRealtimeEvent(
    _ActiveRealtimeSubscription<T> active,
    RealtimeEvent<T> event,
  ) async {
    try {
      active.retryAttempt = 0;
      await applyRealtimeEvent(
        event,
        headers: active.headers,
        extra: active.extra,
      );
    } catch (error, stackTrace) {
      _handleRealtimeFailure(active, error, stackTrace);
    }
  }

  void _handleRealtimeFailure(
    _ActiveRealtimeSubscription<T> active,
    Object error,
    StackTrace stackTrace,
  ) {
    if (active.disposed) return;

    final retryable = active.retryOnFail && isRealtimeRetryableError(error);
    if (!changeController.isClosed) {
      changeController.add(
        RepositoryChange.realtimeError(
          error,
          stackTrace: stackTrace,
          isRetriable: retryable,
        ),
      );
    }

    unawaited(active.subscription?.cancel());
    active.subscription = null;
    active.retryTimer?.cancel();
    active.retryTimer = null;

    if (!retryable) {
      _activeRealtimeSubscriptions.remove(active.key);
      unawaited(active.dispose());
      return;
    }

    active.retryAttempt++;
    final delay = realtimeRetryDelay(active.retryAttempt);
    active.retryTimer = Timer(delay, () {
      active.retryTimer = null;
      _startRealtimeSubscription(active);
    });
  }

  T _requireRealtimeItem(RealtimeEvent<T> event) {
    final item = event.item;
    if (item != null) return item;
    throw ApiException(
      'Realtime ${event.type.name} event for $T ${event.id} requires item.',
    );
  }

  String _canonicalQueryParamsKey(QueryParams? queryParams) {
    if (queryParams == null || !queryParams.hasParameters) {
      return '{}';
    }
    return _canonicalMapKey({
      'filters': queryParams.filters.map(_filterToKey).toList(),
      'sorts': queryParams.sorts.map(_sortToKey).toList(),
      if (queryParams.pagination != null)
        'pagination': {
          'limit': queryParams.pagination!.limit,
          'offset': queryParams.pagination!.offset,
        },
    });
  }

  Map<String, dynamic> _filterToKey(FilterCondition filter) {
    return {
      'field': filter.field.fieldName,
      'operator': filter.operator.name,
      'value': _filterValueToKey(filter.value),
    };
  }

  Object? _filterValueToKey(FilterValue value) {
    return switch (value) {
      SingleValue(:final value) => _normalizeKeyValue(value),
      ListValue(:final values) => values.map(_normalizeKeyValue).toList(),
      NoValue() => null,
    };
  }

  Map<String, dynamic> _sortToKey(SortCondition sort) {
    return {
      'field': sort.field.fieldName,
      'direction': sort.direction.name,
    };
  }

  String _canonicalMapKey(Map<dynamic, dynamic>? value) {
    if (value == null || value.isEmpty) return '{}';
    return convert.jsonEncode(_normalizeKeyValue(value));
  }

  Object? _normalizeKeyValue(Object? value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is Map) {
      final entryList = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return {
        for (final entry in entryList)
          entry.key.toString(): _normalizeKeyValue(entry.value),
      };
    }
    if (value is Iterable) {
      return value.map(_normalizeKeyValue).toList();
    }
    return value.toString();
  }

  @visibleForTesting
  Map<dynamic, dynamic> get activeRealtimeSubscriptionsForTesting =>
      _activeRealtimeSubscriptions;
}

class _ActiveRealtimeSubscription<T extends SynquillDataModel<T>> {
  _ActiveRealtimeSubscription({
    required this.key,
    required this.id,
    required this.queryParams,
    required this.headers,
    required this.extra,
    required bool retryOnFail,
  }) : retryOnFailCount = retryOnFail ? 1 : 0;

  final _RealtimeSubscriptionKey key;
  final String? id;
  final QueryParams? queryParams;
  final Map<String, String>? headers;
  final Map<String, dynamic>? extra;
  int retryOnFailCount;
  bool get retryOnFail => retryOnFailCount > 0;
  int listenerCount = 1;
  int retryAttempt = 0;
  StreamSubscription<RealtimeEvent<T>>? subscription;
  Timer? retryTimer;
  bool disposed = false;

  Future<void> dispose() {
    if (disposed) return Future.value();
    disposed = true;
    retryTimer?.cancel();
    retryTimer = null;
    final cancelFuture = subscription?.cancel();
    subscription = null;
    return cancelFuture ?? Future.value();
  }
}

class _RealtimeSubscriptionKey {
  const _RealtimeSubscriptionKey({
    required this.modelType,
    required this.scope,
    required this.id,
    required this.queryParamsKey,
    required this.headersKey,
    required this.extraKey,
  });

  final String modelType;
  final String scope;
  final String? id;
  final String queryParamsKey;
  final String headersKey;
  final String extraKey;

  @override
  bool operator ==(Object other) {
    return other is _RealtimeSubscriptionKey &&
        modelType == other.modelType &&
        scope == other.scope &&
        id == other.id &&
        queryParamsKey == other.queryParamsKey &&
        headersKey == other.headersKey &&
        extraKey == other.extraKey;
  }

  @override
  int get hashCode {
    return Object.hash(
      modelType,
      scope,
      id,
      queryParamsKey,
      headersKey,
      extraKey,
    );
  }
}
