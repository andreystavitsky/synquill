import 'package:test/test.dart';

import 'in_memory_api_adapter.dart';
import 'test_models.dart';

void main() {
  group('InMemoryApiAdapter', () {
    test('stores models and records default operation labels', () async {
      final adapter = _TestUserMemoryAdapter();
      final user = TestUser(
        id: 'user-1',
        name: 'Ada',
        email: 'ada@example.test',
      );

      await adapter.createOne(user);
      expect(await adapter.findOne('user-1'), same(user));
      expect(await adapter.findAll(), [same(user)]);

      final updated = TestUser(
        id: 'user-1',
        name: 'Ada Lovelace',
        email: 'ada@example.test',
      );
      await adapter.updateOne(updated);
      expect(await adapter.findOne('user-1'), same(updated));

      await adapter.deleteOne('user-1');
      expect(await adapter.findOne('user-1'), isNull);
      expect(adapter.operationLog, [
        'createOne(user-1)',
        'findOne(user-1)',
        'findAll()',
        'updateOne(user-1)',
        'findOne(user-1)',
        'deleteOne(user-1)',
        'findOne(user-1)',
      ]);
    });

    test('can transform created models with a server ID strategy', () async {
      final adapter = _ServerIdMemoryAdapter();
      final user = TestUser(
        id: 'temporary-client-id',
        name: 'Grace',
        email: 'grace@example.test',
      );

      final created = await adapter.createOne(user);

      expect(created?.id, 'server-1000');
      expect(adapter.remoteData.keys, ['server-1000']);
      expect(adapter.operationLog, ['createOne(temporary-client-id)']);
    });

    test('supports failure injection before mutating remote data', () async {
      final adapter = _TestUserMemoryAdapter();
      adapter.failNextOperation('create rejected');

      await expectLater(
        adapter.createOne(
          TestUser(
            id: 'user-2',
            name: 'Linus',
            email: 'linus@example.test',
          ),
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('create rejected'),
          ),
        ),
      );

      expect(adapter.remoteData, isEmpty);
      expect(adapter.operationLog, ['createOne(user-2)']);
    });
  });
}

class _TestUserMemoryAdapter extends InMemoryApiAdapter<TestUser> {
  _TestUserMemoryAdapter()
      : super(
          type: 'user',
          pluralType: 'users',
          fromJsonFactory: (json) => TestUser(
            id: json['id'] as String,
            name: json['name'] as String,
            email: json['email'] as String,
          ),
          toJsonFactory: (model) => model.toJson(),
        );
}

class _ServerIdMemoryAdapter extends _TestUserMemoryAdapter {
  int _nextServerId = 1000;

  @override
  TestUser createRemoteModel(TestUser model) {
    return TestUser(
      id: 'server-${_nextServerId++}',
      name: model.name,
      email: model.email,
    );
  }
}
