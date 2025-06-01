part of synquill;

/// Manages dependency resolution for hierarchical sync ordering.
///
/// This class analyzes @ManyToOne relationships between models to determine
/// the correct sync order, ensuring that parent records are synced before
/// their dependent child records.
///
/// For example, if Project has @ManyToOne(target: User), then User records
/// must be synced before Project records.
class DependencyResolver {
  static final Logger _log = Logger('DependencyResolver');

  /// Maps model types to their parent dependencies.
  ///
  /// Key: Child model type (e.g., 'Project')
  /// Value: Set of parent model types (e.g., {'User', 'Category'})
  static final Map<String, Set<String>> _dependencyMap = {};

  /// Maps model types to their dependency level in the hierarchy.
  ///
  /// Level 0: Models with no dependencies (root/parent models)
  /// Level 1: Models that depend only on level 0 models
  /// Level 2: Models that depend on level 1 or lower models, etc.
  static final Map<String, int> _dependencyLevels = {};

  /// Registers a dependency relationship.
  ///
  /// [childType] The model type that has the dependency
  /// [parentType] The model type that is depended upon
  static void registerDependency(String childType, String parentType) {
    _dependencyMap.putIfAbsent(childType, () => <String>{});
    _dependencyMap[childType]!.add(parentType);

    _log.fine('Registered dependency: $childType depends on $parentType');

    // Recalculate dependency levels when new dependencies are added
    _calculateDependencyLevels();
  }

  /// Gets the dependency level for a model type.
  ///
  /// Returns 0 if the model has no dependencies (is a root/parent model),
  /// or a higher number indicating how deep in the dependency chain it is.
  static int getDependencyLevel(String modelType) {
    return _dependencyLevels[modelType] ?? 0;
  }

  /// Gets all dependencies for a model type.
  ///
  /// Returns the set of parent model types that this model depends on.
  static Set<String> getDependencies(String modelType) {
    return _dependencyMap[modelType] ?? <String>{};
  }

  /// Checks if a model type has any dependencies.
  static bool hasDependencies(String modelType) {
    return _dependencyMap.containsKey(modelType) &&
        _dependencyMap[modelType]!.isNotEmpty;
  }

  /// Sorts sync tasks by dependency order.
  ///
  /// Returns tasks ordered so that parent models are processed before
  /// child models that depend on them.
  ///
  /// [tasks] List of sync queue task data
  /// Returns ordered list with dependencies resolved
  static List<Map<String, dynamic>> sortTasksByDependencyOrder(
    List<Map<String, dynamic>> tasks,
  ) {
    if (tasks.isEmpty) return tasks;

    // Group tasks by model type
    final tasksByModelType = <String, List<Map<String, dynamic>>>{};
    for (final task in tasks) {
      final modelType = task['model_type'] as String;
      tasksByModelType.putIfAbsent(modelType, () => []);
      tasksByModelType[modelType]!.add(task);
    }

    // Sort model types by dependency level
    final sortedModelTypes =
        tasksByModelType.keys.toList()..sort(
          (a, b) => getDependencyLevel(a).compareTo(getDependencyLevel(b)),
        );

    // Build result list maintaining dependency order
    final sortedTasks = <Map<String, dynamic>>[];

    for (final modelType in sortedModelTypes) {
      final modelTasks = tasksByModelType[modelType]!;

      // Within the same model type, sort by creation time to maintain FIFO
      modelTasks.sort((a, b) {
        // Handle flexible types for created_at field
        DateTime? createdAtA;
        DateTime? createdAtB;

        // Parse created_at from whatever form it's in (DateTime, int, String)
        if (a['created_at'] is DateTime) {
          createdAtA = a['created_at'] as DateTime;
        } else if (a['created_at'] is int) {
          final timestamp = a['created_at'] as int;
          createdAtA = DateTime.fromMillisecondsSinceEpoch(timestamp);
        } else if (a['created_at'] is String) {
          try {
            createdAtA = DateTime.parse(a['created_at'] as String);
          } catch (_) {
            createdAtA = null;
          }
        }

        if (b['created_at'] is DateTime) {
          createdAtB = b['created_at'] as DateTime;
        } else if (b['created_at'] is int) {
          createdAtB = DateTime.fromMillisecondsSinceEpoch(
            b['created_at'] as int,
          );
        } else if (b['created_at'] is String) {
          try {
            createdAtB = DateTime.parse(b['created_at'] as String);
          } catch (_) {
            createdAtB = null;
          }
        }

        if (createdAtA == null && createdAtB == null) return 0;
        if (createdAtA == null) return 1;
        if (createdAtB == null) return -1;
        return createdAtA.compareTo(createdAtB);
      });

      sortedTasks.addAll(modelTasks);
    }

    if (sortedTasks.length != tasks.length) {
      _log.warning(
        'Task count mismatch after dependency sorting: '
        'input=${tasks.length}, output=${sortedTasks.length}',
      );
    }

    _log.fine(
      'Sorted ${tasks.length} tasks by dependency order. '
      'Order: ${sortedModelTypes.join(' → ')}',
    );

    return sortedTasks;
  }

  /// Calculates dependency levels for all registered model types.
  ///
  /// Uses topological sorting to assign levels, ensuring that dependencies
  /// are resolved correctly even with complex dependency chains.
  static void _calculateDependencyLevels() {
    _dependencyLevels.clear();

    // Get all model types (both parents and children)
    final allModelTypes = <String>{};
    allModelTypes.addAll(_dependencyMap.keys);
    for (final deps in _dependencyMap.values) {
      allModelTypes.addAll(deps);
    }

    // Initialize all model types to level 0
    for (final modelType in allModelTypes) {
      _dependencyLevels[modelType] = 0;
    }

    // Calculate levels using iterative approach
    bool changed = true;
    int iteration = 0;
    const maxIterations = 100; // Prevent infinite loops

    while (changed && iteration < maxIterations) {
      changed = false;
      iteration++;

      for (final childType in _dependencyMap.keys) {
        final dependencies = _dependencyMap[childType]!;
        if (dependencies.isEmpty) continue;

        // Find the maximum level among all dependencies
        final maxDependencyLevel = dependencies
            .map((parentType) => _dependencyLevels[parentType] ?? 0)
            .fold(0, (max, level) => level > max ? level : max);

        // Set child level to one more than the highest dependency
        final newLevel = maxDependencyLevel + 1;
        if (_dependencyLevels[childType] != newLevel) {
          _dependencyLevels[childType] = newLevel;
          changed = true;
        }
      }
    }

    if (iteration >= maxIterations) {
      _log.warning(
        'Dependency level calculation reached maximum iterations. '
        'Possible circular dependency detected.',
      );
    }

    _log.fine(
      'Calculated dependency levels: '
      '${_dependencyLevels.entries.map((e) => '${e.key}'
      '=${e.value}').join(', ')}',
    );
  }

  /// Detects circular dependencies in the registered dependencies.
  ///
  /// Returns true if circular dependencies are detected, false otherwise.
  static bool hasCircularDependencies() {
    // Use DFS to detect cycles
    final visited = <String>{};
    final recursionStack = <String>{};

    bool hasCycle(String modelType) {
      if (recursionStack.contains(modelType)) {
        return true; // Back edge found - cycle detected
      }
      if (visited.contains(modelType)) {
        return false; // Already processed
      }

      visited.add(modelType);
      recursionStack.add(modelType);

      final dependencies = _dependencyMap[modelType] ?? <String>{};
      for (final dependency in dependencies) {
        if (hasCycle(dependency)) {
          return true;
        }
      }

      recursionStack.remove(modelType);
      return false;
    }

    for (final modelType in _dependencyMap.keys) {
      if (!visited.contains(modelType) && hasCycle(modelType)) {
        _log.severe('Circular dependency detected involving: $modelType');
        return true;
      }
    }

    return false;
  }

  /// Clears all registered dependencies.
  ///
  /// Useful for testing or when reinitializing the dependency system.
  static void clearDependencies() {
    _dependencyMap.clear();
    _dependencyLevels.clear();
    _log.fine('Cleared all dependency registrations');
  }

  /// Gets debug information about the current dependency state.
  static Map<String, dynamic> getDebugInfo() {
    return {
      'dependencyMap': Map<String, List<String>>.fromEntries(
        _dependencyMap.entries.map((e) => MapEntry(e.key, e.value.toList())),
      ),
      'dependencyLevels': Map<String, int>.from(_dependencyLevels),
      'hasCircularDependencies': hasCircularDependencies(),
      'totalModelTypes': _dependencyLevels.length,
      'maxDependencyLevel':
          _dependencyLevels.values.isEmpty
              ? 0
              : _dependencyLevels.values.reduce((a, b) => a > b ? a : b),
    };
  }

  /// Gets the current dependency map for debugging.
  static Map<String, Set<String>> getDebugDependencyMap() {
    return Map<String, Set<String>>.from(_dependencyMap);
  }

  /// Gets the current dependency levels for debugging.
  static Map<String, int> getDebugDependencyLevels() {
    return Map<String, int>.from(_dependencyLevels);
  }

  /// Clears dependency state for testing.
  static void clearForTesting() {
    _dependencyMap.clear();
    _dependencyLevels.clear();
  }
}
