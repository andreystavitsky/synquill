# Synquill Documentation

Welcome to the comprehensive documentation for Synquill - a powerful Flutter package for offline-first data management with automatic REST API synchronization.

## 📚 Documentation Overview

This documentation is organized into several sections to help you get started quickly and master advanced features:

### Getting Started
- **[Quick Start Guide](guide.md)** - Essential concepts, setup, and basic usage
  - Core concepts and architecture
  - Model definition and relationships
  - Basic querying and operations
  - Reactive data streams

### Configuration & Setup
- **[API Adapters](api-adapters.md)** - Customizing HTTP communication
  - Creating custom adapters
  - HTTP methods and headers
  - Authentication patterns
  - Response parsing and error handling

- **[Configuration](configuration.md)** - Storage and sync configuration
  - Database setup and options
  - Background sync configuration
  - Lifecycle integration
  - Performance tuning

### Advanced Features
- **[Advanced Features](advanced-features.md)** - Power user features
  - Database indexing and optimization
  - Data migrations
  - Error handling strategies
  - Performance considerations and limitations

### Reference
- **[API Reference](api-reference.md)** - Complete API documentation
  - All classes, methods, and properties
  - Enums and exceptions
  - Utility functions and helpers
  - Code examples for each component

## 🚀 Quick Navigation

### For New Users
1. Start with the **[Quick Start Guide](guide.md)** to understand core concepts
2. Learn about **[API Adapters](api-adapters.md)** to connect to your backend
3. Configure your app with **[Configuration](configuration.md)**

### For Advanced Users
1. Explore **[Advanced Features](advanced-features.md)** for optimization techniques
2. Dive into **[Queue Management](advanced/queues.md)** for complex sync scenarios
3. Master **[Dependency Resolution](advanced/dependency-resolver.md)** for related data handling

### For Reference
- Use the **[API Reference](api-reference.md)** for detailed method signatures and examples

## 🎯 Key Concepts

Before diving into the documentation, familiarize yourself with these core concepts:

- **Offline-First**: Synquill prioritizes local operations, syncing with remote APIs when connectivity allows
- **Model-Driven**: Define your data models once, generate repositories, DAOs, and database tables automatically
- **Queue-Based Sync**: Smart sync queues handle dependencies between related data operations
- **Reactive Streams**: Real-time UI updates through `Stream<T>` APIs that respond to data changes
- **Configurable Policies**: Control when and how data is loaded and saved with flexible policies

## 🔧 Common Use Cases

| Use Case | Recommended Reading |
|----------|-------------------|
| Getting started with Synquill | [Quick Start Guide](guide.md) |
| Setting up API communication | [API Adapters](api-adapters.md) |
| Configuring background sync | [Configuration](configuration.md) |
| Optimizing database performance | [Advanced Features](advanced-features.md) |
| Managing complex sync scenarios | [Queue Management](advanced/queues.md) |
| Handling related data dependencies | [Dependency Resolution](advanced/dependency-resolver.md) |
| Looking up specific methods | [API Reference](api-reference.md) |

## 💡 Tips for Success

1. **Start Simple**: Begin with basic CRUD operations before implementing complex sync scenarios
2. **Test Offline**: Always test your app's behavior when connectivity is unavailable
3. **Monitor Queues**: Use the queue monitoring tools to debug sync issues
4. **Use Indexes**: Leverage indexes for better performance
5. **Handle Errors**: Implement proper error handling for network and database operations

## 🤝 Contributing to Documentation

Found an error or want to improve the documentation? Contributions are welcome!

1. Documentation lives in the `/doc` directory
2. Follow the existing structure and formatting
3. Include code examples where helpful
4. Test any code snippets before submitting

---

Happy coding with Synquill! 🚀
