import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/models.dart';
import '../notebook/notebook_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('IntelliNote'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: state.notebooks.length,
        itemBuilder: (context, index) {
          final notebook = state.notebooks[index];
          return _NotebookCard(notebook: notebook);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final controller = TextEditingController();
    final emojis = ['📘', '📕', '📗', '📙', '📒', '🧠'];
    var selectedEmoji = emojis.first;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('创建 Notebook'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              const SizedBox(height: 12),
              DropdownButton<String>(
                value: selectedEmoji,
                items: emojis
                    .map(
                      (emoji) => DropdownMenuItem(
                        value: emoji,
                        child: Text(emoji),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  selectedEmoji = value ?? selectedEmoji;
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('创建'),
            ),
          ],
        );
      },
    );

    if (result != true) {
      return;
    }
    final title = controller.text.trim();
    if (title.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('标题不能为空')),
        );
      }
      return;
    }
    final notebook = context.read<AppState>().createNotebook(
          title: title,
          emoji: selectedEmoji,
        );
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => NotebookPage(notebook: notebook)),
      );
    }
  }
}

class _NotebookCard extends StatelessWidget {
  const _NotebookCard({required this.notebook});

  final Notebook notebook;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(child: Text(notebook.emoji)),
        title: Text(notebook.title),
        subtitle: Text(notebook.summary),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => NotebookPage(notebook: notebook)),
          );
        },
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'rename') {
              _showRenameDialog(context, state, notebook);
            }
            if (value == 'delete') {
              state.deleteNotebook(notebook.id);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'rename', child: Text('重命名')),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    AppState state,
    Notebook notebook,
  ) async {
    final controller = TextEditingController(text: notebook.title);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('重命名 Notebook'),
          content: TextField(controller: controller),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (result != true) {
      return;
    }
    state.renameNotebook(notebook.id, controller.text.trim());
  }
}
