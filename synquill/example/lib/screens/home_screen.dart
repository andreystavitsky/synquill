import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/home/home_bloc.dart';
import '../models/index.dart';
import 'posts_screen.dart';
import 'todos_screen.dart';

/// Home screen showing user overview and navigation to posts/todos
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => HomeBloc()..add(HomeLoadRequested()),
      child: const HomeView(),
    );
  }
}

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Synced Data Storage'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: BlocBuilder<HomeBloc, HomeState>(
        builder: (context, state) {
          if (state is HomeLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (state is HomeError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.message,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      context.read<HomeBloc>().add(HomeLoadRequested());
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (state is HomeLoaded) {
            return _buildHomeContent(context, state);
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildHomeContent(BuildContext context, HomeLoaded state) {
    final user = state.user;
    final posts = state.posts;
    final todos = state.todos;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome back, ${user.name}!',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'User ID: ${user.id}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Stats Section
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  'Posts',
                  posts.length.toString(),
                  Icons.article,
                  Colors.blue,
                  () => _navigateToPosts(context),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  context,
                  'Todos',
                  todos.length.toString(),
                  Icons.check_circle,
                  Colors.green,
                  () => _navigateToTodos(context),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Recent Posts Section
          if (posts.isNotEmpty) ...[
            _buildSectionHeader(
                context, 'Recent Posts', () => _navigateToPosts(context)),
            const SizedBox(height: 8),
            _buildRecentPosts(context, posts.take(3).toList()),
            const SizedBox(height: 24),
          ],

          // Recent Todos Section
          if (todos.isNotEmpty) ...[
            _buildSectionHeader(
                context, 'Recent Todos', () => _navigateToTodos(context)),
            const SizedBox(height: 8),
            _buildRecentTodos(context, todos.take(5).toList()),
          ],

          // Empty State
          if (posts.isEmpty && todos.isEmpty) ...[
            const SizedBox(height: 32),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No content yet',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create your first post or todo to get started!',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _navigateToPosts(context),
                        icon: const Icon(Icons.article),
                        label: const Text('Create Post'),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () => _navigateToTodos(context),
                        icon: const Icon(Icons.add_task),
                        label: const Text('Add Todo'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String title,
    String count,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(
                icon,
                size: 32,
                color: color,
              ),
              const SizedBox(height: 8),
              Text(
                count,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
      BuildContext context, String title, VoidCallback onViewAll) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        TextButton(
          onPressed: onViewAll,
          child: const Text('View All'),
        ),
      ],
    );
  }

  Widget _buildRecentPosts(BuildContext context, List<Post> posts) {
    return Column(
      children: posts.map((post) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const CircleAvatar(
              child: Icon(Icons.article),
            ),
            title: Text(
              post.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              post.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _navigateToPosts(context),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRecentTodos(BuildContext context, List<Todo> todos) {
    return Column(
      children: todos.map((todo) {
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: todo.isCompleted ? Colors.green : Colors.orange,
              child: Icon(
                todo.isCompleted ? Icons.check : Icons.radio_button_unchecked,
                color: Colors.white,
              ),
            ),
            title: Text(
              todo.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                decoration:
                    todo.isCompleted ? TextDecoration.lineThrough : null,
              ),
            ),
            onTap: () => _navigateToTodos(context),
          ),
        );
      }).toList(),
    );
  }

  void _navigateToPosts(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const PostsScreen(),
      ),
    );
  }

  void _navigateToTodos(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const TodosScreen(),
      ),
    );
  }
}
