part of 'home_bloc.dart';

/// Base class for all HomeEvents
abstract class HomeEvent {}

/// Event to load the home screen data
class HomeLoadRequested extends HomeEvent {}

/// Event to refresh user data from repositories
class HomeDataRefreshRequested extends HomeEvent {}

/// Event when user data changes (internal use)
class HomeUserDataChanged extends HomeEvent {
  final User user;
  final List<Todo> todos;
  final List<Post> posts;

  HomeUserDataChanged({
    required this.user,
    required this.todos,
    required this.posts,
  });
}

/// Event when todos change
class HomeTodosChanged extends HomeEvent {
  final List<Todo> todos;

  HomeTodosChanged(this.todos);
}

/// Event when posts change
class HomePostsChanged extends HomeEvent {
  final List<Post> posts;

  HomePostsChanged(this.posts);
}

/// Event when users change
class HomeUsersChanged extends HomeEvent {
  final List<User> users;

  HomeUsersChanged(this.users);
}
