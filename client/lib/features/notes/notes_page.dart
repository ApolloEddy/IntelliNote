import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/models.dart';

class NotesPage extends StatelessWidget {
  const NotesPage({super.key, required this.notebookId});

  final String notebookId;

  @override
  Widget build(BuildContext context) {
    final notes = context.watch<AppState>().notesFor(notebookId);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (notes.isEmpty)
          const Center(child: Text('暂无笔记，生成学习指南或测验后会出现在这里。')),
        ...notes.map((note) => _NoteCard(note: note)),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});

  final NoteItem note;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(note.title),
        subtitle: Text(_typeLabel(note.type)),
        onTap: () => _showNote(context, note),
      ),
    );
  }

  String _typeLabel(NoteType type) {
    switch (type) {
      case NoteType.written:
        return '手写';
      case NoteType.savedResponse:
        return '保存回答';
      case NoteType.studyGuide:
        return '学习指南';
      case NoteType.quiz:
        return '测验';
    }
  }

  void _showNote(BuildContext context, NoteItem note) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(note.title),
          content: SizedBox(
            width: double.maxFinite,
            // 使用 Markdown 渲染
            child: Markdown(data: note.contentMarkdown),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }
}