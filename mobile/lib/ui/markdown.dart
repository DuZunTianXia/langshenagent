import 'package:flutter/material.dart';

import 'md/markdown_view.dart';

/// Markdown as the agent writes it, in the conversation — LangshenAgent's own
/// markdown renderer (the desktop's `MarkdownView`), math and tag
/// sections included.
class ChatMarkdown extends StatelessWidget {
  const ChatMarkdown({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return MarkdownView(text);
  }
}
