import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
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
  bool _redirectingMissingNotebook = false;

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
              Icon(Icons.auto_fix_high),
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

  void _openCitationInSources(Citation citation) {
    final state = context.read<AppState>();
    final exists = state.sourcesFor(widget.notebook.id).any((s) => s.id == citation.sourceId);
    if (!exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('对应来源已不存在，无法定位。')),
      );
      return;
    }
    state.focusSourceFromCitation(notebookId: widget.notebook.id, citation: citation);
    if (_index != 0) {
      setState(() => _index = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final notebook = state.notebooks.where((item) => item.id == widget.notebook.id).firstOrNull;
    if (notebook == null) {
      if (!_redirectingMissingNotebook) {
        _redirectingMissingNotebook = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('当前笔记本已被删除，已返回首页。')),
          );
          Navigator.of(context).pop();
        });
      }
      return const Scaffold(body: SizedBox.shrink());
    }
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Hero(
              tag: 'notebook_emoji_${notebook.id}',
              child: Material(
                color: Colors.transparent,
                child: Text(
                  notebook.emoji,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(notebook.title),
          ],
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: [
          SourcesPage(notebookId: notebook.id),
          ChatPage(
            notebookId: notebook.id,
            onOpenCitation: _openCitationInSources,
          ),
          StudioPage(notebookId: notebook.id),
          NotesPage(notebookId: notebook.id),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.folder), label: '来源'),
          NavigationDestination(icon: Icon(Icons.chat_bubble), label: '对话'),
          NavigationDestination(icon: Icon(Icons.school), label: '实验室'),
          NavigationDestination(icon: Icon(Icons.note), label: '笔记'),
        ],
      ),
    );
  }
}
