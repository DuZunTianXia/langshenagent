import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/chat_models.dart';
import '../codicons.dart';
import 'items/chat_item_view.dart' as items;
import 'items/image_preview.dart';
import 'md/md_theme.dart';
import 'widgets.dart';

/// One history item, as the phone shows it: the desktop's view of it
/// ([items.ChatItemView]), its steps opening and closing themselves.
class ChatItemView extends StatefulWidget {
  const ChatItemView({
    super.key,
    required this.item,
    this.onAgent,
    this.onEditResend,
    this.onRewind,
    this.onOpenPlan,
    this.onStop,
  });

  final ChatItem item;

  /// A subagent's card tapped: open its conversation, when it has one.
  final void Function(AgentItem agent)? onAgent;

  /// Opens the full edit-and-resend sheet for this message's plain text.
  final void Function(String text)? onEditResend;

  /// "回退到这一步" for a plan card.
  final VoidCallback? onRewind;

  /// Opens a plan card's file.
  final VoidCallback? onOpenPlan;

  /// Stops a running subagent (its card's stop button).
  final VoidCallback? onStop;

  @override
  State<ChatItemView> createState() => _ChatItemViewState();
}

class _ChatItemViewState extends State<ChatItemView> {
  late bool _expanded = items.defaultExpanded(widget.item);

  @override
  void didUpdateWidget(ChatItemView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The items are redecoded as the feed notifies, new objects each time;
    // only a different kind in the slot is a different step to fold back.
    if (widget.item.runtimeType != oldWidget.item.runtimeType) {
      _expanded = items.defaultExpanded(widget.item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: () => _showDetail(
        context,
        item,
        expanded: _expanded,
        onEditResend: widget.onEditResend,
        onRewind: widget.onRewind,
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: items.ChatItemView(
          item: item,
          expanded: _expanded,
          onToggle: items.isExpandable(item)
              ? () => setState(() => _expanded = !_expanded)
              : null,
          onOpen: item is AgentItem && widget.onAgent != null
              ? () => widget.onAgent!(item)
              : null,
          onStop: item is AgentItem ? widget.onStop : null,
          onOpenPlan: widget.onOpenPlan,
          // The bubble's own click (the desktop's "edit this message")
          // shows the message's detail here instead.
          onEdit: item is UserMessageItem
              ? () => _showDetail(
                  context,
                  item,
                  expanded: _expanded,
                  onEditResend: widget.onEditResend,
                  onRewind: widget.onRewind,
                )
              : null,
        ),
      ),
    );
  }
}

/// A message's detail sheet (the official's message actions): its whole
/// text to read and copy, its pictures to open whole.
void _showDetail(
  BuildContext context,
  ChatItem item, {
  bool expanded = false,
  void Function(String text)? onEditResend,
  VoidCallback? onRewind,
}) {
  final images = switch (item) {
    UserMessageItem(:final images) => images,
    ToolCallItem(:final images) => images,
    _ => const <ImageAttachment>[],
  };
  var text = items.chatItemPlainText(item, expanded: expanded).trim();
  if (images.isNotEmpty) {
    text = text.replaceAll(RegExp(r'\s*\[Image #\d+\]'), '').trim();
  }
  if (text.isEmpty && images.isEmpty) return;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    builder: (context) => SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.45,
        maxChildSize: 0.9,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
              child: Text(
                '消息详情',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (text.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(text),
              ),
            if (images.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final image in images)
                      ImagePreviewClick(
                        image: image,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: 240,
                              maxHeight: 220,
                            ),
                            child: Image.memory(image.bytes),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onEditResend != null)
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onEditResend(text);
                    },
                    child: const Text('编辑重发'),
                  ),
                if (onRewind != null)
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onRewind();
                    },
                    child: const Text('回退到此'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('关闭', style: TextStyle(color: AppColors.textMuted)),
                ),
                const SizedBox(width: 8),
                if (text.isNotEmpty)
                  BButton(
                    icon: Codicons.copy,
                    label: '复制',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: text));
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// The image bytes of an [ImageAttachment] JSON, for a `ToolCallItem`'s
/// images decoded by hand where needed.
Uint8List? attachmentBytes(Map<String, Object?> json) {
  final data = json['data'];
  if (data is! String) return null;
  try {
    return base64.decode(data);
  } on Object {
    return null;
  }
}
