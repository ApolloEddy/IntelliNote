import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../app/app_state.dart';
import '../../core/models.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.notebookId});

  final String notebookId;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _sending = false;
  bool _autoScrollEnabled = true;

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
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) return;
    
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
      final isControlPressed = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlLeft) ||
                               HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.controlRight);
      
      if (isControlPressed) {
        // Ctrl + Enter: Insert newline
        final text = _controller.text;
        final selection = _controller.selection;
        final newText = text.replaceRange(selection.start, selection.end, '\n');
        _controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: selection.start + 1),
        );
      } else {
        // Enter: Send
        _send(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final messages = state.chatsFor(widget.notebookId);
    final sources = state.sourcesFor(widget.notebookId);
    final isProcessing = state.isProcessing(widget.notebookId);
    final selectedIds = state.selectedSourceIdsFor(widget.notebookId);

    if (isProcessing && _autoScrollEnabled) {
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
                  const Expanded(
                    child: Text('引用来源 (可选):', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(source.name),
                        selected: isSelected,
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
                if (notification is UserScrollNotification) {
                  setState(() => _autoScrollEnabled = false);
                }
                if (notification.metrics.extentAfter < 10) {
                  if (!_autoScrollEnabled) {
                    setState(() => _autoScrollEnabled = true);
                  }
                }
                return false;
              },
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final message = messages[index];
                  return _ChatBubble(
                    message: message,
                    sources: sources,
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: KeyboardListener(
                    focusNode: _focusNode,
                    onKeyEvent: _handleKeyEvent,
                    child: TextField(
                      controller: _controller,
                      maxLines: 5,
                      minLines: 1,
                      style: const TextStyle(fontSize: 17),
                      decoration: const InputDecoration(
                        hintText: '输入问题 (Enter发送, Ctrl+Enter换行)',
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey, width: 0.5),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.indigo, width: 1.5),
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: (isProcessing || _sending) ? null : () => _send(context),
                  child: (isProcessing || _sending)
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('发送'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send(BuildContext context) async {
    final question = _controller.text.trim();
    if (question.isEmpty) {
      return;
    }

    final state = context.read<AppState>();
    final selectedIds = state.selectedSourceIdsFor(widget.notebookId);
    
    setState(() {
      _sending = true;
      _autoScrollEnabled = true;
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
  const _ChatBubble({required this.message, required this.sources});

  final ChatMessage message;
  final List<SourceItem> sources;

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble> {
  bool _showActions = false;

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == ChatRole.user;
    final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

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
              margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              padding: const EdgeInsets.all(12),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                color: isUser ? Colors.indigo.shade100 : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: widget.message.content,
                    selectable: false,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(
                        fontFamily: 'Consolas',
                        fontFamilyFallback: ['GWMSansUI', 'SimHei'],
                        fontSize: 17,
                      ),
                      code: const TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 15,
                        backgroundColor: Color(0xFFE0E0E0),
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.shade300),
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
                          label: Text('引用 ${index + 1}', style: const TextStyle(fontSize: 11)),
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
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('引用片段 - $sourceName'),
          content: Text(citation.snippet),
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

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.onTap, required this.label});
  final IconData icon;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 2),
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}
