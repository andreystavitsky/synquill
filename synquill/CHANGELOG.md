## 0.7.0
### Breaking Changes
- `BaseDaoMixin<T>` interface now requires implementations for `saveModel`, `deleteById`, `deleteAll`, and `getAllExcludingIds`. Custom DAOs must be updated.

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
