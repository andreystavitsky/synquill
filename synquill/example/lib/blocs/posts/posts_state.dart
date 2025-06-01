part of 'posts_bloc.dart';

/// States for the Posts screen
abstract class PostsState {}

/// Initial state when the posts screen is first loaded
class PostsInitial extends PostsState {}

/// Loading state while fetching or modifying posts
class PostsLoading extends PostsState {}

/// State when posts are successfully loaded
class PostsLoaded extends PostsState {
  final List<Post> posts;

  PostsLoaded(this.posts);
}

/// Success state when an operation completes successfully
class PostsOperationSuccess extends PostsState {
  final String message;
  final List<Post> posts;

  PostsOperationSuccess({
    required this.message,
    required this.posts,
  });
}

/// Error state when something goes wrong
class PostsError extends PostsState {
  final String message;

  PostsError(this.message);
}
