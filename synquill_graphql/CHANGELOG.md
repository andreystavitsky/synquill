## 0.8.2

- Resolve critical runtime and generator issues.

## 0.8.0

- Initial release of `synquill_graphql` package.
- Implements `GraphQLApiAdapter` supporting GraphQL CRUD operations.
- Added modular execution layers via mixins:
  - `GraphQLExecutionMixin` for sending queries/mutations with built-in AST document caching.
  - `GraphQLResponseParsingMixin` for decoding standardized GraphQL response envelopes.
  - `GraphQLSubscriptionMixin` for managing WebSocket subscription lifecycles over `graphql-transport-ws`.
  - `GraphQLErrorHandlingMixin` for mapping remote errors to standard domain exceptions.
- Added query batching engine (`GraphQLBatchOptions`) with execution safety configurations and debouncing logic.
