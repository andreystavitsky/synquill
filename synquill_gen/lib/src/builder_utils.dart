import 'package:synquill_utils/synquill_utils.dart';


/// Utility functions shared across builder files
class BuilderUtils {
  /// Convert string to camelCase
  static String camelCase(String input) {
    if (input.isEmpty) return input;
    return input[0].toLowerCase() + input.substring(1);
  }

  /// Convert class name to proper camelCase plural form for repository names
  /// e.g., "Category" -> "categories", "PlainModelJson" -> "plainModelJsons"
  static String toCamelCasePlural(String className) {
    return PluralizationUtils.toCamelCasePlural(className);
  }
}
