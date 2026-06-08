import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('library source imports narrow Synquill barrels', () {
    final libFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    final broadImports = <String>[];
    for (final file in libFiles) {
      final source = file.readAsStringSync();
      if (source.contains("import 'package:synquill/synquill.dart'")) {
        broadImports.add(file.path);
      }
    }

    expect(broadImports, isEmpty);
  });
}
