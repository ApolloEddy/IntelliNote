import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/models.dart';
import '../chat/chat_page.dart';
import '../notes/notes_page.dart';
import '../sources/sources_page.dart';
import '../studio/studio_page.dart';

class NotebookPage extends StatefulWidget {
  const NotebookPage({super.key, required this.notebook});

  final Notebook notebook;

  @override
  State<NotebookPage> createState() => _NotebookPageState();
}

class _NotebookPageState extends State<NotebookPage> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Start health check when entering notebook
    WidgetsBinding.instance.addPostFrameCallback((_) => _runHealthCheck());
  }

  Future<void> _runHealthCheck() async {
    final state = context.read<AppState>();
    final removedCount = await state.checkNotebookHealth(widget.notebook.id);
    
    if (removedCount > 0 && mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.auto_fix_high, color: Colors.indigo),
              SizedBox(width: 8),
              Text('自动清理完成'),
            ],
          ),
          content: Text('由于服务器索引已重置或文件失效，我们已为您自动清理了 $removedCount 个无法访问的来源卡片。'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final notebook = state.notebooks.firstWhere((item) => item.id == widget.notebook.id);
    return Scaffold(
      appBar: AppBar(
        title: Text('${notebook.emoji} ${notebook.title}'),
      ),
      body: IndexedStack(
        index: _index,
        children: [
          SourcesPage(notebookId: notebook.id),
          ChatPage(notebookId: notebook.id),
          StudioPage(notebookId: notebook.id),
          NotesPage(notebookId: notebook.id),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.folder), label: 'Sources'),
          NavigationDestination(icon: Icon(Icons.chat_bubble), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.school), label: 'Studio'),
          NavigationDestination(icon: Icon(Icons.note), label: 'Notes'),
        ],
      ),
    );
  }
}
