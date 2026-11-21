import 'package:bao_link/bao_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

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
    final border = (Color color, double width) => OutlineInputBorder(
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
    ),
    padding: padding ?? const EdgeInsets.all(14),
    child: child,
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
          if (trailing != null) trailing!,
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
  Widget? Function(String id)? iconOf,
  String Function(String label)? labelOf,
}) => showModalBottomSheet<LinkOption>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => _ChoiceSheet(
    title: title,
    options: options,
    selected: selected,
    iconOf: iconOf,
    labelOf: labelOf,
  ),
);

class _ChoiceSheet extends StatefulWidget {
  const _ChoiceSheet({
    required this.title,
    required this.options,
    this.selected,
    this.iconOf,
    this.labelOf,
  });

  final String title;
  final List<LinkOption> options;
  final String? selected;
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
    if (!_grouped) _group = '';
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
            if (icon != null) ...[icon, const SizedBox(width: 10)],
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
