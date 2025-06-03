part of synquill;

/// Utility class for English pluralization rules
class PluralizationUtils {
  /// Convert class name to proper camelCase plural form
  /// e.g., "Category" -> "categories", "PlainModelJson" -> "plainModelJsons"
  static String toCamelCasePlural(String className) {
    if (className.isEmpty) return className;

    // Convert to camelCase first (preserve internal capitalization)
    final camelCase = className[0].toLowerCase() + className.substring(1);

    // Apply proper pluralization rules
    return pluralize(camelCase);
  }

  /// Pluralize a string with proper English rules
  static String pluralize(String singular) {
    if (singular.isEmpty) return singular;

    // Handle special cases first
    final lowerSingular = singular.toLowerCase();

    switch (lowerSingular) {
      case 'child':
        return singular.replaceFirst(
          RegExp(r'child$', caseSensitive: false),
          'children',
        );
      case 'foot':
        return singular.replaceFirst(
          RegExp(r'foot$', caseSensitive: false),
          'feet',
        );
      case 'tooth':
        return singular.replaceFirst(
          RegExp(r'tooth$', caseSensitive: false),
          'teeth',
        );
      case 'mouse':
        return singular.replaceFirst(
          RegExp(r'mouse$', caseSensitive: false),
          'mice',
        );
      case 'man':
        return singular.replaceFirst(
          RegExp(r'man$', caseSensitive: false),
          'men',
        );
      case 'woman':
        return singular.replaceFirst(
          RegExp(r'woman$', caseSensitive: false),
          'women',
        );
      case 'todo':
        return singular.replaceFirst(
          RegExp(r'todo$', caseSensitive: false),
          'todos',
        );
    }

    // Standard pluralization rules
    if (singular.endsWith('y') && singular.length > 1) {
      final beforeY = singular[singular.length - 2];
      if (!'aeiou'.contains(beforeY.toLowerCase())) {
        // Consonant + y -> ies (e.g., category -> categories)
        return '${singular.substring(0, singular.length - 1)}ies';
      }
    }

    if (singular.endsWith('sh') ||
        singular.endsWith('ch') ||
        singular.endsWith('x') ||
        singular.endsWith('z') ||
        singular.endsWith('s')) {
      return '${singular}es';
    }

    const Set<String> fToVesWords = {
      'calf', // calves
      'elf', // elves
      'half', // halves
      'knife', // knives
      'leaf', // leaves
      'life', // lives
      'loaf', // loaves
      'self', // selves
      'sheaf', // sheaves
      'shelf', // shelves
      'thief', // thieves
      'wife', // wives
      'wolf', // wolves
    };

    if (fToVesWords.contains(lowerSingular)) {
      if (singular.endsWith('fe')) {
        return '${singular.substring(0, singular.length - 2)}ves';
      } else if (singular.endsWith('f')) {
        return '${singular.substring(0, singular.length - 1)}ves';
      }
    }

    if (singular.endsWith('o') && singular.length > 1) {
      final beforeO = singular[singular.length - 2].toLowerCase();
      if (!'aeiou'.contains(beforeO)) {
        // Consonant + o: Traditional English words usually add 'es'
        // Modern/borrowed words usually just add 's'
        final traditionalWordsNeedingEs = {
          'hero',
          'potato',
          'tomato',
          'echo',
          'cargo',
          'embargo',
          'torpedo',
          'veto',
          'buffalo',
          'volcano',
          'tornado',
        };

        if (traditionalWordsNeedingEs.contains(lowerSingular)) {
          return '${singular}es';
        }
        // Modern words (photo, piano, logo, memo, auto, disco, casino,
        // mojo, mojito, etc.) just add 's'
        return '${singular}s';
      }
    }

    // Default: just add 's'
    return '${singular}s';
  }
}
