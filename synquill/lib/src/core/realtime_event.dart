import 'package:synquill/src/core/synquill_data_model.dart';

/// The semantic kind of a realtime change received from a remote transport.
enum RealtimeEventType {
  /// A new remote item was created.
  created,

  /// An existing remote item was updated.
  updated,

  /// A remote item was deleted.
  deleted,

  /// A remote item should be inserted or replaced locally.
  upserted,
}

/// A transport-neutral realtime change event.
class RealtimeEvent<T extends SynquillDataModel<T>> {
  /// Creates a realtime event.
  const RealtimeEvent({
    required this.type,
    required this.id,
    this.item,
    this.metadata,
    this.raw,
  });

  /// The type of realtime change.
  final RealtimeEventType type;

  /// The affected model ID.
  final String id;

  /// The changed item for create, update, or upsert events.
  final T? item;

  /// Transport-neutral event metadata.
  final Map<String, dynamic>? metadata;

  /// The raw transport payload, when available for debugging/custom handling.
  final Map<String, dynamic>? raw;
}
