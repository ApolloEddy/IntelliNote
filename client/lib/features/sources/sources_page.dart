import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';

import '../../app/app_state.dart';
import '../../core/models.dart';

class SourcesPage extends StatelessWidget {
  const SourcesPage({super.key, required this.notebookId});

  final String notebookId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final sources = state.sourcesFor(notebookId);
    final jobs = state.jobsFor(notebookId);
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...sources.map((source) {
            final job = jobs.firstWhereOrNull((j) => j.type == 'upload:${source.name}');
            return _SourceCard(source: source, job: job);
          }),
          if (sources.isEmpty && jobs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: Text('暂无来源，请导入内容。')),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showImportSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('导入'),
      ),
    );
  }

  void _showImportSheet(BuildContext context) {
    final state = context.read<AppState>(); // Capture state here
    showModalBottomSheet(
      context: context,
      builder: (innerContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.text_fields),
                title: const Text('粘贴文本'),
                onTap: () async {
                  Navigator.pop(innerContext);
                  await _showPasteDialog(context, state); // Pass state
                },
              ),
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('导入 TXT/MD 文件'),
                onTap: () async {
                  Navigator.pop(innerContext);
                  await state.addSourceFromFile(notebookId: notebookId);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showPasteDialog(BuildContext context, AppState state) async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('粘贴文本'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: '来源名称'),
              ),
              TextField(
                controller: contentController,
                maxLines: 6,
                decoration: const InputDecoration(labelText: '文本内容'),
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
              child: const Text('导入'),
            ),
          ],
        );
      },
    );
    if (result != true) {
      return;
    }
    await state.addSourceFromText(
          notebookId: notebookId,
          name: titleController.text.trim().isEmpty ? '粘贴文本' : titleController.text.trim(),
          text: contentController.text.trim(),
        );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.source, this.job});

  final SourceItem source;
  final JobItem? job;

  @override
  Widget build(BuildContext context) {
    final bool isUploading = job != null && job!.state != JobState.done && job!.state != JobState.failed;
    final bool isSuccess = job != null && job!.state == JobState.done;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: (source.status == SourceStatus.processing || isUploading)
            ? const SizedBox(
                width: 24, 
                height: 24, 
                child: CircularProgressIndicator(strokeWidth: 2)
              )
            : Icon(
                _iconFor(source.type),
                color: source.status == SourceStatus.failed ? Colors.red : null,
              ),
        title: Text(
          source.name,
          style: TextStyle(
            color: source.status == SourceStatus.failed ? Colors.red : null,
          ),
        ),
        subtitle: Text(isUploading ? '正在上传...' : (isSuccess ? '上传成功' : _statusLabel(source.status))),
        trailing: _trailingIcon(source.status, isSuccess),
      ),
    );
  }

  Widget? _trailingIcon(SourceStatus status, bool isSuccess) {
    if (status == SourceStatus.ready || isSuccess) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }
    if (status == SourceStatus.failed) {
      return const Icon(Icons.error, color: Colors.red);
    }
    return null;
  }

  IconData _iconFor(SourceType type) {
    switch (type) {
      case SourceType.file:
        return Icons.description;
      case SourceType.url:
        return Icons.link;
      case SourceType.paste:
        return Icons.text_snippet;
    }
  }

  String _statusLabel(SourceStatus status) {
    switch (status) {
      case SourceStatus.queued:
        return '排队中';
      case SourceStatus.processing:
        return '处理中';
      case SourceStatus.ready:
        return '已完成';
      case SourceStatus.failed:
        return '失败';
    }
  }
}
