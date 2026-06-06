## 0.9.0

### Added
- Added code generation support for `@SynquillIdKey`.
- Generated model metadata now registers custom API JSON id keys with the
  runtime registry.

## 0.8.3

### Changed
- Generated ManyToOne watch methods now watch the source object with
  `DataLoadPolicy.localOnly` explicitly, derive a foreign-key stream, apply
  `distinct()`, and only switch target watchers when the foreign key changes.

## 0.8.2

- Resolve critical runtime and generator issues.

## 0.8.1

### Fixes
- Generated repositories now reuse their adapter instance so stateful adapter
  features such as GraphQL HTTP query batching keep their per-adapter state.

## 0.8.0

### Improvements
- Added support for generating adapters extending `GraphQLApiAdapter` based on base class constraints resolved during model analysis.
- Generated relationship watchers (`watchRemote`, `retryOnFail`, etc.) now properly accept and forward realtime parameters.
- Added inline warnings to generated relationship loaders warning of potential N+1 subscription performance issues.

## 0.7.1
* Fixes typos in `synquill_gen`

## 0.7.0
- **Breaking Change**: Migrated the generator's internal `part`/`part of` structure to independent modular libraries and moved internal files to `lib/src/`.
- Generate implementation for `getAllExcludingIds` in DAOs.
- Explicitly add `@override` to `saveModel`, `deleteById`, and `deleteAll` in generated code.
- Synchronized version with `synquill`.

## 0.5.1
- Generate `localOnly` property for repository implementations.
> Note: code must be re-generated via build_runner

## 0.5.0
- Initial version.
