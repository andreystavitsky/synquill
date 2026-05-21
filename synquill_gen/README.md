# synquill_gen

This package contains builder and code generation logic for the `synquill` ecosystem. It is intended to be used as a dev dependency alongside the main `synquill` package.

## Features
- Code generators for models and repositories
- Repository adapters are generated as stable repository-owned instances so
  stateful adapter features such as GraphQL HTTP batching can work across
  nearby repository operations
- Integrates with `build_runner` and `source_gen`

## Getting started
Add this package as a dev dependency in your `pubspec.yaml`:

```yaml
dev_dependencies:
  # Code generation tool - required for synquill
  build_runner: ^2.4.15
  synquill_gen: ^0.8.1
```

## Usage
Run code generation with:

```sh
dart run build_runner build
```
