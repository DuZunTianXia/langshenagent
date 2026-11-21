import 'package:flutter/material.dart';

import '../md/md_theme.dart';
import 'hover_builder.dart';

/// A small pill button, as the desktop's `PanelButton`: [primary] in the
/// accent, else the surface's.
class PanelButton extends StatelessWidget {
  const PanelButton({
    super.key,
    required this.label,
    this.onTap,
    this.primary = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  /// Its hover, e.g. [label] with the keys that do the same; none when null.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = _buildButton();
    return switch (tooltip) {
      final tooltip? => Tooltip(message: tooltip, child: button),
      null => button,
    };
  }

  Widget _buildButton() {
    final enabled = onTap != null;
    return HoverBuilder(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      builder: (context, hovered) => Opacity(
        opacity: enabled ? 1 : 0.4,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primary
                  ? (hovered && enabled
                        ? Color.lerp(AppColors.accent, Colors.white, 0.15)
                        : AppColors.accent)
                  : (hovered && enabled
                        ? AppColors.hover
                        : AppColors.surfaceRaised),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: primary ? Colors.white : AppColors.text,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
