import 'package:synquill_gen/synquill_gen.dart';
import 'package:test/test.dart';

void main() {
  group('synced_data_storage_gen library tests', () {
    setUp(() {
      // Additional setup goes here.
    });

    test('library exports are available', () {
      // Test that the main exports are available
      expect(ModelInfo, isA<Type>());
      expect(TableGenerator, isA<Type>());
      expect(DaoGenerator, isA<Type>());
      expect(RepositoryGenerator, isA<Type>());
    });
  });
}
