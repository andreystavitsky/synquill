import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/graphql_posts/graphql_posts_bloc.dart';
import '../models/index.dart';

/// Screen for exercising the GraphQL adapter with placeholder posts.
class GraphqlPostsScreen extends StatelessWidget {
  const GraphqlPostsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => GraphqlPostsBloc()..add(GraphqlPostsLoadRequested()),
      child: const GraphqlPostsView(),
    );
  }
}

class GraphqlPostsView extends StatelessWidget {
  const GraphqlPostsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GraphQL Posts'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<GraphqlPostsBloc>().add(GraphqlPostsLoadRequested());
            },
          ),
        ],
      ),
      body: BlocBuilder<GraphqlPostsBloc, GraphqlPostsState>(
        builder: (context, state) {
          return Column(
            children: [
              if (state.isLoading) const LinearProgressIndicator(),
              _StatusBanner(state: state),
              Expanded(
                child: _GraphqlPostsList(posts: state.posts),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreatePostDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showCreatePostDialog(BuildContext context) {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create GraphQL Post'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: bodyController,
              decoration: const InputDecoration(
                labelText: 'Body',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final title = titleController.text.trim();
              final body = bodyController.text.trim();

              if (title.isNotEmpty && body.isNotEmpty) {
                context.read<GraphqlPostsBloc>().add(GraphqlPostCreateRequested(
                      title: title,
                      body: body,
                    ));
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.state});

  final GraphqlPostsState state;

  @override
  Widget build(BuildContext context) {
    final message = state.errorMessage ?? state.statusMessage;
    if (message == null) return const SizedBox.shrink();

    final isError = state.errorMessage != null;
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      color: isError ? colors.errorContainer : colors.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.cloud_done,
            color:
                isError ? colors.onErrorContainer : colors.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isError
                        ? colors.onErrorContainer
                        : colors.onSecondaryContainer,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GraphqlPostsList extends StatelessWidget {
  const _GraphqlPostsList({required this.posts});

  final List<GraphqlPost> posts;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_queue,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No GraphQL posts loaded',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                context
                    .read<GraphqlPostsBloc>()
                    .add(GraphqlPostsLoadRequested());
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Load posts'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              child: Text(post.id
                  .substring(0, post.id.length > 3 ? 3 : post.id.length)),
            ),
            title: Text(
              post.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              post.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'update') {
                  _showEditPostDialog(context, post);
                } else if (value == 'delete') {
                  _showDeletePostDialog(context, post);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'update',
                  child: Row(
                    children: [
                      Icon(Icons.edit),
                      SizedBox(width: 8),
                      Text('Update'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete),
                      SizedBox(width: 8),
                      Text('Delete'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditPostDialog(BuildContext context, GraphqlPost post) {
    final titleController = TextEditingController(text: post.title);
    final bodyController = TextEditingController(text: post.body);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit GraphQL Post'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: bodyController,
              decoration: const InputDecoration(
                labelText: 'Body',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final title = titleController.text.trim();
              final body = bodyController.text.trim();

              if (title.isNotEmpty && body.isNotEmpty) {
                context.read<GraphqlPostsBloc>().add(GraphqlPostUpdateRequested(
                      postId: post.id,
                      title: title,
                      body: body,
                    ));
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showDeletePostDialog(BuildContext context, GraphqlPost post) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete GraphQL Post'),
        content: Text(
          'Are you sure you want to delete "${post.title}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              context
                  .read<GraphqlPostsBloc>()
                  .add(GraphqlPostDeleteRequested(post.id));
              Navigator.of(dialogContext).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
