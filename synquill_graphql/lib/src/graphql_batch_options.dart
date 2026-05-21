/// Configuration for GraphQL HTTP query batching.
class GraphQLBatchOptions {
  /// Creates batching options.
  const GraphQLBatchOptions({
    this.enabled = false,
    this.window = const Duration(milliseconds: 10),
    this.maxBatchSize = 10,
  }) : assert(maxBatchSize > 0, 'maxBatchSize must be greater than zero');

  /// Creates disabled batching options.
  const GraphQLBatchOptions.disabled()
      : enabled = false,
        window = const Duration(milliseconds: 10),
        maxBatchSize = 10;

  /// Whether eligible GraphQL operations should be batched.
  final bool enabled;

  /// How long to wait for more operations before flushing a batch.
  final Duration window;

  /// Maximum number of operations to collect before flushing immediately.
  final int maxBatchSize;
}
