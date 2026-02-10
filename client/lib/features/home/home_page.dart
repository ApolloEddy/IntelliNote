import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/models.dart';
import '../notebook/notebook_page.dart';
import '../settings/settings_page.dart';
import 'interactive_search_bar.dart';
import 'modern_menu.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final notebooks = state.filteredNotebooks;
    final query = state.normalizedNotebookQuery;
    final hasSearch = query.isNotEmpty;
    final countText = hasSearch
        ? '你有 ${state.notebooks.length} 个笔记本，检索关键词 “$query” ，检索到 ${notebooks.length} 个结果'
        : '你有 ${state.notebooks.length} 个笔记本';
    
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar.large(
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.asset(
                        'assets/logo.png',
                        width: 28,
                        height: 28,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text('Intelli Note'),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: '设置',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SettingsPage()),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _GreetingText(displayName: state.displayName),
                      const SizedBox(height: 4),
                      if (state.showNotebookCount)
                        Text(
                          countText,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: state.notebooks.isEmpty
                              ? SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(24),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.22),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.auto_stories_rounded,
                                            size: 64,
                                            color: Theme.of(context).colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        Text(
                                          '开始你的知识之旅',
                                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '点击右下角的按钮\n创建你的第一个智能笔记本',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72),
                                                height: 1.5,
                                              ),
                                        ),
                                        const SizedBox(height: 48), // Spacing for FAB
                                      ],
                                    ),
                                  ),
                                )
                              : notebooks.isEmpty 
                                  ? SliverFillRemaining(
                                      hasScrollBody: false,
                                      child: Center(
                                        child: Text(
                                          '未找到相关笔记',
                                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72),
                                              ),
                                        ),
                                      ),
                                    )
                                  : SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      final notebook = notebooks[index];
                                      return _NotebookCard(notebook: notebook);
                                    },
                                    childCount: notebooks.length,
                                  ),
                                ),
                        ),
              
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
          // 悬浮搜索栏
          const Positioned.fill(
            child: InteractiveSearchBar(
              topOffset: 12,
              rightOffset: 72,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建笔记'),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final title = await showNotebookNameDialog(
      context,
      title: '创建 Notebook',
      actionLabel: '创建',
      hintText: '例如：物理复习、项目计划...',
    );
    if (title == null) {
      return;
    }

    final notebook = context.read<AppState>().createNotebook(
          title: title,
          emoji: '📁', // 默认图标，等待 RAG 分类更新
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.16 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.75)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => NotebookPage(notebook: notebook)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Hero(
                tag: 'notebook_emoji_${notebook.id}',
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: Center(
                    child: Material(
                      color: Colors.transparent,
                      child: Text(
                        notebook.emoji,
                        style: const TextStyle(fontSize: 34),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notebook.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notebook.summary.isEmpty ? '暂无摘要' : notebook.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              ModernMenuButton(
                actions: [
                  ModernMenuAction(
                    title: '重命名',
                    icon: Icons.edit_outlined,
                    onTap: () => _showRenameDialog(context, state, notebook),
                  ),
                  ModernMenuAction(
                    title: '删除',
                    icon: Icons.delete_outline,
                    iconColor: Colors.red.shade400,
                    textColor: Colors.red.shade400,
                    onTap: () => _handleDeleteAction(context, state, notebook),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: SizedBox(
                    width: 44,
                    height: 34,
                    child: Center(
                      child: Icon(
                        Icons.more_vert_rounded,
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    AppState state,
    Notebook notebook,
  ) async {
    final title = await showNotebookNameDialog(
      context,
      title: '重命名 Notebook',
      actionLabel: '保存',
      hintText: '输入新的笔记本名称',
      initialValue: notebook.title,
    );
    if (title == null || title == notebook.title) {
      return;
    }
    state.renameNotebook(notebook.id, title);
  }

  Future<void> _handleDeleteAction(
    BuildContext context,
    AppState state,
    Notebook notebook,
  ) async {
    if (!state.confirmBeforeDeleteNotebook) {
      state.deleteNotebook(notebook.id);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除 Notebook'),
        content: Text('确认删除「${notebook.title}」吗？该操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      state.deleteNotebook(notebook.id);
    }
  }
}

Future<String?> showNotebookNameDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  required String hintText,
  String initialValue = '',
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) {
      return _NotebookNameDialogCard(
        title: title,
        actionLabel: actionLabel,
        hintText: hintText,
        initialValue: initialValue,
      );
    },
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
}

class _NotebookNameDialogCard extends StatefulWidget {
  const _NotebookNameDialogCard({
    required this.title,
    required this.actionLabel,
    required this.hintText,
    required this.initialValue,
  });

  final String title;
  final String actionLabel;
  final String hintText;
  final String initialValue;

  @override
  State<_NotebookNameDialogCard> createState() => _NotebookNameDialogCardState();
}

class _NotebookNameDialogCardState extends State<_NotebookNameDialogCard> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String? _errorText;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    _focused = _focusNode.hasFocus;
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _errorText = '标题不能为空');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = _errorText != null
        ? scheme.error
        : (_focused ? scheme.primary : scheme.outlineVariant);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 420,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? const [Color(0xFF252526), Color(0xFF2D2D30)]
                  : const [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.08),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? scheme.surfaceContainerHighest : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? Colors.transparent : borderColor,
                    width: _focused ? 1.4 : 1,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: true,
                  maxLength: 60,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(60),
                  ],
                  onChanged: (_) {
                    if (_errorText != null) {
                      setState(() => _errorText = null);
                    }
                  },
                  onSubmitted: (_) => _submit(),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurface,
                    fontFamily: 'Consolas',
                    fontFamilyFallback: const ['GWMSansUI', 'SimHei'],
                  ),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    hintStyle: TextStyle(
                      color: scheme.onSurface.withValues(alpha: 0.56),
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    counterText: '',
                    isDense: true,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: _errorText == null
                    ? const SizedBox(height: 12)
                    : Padding(
                        padding: const EdgeInsets.only(top: 8, left: 2),
                        child: Text(
                          _errorText!,
                          key: const ValueKey('dialog_error'),
                          style: TextStyle(
                            color: scheme.error,
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
                    child: Text(widget.actionLabel),
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

class _GreetingText extends StatelessWidget {
  const _GreetingText({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    String greeting;
    if (hour < 6) {
      greeting = '夜深了';
    } else if (hour < 12) {
      greeting = '早上好';
    } else if (hour < 14) {
      greeting = '中午好';
    } else if (hour < 18) {
      greeting = '下午好';
    } else {
      greeting = '晚上好';
    }

    return Text(
      '$greeting, $displayName',
      style: Theme.of(context).textTheme.headlineMedium,
    );
  }
}
