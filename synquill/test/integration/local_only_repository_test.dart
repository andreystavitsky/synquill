import 'package:synquill/synquill.generated.dart';
import 'package:test/test.dart';

// Import from example project to get LocalNote model and generated code
import 'package:synquill/src/test_models/index.dart';

void main() {
  group('Local-only Repository Tests', () {
    late SynquillDatabase database;
    late LocalNoteRepository localRepo;

    setUp(() async {
      // Create an in-memory database for testing
      database = SynquillDatabase(NativeDatabase.memory());

      // Initialize SynquillStorage with the database
      await SynquillStorage.init(
        database: database,
        config: const SynquillStorageConfig(
          defaultSavePolicy: DataSavePolicy.localFirst,
          defaultLoadPolicy: DataLoadPolicy.localOnly,
        ),
        enableInternetMonitoring: false,
      );

      localRepo = LocalNoteRepository(database);
    });

    tearDown(() async {
      await SynquillStorage.close();
      await database.close();
    });

    group('Local-only Repository API restrictions', () {
      test('apiAdapter throws UnsupportedError', () {
        expect(
          () => localRepo.apiAdapter,
          throwsA(isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains('API adapter not available for local-only repository'),
          )),
        );
      });

      test('fetchFromRemote returns null', () async {
        final result = await localRepo.fetchFromRemote('test-id');
        expect(result, isNull);
      });

      test('fetchAllFromRemote returns empty list', () async {
        final result = await localRepo.fetchAllFromRemote();
        expect(result, isEmpty);
      });
    });

    group('Local-only Repository local operations', () {
      test('can save items locally', () async {
        final note = LocalNote(
          id: 'test-1',
          content: 'Test Content',
          ownerId: 'user-1',
        );

        // Save the note
        await localRepo.save(note);

        // Verify it was saved using findOne
        final saved = await localRepo.findOne('test-1');
        expect(saved, isNotNull);
        expect(saved!.content, equals('Test Content'));
        expect(saved.ownerId, equals('user-1'));
      });

      test('can update items locally', () async {
        final note = LocalNote(
          id: 'test-2',
          content: 'Original Content',
          ownerId: 'user-1',
        );

        // Save the note
        await localRepo.save(note);

        // Update the note (by creating new instance with same ID)
        final updated = LocalNote(
          id: 'test-2',
          content: 'Updated Content',
          ownerId: 'user-1',
          category: 'Important',
        );
        await localRepo.save(updated);

        // Verify the update
        final saved = await localRepo.findOne('test-2');
        expect(saved!.content, equals('Updated Content'));
        expect(saved.category, equals('Important'));
      });

      test('can delete items locally', () async {
        final note = LocalNote(
          id: 'test-3',
          content: 'This will be deleted',
          ownerId: 'user-1',
        );

        // Save the note
        await localRepo.save(note);

        // Verify it exists
        var saved = await localRepo.findOne('test-3');
        expect(saved, isNotNull);

        // Delete the note
        await localRepo.delete('test-3');

        // Verify it's gone
        saved = await localRepo.findOne('test-3');
        expect(saved, isNull);
      });

      test('can find all items locally', () async {
        final notes = [
          LocalNote(
            id: 'test-4',
            content: 'Content 1',
            ownerId: 'user-1',
          ),
          LocalNote(
            id: 'test-5',
            content: 'Content 2',
            ownerId: 'user-1',
          ),
          LocalNote(
            id: 'test-6',
            content: 'Content 3',
            ownerId: 'user-1',
          ),
        ];

        // Save all notes
        for (final note in notes) {
          await localRepo.save(note);
        }

        // Find all notes
        final found = await localRepo.findAll();
        expect(found.length, greaterThanOrEqualTo(3));

        // Verify all our notes are there
        final foundIds = found.map((n) => n.id).toSet();
        expect(foundIds, containsAll(['test-4', 'test-5', 'test-6']));
      });

      test('supports filtering with QueryParams', () async {
        final notes = [
          LocalNote(
            id: 'filter-1',
            content: 'Important note content',
            ownerId: 'user-1',
            category: 'Important',
          ),
          LocalNote(
            id: 'filter-2',
            content: 'Regular note content',
            ownerId: 'user-1',
            category: 'Regular',
          ),
          LocalNote(
            id: 'filter-3',
            content: 'Another important item',
            ownerId: 'user-1',
            category: 'Important',
          ),
        ];

        // Save all notes
        for (final note in notes) {
          await localRepo.save(note);
        }

        // Find notes with "Important" category
        final importantNotes = await localRepo.findAll(
          queryParams: QueryParams(
            filters: [
              LocalNoteFields.category.equals('Important'),
            ],
          ),
        );

        expect(importantNotes.length, equals(2));
        final importantIds = importantNotes.map((n) => n.id);
        expect(importantIds, containsAll(['filter-1', 'filter-3']));
      });

      test('supports pagination with QueryParams', () async {
        // Create 10 test notes
        final notes = List.generate(
            10,
            (i) => LocalNote(
                  id: 'page-$i',
                  content: 'Content $i',
                  ownerId: 'user-1',
                ));

        // Save all notes
        for (final note in notes) {
          await localRepo.save(note);
        }

        // Test pagination
        final firstPage = await localRepo.findAll(
          queryParams: const QueryParams(
            pagination: PaginationParams(limit: 3, offset: 0),
            sorts: [
              SortCondition(
                field: LocalNoteFields.id,
                direction: SortDirection.ascending,
              ),
            ],
          ),
        );

        expect(firstPage.length, equals(3));

        final secondPage = await localRepo.findAll(
          queryParams: const QueryParams(
            pagination: PaginationParams(limit: 3, offset: 3),
            sorts: [
              SortCondition(
                field: LocalNoteFields.id,
                direction: SortDirection.ascending,
              ),
            ],
          ),
        );

        expect(secondPage.length, equals(3));

        // Verify no overlap
        final firstPageIds = firstPage.map((n) => n.id).toSet();
        final secondPageIds = secondPage.map((n) => n.id).toSet();
        expect(firstPageIds.intersection(secondPageIds), isEmpty);
      });
    });

    group('Local-only Repository behavior verification', () {
      test('only uses local database (loadPolicy ignored)', () async {
        final note = LocalNote(
          id: 'policy-test',
          content: 'Policy test content',
          ownerId: 'user-1',
        );

        await localRepo.save(note);

        // Test that different load policies all work the same
        // (only local database is used)
        final localOnly = await localRepo.findOne(
          'policy-test',
          loadPolicy: DataLoadPolicy.localOnly,
        );
        final localThenRemote = await localRepo.findOne(
          'policy-test',
          loadPolicy: DataLoadPolicy.localThenRemote,
        );
        final remoteFirst = await localRepo.findOne(
          'policy-test',
          loadPolicy: DataLoadPolicy.remoteFirst,
        );

        expect(localOnly, isNotNull);
        expect(localThenRemote, isNotNull);
        expect(remoteFirst, isNotNull);

        expect(localOnly!.content, equals('Policy test content'));
        expect(localThenRemote!.content, equals('Policy test content'));
        expect(remoteFirst!.content, equals('Policy test content'));
      });

      test('handles non-existent items gracefully', () async {
        // Try to find a non-existent item
        final result = await localRepo.findOne('non-existent');
        expect(result, isNull);

        // Try to delete a non-existent item (should not throw)
        expect(() => localRepo.delete('non-existent'), returnsNormally);
      });

      test('concurrent operations work correctly', () async {
        final note = LocalNote(
          id: 'concurrent-test',
          content: 'Concurrent test content',
          ownerId: 'user-1',
        );

        // Perform multiple operations concurrently
        final futures = [
          localRepo.save(note),
          localRepo.save(LocalNote(
            id: note.id,
            content: note.content,
            ownerId: note.ownerId,
            category: 'Updated',
          )),
          localRepo.findOne('concurrent-test'),
        ];

        final results = await Future.wait(futures);
        expect(results.length, equals(3));

        // Verify final state
        final finalNote = await localRepo.findOne('concurrent-test');
        expect(finalNote, isNotNull);
      });
    });

    group('Local-only Repository edge cases', () {
      test('handles empty queries', () async {
        // Test findAll with no items
        final allNotes = await localRepo.findAll();
        expect(allNotes, isA<List<LocalNote>>());

        // Test with empty QueryParams
        final notesWithEmptyQuery = await localRepo.findAll(
          queryParams: QueryParams.empty,
        );
        expect(notesWithEmptyQuery, isA<List<LocalNote>>());
      });

      test('handles special characters in content', () async {
        final note = LocalNote(
          id: 'special-chars',
          content: 'Content with émojis 🎉 and special chars: @#\$%^&*()',
          ownerId: 'user-1',
        );

        await localRepo.save(note);

        final saved = await localRepo.findOne('special-chars');
        expect(saved, isNotNull);
        expect(
          saved!.content,
          equals('Content with émojis 🎉 and special chars: @#\$%^&*()'),
        );
      });

      test('handles null optional fields', () async {
        final note = LocalNote(
          id: 'null-category',
          content: 'Note with null category',
          ownerId: 'user-1',
          category: null, // Explicitly set to null
        );

        await localRepo.save(note);

        final saved = await localRepo.findOne('null-category');
        expect(saved, isNotNull);
        expect(saved!.category, isNull);
      });
    });

    group('Local-only Repository remoteFirst behavior', () {
      test('remoteFirst delete works for localOnly repository', () async {
        final note = LocalNote(
          id: 'remotefirst-1',
          content: 'Should be deleted with remoteFirst',
          ownerId: 'user-remote',
        );

        // Save the note
        await localRepo.save(note);

        // Verify it exists
        var saved = await localRepo.findOne('remotefirst-1');
        expect(saved, isNotNull);

        // Delete the note with remoteFirst policy
        await localRepo.delete(
          'remotefirst-1',
          savePolicy: DataSavePolicy.remoteFirst,
        );

        // Verify it's gone
        saved = await localRepo.findOne('remotefirst-1');
        expect(saved, isNull);
      });

      test('remoteFirst save works for localOnly repository', () async {
        final note = LocalNote(
          id: 'remotefirst-save-1',
          content: 'Should be saved with remoteFirst',
          ownerId: 'user-remote',
        );

        // Save the note with remoteFirst policy
        await localRepo.save(
          note,
          savePolicy: DataSavePolicy.remoteFirst,
        );

        // Verify it was saved
        final saved = await localRepo.findOne('remotefirst-save-1');
        expect(saved, isNotNull);
        expect(saved!.content, equals('Should be saved with remoteFirst'));
      });

      test('remoteFirst find works for localOnly repository', () async {
        final note = LocalNote(
          id: 'remotefirst-find-1',
          content: 'Should be found with remoteFirst',
          ownerId: 'user-remote',
        );

        // Save the note
        await localRepo.save(note);

        // Find the note with remoteFirst load policy
        final found = await localRepo.findOne(
          'remotefirst-find-1',
          loadPolicy: DataLoadPolicy.remoteFirst,
        );
        expect(found, isNotNull);
        expect(found!.content, equals('Should be found with remoteFirst'));
      });
    });
  });
}
