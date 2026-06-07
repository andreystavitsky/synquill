import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('RepositorySaveOperations sync architecture', () {
    late String source;

    setUpAll(() async {
      source = await File(
        'lib/src/core/repository_mixins/repository_save_operations.dart',
      ).readAsString();
    });

    test('standard local-first save delegates sync scheduling', () {
      final standardSaveBody = _extractMethod(
        source,
        'Future<T> _handleStandardSave',
      );

      expect(standardSaveBody, contains('processBackgroundSync('));
      expect(standardSaveBody, isNot(contains('SyncQueueDao(')));
      expect(standardSaveBody, isNot(contains('NetworkTask<void>(')));
      expect(
          standardSaveBody, isNot(contains('_tryImmediateSyncInBackground')));
      expect(source, isNot(contains('Future<void> _executeSyncOperation(')));
      expect(source, isNot(contains('void _tryImmediateSyncInBackground(')));
    });
  });
}

String _extractMethod(String source, String signature) {
  final start = source.indexOf(signature);
  if (start == -1) {
    fail('Could not find method signature: $signature');
  }

  final declarationEnd = source.indexOf(') async {', start);
  if (declarationEnd == -1) {
    fail('Could not find async method declaration end for: $signature');
  }

  final bodyStart = source.indexOf('{', declarationEnd);
  if (bodyStart == -1) {
    fail('Could not find method body for: $signature');
  }

  var depth = 0;
  for (var index = bodyStart; index < source.length; index++) {
    final char = source[index];
    if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(start, index + 1);
      }
    }
  }

  fail('Could not find method end for: $signature');
}
