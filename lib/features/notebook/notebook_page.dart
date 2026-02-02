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
