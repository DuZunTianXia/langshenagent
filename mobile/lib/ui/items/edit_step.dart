import 'package:flutter/material.dart';

import '../../chat/chat_models.dart';
import '../../chat/edit_detail.dart';
import '../md/md_theme.dart';
import 'chat_selection.dart';
import 'l10n.dart';
import 'step_header.dart';

/// A file edit, as [EditDetail] has it: a card of the file's icon, name
/// and counts over its diff; or a step, "已编辑 main.dart +12 -3", a click
/// opening it to that card. The desktop renders the diff in its IDE
/// editor; the phone lays it out as text.
class EditStep extends StatelessWidget {
  const EditStep({
    super.key,
    required this.item,
    this.expanded = false,
    this.onToggle,
  });

  final CodeDiffItem item;

  /// Whether the step is open, as [EditDetail.compact] shows it; a card
  /// is always.
  final bool expanded;
  final VoidCallback? onToggle;

  /// How tall the card's diff grows before it scrolls.
  static const maxCardHeight = 160.0;

  /// How tall the diff grows inside an opened step, as the desktop's
  /// `CodeCitationCard.maxCodeHeight`.
  static const maxCodeHeight = 220.0;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: EditDetail.current,
    builder: (context, detail, _) => switch (detail) {
      EditDetail.card => _card(
        counts: true,
        maxHeight: maxCardHeight,
        // The lines start right under the name.
        padding: EdgeInsets.zero,
      ),
      EditDetail.compact => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StepHeader(
            verb: context.l10n.toolEdited,
            object: item.fileName,
            expanded: expanded,
            onToggle: onToggle,
            trailing: _Counts(item),
          ),
          ExpandReveal(
            show: expanded,
            child: _card(
              counts: false,
              maxHeight: maxCodeHeight,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    },
  );

  /// The file's name over its diff; its [counts] at the right when the
  /// card stands alone.
  Widget _card({
    required bool counts,
    required double maxHeight,
    required EdgeInsetsGeometry padding,
  }) {
    return StepBody(
      maxHeight: maxHeight,
      padding: padding,
      // Its lines fade under the name and at the bottom as they scroll.
      fadeEdges: true,
      scrollbar: true,
      // A line round it, no background.
      codeBlock: true,
      // Scrolled to its end, a wheel goes on to the conversation only from
      // outside it.
      keepWheel: true,
      header: _FileHeader(item: item, counts: counts),
      child: _Diff(item),
    );
  }
}

/// "+12 -3", in the chat's colors for lines added and removed; a count of
/// none is left out.
class _Counts extends StatelessWidget {
  const _Counts(this.item);

  final CodeDiffItem item;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        if (item.added > 0)
          TextSpan(
            text: '+${item.added}',
            style: TextStyle(color: themeColors['chat.linesAddedForeground']),
          ),
        if (item.added > 0 && item.removed > 0) const TextSpan(text: ' '),
        if (item.removed > 0)
          TextSpan(
            text: '-${item.removed}',
            style: TextStyle(color: themeColors['chat.linesRemovedForeground']),
          ),
      ],
    ),
    style: TextStyle(
      fontFamily: AppFonts.mono,
      fontFamilyFallback: AppFonts.monoFallbacks,
      fontSize: 11.5,
    ),
  );
}

/// The edited file's icon and name over its diff, its counts at the right
/// when [counts].
class _FileHeader extends StatelessWidget {
  const _FileHeader({required this.item, this.counts = false});

  final CodeDiffItem item;
  final bool counts;

  /// How tall it is: its name's line and room round it, as tall as a code
  /// block's title.
  static double heightOf(BuildContext context) =>
      (MediaQuery.textScalerOf(context).scale(12.5) * 1.3 + 10).roundToDouble();

  @override
  Widget build(BuildContext context) {
    return ChatUnselectable(
      child: Container(
        height: heightOf(context),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 15,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                item.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.text, fontSize: 12.5),
              ),
            ),
            if (counts) ...[const SizedBox(width: 8), _Counts(item)],
          ],
        ),
      ),
    );
  }
}

/// The diff as a unified view: each line numbered as in its file, added
/// and removed lines in their colors over their backgrounds.
class _Diff extends StatelessWidget {
  const _Diff(this.item);

  final CodeDiffItem item;

  @override
  Widget build(BuildContext context) {
    final mono = AppFonts.uiCodeStyle(11.5).copyWith(height: 1.45);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in item.lines) _line(line, mono),
      ],
    );
  }

  Widget _line(DiffLine line, TextStyle mono) {
    final (prefix, color, background) = switch (line.type) {
      DiffLineType.added => (
        '+',
        themeColors['chat.linesAddedForeground'],
        AppColors.addedBackground,
      ),
      DiffLineType.removed => (
        '-',
        themeColors['chat.linesRemovedForeground'],
        AppColors.removedBackground,
      ),
      DiffLineType.context => (' ', AppColors.textMuted, null),
    };
    return Container(
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '${line.lineNumber}',
              textAlign: TextAlign.right,
              style: mono.copyWith(color: AppColors.textFaint),
            ),
          ),
          const SizedBox(width: 8),
          Text(prefix, style: mono.copyWith(color: color)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              line.text.isEmpty ? ' ' : line.text,
              style: mono.copyWith(
                color: line.type == DiffLineType.context
                    ? AppColors.textMuted
                    : color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
