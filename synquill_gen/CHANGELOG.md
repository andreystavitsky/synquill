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
