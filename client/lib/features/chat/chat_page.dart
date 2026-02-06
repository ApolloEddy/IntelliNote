import 'package:flutter/material.dart';
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
  SourceScope _scope = const SourceScope.all();
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final messages = state.chatsFor(widget.notebookId);
    final sources = state.sourcesFor(widget.notebookId);
    return Column(
      children: [
        if (sources.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<SourceScope>(
              value: _scope,
              decoration: const InputDecoration(labelText: '引用范围'),
              items: [
                const DropdownMenuItem(
                  value: SourceScope.all(),
                  child: Text('全部来源'),
                ),
                ...sources.map(
                  (source) => DropdownMenuItem(
                    value: SourceScope.sources([source.id]),
                    child: Text(source.name),
                  ),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _scope = value);
                }
              },
            ),
          ),
        Expanded(
          child: ListView.builder(
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
                onPressed: _sending ? null : () => _send(context),
                child: _sending
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
    );
  }

  Future<void> _send(BuildContext context) async {
    final question = _controller.text.trim();
    if (question.isEmpty) {
      return;
    }
    setState(() => _sending = true);
    _controller.clear();
    await context.read<AppState>().askQuestion(
          notebookId: widget.notebookId,
          question: question,
          scope: _scope,
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
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? Colors.indigo.shade100 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.content),
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
