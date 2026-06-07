import 'package:synquill_gen/src/model_extension_generator.dart';
import 'package:synquill_gen/src/model_info.dart';
import 'package:test/test.dart';

void main() {
  group('ModelExtensionGenerator id management', () {
    test('uses custom id JSON key in replaceIdEverywhere', () {
      final code = ModelExtensionGenerator.generateModelExtensions(
        const ModelInfo(
          className: 'FavoritePlace',
          tableName: 'favorite_places',
          endpoint: 'favorite_places',
          importPath: 'favorite_place.dart',
          fields: [],
          idJsonKey: 'placeId',
        ),
        const [],
      );

      expect(code, contains("json['placeId'] = newId;"));
      expect(code, isNot(contains("json['id'] = newId;")));
    });

    test('escapes custom id JSON key in replaceIdEverywhere', () {
      final code = ModelExtensionGenerator.generateModelExtensions(
        const ModelInfo(
          className: 'FavoritePlace',
          tableName: 'favorite_places',
          endpoint: 'favorite_places',
          importPath: 'favorite_place.dart',
          fields: [],
          idJsonKey: r"place'Id$bad\name",
        ),
        const [],
      );

      expect(code, contains(r"json['place\'Id\$bad\\name'] = newId;"));
    });
  });

  group('ModelExtensionGenerator realtime watch arguments', () {
    test('passes realtime arguments through OneToMany watch methods', () {
      final code = ModelExtensionGenerator.generateModelExtensions(
        const ModelInfo(
          className: 'User',
          tableName: 'users',
          endpoint: 'users',
          importPath: 'user.dart',
          fields: [],
          relations: [
            RelationInfo(
              relationType: RelationType.oneToMany,
              targetType: 'Todo',
              mappedBy: 'userId',
            ),
          ],
        ),
        const [],
      );

      expect(code, contains('bool watchRemote = false,'));
      expect(code, contains('bool retryOnFail = true,'));
      expect(code, contains('Map<String, String>? headers,'));
      expect(code, contains('Map<String, dynamic>? extra,'));
      expect(code, contains('watchRemote: watchRemote,'));
      expect(code, contains('retryOnFail: retryOnFail,'));
      expect(code, contains('headers: headers,'));
      expect(code, contains('extra: extra,'));
      expect(code, contains('N+1 subscriptions'));
    });

    test('passes realtime arguments through ManyToOne watch methods', () {
      final code = ModelExtensionGenerator.generateModelExtensions(
        const ModelInfo(
          className: 'Todo',
          tableName: 'todos',
          endpoint: 'todos',
          importPath: 'todo.dart',
          fields: [],
          relations: [
            RelationInfo(
              relationType: RelationType.manyToOne,
              targetType: 'User',
              foreignKeyColumn: 'userId',
            ),
          ],
        ),
        const [],
      );

      expect(code, contains('bool watchRemote = false,'));
      expect(code, contains('bool retryOnFail = true,'));
      expect(code, contains('Map<String, String>? headers,'));
      expect(code, contains('Map<String, dynamic>? extra,'));
      expect(code, contains('watchRemote: watchRemote,'));
      expect(code, contains('retryOnFail: retryOnFail,'));
      expect(code, contains('headers: headers,'));
      expect(code, contains('extra: extra,'));
      expect(code, contains('N+1 subscriptions'));
    });

    test(
      'ManyToOne source watch is explicitly localOnly',
      () {
        final code = ModelExtensionGenerator.generateModelExtensions(
          const ModelInfo(
            className: 'Todo',
            tableName: 'todos',
            endpoint: 'todos',
            importPath: 'todo.dart',
            fields: [],
            relations: [
              RelationInfo(
                relationType: RelationType.manyToOne,
                targetType: 'User',
                foreignKeyColumn: 'userId',
              ),
            ],
          ),
          const [],
        );

        final sourceWatchStart =
            code.indexOf('return sourceRepository.watchOne(');
        final mapStart = code.indexOf('.map((sourceObject) {');
        final legacySwitchStart = code.indexOf('.switchMap((sourceObject) {');
        final sourceWatchEnd = mapStart == -1 ? legacySwitchStart : mapStart;
        expect(sourceWatchEnd, isNot(-1));
        final sourceWatchBlock =
            code.substring(sourceWatchStart, sourceWatchEnd);

        expect(
          sourceWatchBlock,
          contains('loadPolicy: DataLoadPolicy.localOnly,'),
        );
        expect(sourceWatchBlock, contains('watchRemote: watchRemote,'));
        expect(
          code,
          contains('loadPolicy: loadPolicy ?? DataLoadPolicy.localOnly,'),
        );
      },
    );

    test(
      'ManyToOne watch switches only when the foreign key changes',
      () {
        final code = ModelExtensionGenerator.generateModelExtensions(
          const ModelInfo(
            className: 'Todo',
            tableName: 'todos',
            endpoint: 'todos',
            importPath: 'todo.dart',
            fields: [],
            relations: [
              RelationInfo(
                relationType: RelationType.manyToOne,
                targetType: 'User',
                foreignKeyColumn: 'userId',
              ),
            ],
          ),
          const [],
        );

        expect(code, contains('.map((sourceObject) {'));
        expect(code, contains('return sourceObject.userId.toString();'));
        expect(code, contains('.distinct()'));
        expect(code, contains('.switchMap((foreignKey) {'));
      },
    );
  });
}
