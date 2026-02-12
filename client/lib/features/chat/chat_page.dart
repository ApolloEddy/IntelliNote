import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../app/app_state.dart';
import '../../core/models.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.notebookId,
    this.onOpenCitation,
  });

  final String notebookId;
  final ValueChanged<Citation>? onOpenCitation;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _sending = false;
  bool _autoScrollEnabled = true;
  bool _isUserInteracting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      if (state.isFirstOpenInSession(widget.notebookId)) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    if (!_autoScrollEnabled || _isUserInteracting) return;
    final position = _scrollController.position;
    final target = position.maxScrollExtent;
    final delta = (target - position.pixels).abs();
    if (delta < 2) return;
    if (delta < 88) {
      _scrollController.jumpTo(target);
      return;
    }
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
    );
  }

  void _disableAutoScrollByUserIntent() {
    if (_autoScrollEnabled) {
      setState(() => _autoScrollEnabled = false);
    }
  }

  bool _isNearBottom([double threshold = 2]) {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.extentAfter <= threshold;
  }

  void _enableAutoScrollIfAtBottom() {
    if (_isNearBottom(2) && !_autoScrollEnabled) {
      setState(() => _autoScrollEnabled = true);
    }
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) return KeyEventResult.ignored;
    
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
      final isControlPressed = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
                               HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight);
      
      if (isControlPressed) {
        // Ctrl + Enter inserts a newline at caret position.
        final text = _controller.text;
        final selection = _controller.selection;
        final start = selection.isValid ? selection.start : text.length;
        final end = selection.isValid ? selection.end : text.length;
        final newText = text.replaceRange(start, end, '\n');
        _controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: start + 1),
        );
        return KeyEventResult.handled;
      } else {
        // Enter: Send
        _send(context);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final messages = state.chatsFor(widget.notebookId);
    final sources = state.sourcesFor(widget.notebookId);
    final isProcessing = state.isProcessing(widget.notebookId);
    final isGenerating = state.isGeneratingResponse(widget.notebookId);
    final selectedIds = state.selectedSourceIdsFor(widget.notebookId);
    final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    if (isProcessing && _autoScrollEnabled && !_isUserInteracting) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
    
    return SelectionArea(
      child: Column(
        children: [
          if (sources.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                  Expanded(
                    child: Text(
                      '引用来源 (可选):',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => state.setAllSourcesSelection(widget.notebookId, true),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: const Text('全选', style: TextStyle(fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: () => state.setAllSourcesSelection(widget.notebookId, false),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: const Text('全不选', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ...sources.map((source) {
                    final isSelected = selectedIds.contains(source.id);
                    final scheme = Theme.of(context).colorScheme;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(source.name),
                        selected: isSelected,
                        selectedColor: scheme.primary.withValues(alpha: 0.14),
                        checkmarkColor: scheme.primary,
                        side: BorderSide(
                          color: isSelected
                              ? scheme.primary.withValues(alpha: 0.45)
                              : scheme.outlineVariant.withValues(alpha: 0.72),
                        ),
                        labelStyle: TextStyle(
                          color: isSelected ? scheme.primary : scheme.onSurface,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        ),
                        onSelected: (value) {
                          state.toggleSourceSelection(widget.notebookId, source.id, value);
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollStartNotification && notification.dragDetails != null) {
                  _isUserInteracting = true;
                  _disableAutoScrollByUserIntent();
                }
                if (notification is ScrollUpdateNotification &&
                    notification.dragDetails != null &&
                    notification.metrics.extentAfter > 2) {
                  _disableAutoScrollByUserIntent();
                }
                if (notification is ScrollEndNotification) {
                  _isUserInteracting = false;
                  _enableAutoScrollIfAtBottom();
                }
                return false;
              },
              child: ScrollConfiguration(
                behavior: const _ChatScrollBehavior(),
                child: Listener(
                  onPointerDown: (_) {
                    _isUserInteracting = true;
                    if (_scrollController.hasClients && _scrollController.position.extentAfter > 2) {
                      _disableAutoScrollByUserIntent();
                    }
                  },
                  onPointerSignal: (event) {
                    _isUserInteracting = true;
                    if (_scrollController.hasClients &&
                        _scrollController.position.extentAfter > 2) {
                      _disableAutoScrollByUserIntent();
                    }
                  },
                  onPointerUp: (_) {
                    _isUserInteracting = false;
                    _enableAutoScrollIfAtBottom();
                  },
                  onPointerCancel: (_) {
                    _isUserInteracting = false;
                    _enableAutoScrollIfAtBottom();
                  },
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: isDesktop,
                    trackVisibility: isDesktop,
                    interactive: true,
                    radius: const Radius.circular(10),
                    thickness: isDesktop ? 10 : 6,
                    child: ListView.builder(
                      controller: _scrollController,
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(14, 10, 10, 14),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        return _ChatBubble(
                          message: message,
                          sources: sources,
                          isDesktop: isDesktop,
                          useAccentUserBubble: state.useAccentUserBubble,
                          onOpenCitation: widget.onOpenCitation,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          _ChatComposer(
            controller: _controller,
            focusNode: _focusNode,
            isBusy: isProcessing || _sending || isGenerating,
            canStop: isGenerating,
            onKeyEvent: _handleKeyEvent,
            onSend: () => _send(context),
            onStop: () => state.stopGeneratingResponse(widget.notebookId),
          ),
        ],
      ),
    );
  }

  Future<void> _send(BuildContext context) async {
    final state = context.read<AppState>();
    if (_sending || state.isProcessing(widget.notebookId)) {
      return;
    }

    final question = _controller.text.trim();
    if (question.isEmpty) {
      return;
    }

    final selectedIds = state.selectedSourceIdsFor(widget.notebookId);
    
    setState(() {
      _sending = true;
      _autoScrollEnabled = true;
      _isUserInteracting = false;
    });
    _controller.clear();
    
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    final scope = SourceScope.sources(selectedIds.toList());

    await state.askQuestion(
          notebookId: widget.notebookId,
          question: question,
          scope: scope,
        );
    if (mounted) {
      setState(() => _sending = false);
    }
  }
}

class _ChatBubble extends StatefulWidget {
  const _ChatBubble({
    required this.message,
    required this.sources,
    required this.isDesktop,
    required this.useAccentUserBubble,
    this.onOpenCitation,
  });

  final ChatMessage message;
  final List<SourceItem> sources;
  final bool isDesktop;
  final bool useAccentUserBubble;
  final ValueChanged<Citation>? onOpenCitation;

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble> {
  bool _showActions = false;

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == ChatRole.user;
    final isDesktop = widget.isDesktop;
    final maxBubbleWidth = MediaQuery.of(context).size.width * (isDesktop ? 0.74 : 0.88);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bubbleColor = isUser
        ? (widget.useAccentUserBubble
            ? (isDark
                ? scheme.primary.withValues(alpha: 0.22)
                : scheme.primary.withValues(alpha: 0.12))
            : (isDark ? const Color(0xFF2A2D31) : const Color(0xFFEFF2F5)))
        : (isDark ? scheme.surfaceContainerHigh : Colors.grey.shade200);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () {
          if (!isDesktop && !isUser) {
            setState(() => _showActions = !_showActions);
          }
        },
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
              constraints: BoxConstraints(
                maxWidth: maxBubbleWidth,
                minWidth: isDesktop ? 116 : 96,
              ),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: widget.message.content,
                    selectable: false,
                    builders: {
                      'latex-inline': _LatexElementBuilder(displayMode: false),
                      'latex-block': _LatexElementBuilder(displayMode: true),
                    },
                    inlineSyntaxes: [
                      _BlockLatexSyntax(),
                      _InlineLatexSyntax(),
                    ],
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(
                        fontFamily: 'Consolas',
                        fontFamilyFallback: const ['GWMSansUI', 'SimHei'],
                        fontSize: 16,
                        height: 1.45,
                        color: scheme.onSurface,
                      ),
                      code: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 14,
                        backgroundColor: isDark
                            ? scheme.surfaceContainerHighest
                            : const Color(0xFFE0E0E0),
                        color: scheme.onSurface,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: isDark
                            ? scheme.surfaceContainerHighest
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                    ),
                  ),
                  if (widget.message.citations.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: List.generate(
                        widget.message.citations.length,
                        (index) => ActionChip(
                          backgroundColor: scheme.primary.withValues(alpha: 0.12),
                          side: BorderSide(
                            color: scheme.primary.withValues(alpha: 0.35),
                          ),
                          label: Text(
                            _citationLabel(index, widget.message.citations[index]),
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: () => _showCitation(context, widget.message.citations[index]),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!isUser) 
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: (isDesktop || _showActions)
                    ? Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ActionButton(
                              icon: Icons.copy_rounded,
                              onTap: () => _copyToClipboard(context, widget.message.content),
                              label: '复制',
                            ),
                            const SizedBox(width: 8),
                            _ActionButton(
                              icon: Icons.share_rounded,
                              onTap: () {
                                // TODO: Implement share
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('分享功能开发中...'))
                                );
                              },
                              label: '分享',
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    // Regex to strip markdown and keep plain text with emojis
    // A simple approach is to use the raw content but focus on the 'text' aspect.
    // For a deeper plain-text conversion, more complex regex would be needed.
    Clipboard.setData(ClipboardData(text: text)).then((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('已复制到剪切板'),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            width: 200,
            duration: const Duration(seconds: 1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    });
  }

  void _showCitation(BuildContext context, Citation citation) {
    final sourceName = widget.sources
            .firstWhere(
              (item) => item.id == citation.sourceId,
              orElse: () => SourceItem(
                id: '-',
                notebookId: '-',
                type: SourceType.paste,
                name: '未知来源',
                status: SourceStatus.ready,
                content: '',
                createdAt: DateTime(2000),
              ),
            )
            .name;
    final pageInfo = citation.pageNumber != null ? ' (第${citation.pageNumber}页)' : '';
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('引用片段$pageInfo - $sourceName'),
          content: Text(citation.snippet),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onOpenCitation?.call(citation);
              },
              child: const Text('查看来源'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  String _citationLabel(int index, Citation citation) {
    if (citation.pageNumber == null) {
      return '引用 ${index + 1}';
    }
    return '引用 ${index + 1} · P${citation.pageNumber}';
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.onTap, required this.label});
  final IconData icon;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 14, color: scheme.onSurface.withValues(alpha: 0.72)),
            const SizedBox(width: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockLatexSyntax extends md.InlineSyntax {
  _BlockLatexSyntax() : super(r'(?<!\\)\$\$([\s\S]+?)(?<!\\)\$\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final expression = (match[1] ?? '').trim();
    if (expression.isEmpty) {
      parser.addNode(md.Text(match[0] ?? ''));
      return true;
    }
    parser.addNode(md.Element.text('latex-block', expression));
    return true;
  }
}

class _ChatComposer extends StatefulWidget {
  const _ChatComposer({
    required this.controller,
    required this.focusNode,
    required this.isBusy,
    required this.canStop,
    required this.onKeyEvent,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isBusy;
  final bool canStop;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  State<_ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<_ChatComposer> {
  bool _focused = false;
  int _lineCount = 1;

  @override
  void initState() {
    super.initState();
    _focused = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_handleFocusChange);
    widget.controller.addListener(_handleTextChange);
    _lineCount = _calcLineCount(widget.controller.text);
  }

  @override
  void didUpdateWidget(covariant _ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChange);
      widget.focusNode.addListener(_handleFocusChange);
      _focused = widget.focusNode.hasFocus;
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChange);
      widget.controller.addListener(_handleTextChange);
      _lineCount = _calcLineCount(widget.controller.text);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChange);
    widget.controller.removeListener(_handleTextChange);
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _focused = widget.focusNode.hasFocus);
  }

  int _calcLineCount(String text) {
    if (text.isEmpty) return 1;
    return '\n'.allMatches(text).length + 1;
  }

  void _handleTextChange() {
    final next = _calcLineCount(widget.controller.text);
    if (next == _lineCount || !mounted) return;
    setState(() => _lineCount = next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final borderColor = isDark
        ? Colors.transparent
        : (_focused ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.6));
    final shadowColor = _focused
        ? scheme.primary.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: isDark ? 0.16 : 0.04);
    final isCompact = _lineCount <= 1;
    final fieldFontSize = isCompact ? 14.5 : 15.0;
    final hintFontSize = isCompact ? 13.5 : 14.0;
    final buttonSize = isCompact ? 36.0 : 40.0;
    final containerVerticalPadding = isCompact ? 6.0 : 8.0;
    final fieldMinHeight = isCompact ? 34.0 : 40.0;
    final textPaddingY = isCompact ? 7.0 : 9.0;
    final sendIconSize = isCompact ? 16.0 : 18.0;
    final loadingSize = isCompact ? 15.0 : 17.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.fromLTRB(12, containerVerticalPadding, 8, containerVerticalPadding),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              isDark ? scheme.surfaceContainer : Colors.white,
              isDark
                  ? scheme.surfaceContainerHigh
                  : scheme.surface.withValues(alpha: 0.92),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: _focused ? 1.4 : 1),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: _focused ? 12 : 7,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: fieldMinHeight),
                    child: Focus(
                      onKeyEvent: (_, event) => widget.onKeyEvent(event),
                      child: TextField(
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        minLines: 1,
                        maxLines: 4,
                        textAlignVertical: TextAlignVertical.center,
                        textInputAction: TextInputAction.newline,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontFamily: 'Consolas',
                          fontFamilyFallback: const ['GWMSansUI', 'SimHei'],
                          color: scheme.onSurface,
                          fontSize: fieldFontSize,
                          height: 1.28,
                        ),
                        decoration: InputDecoration(
                          hintText: isDesktop ? '输入问题  Enter发送 / Ctrl+Enter换行' : '输入问题...',
                          hintStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.6),
                            fontSize: hintFontSize,
                          ),
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.fromLTRB(0, textPaddingY, 8, textPaddingY),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  scale: widget.isBusy ? 0.99 : (_focused ? 1.01 : 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: widget.isBusy
                          ? null
                          : LinearGradient(
                              colors: [scheme.primary, scheme.primary.withValues(alpha: 0.85)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      color: widget.isBusy ? scheme.surfaceContainerHighest : null,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: widget.isBusy
                          ? (widget.canStop ? widget.onStop : null)
                          : widget.onSend,
                      splashRadius: 22,
                      tooltip: widget.isBusy && widget.canStop ? '停止生成' : '发送',
                      constraints: BoxConstraints.tightFor(width: buttonSize, height: buttonSize),
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: widget.isBusy
                            ? widget.canStop
                                ? Icon(
                                    Icons.stop_rounded,
                                    key: const ValueKey('stop-small'),
                                    color: scheme.error,
                                    size: sendIconSize + 1,
                                  )
                                : SizedBox(
                                    key: const ValueKey('loading-small'),
                                    width: loadingSize,
                                    height: loadingSize,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: scheme.primary,
                                    ),
                                  )
                            : Icon(
                                Icons.send_rounded,
                                key: const ValueKey('send-small'),
                                color: scheme.onPrimary,
                                size: sendIconSize,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
          ],
        ),
      ),
    );
  }
}

class _InlineLatexSyntax extends md.InlineSyntax {
  _InlineLatexSyntax() : super(r'(?<!\\)\$(?!\$)([^$\n]+?)(?<!\\)\$(?!\$)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final expression = (match[1] ?? '').trim();
    if (expression.isEmpty) {
      parser.addNode(md.Text(match[0] ?? ''));
      return true;
    }
    parser.addNode(md.Element.text('latex-inline', expression));
    return true;
  }
}

class _LatexElementBuilder extends MarkdownElementBuilder {
  _LatexElementBuilder({required this.displayMode});

  final bool displayMode;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final expression = element.textContent.trim();
    if (expression.isEmpty) {
      return null;
    }
    final textStyle = preferredStyle ??
        const TextStyle(
          fontFamily: 'Consolas',
          fontFamilyFallback: ['GWMSansUI', 'SimHei'],
          fontSize: 17,
        );
    return Padding(
      padding: displayMode ? const EdgeInsets.symmetric(vertical: 6) : EdgeInsets.zero,
      child: Math.tex(
        expression,
        mathStyle: displayMode ? MathStyle.display : MathStyle.text,
        textStyle: textStyle,
        onErrorFallback: (FlutterMathException e) {
          final wrapped = displayMode ? '\$\$$expression\$\$' : '\$$expression\$';
          return Text(
            wrapped,
            style: textStyle.copyWith(color: Colors.red.shade700),
          );
        },
      ),
    );
  }
}

class _ChatScrollBehavior extends MaterialScrollBehavior {
  const _ChatScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}
