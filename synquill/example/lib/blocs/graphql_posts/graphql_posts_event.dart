part of 'graphql_posts_bloc.dart';

/// Base class for GraphQL posts screen events.
abstract class GraphqlPostsEvent {}

/// Loads posts from the GraphQL endpoint.
class GraphqlPostsLoadRequested extends GraphqlPostsEvent {}

/// Creates a new post through the GraphQL repository.
class GraphqlPostCreateRequested extends GraphqlPostsEvent {
  final String title;
  final String body;

  GraphqlPostCreateRequested({required this.title, required this.body});
}

/// Updates a selected post.
class GraphqlPostUpdateRequested extends GraphqlPostsEvent {
  final String postId;
  final String title;
  final String body;

  GraphqlPostUpdateRequested({
    required this.postId,
    required this.title,
    required this.body,
  });
}

/// Deletes a selected post through the GraphQL endpoint.
class GraphqlPostDeleteRequested extends GraphqlPostsEvent {
  final String postId;

  GraphqlPostDeleteRequested(this.postId);
}

/// Internal event emitted when local GraphQL post storage changes.
class _GraphqlPostsChanged extends GraphqlPostsEvent {
  final List<GraphqlPost> posts;

  _GraphqlPostsChanged(this.posts);
}
