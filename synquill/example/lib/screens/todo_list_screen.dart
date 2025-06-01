import 'package:drift_db_viewer/drift_db_viewer.dart';
import 'package:flutter/material.dart';
import 'package:synquill_example/models/index.dart';
import 'package:synquill_example/synquill.generated.dart';

class TodoListScreen extends StatefulWidget {
  const TodoListScreen({
    super.key,
  });

  @override
  State<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends State<TodoListScreen>
    with WidgetsBindingObserver {
  final List<Todo> _todos = [];
  final List<User> _users = [];
  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUsers().then((_) async {
        _users.firstOrNull
            ?.loadTodos(
          loadPolicy: DataLoadPolicy.localThenRemote,
        )
            .then((todos) {
          // should load todos from the remote
        });
        final stream = _users.firstOrNull?.watchTodos();
        if (stream != null) {
          stream.listen((todos) {
            setState(() {
              _todos.clear();
              _todos.addAll(todos);
            });
          });
        } else {
          print('No user found to watch todos.');
        }
      }).catchError((error) {
        print('Error loading users: $error');
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        SynquillStorage.enableForegroundMode(forceSync: true);
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        SynquillStorage.enableBackgroundMode();
        break;
      default:
        break;
    }
  }

  Future<void> _loadUsers() async {
    try {
      // Load users using the static findAll method
      final usersLoaded = await SynquillDataRepository.users.findAll(
        loadPolicy: DataLoadPolicy.localOnly,
      );

      setState(() {
        _users.clear();
        _users.addAll(usersLoaded);
      });
    } catch (error) {
      print('Error loading users: $error');
    }
  }

  Future<void> _addTodo() async {
    if (_textController.text.isNotEmpty) {
      try {
        final newTodo = Todo(
          title: _textController.text,
          isCompleted: false,
          userId: _users.isNotEmpty
              ? _users.first.id
              : 'default_user', // Provide a userId
        );

        try {
          await newTodo.save(
            savePolicy: DataSavePolicy.localFirst,
          );
        } catch (e) {
          rethrow;
        }

        _textController.clear();
      } catch (error) {
        print('Error adding todo: $error');
      }
    }
  }

  Future<void> _toggleTodoCompletion(int index) async {
    try {
      final todo = _todos[index];
      final updatedTodo = Todo(
        id: todo.id,
        title: todo.title,
        isCompleted: !todo.isCompleted,
        userId: todo.userId,
      );

      await updatedTodo.save(
        savePolicy: DataSavePolicy.localFirst,
      );
    } catch (error) {
      print('Error updating todo: $error');
    }
  }

  Future<void> _deleteTodo(int index) async {
    try {
      await SynquillDataRepository.todos.delete(
        _todos[index].id,
        savePolicy: DataSavePolicy.remoteFirst,
      );
    } catch (error) {
      print('Error deleting todo: $error');
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Synced Storage Todo Example'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.storage),
            tooltip: 'Open Drift DB Viewer',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => DriftDbViewer(SynquillStorage.database),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Add todo section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Enter a new todo...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addTodo(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _addTodo, child: const Text('Add')),
              ],
            ),
          ),
          // Todo list
          Expanded(
            child: _todos.isEmpty
                ? const Center(
                    child: Text(
                      'No todos yet. Add one above!',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _todos.length,
                    itemBuilder: (context, index) {
                      final todo = _todos[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 4.0,
                        ),
                        child: ListTile(
                          leading: Checkbox(
                            value: todo.isCompleted,
                            onChanged: (_) => _toggleTodoCompletion(index),
                          ),
                          title: Text(
                            todo.title,
                            style: TextStyle(
                              decoration: todo.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: todo.isCompleted ? Colors.grey : null,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                todo.isCompleted ? 'Completed' : 'Pending',
                                style: TextStyle(
                                  color: todo.isCompleted
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              ),
                              Text(
                                'Created: ${_formatDateTime(todo.createdAt ?? DateTime.now())}',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54),
                              ),
                              Text(
                                'Updated: ${_formatDateTime(todo.updatedAt ?? DateTime.now())}',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _deleteTodo(index),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
