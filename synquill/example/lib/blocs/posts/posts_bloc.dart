import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/index.dart';

part 'posts_event.dart';
part 'posts_state.dart';

/// BLoC for managing posts state
class PostsBloc extends Bloc<PostsEvent, PostsState> {
  StreamSubscription<List<Post>>? _postsSubscription;

  PostsBloc() : super(PostsInitial()) {
    on<PostsLoadRequested>(_onPostsLoadRequested);
    on<PostsCreateRequested>(_onPostsCreateRequested);
    on<PostsUpdateRequested>(_onPostsUpdateRequested);
    on<PostsDeleteRequested>(_onPostsDeleteRequested);
    on<_PostsUpdated>(_onPostsUpdated);
  }

  Future<void> _onPostsLoadRequested(
    PostsLoadRequested event,
    Emitter<PostsState> emit,
  ) async {
    emit(PostsLoading());

    try {
      // Get the current user (assuming first user is the current user)
      final users = await SynquillStorage.instance.users.findAll();
      if (users.isEmpty) {
        emit(PostsError('No user found. Please create a user first.'));
        return;
      }

      final user = users.first;

      // Start listening to posts changes
      _listenToPosts(user.id);
    } catch (e) {
      emit(PostsError('Failed to load posts: $e'));
    }
  }

  void _listenToPosts(String userId) {
    _postsSubscription?.cancel();
    _postsSubscription = SynquillStorage.instance.posts
        .watchAll(
          queryParams: QueryParams(
            sorts: [
              SortCondition(
                  field: PostFields.updatedAt,
                  direction: SortDirection.descending)
            ],
          ),
        )
        .map((posts) => posts.where((p) => p.userId == userId).toList())
        .listen((posts) {
      add(_PostsUpdated(posts));
    });
  }

  Future<void> _onPostsCreateRequested(
    PostsCreateRequested event,
    Emitter<PostsState> emit,
  ) async {
    try {
      final users = await SynquillStorage.instance.users.findAll();
      if (users.isEmpty) {
        emit(PostsError('No user found.'));
        return;
      }

      final user = users.first;

      final newPost = Post(
        title: event.title,
        body: event.body,
        userId: user.id,
      );

      await SynquillStorage.instance.posts.save(newPost);

      // The stream listener will automatically emit the updated state
    } catch (e) {
      emit(PostsError('Failed to create post: $e'));
    }
  }

  Future<void> _onPostsUpdateRequested(
    PostsUpdateRequested event,
    Emitter<PostsState> emit,
  ) async {
    try {
      final users = await SynquillStorage.instance.users.findAll();
      if (users.isEmpty) {
        emit(PostsError('No user found.'));
        return;
      }

      final user = users.first;

      final updatedPost = Post.fromDb(
        id: event.postId,
        title: event.title,
        body: event.body,
        userId: user.id,
      );

      await SynquillStorage.instance.posts.save(updatedPost);

      // The stream listener will automatically emit the updated state
    } catch (e) {
      emit(PostsError('Failed to update post: $e'));
    }
  }

  Future<void> _onPostsDeleteRequested(
    PostsDeleteRequested event,
    Emitter<PostsState> emit,
  ) async {
    try {
      await SynquillStorage.instance.posts.delete(event.postId);

      // The stream listener will automatically emit the updated state
    } catch (e) {
      emit(PostsError('Failed to delete post: $e'));
    }
  }

  void _onPostsUpdated(
    _PostsUpdated event,
    Emitter<PostsState> emit,
  ) {
    emit(PostsLoaded(event.posts));
  }

  @override
  Future<void> close() {
    _postsSubscription?.cancel();
    return super.close();
  }
}
