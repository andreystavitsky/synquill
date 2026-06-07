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

  /// Escapes [value] as a single-quoted Dart string literal.
  static String dartStringLiteral(String value) {
    final buffer = StringBuffer("'");

    for (final codeUnit in value.codeUnits) {
      switch (codeUnit) {
        case 0x08:
          buffer.write(r'\b');
          break;
        case 0x09:
          buffer.write(r'\t');
          break;
        case 0x0A:
          buffer.write(r'\n');
          break;
        case 0x0C:
          buffer.write(r'\f');
          break;
        case 0x0D:
          buffer.write(r'\r');
          break;
        case 0x24:
          buffer.write(r'\$');
          break;
        case 0x27:
          buffer.write(r"\'");
          break;
        case 0x5C:
          buffer.write(r'\\');
          break;
        default:
          if (codeUnit < 0x20) {
            buffer.write(r'\u{');
            buffer.write(codeUnit.toRadixString(16));
            buffer.write('}');
          } else {
            buffer.writeCharCode(codeUnit);
          }
      }
    }

    buffer.write("'");
    return buffer.toString();
  }
}
