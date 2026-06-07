## 0.9.1

### Changed
- Moved Synquill's internal test models and generated fixture database out of
  the runtime package and into `test/support`.
- Disabled Synquill's own aggregate code generation target so
  `dart run build_runner build` no longer recreates runtime
  `lib/synquill.generated.dart` fixture output for the `synquill` package.

### Migration note
- Applications should import their own generated file, for example
  `package:your_app/synquill.generated.dart`, not
  `package:synquill/synquill.generated.dart`.
- Code importing `package:synquill/src/test_models/...` or
  `package:synquill/generated/database.generated.dart` was depending on
  internal test fixtures and should move to app-owned models or test support
  fixtures.

## 0.9.0

### Added
- Added `@SynquillIdKey` to map `SynquillDataModel.id` to custom API JSON
  keys such as `placeId`.
- Models using `json_serializable` can now rely on `@JsonKey(name: ...)` on the
  `id` field; Synquill infers the same custom id JSON key automatically unless
  `@SynquillIdKey` is present.
- Retry sync now resolves queued task identity from the configured custom id
  key, payload `id`, then `sync_queue_items.model_id`.

### Fixed
- Local-first retry processing no longer fails when `toJson()` omits a literal
  `id` key but the queued row already stores the model id.
- Server-generated ID replacement now honors the configured API JSON id key
  before rebuilding a model from JSON.

## 0.8.3

### Changed
- `watchOne(id)` is now passive by default and no longer inherits
  `defaultLoadPolicy`; use `loadPolicy: DataLoadPolicy.localThenRemote`
  explicitly when a remote refresh is required.

### Fixed
- `watchOne` now follows `RepositoryChange.idChanged` events so active
  watches move from temporary client IDs to server-generated IDs.
- `watchOne(watchRemote: true)` now rebinds realtime subscriptions after an
  ID change.
- Generated relation watch paths avoid unnecessary ManyToOne re-subscription
  churn when the source model changes but its foreign key does not.

## 0.8.2

- Resolve critical runtime and generator issues.

## 0.8.0

### New Features
- Introduced realtime synchronization support for repositories via `RepositoryRealtimeOperations` mixin.
- Extended repository `watchOne` and `watchAll` methods with a new `watchRemote` parameter and automated retry logic (`retryOnFail`).
- Added transport-neutral `RealtimeEvent` and `RealtimeEventType` models for processing remote updates.
- Added `RealtimeApiAdapter` interface to define standard subscription contracts.
- Enhanced `RepositoryChange` with `realtimeError` factory constructor for unified error propagation.

## 0.7.2
* Fixes imports.

## 0.7.1
* Fixes imports. Fixes typos in `synquill_gen`

## 0.7.0
### Breaking Changes
- `BaseDaoMixin<T>` interface now requires implementations for `saveModel`, `deleteById`, `deleteAll`, and `getAllExcludingIds`. Custom DAOs must be updated.
- Migrated the monolithic `part`/`part of` structure to modular libraries using `import`/`export`. Internal code moved to `lib/src/` for true compile-time encapsulation. Consumers relying on internal package visibility or private members will need to update their code.

### Improvements & Optimizations
- **Type Safety**: Eliminated all `dynamic` dispatch in `RepositoryHelpersMixin` by leveraging `BaseDaoMixin` interface.
- **Performance**: Optimized `fetchAllFromLocalWithoutPendingSyncOps` to use a single SQL `NOT IN` query instead of N+1 per-item checks, improving performance by orders of magnitude for large datasets.
- **Reliability**: Added atomic transaction to `obliterateLocalStorage` to guarantee data consistency even if the app crashes or device loses power mid-operation.
- **Sync Engine**: Added bulk operation support to `SyncQueueDao` for faster queue clearing and pending status detection.

### Bug Fixes
- Fixed critical type safety in `SynquillStorageConfig` (`dio` typed as `Dio?`, `maximumNetworkTimeout` as `Duration`).
- Fixed logic errors in `logger` and `backgroundSyncManager` initialization guards.
- Prevented listener leaks and duplicate logs by making `_defaultLogger` a `static final` field.
- Fixed `NetworkTask.isCancelled` to correctly distinguish between explicit cancellation and completion.

## 0.6.0
### Breaking Changes
- `methodForFind` and all `urlForFind*` methods now support a `QueryParams` parameter, enabling adaptive API method and URL selection based on query complexity.
- The `type` getter in `ApiAdapterBase` now returns the snake_case type name by default instead of lowercase, which may affect endpoint URLs and serialization logic.

## 0.5.5+1
* Correctly implemented `localOnly` repositories in mixins.
> Note: code must be re-generated via build_runner

## 0.5.4
* Fixed a bug where `localOnly` repositories might throw an error during `remoteFirst` operations.

## 0.5.3
* Fixed a bug where pending operations did not respect parent ID changes.

## 0.5.2
* Initial release.
