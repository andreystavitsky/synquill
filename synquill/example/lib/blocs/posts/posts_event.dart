part of 'posts_bloc.dart';

/// Base class for all PostsEvents
abstract class PostsEvent {}

/// Event to load all posts
class PostsLoadRequested extends PostsEvent {}

/// Event to create a new post
class PostsCreateRequested extends PostsEvent {
  final String title;
  final String body;

  PostsCreateRequested({
    required this.title,
    required this.body,
  });
}

/// Event to update an existing post
class PostsUpdateRequested extends PostsEvent {
  final String postId;
  final String title;
  final String body;

  PostsUpdateRequested({
    required this.postId,
    required this.title,
    required this.body,
  });
}

/// Event to delete a post
class PostsDeleteRequested extends PostsEvent {
  final String postId;

  PostsDeleteRequested(this.postId);
}

/// Internal event when posts are updated via stream
class _PostsUpdated extends PostsEvent {
  final List<Post> posts;

  _PostsUpdated(this.posts);
}
