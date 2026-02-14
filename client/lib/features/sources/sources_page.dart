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
    final focusCitation = state.sourceFocusFor(notebookId);
    final focusSource = focusCitation == null
        ? null
        : sources.firstWhereOrNull((s) => s.id == focusCitation.sourceId);
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (focusCitation != null && focusSource != null) ...[
            _SourceFocusBanner(
              sourceName: focusSource.name,
              pageNumber: focusCitation.pageNumber,
              snippet: focusCitation.snippet,
              onOpenSnippet: () => _showFocusedSnippetDialog(
                context,
                sourceName: focusSource.name,
                pageNumber: focusCitation.pageNumber,
                snippet: focusCitation.snippet,
              ),
              onOpenPdfPage: (focusCitation.pageNumber != null &&
                      focusSource.name.toLowerCase().endsWith('.pdf'))
                  ? () => _showPdfPagePreviewDialog(
                        context,
                        sourceId: focusSource.id,
                        sourceName: focusSource.name,
                        pageNumber: focusCitation.pageNumber!,
                      )
                  : null,
              onClear: () => state.clearSourceFocus(notebookId),
            ),
            const SizedBox(height: 10),
          ],
          ...sources.map((source) {
            final job = jobs.firstWhereOrNull((j) => j.type == 'upload:${source.name}');
            return _SourceCard(
              source: source,
              job: job,
              focused: focusCitation?.sourceId == source.id,
              focusPage: focusCitation?.sourceId == source.id ? focusCitation?.pageNumber : null,
            );
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
                    '导入 PDF、TXT、MD 或粘贴文本\nAI 将为你自动索引与分析',
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

  void _showFocusedSnippetDialog(
    BuildContext context, {
    required String sourceName,
    required int? pageNumber,
    required String snippet,
  }) {
    final pageSuffix = pageNumber == null ? '' : '（第 $pageNumber 页）';
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('引用片段$pageSuffix - $sourceName'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(snippet),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showPdfPagePreviewDialog(
    BuildContext context, {
    required String sourceId,
    required String sourceName,
    required int pageNumber,
  }) {
    if (pageNumber < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('页码无效，无法预览。')),
      );
      return;
    }
    final future = context.read<AppState>().getPdfPagePreview(
          sourceId: sourceId,
          pageNumber: pageNumber,
          maxChars: 5000,
        );
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('PDF 第 $pageNumber 页预览 - $sourceName'),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<Map<String, dynamic>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Text('预览失败：${snapshot.error}');
              }
              final data = snapshot.data ?? const <String, dynamic>{};
              final text = (data['text'] ?? '').toString();
              final totalPages = data['total_pages'];
              final imageRatio = data['image_ratio'];
              final header = '第 $pageNumber 页 / 共 $totalPages 页'
                  '${imageRatio != null ? ' · 图片占比 $imageRatio' : ''}';
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      header,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 10),
                    SelectableText(
                      text.isEmpty ? '该页未提取到可读文本（可能为扫描页）。' : text,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
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
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 520,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [scheme.surfaceContainerHigh, scheme.surfaceContainer]
                  : const [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.12),
                blurRadius: isDark ? 20 : 26,
                offset: const Offset(0, 10),
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
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '选择一种导入方式，系统将自动进行索引和检索准备。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.72),
                ),
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
                title: '导入 TXT/MD/PDF 文件',
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered
                ? scheme.primaryContainer.withValues(alpha: isDark ? 0.34 : 0.36)
                : (isDark ? scheme.surfaceContainerLowest : Colors.white),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered
                  ? scheme.primary.withValues(alpha: 0.45)
                  : scheme.outlineVariant.withValues(alpha: 0.75),
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
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurface.withValues(alpha: 0.72),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 640,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          decoration: BoxDecoration(
            color: isDark ? scheme.surfaceContainer : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.12),
                blurRadius: isDark ? 20 : 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '粘贴文本',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                maxLength: 60,
                decoration: InputDecoration(
                  hintText: '来源名称（可选）',
                  border: isDark ? InputBorder.none : const OutlineInputBorder(),
                  enabledBorder: isDark ? InputBorder.none : null,
                  focusedBorder: isDark ? InputBorder.none : null,
                  filled: true,
                  fillColor: isDark ? scheme.surfaceContainerHigh : null,
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
                decoration: InputDecoration(
                  hintText: '粘贴要导入的文本内容...',
                  border: isDark ? InputBorder.none : const OutlineInputBorder(),
                  enabledBorder: isDark ? InputBorder.none : null,
                  focusedBorder: isDark ? InputBorder.none : null,
                  filled: true,
                  fillColor: isDark ? scheme.surfaceContainerHigh : null,
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
  const _SourceCard({
    required this.source,
    this.job,
    this.focused = false,
    this.focusPage,
  });

  final SourceItem source;
  final JobItem? job;
  final bool focused;
  final int? focusPage;

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  bool _deleting = false;

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isLoading = source.status == SourceStatus.processing;
    final progressValue = source.progress.clamp(0.0, 1.0).toDouble();
    final titleColor = source.status == SourceStatus.failed ? scheme.error : scheme.onSurface;
    final subtitleColor = source.status == SourceStatus.failed
        ? scheme.error
        : (isLoading ? scheme.primary : scheme.onSurface.withValues(alpha: 0.72));
    final badgeBackground = source.status == SourceStatus.failed
        ? scheme.errorContainer.withValues(alpha: isDark ? 0.25 : 0.45)
        : scheme.surfaceContainerHighest;
    final badgeTextColor = source.status == SourceStatus.failed ? scheme.error : scheme.primary;
    final badgeLabel = _sourceBadgeLabel(source);
    final statusText = isLoading
        ? _processingLabel(source)
        : (source.status == SourceStatus.failed ? '处理失败' : '准备就绪');
    final parseSummary = _parseSummary(source.parseDetail);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: widget.focused
          ? scheme.primaryContainer.withValues(alpha: isDark ? 0.30 : 0.42)
          : (isDark ? scheme.surfaceContainerHigh : scheme.surface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.focused
              ? scheme.primary.withValues(alpha: 0.6)
              : scheme.outlineVariant.withValues(alpha: 0.75),
          width: widget.focused ? 1.4 : 1,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: badgeBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: source.status == SourceStatus.failed
                      ? scheme.error.withValues(alpha: 0.35)
                      : scheme.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              child: Center(
                child: Text(
                  badgeLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: badgeTextColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
            title: Text(
              source.name,
              style: TextStyle(
                color: titleColor,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: subtitleColor,
                      fontWeight: isLoading ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                  if (parseSummary != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        parseSummary,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (widget.focused)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        widget.focusPage != null
                            ? '已定位到引用来源（第 ${widget.focusPage} 页）'
                            : '已定位到引用来源',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            trailing: IconButton(
              icon: _deleting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.primary,
                      ),
                    )
                  : Icon(
                      Icons.delete_outline,
                      color: scheme.onSurface.withValues(alpha: 0.62),
                      size: 22,
                    ),
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
                        backgroundColor: scheme.primary.withValues(alpha: 0.12),
                        value: progressValue > 0 ? progressValue : null,
                        valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(progressValue * 100).round()}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.primary,
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

  String _sourceBadgeLabel(SourceItem source) {
    switch (source.type) {
      case SourceType.url:
        return 'URL';
      case SourceType.paste:
        return 'TXT';
      case SourceType.file:
        final dotIndex = source.name.lastIndexOf('.');
        if (dotIndex <= -1 || dotIndex >= source.name.length - 1) {
          return 'FILE';
        }
        final extension = source.name
            .substring(dotIndex + 1)
            .trim()
            .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
        if (extension.isEmpty) {
          return 'FILE';
        }
        final upper = extension.toUpperCase();
        return upper.length <= 4 ? upper : upper.substring(0, 4);
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

  String? _parseSummary(Map<String, dynamic>? detail) {
    if (detail == null || detail.isEmpty) return null;
    final totalPages = _toInt(detail['total_pages']);
    final textPages = _toInt(detail['text_pages']);
    final ocrPages = _toInt(detail['ocr_pages']);
    final visionPages = _toInt(detail['vision_pages']);
    final visionImages = _toInt(detail['vision_images']);
    final skippedPages = _toInt(detail['skipped_pages']);
    if (totalPages == null &&
        textPages == null &&
        ocrPages == null &&
        visionPages == null &&
        visionImages == null &&
        skippedPages == null) {
      return null;
    }
    return '解析统计'
        ' · 总页 ${totalPages ?? '-'}'
        ' · 文本 ${textPages ?? '-'}'
        ' · OCR ${ocrPages ?? '-'}'
        ' · Vision页 ${visionPages ?? '-'}'
        ' · Vision图 ${visionImages ?? '-'}'
        ' · 跳过 ${skippedPages ?? '-'}';
  }

  int? _toInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }
}

class _SourceFocusBanner extends StatelessWidget {
  const _SourceFocusBanner({
    required this.sourceName,
    required this.pageNumber,
    required this.snippet,
    required this.onOpenSnippet,
    required this.onOpenPdfPage,
    required this.onClear,
  });

  final String sourceName;
  final int? pageNumber;
  final String snippet;
  final VoidCallback onOpenSnippet;
  final VoidCallback? onOpenPdfPage;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pageText = pageNumber == null ? '' : ' · 第 $pageNumber 页';
    final normalizedSnippet = snippet.trim();
    final preview = normalizedSnippet.length <= 88
        ? normalizedSnippet
        : '${normalizedSnippet.substring(0, 88)}...';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.my_location_rounded, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已定位到来源：$sourceName$pageText',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                if (normalizedSnippet.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: GestureDetector(
                      onTap: onOpenSnippet,
                      child: Text(
                        '片段预览：$preview',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onPrimaryContainer.withValues(alpha: 0.9),
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: onOpenSnippet,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('查看片段'),
          ),
          if (onOpenPdfPage != null)
            TextButton(
              onPressed: onOpenPdfPage,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('查看页预览'),
            ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }
}
