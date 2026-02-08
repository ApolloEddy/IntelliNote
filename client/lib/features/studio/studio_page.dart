import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';

class StudioPage extends StatefulWidget {
  const StudioPage({super.key, required this.notebookId});

  final String notebookId;

  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isProcessing = state.isProcessing(widget.notebookId);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          '学习室',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _StudioCard(
          title: '学习指南',
          description: '根据来源生成复习提纲与重点。',
          onTap: () => _run(context, ToolType.studyGuide),
          loading: isProcessing,
        ),
        const SizedBox(height: 12),
        _StudioCard(
          title: '测验题',
          description: '生成可用于自测的问题与答案要点。',
          onTap: () => _run(context, ToolType.quiz),
          loading: isProcessing,
        ),
      ],
    );
  }

  Future<void> _run(BuildContext context, ToolType type) async {
    final state = context.read<AppState>();
    try {
      if (type == ToolType.studyGuide) {
        await state.generateStudyGuide(notebookId: widget.notebookId);
      } else {
        await state.generateQuiz(notebookId: widget.notebookId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已生成并保存到 Notes')), 
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败: $e'), backgroundColor: Colors.red), 
        );
      }
    }
  }
}

enum ToolType { studyGuide, quiz }

class _StudioCard extends StatelessWidget {
  const _StudioCard({
    required this.title,
    required this.description,
    required this.onTap,
    required this.loading,
  });

  final String title;
  final String description;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(description),
        trailing: loading ? const CircularProgressIndicator() : const Icon(Icons.chevron_right),
        onTap: loading ? null : onTap,
      ),
    );
  }
}
