import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

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
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: '输入问题',
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
      _autoScrollEnabled = true; // Reset auto-scroll on new message
    });
    _controller.clear();
    
    // Immediate scroll for user message
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    // Always send the selected IDs. If empty, the server will handle it as general chat.
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

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.sources});

  final ChatMessage message;
  final List<SourceItem> sources;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
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
              data: message.content,
              selectable: false,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(
                  fontFamily: 'Consolas',
                  fontFamilyFallback: ['GWMSansUI', 'SimHei'],
                  fontSize: 15,
                ),
                code: const TextStyle(
                  fontFamily: 'Consolas',
                  backgroundColor: Color(0xFFE0E0E0),
                ),
                codeblockDecoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
              ),
            ),
            if (message.citations.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: List.generate(
                  message.citations.length,
                  (index) => ActionChip(
                    label: Text('引用 ${index + 1}'),
                    onPressed: () => _showCitation(context, message.citations[index]),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showCitation(BuildContext context, Citation citation) {
    final sourceName = sources
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
