# Advanced Features

This directory contains documentation for advanced Synquill features and internal systems.

## Contents

### Core Architecture
- **[Dependency Resolver](./dependency-resolver.md)** - Hierarchical sync ordering and model dependency management
- **[Queues](./queues.md)** - Three-queue system for foreground, load, and background operations

### Queue Management System
The queue system manages three distinct queues with different priorities and behaviors:

- **Foreground Queue**: High-priority operations initiated directly by user interactions
- **Load Queue**: Medium-priority operations for data fetching and background loading
- **Background Queue**: Low-priority operations for sync and maintenance tasks

### Dependency Resolution
The dependency resolver ensures that model operations are executed in the correct order based on relationship dependencies:

- Parent models are synced before child models
- Cascade delete operations follow dependency hierarchy  
- Circular dependency detection and handling
- Dynamic dependency registration for runtime model relationships

### Background Processing
Integration with platform-specific background task systems:

- WorkManager integration on Android
- BGTaskScheduler integration on iOS
- Isolate-based background processing
- Battery-optimized sync strategies

### Advanced Configuration
Fine-tuning system behavior for production use:

- Queue capacity management and timeouts
- Adaptive polling intervals for foreground vs background modes
- Retry strategies with exponential backoff and jitter
- Network timeout and connectivity handling

---

For basic usage and setup, see the main [documentation directory](../).
