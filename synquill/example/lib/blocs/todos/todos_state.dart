part of 'todos_bloc.dart';

/// States for the todos BLoC
abstract class TodosState {}

/// Initial state
class TodosInitial extends TodosState {}

/// Loading state
class TodosLoading extends TodosState {}

/// Loaded state with todos
class TodosLoaded extends TodosState {
  final List<Todo> todos;

  TodosLoaded(this.todos);
}

/// Error state
class TodosError extends TodosState {
  final String message;

  TodosError(this.message);
}
