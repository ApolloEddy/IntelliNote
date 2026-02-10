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
            Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.only(top: 60),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.cloud_upload_outlined, size: 40, color: Colors.grey.shade400),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '暂无知识来源',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '导入 PDF、MD 或粘贴文本\nAI 将为你自动索引与分析',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _showImportDialog(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('立即导入'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showImportDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('导入'),
      ),
    );
  }

  Future<void> _showImportDialog(BuildContext context) async {
    final state = context.read<AppState>();
    final action = await showGeneralDialog<_ImportAction>(
      context: context,
      barrierLabel: '导入知识来源',
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const _ImportChooserDialog(),
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );

    if (action == null || !context.mounted) return;
    if (action == _ImportAction.paste) {
      await _showPasteDialog(context, state);
      return;
    }
    await state.addSourceFromFile(notebookId: notebookId).catchError((e) {
      if (e.toString().contains('DUPLICATE_FILE')) {
        _showDuplicateDialog(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入失败，请检查网络或稍后重试')),
        );
      }
    });
  }

  Future<void> _showPasteDialog(BuildContext context, AppState state) async {
    final payload = await showGeneralDialog<_PastePayload>(
      context: context,
      barrierLabel: '粘贴文本',
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => const _PasteSourceDialog(),
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
    if (payload == null || !context.mounted) {
      return;
    }
    await state.addSourceFromText(
          notebookId: notebookId,
          name: payload.name,
          text: payload.content,
        ).catchError((e) {
          if (e.toString().contains('DUPLICATE_FILE')) {
            _showDuplicateDialog(context);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('导入失败，请稍后重试')),
            );
          }
        });
  }

  void _showDuplicateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('文件已存在'),
        content: const Text('该内容已经上传过了，不需要重复导入。'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }
}

enum _ImportAction { paste, file }

class _ImportChooserDialog extends StatelessWidget {
  const _ImportChooserDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 520,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '导入知识来源',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '选择一种导入方式，系统将自动进行索引和检索准备。',
                style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
              ),
              const SizedBox(height: 14),
              _ImportActionCard(
                icon: Icons.text_snippet_outlined,
                title: '粘贴文本',
                description: '适合临时资料、网页摘录和会议纪要',
                onTap: () => Navigator.of(context).pop(_ImportAction.paste),
              ),
              const SizedBox(height: 10),
              _ImportActionCard(
                icon: Icons.upload_file_rounded,
                title: '导入 TXT/MD 文件',
                description: '从本地文件导入并构建可检索知识片段',
                onTap: () => Navigator.of(context).pop(_ImportAction.file),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportActionCard extends StatefulWidget {
  const _ImportActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  State<_ImportActionCard> createState() => _ImportActionCardState();
}

class _ImportActionCardState extends State<_ImportActionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered ? scheme.primaryContainer.withValues(alpha: 0.36) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hovered ? scheme.primary.withValues(alpha: 0.45) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icon, color: scheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.description,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _PastePayload {
  const _PastePayload({required this.name, required this.content});

  final String name;
  final String content;
}

class _PasteSourceDialog extends StatefulWidget {
  const _PasteSourceDialog();

  @override
  State<_PasteSourceDialog> createState() => _PasteSourceDialogState();
}

class _PasteSourceDialogState extends State<_PasteSourceDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _submit() {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      setState(() => _errorText = '文本内容不能为空');
      return;
    }
    final name = _nameController.text.trim().isEmpty ? '粘贴文本' : _nameController.text.trim();
    Navigator.of(context).pop(_PastePayload(name: name, content: content));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 640,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '粘贴文本',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                maxLength: 60,
                decoration: const InputDecoration(
                  hintText: '来源名称（可选）',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _contentController,
                maxLines: 8,
                onChanged: (_) {
                  if (_errorText != null) {
                    setState(() => _errorText = null);
                  }
                },
                decoration: const InputDecoration(
                  hintText: '粘贴要导入的文本内容...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: _errorText == null
                    ? const SizedBox(height: 12)
                    : Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _errorText!,
                          key: const ValueKey('paste_error'),
                          style: TextStyle(
                            color: Colors.red.shade500,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('导入'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceCard extends StatefulWidget {
  const _SourceCard({required this.source, this.job});

  final SourceItem source;
  final JobItem? job;

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final bool isLoading = source.status == SourceStatus.processing;
    final double progressValue = source.progress.clamp(0.0, 1.0).toDouble();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: source.status == SourceStatus.failed
                    ? Colors.red.withValues(alpha: 0.1)
                    : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _iconFor(source.type),
                color: source.status == SourceStatus.failed ? Colors.red : Theme.of(context).colorScheme.primary,
                size: 24,
              ),
            ),
            title: Text(
              source.name,
              style: TextStyle(
                color: source.status == SourceStatus.failed ? Colors.red : const Color(0xFF1E293B),
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                isLoading ? _processingLabel(source) : (source.status == SourceStatus.failed ? '处理失败' : '准备就绪'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isLoading ? Theme.of(context).colorScheme.primary : Colors.grey,
                  fontWeight: isLoading ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
            trailing: IconButton(
              icon: _deleting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  : Icon(Icons.delete_outline, color: Colors.grey.shade400, size: 22),
              onPressed: _deleting ? null : () => _confirmDelete(context),
            ),
          ),
          if (isLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                        value: progressValue > 0 ? progressValue : null,
                        valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(progressValue * 100).round()}%',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    if (_deleting) return;
    final source = widget.source;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "$source.name" 吗？这也会从索引库中清理该文件。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    setState(() => _deleting = true);
    try {
      await context.read<AppState>().deleteSource(source.notebookId, source.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除 "${source.name}"')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除 "${source.name}" 失败，请重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
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

  String _processingLabel(SourceItem source) {
    if (source.stageMessage.trim().isNotEmpty) return source.stageMessage;
    switch (source.stage) {
      case 'loading':
        return '读取文件中';
      case 'parsing':
      case 'parsed':
        return '解析文档中';
      case 'classifying':
        return '文档分类中';
      case 'chunking':
        return '切分 Chunk 中';
      case 'embedding':
      case 'embedding_done':
        return '计算 Embedding 中';
      case 'indexing':
        return '写入索引中';
      default:
        return '处理中';
    }
  }
}
