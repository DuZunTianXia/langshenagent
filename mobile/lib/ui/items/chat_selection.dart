import 'package:flutter/widgets.dart';

/// What the desktop's `selection/chat_selection.dart` gives the item
/// widgets, reduced on the phone to marking controls out of the text
/// selection around them: the phone has no conversation-wide selection,
/// so this is only `SelectionContainer.disabled` with the old name.
class ChatUnselectable extends StatelessWidget {
  const ChatUnselectable({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      SelectionContainer.disabled(child: child);
}
