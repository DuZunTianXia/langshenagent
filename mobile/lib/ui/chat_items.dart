import 'dart:convert';
import 'dart:typed_data';

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
  });

  final ChatItem item;

  /// A subagent's card tapped: open its conversation, when it has one.
  final void Function(AgentItem agent)? onAgent;

  /// "编辑重发" for a user's own message: `(newText, revertFiles)`.
  final void Function(String text, bool revertFiles)? onEditResend;

  /// "回退到这一步" for a plan card.
  final VoidCallback? onRewind;

  /// Opens a plan card's file.
  final VoidCallback? onOpenPlan;

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
  void Function(String text, bool revertFiles)? onEditResend,
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
                      _editResend(context, text, onEditResend);
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

/// The "编辑重发" flow: the message's text editable, whether the files the
/// agent touched after it should be put back first.
Future<void> _editResend(
  BuildContext context,
  String text,
  void Function(String text, bool revertFiles) onSend,
) async {
  final controller = TextEditingController(text: text);
  var revert = false;
  String? edited;
  final send = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Dialog(
        backgroundColor: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.edit_note, size: 20, color: AppColors.accent),
                  const SizedBox(width: 8),
                  const Text('编辑并重发', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 3,
                maxLines: 8,
                decoration: BTextField.decoration(hint: '修改消息后重新发送'),
              ),
              const SizedBox(height: 10),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => revert = !revert),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: revert ? AppColors.accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: revert ? AppColors.accent : AppColors.textFaint,
                            width: 1.5,
                          ),
                        ),
                        child: revert
                            ? const Icon(Icons.check, size: 14, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '回滚之后的文件改动',
                          style: TextStyle(fontSize: 13, color: AppColors.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  BButton(
                    label: '取消',
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 10),
                  BButton(
                    label: '重发',
                    icon: Icons.send,
                    primary: true,
                    onPressed: () {
                      edited = controller.text.trim();
                      Navigator.of(context).pop(true);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  controller.dispose();
  final editedText = edited;
  if (send == true && editedText != null && editedText.isNotEmpty) {
    onSend(editedText, revert);
  }
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
