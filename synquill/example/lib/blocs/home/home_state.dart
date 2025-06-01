part of 'home_bloc.dart';

/// States for the Home screen
abstract class HomeState {}

/// Initial state when the home screen is first loaded
class HomeInitial extends HomeState {}

/// Loading state while fetching user data
class HomeLoading extends HomeState {}

/// State when user data is successfully loaded
class HomeLoaded extends HomeState {
  final User user;
  final List<Todo> todos;
  final List<Post> posts;

  HomeLoaded({
    required this.user,
    required this.todos,
    required this.posts,
  });

  HomeLoaded copyWith({
    User? user,
    List<Todo>? todos,
    List<Post>? posts,
  }) {
    return HomeLoaded(
      user: user ?? this.user,
      todos: todos ?? this.todos,
      posts: posts ?? this.posts,
    );
  }
}

/// Error state when something goes wrong
class HomeError extends HomeState {
  final String message;

  HomeError(this.message);
}
