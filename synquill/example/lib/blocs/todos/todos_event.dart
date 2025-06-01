part of 'todos_bloc.dart';

/// Events for the todos BLoC
abstract class TodosEvent {}

/// Event to load todos
class TodosLoadRequested extends TodosEvent {}

/// Event to create a new todo
class TodosCreateRequested extends TodosEvent {
  final String title;
  final bool? completed;

  TodosCreateRequested({
    required this.title,
    this.completed = false,
  });
}

/// Event to update an existing todo
class TodosUpdateRequested extends TodosEvent {
  final String todoId;
  final String title;
  final bool completed;

  TodosUpdateRequested({
    required this.todoId,
    required this.title,
    required this.completed,
  });
}

/// Event to delete a todo
class TodosDeleteRequested extends TodosEvent {
  final String todoId;

  TodosDeleteRequested(this.todoId);
}

/// Internal event when todos are updated
class _TodosUpdated extends TodosEvent {
  final List<Todo> todos;

  _TodosUpdated(this.todos);
}
