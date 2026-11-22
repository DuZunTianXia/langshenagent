import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../chat/chat_models.dart';
import '../md/md_theme.dart';
import '../widgets.dart';
import 'hover_builder.dart';
import 'l10n.dart';
import 'shell_highlight.dart';
import 'step_header.dart';
import 'terminal_output.dart';

/// A shell command as a step: "已运行  Check the Flutter version", opening to
/// the command, colored, and what it printed.
class CommandStep extends StatelessWidget {
  const CommandStep({
    super.key,
    required this.command,
    required this.output,
    this.description,
    this.status = CommandStatus.succeeded,
    this.background = false,
    this.expanded = false,
    this.onToggle,
    this.onMoveToBackground,
  });

  final String command;
  final String output;
  final String? description;
  final CommandStatus status;

  /// Left running on its own: the turn went on.
  final bool background;
  final bool expanded;
  final VoidCallback? onToggle;

  /// Lets the turn go on while the command keeps running.
  final VoidCallback? onMoveToBackground;

  bool get _running => status == CommandStatus.running && !background;

  /// Anything to open to: the command may still be on its way.
  bool get _opens => command.trim().isNotEmpty || output.trim().isNotEmpty;

  /// What the header says it is: its description, or its first line.
  static String title(String command, String? description) =>
      switch (description?.trim()) {
        final text? when text.isNotEmpty => text,
        _ => command.trim().split('\n').first,
      };

  /// In [l10n]'s language.
  static String verb(
    CommandStatus status, {
    required bool background,
    AppLocalizations? l10n,
  }) {
    final strings = l10n ?? englishLocalizations;
    return background
        ? strings.commandStarted
        : status == CommandStatus.running
        ? strings.toolRunning
        : strings.toolRan;
  }

  @override
  Widget build(BuildContext context) {
    // Rendered once opened: most steps stay closed.
    final printed = expanded ? terminalOutput(output) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepHeader(
          verb: verb(status, background: background, l10n: context.l10n),
          object: title(command, description),
          detail: background ? context.l10n.commandInBackground : null,
          running: _running,
          expanded: expanded,
          onToggle: _opens ? onToggle : null,
        ),
        if (expanded && _opens)
          StepBody(
            followEnd: _running,
            scrollbar: true,
            // Clear of the menu button.
            padding: const EdgeInsets.fromLTRB(12, 10, 36, 10),
            overlay: _CommandMenu(
              command: command,
              output: output,
              onMoveToBackground: onMoveToBackground,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '\$ ',
                        style: TextStyle(color: AppColors.textFaint),
                      ),
                      ...highlightShell(command),
                    ],
                  ),
                  style: stepMono,
                ),
                if (printed != null && printed.text.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  if (printed.styled)
                    Text.rich(printed.span, style: stepMono)
                  else
                    Text(printed.text, style: stepMono),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// `…`: copy the command or its output; while it runs, move it to the
/// background.
class _CommandMenu extends StatelessWidget {
  const _CommandMenu({
    required this.command,
    required this.output,
    this.onMoveToBackground,
  });

  final String command;
  final String output;
  final VoidCallback? onMoveToBackground;

  static void _copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: l10n.commandMore,
      child: GestureDetector(
        onTap: () async {
          final action = await showBActions<void Function()>(
            context,
            actions: [
              (
                Icons.content_copy_rounded,
                l10n.commandCopyCommand,
                null,
                () => _copy(command),
              ),
              if (terminalOutput(output).text case final printed
                  when printed.isNotEmpty)
                (
                  Icons.notes_rounded,
                  l10n.commandCopyOutput,
                  null,
                  () => _copy(printed),
                ),
              if (onMoveToBackground case final move?)
                (
                  Icons.move_down_rounded,
                  l10n.commandMoveToBackground,
                  null,
                  move,
                ),
            ],
          );
          action?.call();
        },
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: hovered ? AppColors.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(
              Icons.more_horiz_rounded,
              size: 16,
              color: hovered ? AppColors.text : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
