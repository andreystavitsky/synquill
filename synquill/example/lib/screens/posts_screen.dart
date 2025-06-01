import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../blocs/posts/posts_bloc.dart';
import '../models/index.dart';

/// Screen for managing posts
class PostsScreen extends StatelessWidget {
  const PostsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => PostsBloc()..add(PostsLoadRequested()),
      child: const PostsView(),
    );
  }
}

class PostsView extends StatelessWidget {
  const PostsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Posts'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: BlocBuilder<PostsBloc, PostsState>(
        builder: (context, state) {
          if (state is PostsLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (state is PostsError) {
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
                      context.read<PostsBloc>().add(PostsLoadRequested());
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (state is PostsLoaded) {
            return _buildPostsList(context, state.posts);
          }

          return const SizedBox.shrink();
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreatePostDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildPostsList(BuildContext context, List<Post> posts) {
    if (posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.article_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No posts yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first post to get started!',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
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
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        post.title,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          _showEditPostDialog(context, post);
                        } else if (value == 'delete') {
                          _showDeletePostDialog(context, post);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
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
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  post.body,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCreatePostDialog(BuildContext context) {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create Post'),
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
                context.read<PostsBloc>().add(PostsCreateRequested(
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

  void _showEditPostDialog(BuildContext context, Post post) {
    final titleController = TextEditingController(text: post.title);
    final bodyController = TextEditingController(text: post.body);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Post'),
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
                context.read<PostsBloc>().add(PostsUpdateRequested(
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

  void _showDeletePostDialog(BuildContext context, Post post) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Post'),
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
              context.read<PostsBloc>().add(PostsDeleteRequested(post.id));
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
