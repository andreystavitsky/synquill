import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('Repository policy architecture', () {
    late String saveSource;
    late String deleteSource;
    late String querySource;

    setUpAll(() async {
      saveSource = await File(
        'lib/src/core/repository_mixins/repository_save_operations.dart',
      ).readAsString();
      deleteSource = await File(
        'lib/src/core/repository_mixins/repository_delete_operations.dart',
      ).readAsString();
      querySource = await File(
        'lib/src/core/repository_mixins/repository_query_operations.dart',
      ).readAsString();
    });

    test('remote-first writes delegate foreground execution and errors', () {
      final standardSaveBody = _extractAsyncMethod(
        saveSource,
        'Future<T> _handleStandardSave',
      );
      final deleteWithContextBody = _extractAsyncMethod(
        deleteSource,
        'Future<void> _deleteWithContext',
      );

      expect(standardSaveBody, contains('runRemoteFirstWriteTask<T>('));
      expect(deleteWithContextBody, contains('runRemoteFirstWriteTask<bool>('));

      expect(standardSaveBody, isNot(contains('NetworkTask<T>(')));
      expect(deleteWithContextBody, isNot(contains('NetworkTask<void>(')));
      expect(standardSaveBody, isNot(contains('on OfflineException')));
      expect(deleteWithContextBody, isNot(contains('on OfflineException')));
      expect(standardSaveBody, isNot(contains('SynquillStorageException(')));
      expect(
          deleteWithContextBody, isNot(contains('SynquillStorageException(')));
    });

    test('remote-first queries delegate foreground task construction', () {
      final findOneBody = _extractAsyncMethod(
        querySource,
        'Future<T?> findOne',
      );
      final findAllBody = _extractAsyncMethod(
        querySource,
        'Future<List<T>> findAll',
      );

      expect(findOneBody, contains('enqueueForegroundRemoteTask<T?>('));
      expect(findAllBody, contains('enqueueForegroundRemoteTask<List<T>>('));
      expect(findOneBody, isNot(contains('NetworkTask<T?>(')));
      expect(findAllBody, isNot(contains('NetworkTask<List<T>>(')));
    });
  });
}

String _extractAsyncMethod(String source, String signature) {
  final start = source.indexOf(signature);
  if (start == -1) {
    fail('Could not find method signature: $signature');
  }

  final declarationEnd = source.indexOf(') async {', start);
  if (declarationEnd == -1) {
    fail('Could not find async method declaration end for: $signature');
  }

  return _extractBlock(source, start, declarationEnd);
}

String _extractBlock(String source, int start, int declarationEnd) {
  final bodyStart = source.indexOf('{', declarationEnd);
  if (bodyStart == -1) {
    fail('Could not find method body');
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

  fail('Could not find method end');
}
