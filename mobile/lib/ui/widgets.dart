import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../codicons.dart';
import 'md/md_theme.dart';

/// The app's own widget kit — every input, button, card, sheet and toast
/// looks the same everywhere: the official phone app's rounded, soft
/// green-and-white style rather than Material's defaults.

/// A rounded filled text field. [label] above the box, [hint] inside it.
class BTextField extends StatelessWidget {
  const BTextField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.lines = 1,
    this.number = false,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final int lines;
  final bool number;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  static InputDecoration decoration({
    String? hint,
    String? label,
    double radius = 12,
    EdgeInsetsGeometry? contentPadding,
  }) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: color == Colors.transparent
          ? BorderSide.none
          : BorderSide(color: color, width: width),
    );
    return InputDecoration(
      hintText: hint,
      labelText: label,
      hintStyle: TextStyle(color: AppColors.textFaint, fontSize: 14),
      isDense: true,
      filled: true,
      fillColor: AppColors.bubbleFill,
      contentPadding:
          contentPadding ??
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: border(Colors.transparent, 0),
      enabledBorder: border(Colors.transparent, 0),
      focusedBorder: border(AppColors.accent, 1.2),
    );
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    minLines: 1,
    maxLines: lines,
    autofocus: autofocus,
    keyboardType: number
        ? TextInputType.number
        : lines > 1
        ? TextInputType.multiline
        : TextInputType.text,
    style: const TextStyle(fontSize: 14),
    decoration: decoration(hint: hint, label: label),
    onSubmitted: onSubmitted,
  );
}

/// The app's button: [primary] is the filled green pill, [danger] the
/// filled red one, none the quiet tonal one. [icon] before the label,
/// [busy] swaps the label for a spinner.
class BButton extends StatelessWidget {
  const BButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.primary = false,
    this.danger = false,
    this.busy = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool primary;
  final bool danger;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16),
                const SizedBox(width: 6),
              ],
              Text(label, style: const TextStyle(fontSize: 13.5)),
            ],
          );
    final style = FilledButton.styleFrom(
      backgroundColor: danger
          ? Theme.of(context).colorScheme.error
          : primary
          ? AppColors.accent
          : AppColors.surface,
      foregroundColor: danger || primary
          ? Colors.white
          : AppColors.textPrimary,
      disabledBackgroundColor: AppColors.surface,
      disabledForegroundColor: AppColors.textFaint,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
    final button = FilledButton(
      onPressed: busy ? null : onPressed,
      style: style,
      child: child,
    );
    if (expand) return SizedBox(width: double.infinity, child: button);
    return button;
  }
}

/// A section of settings-like content: a small grey title above a white
/// rounded card holding [children].
class BSection extends StatelessWidget {
  const BSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
          child: Text(
            title,
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
        ),
        BCard(padding: EdgeInsets.zero, child: Column(children: children)),
      ],
    ),
  );
}

/// A white rounded card, the surface every section and detail uses.
class BCard extends StatelessWidget {
  const BCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.partBorder.withValues(alpha: 0.55)),
      boxShadow: [
        BoxShadow(
          color: MdTheme.dark
              ? Colors.black.withValues(alpha: 0.3)
              : Colors.black.withValues(alpha: 0.08),
          blurRadius: MdTheme.dark ? 8 : 6,
          offset: MdTheme.dark ? const Offset(0, 2) : const Offset(0, 1),
        ),
      ],
    ),
    padding: padding ?? const EdgeInsets.all(14),
    child: child,
  );
}

/// Centered placeholder when a list or tab has nothing to show.
class BEmptyState extends StatelessWidget {
  const BEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 34, color: AppColors.accent),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: AppColors.textMuted,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 22),
            BButton(label: actionLabel!, primary: true, onPressed: onAction),
          ],
        ],
      ),
    ),
  );
}

/// Red unread capsule for inbox rows and tab badges.
class BUnreadBadge extends StatelessWidget {
  const BUnreadBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 18),
    height: 18,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFFA5151),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: AppColors.surfaceRaised, width: 1.5),
    ),
    alignment: Alignment.center,
    child: Text(
      count > 99 ? '99+' : '$count',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        height: 1,
      ),
    ),
  );
}

/// WeChat-style conversation list row: avatar, title, subtitle, time, badge.
class BInboxRow extends StatelessWidget {
  const BInboxRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.time,
    this.badge = 0,
    this.pinned = false,
    this.titleWeight = FontWeight.w600,
    this.onTap,
    this.onLongPress,
  });

  final Widget leading;
  final String title;
  final Widget? subtitle;
  final String? time;
  final int badge;
  final bool pinned;
  final FontWeight titleWeight;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: titleWeight,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    DefaultTextStyle(
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                        height: 1.25,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: subtitle!,
                    ),
                  ],
                ],
              ),
            ),
            if (time != null || badge > 0 || pinned) ...[
              const SizedBox(width: 8),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (time != null)
                    Text(
                      time!,
                      style: TextStyle(fontSize: 11.5, color: AppColors.textFaint),
                    ),
                  if (badge > 0 || pinned) ...[
                    const SizedBox(height: 5),
                    if (badge > 0)
                      BUnreadBadge(count: badge)
                    else if (pinned)
                      Icon(Icons.push_pin, size: 14, color: AppColors.textFaint),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// A row in a [BCard]: optional leading icon in a tinted box, title,
/// subtitle, chevron or [trailing], [onTap].
class BCell extends StatelessWidget {
  const BCell({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.trailing,
    this.titleColor,
    this.onTap,
    this.showChevron = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Color? titleColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: (iconColor ?? AppColors.accent).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 19, color: iconColor ?? AppColors.accent),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: titleColor ?? AppColors.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
          if (onTap != null && showChevron)
            Icon(Icons.chevron_right, size: 20, color: AppColors.textFaint),
        ],
      ),
    ),
  );
}

/// A divider for between [BCell]s, indented past a leading icon.
class BDivider extends StatelessWidget {
  const BDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Divider(height: 0.5, indent: 60, color: AppColors.partBorder);
}

/// A softly pulsing dot — the "working" marker on a session or a
/// workspace's tile while an agent runs inside.
class BPulseDot extends StatefulWidget {
  const BPulseDot({super.key, this.color, this.size = 10});

  final Color? color;
  final double size;

  @override
  State<BPulseDot> createState() => _BPulseDotState();
}

class _BPulseDotState extends State<BPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.accent;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.55 * (1 - t)),
                blurRadius: widget.size * (0.6 + 0.9 * t),
                spreadRadius: widget.size * 0.18 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A toast — the pill at the bottom, green tick by default, red cross on
/// [isError].
void showBToast(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: Colors.transparent,
        duration: const Duration(seconds: 2),
        content: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: const Color(0xF2202020),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.check_circle_outline,
                  size: 17,
                  color: isError ? const Color(0xFFFF6B6B) : AppColors.accent,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    message,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
}

/// Picks one of [options]: grouped ones (e.g. models under their
/// providers) are two pages in one sheet — the group first, then its
/// options, a back arrow between them. Ungrouped lists go straight to
/// the options page.
Future<LinkOption?> showBChoicePicker(
  BuildContext context, {
  required String title,
  required List<LinkOption> options,
  String? selected,
  String? initialGroup,
  Widget? Function(String id)? iconOf,
  String Function(String label)? labelOf,
}) => showModalBottomSheet<LinkOption>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  backgroundColor: AppColors.surfaceRaised,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
  ),
  builder: (context) => _ChoiceSheet(
    title: title,
    options: options,
    selected: selected,
    initialGroup: initialGroup,
    iconOf: iconOf,
    labelOf: labelOf,
  ),
);

class _ChoiceSheet extends StatefulWidget {
  const _ChoiceSheet({
    required this.title,
    required this.options,
    this.selected,
    this.initialGroup,
    this.iconOf,
    this.labelOf,
  });

  final String title;
  final List<LinkOption> options;
  final String? selected;

  /// Opens the sheet drilled into this group instead of the group list.
  final String? initialGroup;
  final Widget? Function(String id)? iconOf;
  final String Function(String label)? labelOf;

  @override
  State<_ChoiceSheet> createState() => _ChoiceSheetState();
}

class _ChoiceSheetState extends State<_ChoiceSheet> {
  /// The group picked; null lists the groups. Directly an option list
  /// when there is nothing to group by.
  String? _group;

  bool get _grouped {
    final groups = widget.options.map((o) => o.group).toSet();
    return groups.length > 1 ||
        (groups.length == 1 && groups.single != null);
  }

  @override
  void initState() {
    super.initState();
    _group = _grouped ? widget.initialGroup : '';
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final group = _group;
    final groups = <String, List<LinkOption>>{};
    for (final option in widget.options) {
      groups.putIfAbsent(option.group ?? '', () => []).add(option);
    }
    final header = group != null && grouped
        ? (widget.options
              .where((o) => (o.group ?? '') == group)
              .first
              .groupLabel ??
          group)
        : widget.title;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  if (group != null && grouped)
                    GestureDetector(
                      onTap: () => setState(() => _group = null),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.arrow_back_ios_new,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      header,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (group == null && grouped)
                    for (final entry in groups.entries)
                      _groupTile(entry.key, entry.value)
                  else
                    for (final option in widget.options.where(
                      (o) => !grouped || (o.group ?? '') == group,
                    ))
                      _optionTile(option),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupTile(String group, List<LinkOption> options) {
    final label = options.first.groupLabel ?? (group.isEmpty ? '其他' : group);
    final selectedHere = options.any((o) => o.id == widget.selected);
    return InkWell(
      onTap: () => setState(() => _group = group),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: AppColors.textPrimary,
                      fontWeight: selectedHere
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${options.length} 个选项',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            if (selectedHere)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.check, size: 18, color: AppColors.accent),
              ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textFaint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionTile(LinkOption option) {
    final selected = option.id == widget.selected;
    final icon = widget.iconOf?.call(option.id);
    return InkWell(
      onTap: () => Navigator.of(context).pop(option),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // With any iconOf at all, a row keeps the icon's room whether
            // or not this option has one: the labels line up.
            if (widget.iconOf != null) ...[
              SizedBox(
                width: 20,
                height: 20,
                child: icon ??
                    Icon(
                      Icons.memory_rounded,
                      size: 18,
                      color: AppColors.textFaint,
                    ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.labelOf?.call(option.label) ?? option.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (option.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      option.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (option.caution)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.warning_amber,
                  size: 18,
                  color: Colors.orange,
                ),
              ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected ? AppColors.accent : AppColors.textFaint,
            ),
          ],
        ),
      ),
    );
  }
}

/// An action sheet in the app's look: each row a tinted icon box (or a
/// custom [leadingOf] widget, or none when the tuple's icon is null), a
/// label and an optional subtitle. Rows whose value is in [danger]
/// render in the error tone; [selected] gets an accent check. Returns
/// the tapped action's value.
Future<T?> showBActions<T>(
  BuildContext context, {
  required List<(IconData? icon, String label, String? subtitle, T value)>
  actions,
  String? title,
  T? selected,
  Set<T> danger = const {},
  Widget? Function(T value)? leadingOf,
}) => showModalBottomSheet<T>(
  context: context,
  showDragHandle: true,
  backgroundColor: AppColors.surfaceRaised,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
  ),
  builder: (sheet) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        for (final (icon, label, subtitle, value) in actions)
          InkWell(
            onTap: () => Navigator.of(sheet).pop(value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Builder(
                builder: (context) {
                  final isDanger = danger.contains(value);
                  final tint = isDanger
                      ? Theme.of(context).colorScheme.error
                      : AppColors.accent;
                  final leading = leadingOf?.call(value);
                  final checked = selected == value;
                  return Row(
                    children: [
                      if (leading != null) ...[
                        leading,
                        const SizedBox(width: 12),
                      ] else if (icon != null) ...[
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: tint.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon, size: 20, color: tint),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: checked
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isDanger
                                    ? tint
                                    : AppColors.textPrimary,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (checked)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 20,
                          color: AppColors.accent,
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    ),
  ),
);

/// A one-line input dialog in the app's look — rename-a-thing prompts.
/// Returns the trimmed text, or null when cancelled or left empty.
Future<String?> showBPrompt(
  BuildContext context, {
  required String title,
  String? initial,
  String? hint,
  String confirm = '保存',
  int lines = 1,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => _BPromptDialog(
      title: title,
      controller: controller,
      hint: hint,
      confirm: confirm,
      lines: lines,
    ),
  );
  controller.dispose();
  return result;
}

class _BPromptDialog extends StatefulWidget {
  const _BPromptDialog({
    required this.title,
    required this.controller,
    required this.confirm,
    required this.lines,
    this.hint,
  });

  final String title;
  final TextEditingController controller;
  final String? hint;
  final String confirm;
  final int lines;

  @override
  State<_BPromptDialog> createState() => _BPromptDialogState();
}

class _BPromptDialogState extends State<_BPromptDialog> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text.trim();
    return AlertDialog(
      backgroundColor: AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(widget.title, style: const TextStyle(fontSize: 16)),
      content: TextField(
        controller: widget.controller,
        autofocus: true,
        minLines: 1,
        maxLines: widget.lines,
        decoration: BTextField.decoration(hint: widget.hint),
        onSubmitted: (_) {
          if (text.isNotEmpty) Navigator.of(context).pop(text);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TextStyle(color: AppColors.textMuted)),
        ),
        BButton(
          label: widget.confirm,
          primary: true,
          onPressed: text.isEmpty
              ? null
              : () => Navigator.of(context).pop(text),
        ),
      ],
    );
  }
}

/// A confirm dialog in the app's look: [danger] paints the action red.
/// Returns whether confirmed.
Future<bool> showBConfirm(
  BuildContext context, {
  required String title,
  String? body,
  String confirm = '确定',
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: body == null
          ? null
          : Text(
              body,
              style: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('取消', style: TextStyle(color: AppColors.textMuted)),
        ),
        BButton(
          label: confirm,
          danger: danger,
          primary: !danger,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return ok == true;
}

/// A list row with left-swipe actions (置顶/删除), as chat apps have it.
class BSlidable extends StatelessWidget {
  const BSlidable({
    super.key,
    required this.child,
    this.pinned = false,
    this.onPin,
    this.onDelete,
  });

  final Widget child;
  final bool pinned;
  final VoidCallback? onPin;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Slidable(
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: onDelete != null && onPin != null ? 0.5 : 0.25,
        children: [
          if (onPin != null)
            CustomSlidableAction(
              backgroundColor: AppColors.accent.withValues(alpha: 0.14),
              onPressed: (_) => onPin!(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    pinned ? Icons.push_pin_outlined : Icons.push_pin,
                    size: 20,
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pinned ? '取消置顶' : '置顶',
                    style: TextStyle(fontSize: 11, color: AppColors.accent),
                  ),
                ],
              ),
            ),
          if (onDelete != null)
            CustomSlidableAction(
              backgroundColor: const Color(0x1AD64545),
              onPressed: (_) => onDelete!(),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_outline, size: 20, color: Color(0xFFD64545)),
                  SizedBox(height: 2),
                  Text(
                    '删除',
                    style: TextStyle(fontSize: 11, color: Color(0xFFD64545)),
                  ),
                ],
              ),
            ),
        ],
      ),
      child: child,
    );
  }
}

/// A dropdown that reads like a [BTextField] and picks from a sheet.
class BDropdown<T> extends StatelessWidget {
  const BDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final String? hint;

  String get _label {
    for (final (v, label) in items) {
      if (v == value) return label;
    }
    return hint ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final picked = await showModalBottomSheet<T>(
          context: context,
          builder: (sheet) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (v, label) in items)
                  ListTile(
                    title: Text(label),
                    trailing: v == value
                        ? Icon(Icons.check, color: AppColors.accent, size: 18)
                        : null,
                    onTap: () => Navigator.of(sheet).pop(v),
                  ),
              ],
            ),
          ),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: BTextField.decoration(hint: hint),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _label,
                style: TextStyle(
                  fontSize: 14,
                  color: _label.isEmpty ? AppColors.textFaint : AppColors.text,
                ),
              ),
            ),
            Icon(Icons.unfold_more, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// The chat's input pill: a quiet +, the growing field, and bare
/// send or stop glyphs that spring in when there is something to act
/// on — send while [canSend], stop while [live] (both while it works:
/// a message sent then waits its turn).
class BComposer extends StatefulWidget {
  const BComposer({
    super.key,
    required this.controller,
    this.hint = '发消息…',
    this.live = false,
    this.canSend = false,
    this.onAttach,
    this.onChanged,
    this.onSend,
    this.onStop,
  });

  final TextEditingController controller;
  final String hint;
  final bool live;
  final bool canSend;
  final VoidCallback? onAttach;
  final VoidCallback? onChanged;
  final VoidCallback? onSend;
  final VoidCallback? onStop;

  @override
  State<BComposer> createState() => _BComposerState();
}

class _BComposerState extends State<BComposer> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final action = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.live && widget.onStop != null)
          _ComposerRoundButton(
            background: Theme.of(context).colorScheme.error,
            onPressed: widget.onStop,
            child: const Icon(
              Icons.stop_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
        if (widget.canSend)
          _ComposerRoundButton(
            background: AppColors.accent,
            onPressed: widget.onSend,
            child: const Icon(
              Icons.arrow_upward_rounded,
              size: 19,
              color: Colors.white,
            ),
          ),
      ],
    );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bubbleFill,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: AppColors.bubbleBorder(focused: _focused)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (widget.onAttach != null)
            _ComposerGlyph(
              icon: Codicons.plus,
              color: AppColors.textMuted,
              onPressed: widget.onAttach,
            ),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              cursorColor: AppColors.accent,
              style: TextStyle(fontSize: 15, color: AppColors.text),
              onChanged: (_) => widget.onChanged?.call(),
              onSubmitted: (_) {
                if (widget.canSend) widget.onSend?.call();
              },
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: TextStyle(color: AppColors.textFaint, fontSize: 15),
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
              ),
            ),
          ),
          action,
        ],
      ),
    );
  }
}

/// A bare icon inside [BComposer] — no circle, no border, just the
/// glyph in its color with a small ripple on tap.
class _ComposerGlyph extends StatelessWidget {
  const _ComposerGlyph({
    required this.icon,
    required this.color,
    this.onPressed,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onPressed,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 23, color: color),
      ),
    );
  }
}

/// A filled circular action button inside [BComposer] — the send key's
/// accent-green disc and the stop key's error-red one, as WeChat and the
/// mainstream IMs draw them.
class _ComposerRoundButton extends StatelessWidget {
  const _ComposerRoundButton({
    required this.background,
    required this.child,
    this.onPressed,
  });

  final Color background;
  final Widget child;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(width: 32, height: 32, child: Center(child: child)),
        ),
      ),
    );
  }
}

/// A file-type icon: the official / widely-used brand SVG for the
/// file's language or format (Material Icon Theme set, bundled in
/// `assets/file_icons/`), falling back to a generic file glyph.
class BFileIcon extends StatelessWidget {
  const BFileIcon({super.key, required this.name, this.size = 24});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/file_icons/${_icon(name)}.svg',
    width: size,
    height: size,
  );

  static String _icon(String path) {
    final name = path.split('/').last.toLowerCase();
    if (name.startsWith('docker') || name.startsWith('containerfile')) {
      return 'docker';
    }
    if (name.startsWith('makefile') || name == 'gnumakefile') {
      return 'makefile';
    }
    if (name.startsWith('cmakelists')) return 'cmake';
    if (name.startsWith('jenkins')) return 'jenkins';
    if (name.startsWith('gradle')) return 'gradle';
    if (name.startsWith('.env')) return 'tune';
    if (_names[name] case final icon?) return icon;
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1);
    if (dot <= 0) {
      if (_names[ext] case final icon?) return icon;
    }
    return _icons[ext] ?? 'file';
  }

  /// Whole filenames that carry their type.
  static const _names = {
    'license': 'license', 'licence': 'license', 'copying': 'license',
    'notice': 'license', 'unlicense': 'unlicense',
    'changelog': 'changelog', 'history': 'changelog',
    'news': 'changelog', 'readme': 'readme',
    'authors': 'authors', 'contributing': 'contributing',
    'codeowners': 'codeowners', 'robots.txt': 'robots',
    'gemfile': 'gemfile', 'gemfile.lock': 'ruby',
    'rakefile': 'ruby', 'podfile': 'ruby', 'podfile.lock': 'ruby',
    'brewfile': 'ruby', 'vagrantfile': 'vagrant',
    'fastfile': 'fastlane', 'appfile': 'fastlane',
    'guardfile': 'ruby', 'capfile': 'ruby', 'thorfile': 'ruby',
    'meson.build': 'meson', 'sconstruct': 'scons',
    'sconscript': 'scons', 'wscript': 'scons',
    'build': 'bazel', 'build.bazel': 'bazel', 'workspace': 'bazel',
    'workspace.bazel': 'bazel', 'buck': 'buck',
    'go.mod': 'go-mod', 'go.sum': 'go-mod',
    'pubspec.yaml': 'dart', 'pubspec.lock': 'dart',
    'package-lock.json': 'npm', 'yarn.lock': 'yarn',
    'pnpm-lock.yaml': 'pnpm', 'bun.lockb': 'bun', 'bun.lock': 'bun',
    'deno.lock': 'deno', 'cargo.lock': 'rust', 'cargo.toml': 'rust',
    'poetry.lock': 'python', 'pyproject.toml': 'python',
    'composer.lock': 'php', 'composer.json': 'php',
    'tsconfig.json': 'tsconfig', 'jsconfig.json': 'jsconfig',
    'docker-compose.yml': 'docker', 'docker-compose.yaml': 'docker',
    'compose.yml': 'docker', 'compose.yaml': 'docker',
    'cmakelists.txt': 'cmake',
    'ssh_config': 'key', 'sshd_config': 'key',
    'vimrc': 'vim', 'gvimrc': 'vim',
    'zshrc': 'console', 'bashrc': 'console', 'bash_profile': 'console',
    'bash_login': 'console', 'profile': 'console', 'zprofile': 'console',
    'zshenv': 'console', 'zlogin': 'console', 'shrc': 'console',
    'kshrc': 'console', 'xinitrc': 'console', 'xsession': 'console',
    'bash_aliases': 'console', 'envrc': 'console',
    'gdbinit': 'console', 'lldbinit': 'console', 'inputrc': 'console',
    'gitconfig': 'git', 'gitattributes': 'git', 'gitmodules': 'git',
    'gitignore': 'git', 'gitignore_global': 'git',
    'dockerignore': 'docker', 'npmignore': 'npm',
    'prettierignore': 'prettier', 'eslintignore': 'eslint',
    'editorconfig': 'editorconfig',
    'condarc': 'yaml', 'clang-format': 'yaml', 'clang-tidy': 'yaml',
    'yamllint': 'yaml', 'folder': 'folder',
  };

  /// Extension → bundled icon name.
  static const _icons = {
    'dart': 'dart',
    'js': 'javascript', 'mjs': 'javascript', 'cjs': 'javascript',
    'jsx': 'react', 'ts': 'typescript', 'mts': 'typescript',
    'cts': 'typescript', 'tsx': 'react_ts',
    'sol': 'solidity',
    'html': 'html', 'htm': 'html', 'xhtml': 'html', 'shtml': 'html',
    'mdoc': 'html', 'jsp': 'html', 'asp': 'html', 'aspx': 'html',
    'css': 'css', 'wxss': 'css', 'pcss': 'css', 'postcss': 'postcss',
    'scss': 'sass', 'sass': 'sass', 'styl': 'stylus', 'less': 'less',
    'vue': 'vue', 'svelte': 'svelte', 'astro': 'astro',
    'jinja': 'jinja', 'jinja2': 'jinja', 'j2': 'jinja',
    'eta': 'html', 'njk': 'nunjucks', 'ejs': 'ejs', 'erb': 'ruby',
    'hbs': 'handlebars', 'handlebars': 'handlebars',
    'mustache': 'handlebars', 'twig': 'twig', 'liquid': 'liquid',
    'xml': 'xml', 'wxml': 'xml', 'xsd': 'xml', 'dtd': 'xml',
    'rss': 'xml', 'atom': 'xml', 'opml': 'xml', 'plist': 'xml',
    'resx': 'xml', 'iml': 'xml', 'pbxproj': 'xml', 'ui': 'xml',
    'storyboard': 'xml', 'xib': 'xml', 'entitlements': 'xml',
    'xaml': 'xaml', 'wsf': 'xml', 'svg': 'svg',
    'csproj': 'visualstudio', 'vbproj': 'visualstudio',
    'fsproj': 'visualstudio', 'vcxproj': 'visualstudio',
    'json': 'json', 'jsonc': 'json', 'json5': 'json', 'jsonl': 'json',
    'ndjson': 'json', 'hjson': 'hjson', 'jsonnet': 'json',
    'map': 'javascript-map', 'ipynb': 'jupyter', 'arb': 'i18n',
    'tfstate': 'terraform', 'mcmeta': 'minecraft', 'har': 'json',
    'geojson': 'json', 'jsonld': 'json', 'webmanifest': 'json',
    'babelrc': 'babel', 'eslintrc': 'eslint', 'prettierrc': 'prettier',
    'swcrc': 'swc', 'lintstagedrc': 'lintstaged', 'vuerc': 'vue-config',
    'jscsrc': 'json', 'jslintrc': 'json', 'jshintrc': 'json',
    'hintrc': 'webhint', 'bowerrc': 'bower', 'tsbuildinfo': 'tsconfig',
    'yaml': 'yaml', 'yml': 'yaml', 'eyaml': 'yaml', 'eyml': 'yaml',
    'cff': 'yaml', 'lock': 'lock',
    'toml': 'toml', 'env': 'tune', 'cfg': 'settings', 'conf': 'settings',
    'properties': 'settings', 'ini': 'settings',
    'editorconfig': 'editorconfig',
    'reg': 'regedit', 'url': 'url', 'desktop': 'settings',
    'service': 'systemd', 'socket': 'systemd', 'timer': 'systemd',
    'path': 'systemd', 'mount': 'systemd', 'automount': 'systemd',
    'slice': 'systemd', 'scope': 'systemd', 'device': 'systemd',
    'htaccess': 'settings', 'npmrc': 'npm', 'yarnrc': 'yarn',
    'gitmodules': 'git', 'xcconfig': 'settings',
    'gitignore': 'git', 'dockerignore': 'docker', 'npmignore': 'npm',
    'prettierignore': 'prettier', 'eslintignore': 'eslint',
    'nomad': 'hcl', 'cue': 'cue', 'tf': 'hcl', 'tfvars': 'hcl',
    'hcl': 'hcl', 'bicep': 'bicep',
    'py': 'python', 'pyw': 'python', 'pyi': 'python', 'pyx': 'python',
    'vpy': 'python', 'nim': 'nim', 'star': 'bazel', 'bzl': 'bazel',
    'starlark': 'bazel', 'gyp': 'python', 'gypi': 'python',
    'java': 'java', 'jav': 'java', 'kt': 'kotlin', 'kts': 'kotlin',
    'scala': 'scala', 'sc': 'scala', 'sbt': 'sbt',
    'gradle': 'gradle', 'gvy': 'groovy', 'groovy': 'groovy',
    'nf': 'nextflow',
    'go': 'go', 'rs': 'rust', 'rlib': 'rust', 'move': 'rust',
    'cairo': 'cairo',
    'c': 'c', 'h': 'h', 'i': 'c',
    'cpp': 'cpp', 'cc': 'cpp', 'cxx': 'cpp', 'cppm': 'cpp',
    'hpp': 'hpp', 'hh': 'hpp', 'hxx': 'hpp', 'inl': 'hpp',
    'cu': 'cuda', 'cuh': 'cuda', 'ino': 'arduino', 'metal': 'cpp',
    'd': 'd', 'di': 'd',
    'glsl': 'shader', 'vert': 'shader', 'frag': 'shader',
    'geom': 'shader', 'comp': 'shader', 'cg': 'shader',
    'cginc': 'shader', 'shader': 'shader', 'fx': 'shader',
    'fxh': 'shader', 'hlsl': 'shader', 'hlsli': 'shader',
    'compute': 'shader', 'vsh': 'shader', 'psh': 'shader',
    'wgsl': 'shader',
    'cs': 'csharp', 'csx': 'csharp', 'cake': 'cake',
    'vala': 'vala', 'pas': 'pascal', 'p': 'pascal', 'pp': 'pascal',
    'fs': 'fsharp', 'fsi': 'fsharp', 'fsx': 'fsharp',
    'fsscript': 'fsharp',
    'hs': 'haskell', 'elm': 'elm', 'ml': 'ocaml', 'mli': 'ocaml',
    'rb': 'ruby', 'rbx': 'ruby', 'rjs': 'ruby', 'gemspec': 'ruby',
    'rake': 'ruby', 'ru': 'ruby', 'podspec': 'ruby', 'rbi': 'ruby',
    'cr': 'crystal',
    'php': 'php', 'php4': 'php', 'php5': 'php', 'phtml': 'php',
    'ctp': 'php', 'hack': 'hack',
    'lua': 'lua', 'luau': 'luau', 'fnl': 'lua', 'wlua': 'lua',
    'swift': 'swift', 'm': 'objective-c', 'mm': 'objective-cpp',
    'r': 'r', 'rhistory': 'r', 'rprofile': 'r', 'rt': 'r', 'rmd': 'r',
    'jl': 'julia', 'jmd': 'julia',
    'ex': 'elixir', 'exs': 'elixir', 'erl': 'erlang', 'hrl': 'erlang',
    'pl': 'perl', 'pm': 'perl', 'pod': 'perl', 't': 'perl',
    'awk': 'console', 'tcl': 'tcl',
    'clj': 'clojure', 'cljs': 'clojure', 'cljc': 'clojure',
    'edn': 'clojure', 'cljx': 'clojure',
    'scm': 'scheme', 'ss': 'scheme', 'lisp': 'lisp', 'lsp': 'lisp',
    'el': 'lisp', 'sld': 'scheme', 'rkt': 'racket',
    'coffee': 'coffee', 'asm': 'assembly', 's': 'assembly',
    'proto': 'proto', 'thrift': 'proto', 'capnp': 'capnp',
    'graphql': 'graphql', 'gql': 'graphql',
    'nix': 'nix', 'zig': 'zig', 'v': 'verilog', 'vh': 'verilog',
    'sv': 'verilog', 'svh': 'verilog', 'vlang': 'vlang',
    'sh': 'console', 'bash': 'console', 'zsh': 'console',
    'fish': 'console', 'csh': 'console', 'ksh': 'console',
    'ash': 'console', 'envrc': 'console', 'shrc': 'console',
    'kshrc': 'console', 'xinitrc': 'console',
    'ps1': 'powershell', 'psm1': 'powershell', 'psd1': 'powershell',
    'ps1xml': 'powershell',
    'bat': 'command', 'cmd': 'command', 'btm': 'command',
    'mk': 'makefile', 'mak': 'makefile', 'am': 'makefile',
    'cmake': 'cmake',
    'sql': 'database', 'psql': 'database', 'pgsql': 'database',
    'plsql': 'database', 'mysql': 'database', 'hql': 'database',
    'db': 'database', 'sqlite': 'database', 'sqlite3': 'database',
    'md': 'markdown', 'markdown': 'markdown', 'mkd': 'markdown',
    'mdown': 'markdown', 'mdx': 'mdx', 'adoc': 'asciidoc',
    'asciidoc': 'asciidoc', 'org': 'markdown', 'wiki': 'markdown',
    'rst': 'markdown',
    'tex': 'tex', 'sty': 'tex', 'cls': 'tex', 'bib': 'bibliography',
    'diff': 'diff', 'patch': 'diff', 'rej': 'diff',
    'png': 'image', 'jpg': 'image', 'jpeg': 'image', 'gif': 'image',
    'webp': 'image', 'bmp': 'image', 'ico': 'image', 'heic': 'image',
    'heif': 'image', 'avif': 'image', 'tiff': 'image', 'tif': 'image',
    'mp4': 'video', 'mov': 'video', 'mkv': 'video', 'avi': 'video',
    'webm': 'video', 'flv': 'video', 'wmv': 'video', 'm4v': 'video',
    'mp3': 'audio', 'wav': 'audio', 'ogg': 'audio', 'flac': 'audio',
    'm4a': 'audio', 'aac': 'audio', 'opus': 'audio',
    'zip': 'zip', 'tar': 'zip', 'gz': 'zip', 'tgz': 'zip',
    'bz2': 'zip', 'xz': 'zip', 'rar': 'zip', '7z': 'zip',
    'jar': 'jar', 'war': 'jar', 'aar': 'jar',
    'pdf': 'pdf',
    'doc': 'word', 'docx': 'word', 'pages': 'word', 'rtf': 'word',
    'odt': 'word',
    'xls': 'table', 'xlsx': 'table', 'numbers': 'table',
    'ods': 'table', 'csv': 'table', 'tsv': 'table',
    'ppt': 'powerpoint', 'pptx': 'powerpoint', 'odp': 'powerpoint',
    'exe': 'exe', 'msi': 'exe', 'dmg': 'exe', 'pkg': 'exe',
    'app': 'exe', 'bin': 'exe', 'deb': 'exe', 'rpm': 'exe',
    'ipa': 'exe', 'apk': 'android', 'aab': 'android',
    'so': 'dll', 'dll': 'dll', 'dylib': 'dll', 'wasm': 'webassembly',
    'ttf': 'font', 'otf': 'font', 'woff': 'font', 'woff2': 'font',
    'eot': 'font',
    'key': 'key', 'pem': 'key', 'p12': 'key', 'pfx': 'key',
    'pub': 'key', 'asc': 'key', 'gpg': 'key',
    'crt': 'certificate', 'cer': 'certificate', 'der': 'certificate',
    'sig': 'certificate',
    'sketch': 'sketch', 'fig': 'figma', 'xd': 'palette',
    'psd': 'adobe-photoshop', 'ai': 'adobe-illustrator',
    'log': 'log', 'txt': 'document', 'out': 'document',
  };
}

/// A loading placeholder: grey rounded bars where messages will be, one
/// breathing softly, until the conversation's items arrive.
class BSkeletonLines extends StatefulWidget {
  const BSkeletonLines({super.key, this.lines = 4});

  final int lines;

  @override
  State<BSkeletonLines> createState() => _BSkeletonLinesState();
}

class _BSkeletonLinesState extends State<BSkeletonLines>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  // Widths cycling through 40%..80% so the bars read as bubbles of
  // different lengths, alternating the side they start from.
  static const _widths = [0.62, 0.4, 0.78, 0.5, 0.68, 0.45];

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _breath, curve: Curves.easeInOut),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < widget.lines; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: i.isEven
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: i.isEven
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: FractionallySizedBox(
                          widthFactor: _widths[i % _widths.length],
                          child: Container(
                            height: 15,
                            decoration: BoxDecoration(
                              color: AppColors.bubbleFill,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A scroll controller that pins its list to the end while [anchored], as
/// the desktop's does: the correction happens inside layout, so content
/// growing while streaming never shows a frame off the bottom — no
/// post-frame jump that lands short of the real extent. Scrolling up by
/// hand lets go of the anchor; landing at the very bottom re-engages it.
class BottomAnchoredScrollController extends ScrollController {
  bool anchored = true;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) =>
      _BottomAnchoredScrollPosition(
    controller: this,
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _BottomAnchoredScrollPosition extends ScrollPositionWithSingleContext {
  _BottomAnchoredScrollPosition({
    required this.controller,
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  final BottomAnchoredScrollController controller;

  @override
  void jumpTo(double value) {
    if (hasContentDimensions) {
      controller.anchored = value >= maxScrollExtent - 1;
    }
    super.jumpTo(value);
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final accepted = super.applyContentDimensions(
      minScrollExtent,
      maxScrollExtent,
    );
    if (controller.anchored &&
        hasPixels &&
        pixels != maxScrollExtent &&
        activity is! DragScrollActivity) {
      // Re-run layout at the new offset: a jump scheduled after the frame
      // would read the extent before the growth, landing above the end.
      correctPixels(maxScrollExtent);
      return false;
    }
    return accepted;
  }
}
