part of 'graphql_posts_bloc.dart';

/// State for the GraphQL posts screen.
class GraphqlPostsState {
  final List<GraphqlPost> posts;
  final bool isLoading;
  final String? statusMessage;
  final String? errorMessage;

  const GraphqlPostsState({
    this.posts = const [],
    this.isLoading = false,
    this.statusMessage,
    this.errorMessage,
  });

  GraphqlPostsState copyWith({
    List<GraphqlPost>? posts,
    bool? isLoading,
    String? statusMessage,
    String? errorMessage,
    bool clearStatus = false,
    bool clearError = false,
  }) {
    return GraphqlPostsState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      statusMessage: clearStatus ? null : statusMessage ?? this.statusMessage,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}
