import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/index.dart';

part 'graphql_posts_event.dart';
part 'graphql_posts_state.dart';

/// BLoC for the GraphQL placeholder posts example.
class GraphqlPostsBloc extends Bloc<GraphqlPostsEvent, GraphqlPostsState> {
  StreamSubscription<List<GraphqlPost>>? _postsSubscription;

  GraphqlPostsBloc() : super(const GraphqlPostsState()) {
    on<GraphqlPostsLoadRequested>(_onLoadRequested);
    on<GraphqlPostCreateRequested>(_onCreateRequested);
    on<GraphqlPostUpdateRequested>(_onUpdateRequested);
    on<GraphqlPostDeleteRequested>(_onDeleteRequested);
    on<_GraphqlPostsChanged>(_onPostsChanged);
  }

  Future<void> _onLoadRequested(
    GraphqlPostsLoadRequested event,
    Emitter<GraphqlPostsState> emit,
  ) async {
    emit(state.copyWith(
      isLoading: true,
      statusMessage: 'Loading GraphQL posts...',
      clearError: true,
    ));
    _watchLocalPosts();

    try {
      final posts = await SynquillStorage.instance.graphqlPosts.findAll(
        queryParams: const QueryParams(
          pagination: PaginationParams.limit(10),
          sorts: [
            SortCondition(
              field: GraphqlPostFields.updatedAt,
              direction: SortDirection.descending,
            ),
            SortCondition(
              field: GraphqlPostFields.id,
              direction: SortDirection.ascending,
            ),
          ],
        ),
      );
      emit(state.copyWith(
        posts: posts,
        isLoading: false,
        statusMessage: 'Loaded ${posts.length} posts.',
        clearError: true,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load GraphQL posts: $e',
        clearStatus: true,
      ));
    }
  }

  Future<void> _onCreateRequested(
    GraphqlPostCreateRequested event,
    Emitter<GraphqlPostsState> emit,
  ) async {
    try {
      final newPost = GraphqlPost(
        title: event.title,
        body: event.body,
        userId: 1,
      );
      await SynquillStorage.instance.graphqlPosts.save(newPost);
    } catch (e) {
      emit(state.copyWith(
        errorMessage: 'Failed to create GraphQL post: $e',
      ));
    }
  }

  Future<void> _onUpdateRequested(
    GraphqlPostUpdateRequested event,
    Emitter<GraphqlPostsState> emit,
  ) async {
    try {
      final updated = GraphqlPost.fromDb(
        id: event.postId,
        title: event.title,
        body: event.body,
        userId: 1,
      );
      await SynquillStorage.instance.graphqlPosts.save(updated);
    } catch (e) {
      emit(state.copyWith(
        errorMessage: 'Failed to update GraphQL post: $e',
      ));
    }
  }

  Future<void> _onDeleteRequested(
    GraphqlPostDeleteRequested event,
    Emitter<GraphqlPostsState> emit,
  ) async {
    try {
      await SynquillStorage.instance.graphqlPosts.delete(event.postId);
    } catch (e) {
      emit(state.copyWith(
        errorMessage: 'Failed to delete GraphQL post: $e',
      ));
    }
  }

  void _onPostsChanged(
    _GraphqlPostsChanged event,
    Emitter<GraphqlPostsState> emit,
  ) {
    emit(state.copyWith(
      posts: event.posts,
      statusMessage: 'Loaded ${event.posts.length} posts.',
    ));
  }

  void _watchLocalPosts() {
    _postsSubscription ??= SynquillStorage.instance.graphqlPosts
        .watchAll(
      queryParams: const QueryParams(
        sorts: [
          SortCondition(
            field: GraphqlPostFields.updatedAt,
            direction: SortDirection.descending,
          ),
          SortCondition(
            field: GraphqlPostFields.id,
            direction: SortDirection.ascending,
          ),
        ],
      ),
    )
        .listen((posts) {
      if (!isClosed) {
        add(_GraphqlPostsChanged(posts));
      }
    });
  }

  @override
  Future<void> close() {
    _postsSubscription?.cancel();
    return super.close();
  }
}
