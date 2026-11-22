import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';

import '../link/phone_link.dart';
import 'widgets.dart';
import '../ui/markdown.dart';

/// A group chat of the user and bots: its messages, and the composer.
class GroupPage extends StatefulWidget {
  const GroupPage({super.key, required this.link, required this.group});

  final PhoneLink link;
  final LinkGroup group;

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  GroupFeed? _feed;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      final feed = await widget.link.openGroup(widget.group.id);
      if (mounted) setState(() => _feed = feed);
    } on Object {}
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _busy) return;
    _text.clear();
    setState(() => _busy = true);
    try {
      await widget.link.sendGroup(widget.group.id, text: text);
    } on Object {
      if (mounted) {
        showBToast(context, '发送失败');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _nameOf(String id) {
    if (id == 'user' || id == 'me') return '我';
    for (final bot in widget.link.state?.bots ?? const []) {
      if (bot.id == id) return bot.name;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feed;
    return Scaffold(
      appBar: AppBar(title: Text(widget.group.name)),
      body: Column(
        children: [
          Expanded(
            child: feed == null
                ? const Center(child: CircularProgressIndicator())
                : ListenableBuilder(
                    listenable: feed,
                    builder: (context, _) => ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: feed.messages.length,
                      itemBuilder: (context, index) {
                        final message = feed.messages[index];
                        return _message(context, message);
                      },
                    ),
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: BComposer(
                controller: _text,
                hint: '向群里发消息…',
                canSend: _text.text.trim().isNotEmpty,
                onChanged: () => setState(() {}),
                onSend: _send,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(BuildContext context, LinkGroupMessage message) {
    final theme = Theme.of(context);
    final mine = message.from == 'user' || message.from == 'me';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: mine
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Text(
                _nameOf(message.from),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ChatMarkdown(text: message.text),
            if (message.images.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${message.images.length} 张图片',
                  style: theme.textTheme.labelSmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
