import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('Public barrels', () {
    test('provide narrow entry points', () {
      expect(File('lib/synquill_contracts.dart').existsSync(), isTrue);
      expect(File('lib/synquill_rest.dart').existsSync(), isTrue);
      expect(File('lib/synquill_drift.dart').existsSync(), isTrue);
    });

    test('core barrel does not re-export the compatibility aggregate', () {
      final coreSource = File('lib/synquill_core.dart').readAsStringSync();

      expect(
        coreSource,
        isNot(contains("export 'package:synquill/synquill.dart';")),
      );
    });

    test('core barrel does not re-export REST, Drift, or runtime layers', () {
      final coreSource = File('lib/synquill_core.dart').readAsStringSync();

      expect(coreSource, isNot(contains("export 'synquill_rest.dart';")));
      expect(coreSource, isNot(contains("export 'synquill_drift.dart';")));
      expect(coreSource, isNot(contains("export 'src/runtime/")));
    });

    test('contracts barrel avoids transport and database engine exports', () {
      final contractsSource =
          File('lib/synquill_contracts.dart').readAsStringSync();

      expect(contractsSource, isNot(contains('package:dio/')));
      expect(contractsSource, isNot(contains('package:drift/native.dart')));
    });

    test('rest barrel does not re-export core contracts transitively', () {
      final restSource = File('lib/synquill_rest.dart').readAsStringSync();

      expect(restSource, isNot(contains("export 'synquill_contracts.dart';")));
    });

    test('drift barrel owns Drift core and native VM exports', () {
      final driftSource = File('lib/synquill_drift.dart').readAsStringSync();

      expect(driftSource, contains("export 'package:drift/drift.dart'"));
      expect(driftSource, contains("export 'package:drift/native.dart'"));
    });
  });
}
