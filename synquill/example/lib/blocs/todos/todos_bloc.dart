import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../synquill.generated.dart';
import '../../models/index.dart';

part 'todos_event.dart';
part 'todos_state.dart';

/// BLoC for managing todos state
class TodosBloc extends Bloc<TodosEvent, TodosState> {
  StreamSubscription<List<Todo>>? _todosSubscription;

  TodosBloc() : super(TodosInitial()) {
    on<TodosLoadRequested>(_onTodosLoadRequested);
    on<TodosCreateRequested>(_onTodosCreateRequested);
    on<TodosUpdateRequested>(_onTodosUpdateRequested);
    on<TodosDeleteRequested>(_onTodosDeleteRequested);
    on<_TodosUpdated>(_onTodosUpdated);
  }

  Future<void> _onTodosLoadRequested(
    TodosLoadRequested event,
    Emitter<TodosState> emit,
  ) async {
    emit(TodosLoading());

    try {
      // Get the current user (assuming first user is the current user)
      final users = await SynquillDataRepository.users.findAll();
      if (users.isEmpty) {
        emit(TodosError('No user found. Please create a user first.'));
        return;
      }

      final user = users.first;

      // Start listening to todos changes
      _listenToTodos(user.id);
    } catch (e) {
      emit(TodosError('Failed to load todos: $e'));
    }
  }

  void _listenToTodos(String userId) {
    _todosSubscription?.cancel();
    _todosSubscription = SynquillDataRepository.todos
        .watchAll(
          queryParams: QueryParams(
            sorts: [
              SortCondition(
                  field: TodoFields.updatedAt,
                  direction: SortDirection.descending)
            ],
          ),
        )
        .map((todos) => todos.where((t) => t.userId == userId).toList())
        .listen((todos) {
      add(_TodosUpdated(todos));
    });
  }

  Future<void> _onTodosCreateRequested(
    TodosCreateRequested event,
    Emitter<TodosState> emit,
  ) async {
    try {
      final users = await SynquillDataRepository.users.findAll();
      if (users.isEmpty) {
        emit(TodosError('No user found.'));
        return;
      }

      final user = users.first;

      final newTodo = Todo(
        title: event.title,
        isCompleted: event.completed ?? false,
        userId: user.id,
      );

      await SynquillDataRepository.todos.save(newTodo);

      // The stream listener will automatically emit the updated state
    } catch (e) {
      emit(TodosError('Failed to create todo: $e'));
    }
  }

  Future<void> _onTodosUpdateRequested(
    TodosUpdateRequested event,
    Emitter<TodosState> emit,
  ) async {
    try {
      final users = await SynquillDataRepository.users.findAll();
      if (users.isEmpty) {
        emit(TodosError('No user found.'));
        return;
      }

      final user = users.first;

      final updatedTodo = Todo.fromDb(
        id: event.todoId,
        title: event.title,
        isCompleted: event.completed,
        userId: user.id,
      );

      await SynquillDataRepository.todos.save(updatedTodo);

      // The stream listener will automatically emit the updated state
    } catch (e) {
      emit(TodosError('Failed to update todo: $e'));
    }
  }

  Future<void> _onTodosDeleteRequested(
    TodosDeleteRequested event,
    Emitter<TodosState> emit,
  ) async {
    try {
      await SynquillDataRepository.todos.delete(event.todoId);

      // The stream listener will automatically emit the updated state
    } catch (e) {
      emit(TodosError('Failed to delete todo: $e'));
    }
  }

  void _onTodosUpdated(
    _TodosUpdated event,
    Emitter<TodosState> emit,
  ) {
    emit(TodosLoaded(event.todos));
  }

  @override
  Future<void> close() {
    _todosSubscription?.cancel();
    return super.close();
  }
}
