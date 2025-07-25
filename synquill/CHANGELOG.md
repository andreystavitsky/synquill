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
