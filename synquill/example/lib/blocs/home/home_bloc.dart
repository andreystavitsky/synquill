import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/index.dart';
import '../../synquill.generated.dart';

part 'home_event.dart';
part 'home_state.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  static const String _currentUserId = '1';

  StreamSubscription<List<Todo>>? _todosSubscription;
  StreamSubscription<List<Post>>? _postsSubscription;
  StreamSubscription<List<User>>? _usersSubscription;

  HomeBloc() : super(HomeInitial()) {
    on<HomeLoadRequested>(_onLoadRequested);
    on<HomeDataRefreshRequested>(_onDataRefreshRequested);
    on<HomeUserDataChanged>(_onUserDataChanged);
    on<HomeTodosChanged>(_onTodosChanged);
    on<HomePostsChanged>(_onPostsChanged);
    on<HomeUsersChanged>(_onUsersChanged);
  }

  Future<void> _onLoadRequested(
    HomeLoadRequested event,
    Emitter<HomeState> emit,
  ) async {
    developer.log('[HomeBloc] Load requested', name: 'HomeBloc');
    emit(HomeLoading());
    await _loadData(emit);
    _startWatchingData();
  }

  Future<void> _onDataRefreshRequested(
    HomeDataRefreshRequested event,
    Emitter<HomeState> emit,
  ) async {
    developer.log('[HomeBloc] Data refresh requested', name: 'HomeBloc');
    await _loadData(emit);
  }

  Future<void> _onUserDataChanged(
    HomeUserDataChanged event,
    Emitter<HomeState> emit,
  ) async {
    developer.log('[HomeBloc] User data changed - updating state',
        name: 'HomeBloc');
    emit(HomeLoaded(
      user: event.user,
      todos: event.todos,
      posts: event.posts,
    ));
  }

  Future<void> _onTodosChanged(
    HomeTodosChanged event,
    Emitter<HomeState> emit,
  ) async {
    if (state is HomeLoaded) {
      developer.log('[HomeBloc] Todos changed - updating state',
          name: 'HomeBloc');
      final currentState = state as HomeLoaded;
      final userTodos =
          event.todos.where((todo) => todo.userId == _currentUserId).toList();

      // Only emit if todos actually changed
      if (!_listsEqual(currentState.todos, userTodos)) {
        emit(currentState.copyWith(todos: userTodos));
      }
    }
  }

  Future<void> _onPostsChanged(
    HomePostsChanged event,
    Emitter<HomeState> emit,
  ) async {
    if (state is HomeLoaded) {
      developer.log('[HomeBloc] Posts changed - updating state',
          name: 'HomeBloc');
      final currentState = state as HomeLoaded;
      final userPosts =
          event.posts.where((post) => post.userId == _currentUserId).toList();

      // Only emit if posts actually changed
      if (!_listsEqual(currentState.posts, userPosts)) {
        emit(currentState.copyWith(posts: userPosts));
      }
    }
  }

  Future<void> _onUsersChanged(
    HomeUsersChanged event,
    Emitter<HomeState> emit,
  ) async {
    if (state is HomeLoaded) {
      developer.log('[HomeBloc] Users changed - updating state',
          name: 'HomeBloc');
      final currentState = state as HomeLoaded;
      final currentUser =
          event.users.where((user) => user.id == _currentUserId).firstOrNull;

      if (currentUser != null && currentUser != currentState.user) {
        emit(currentState.copyWith(user: currentUser));
      }
    }
  }

  void _startWatchingData() {
    developer.log('[HomeBloc] Starting to watch data changes',
        name: 'HomeBloc');

    // Cancel any existing subscriptions
    _todosSubscription?.cancel();
    _postsSubscription?.cancel();
    _usersSubscription?.cancel();

    // Watch todos changes
    _todosSubscription = SynquillDataRepository.todos
        .watchAll(
      queryParams: QueryParams(
        sorts: [
          SortCondition(
              field: TodoFields.updatedAt, direction: SortDirection.descending)
        ],
      ),
    )
        .listen((todos) {
      if (!isClosed) {
        add(HomeTodosChanged(todos));
      }
    });

    // Watch posts changes
    _postsSubscription = SynquillDataRepository.posts
        .watchAll(
      queryParams: QueryParams(
        sorts: [
          SortCondition(
              field: PostFields.updatedAt, direction: SortDirection.descending)
        ],
      ),
    )
        .listen((posts) {
      if (!isClosed) {
        add(HomePostsChanged(posts));
      }
    });

    // Watch user changes
    _usersSubscription =
        SynquillDataRepository.users.watchAll().listen((users) {
      if (!isClosed) {
        add(HomeUsersChanged(users));
      }
    });
  }

  bool _listsEqual<T>(List<T> list1, List<T> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }

  Future<void> _loadData(Emitter<HomeState> emit) async {
    try {
      developer.log('[HomeBloc] Loading data for user $_currentUserId',
          name: 'HomeBloc');

      // Load user data
      final users = await SynquillDataRepository.users.findAll();
      final currentUser =
          users.where((user) => user.id == _currentUserId).firstOrNull;

      if (currentUser == null) {
        developer.log('[HomeBloc] User $_currentUserId not found',
            name: 'HomeBloc');
        emit(HomeError('User not found'));
        return;
      }

      /*// Load todos and posts for the current user
      final todos = await SyncedRepository.todos.findAll();
      final posts = await SyncedRepository.posts.findAll();

      final userTodos =
          todos.where((todo) => todo.userId == _currentUserId).toList();
      final userPosts =
          posts.where((post) => post.userId == _currentUserId).toList();

      developer.log(
          '[HomeBloc] Data loaded - todos: ${userTodos.length}, posts: ${userPosts.length}',
          name: 'HomeBloc');*/

      emit(HomeLoaded(
        user: currentUser,
        todos: [],
        posts: [],
      ));
    } catch (e, stackTrace) {
      developer.log('[HomeBloc] Error loading data: $e',
          name: 'HomeBloc', error: e, stackTrace: stackTrace);
      emit(HomeError('Failed to load data: $e'));
    }
  }

  @override
  Future<void> close() {
    _todosSubscription?.cancel();
    _postsSubscription?.cancel();
    _usersSubscription?.cancel();
    return super.close();
  }
}
