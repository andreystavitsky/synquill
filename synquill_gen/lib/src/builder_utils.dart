part of synquill_gen;

/// Utility functions shared across builder files
class BuilderUtils {
  /// Convert string to camelCase
  static String camelCase(String input) {
    if (input.isEmpty) return input;
    return input[0].toLowerCase() + input.substring(1);
  }

  /// Convert package URI to relative path
  static String makeRelativePath(String packageUri) {
    // Convert package:synced_storage_example/models/todo.dart
    // to models/todo.dart
    if (packageUri.startsWith('package:')) {
      final uri = Uri.parse(packageUri);
      final pathSegments = uri.pathSegments;
      if (pathSegments.length > 1) {
        // Skip the first segment (package name) and join the rest
        return pathSegments.skip(1).join('/');
      }
    }
    return packageUri;
  }
}
