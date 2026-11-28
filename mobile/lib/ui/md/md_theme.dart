import 'package:flutter/material.dart';

/// The colors and fonts LangshenAgent's chat draws markdown with, as the desktop's
/// `AppColors`/`AppFonts` give them from its theme — as it looks in the
/// default dark theme, a light set beside it (the phone has no themes).
abstract final class MdTheme {
  static bool dark = true;
}

/// Refined obsidian-dark and airy-light color tokens for the mobile app.
abstract final class AppColors {
  static Color get background =>
      MdTheme.dark ? const Color(0xFF0D0E11) : const Color(0xFFF4F6F9);
  static Color get surface =>
      MdTheme.dark ? const Color(0xFF171920) : const Color(0xFFEBEFF5);
  static Color get surfaceRaised =>
      MdTheme.dark ? const Color(0xFF1A1C23) : const Color(0xFFFFFFFF);

  /// The conversation's surface and code blocks.
  static Color get conversationSurface =>
      MdTheme.dark ? const Color(0xFF101216) : const Color(0xFFFFFFFF);
  static Color get code => conversationSurface;

  /// Soft elevated fill for inputs, pills, and secondary containers.
  static Color get bubbleFill =>
      MdTheme.dark ? const Color(0xFF20232C) : const Color(0xFFF0F2F6);

  static Color get partBorder =>
      MdTheme.dark ? const Color(0xFF272B36) : const Color(0xFFE3E7EE);
  static Color get border =>
      MdTheme.dark ? const Color(0xFF272B36) : const Color(0xFFE3E7EE);
  static Color get borderStrong =>
      MdTheme.dark ? const Color(0xFF383E4D) : const Color(0xFFD0D7E2);

  static Color get textPrimary =>
      MdTheme.dark ? const Color(0xFFF3F5F8) : const Color(0xFF111418);
  static Color get text =>
      MdTheme.dark ? const Color(0xFFD1D5DE) : const Color(0xFF2E3440);
  static Color get textMuted =>
      MdTheme.dark ? const Color(0xFF8C93A4) : const Color(0xFF646E7E);
  static Color get textFaint =>
      MdTheme.dark ? const Color(0xFF5A6070) : const Color(0xFF98A2B3);

  /// Refined emerald accent.
  static Color get accent =>
      MdTheme.dark ? const Color(0xFF10B981) : const Color(0xFF059669);

  /// User's own message bubble in bubble mode: rich emerald tint.
  static Color get userBubble =>
      MdTheme.dark ? const Color(0xFF144535) : const Color(0xFFD1FAE5);

  /// Text on [userBubble].
  static Color get onUserBubble =>
      MdTheme.dark ? const Color(0xFFECFDF5) : const Color(0xFF064E3B);

  static const claude = Color(0xFFD97857);

  /// `textPreformat.*`.
  static Color get inlineCode =>
      MdTheme.dark ? const Color(0xFFE2C08D) : const Color(0xFF9A3412);
  static Color get inlineCodeBackground =>
      MdTheme.dark ? const Color(0x18FFFFFF) : const Color(0x10000000);

  /// `gitDecoration.*` — diff greens and reds.
  static Color get added =>
      MdTheme.dark ? const Color(0xFF34D399) : const Color(0xFF15803D);
  static Color get addedBackground =>
      MdTheme.dark ? const Color(0x1F10B981) : const Color(0x2822C55E);
  static Color get removed =>
      MdTheme.dark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
  static Color get removedBackground =>
      MdTheme.dark ? const Color(0x24EF4444) : const Color(0x24EF4444);

  /// `editorWarning.foreground`.
  static Color get caution =>
      MdTheme.dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);

  /// `list.hoverBackground`.
  static Color get hover =>
      MdTheme.dark ? const Color(0xFF232732) : const Color(0xFFE8ECF2);

  /// The chat's message bubbles and its input: their line a step towards
  /// the text's color from [bubbleFill], tinged with [accent]; the input's
  /// when typed into ([focused]), a step on towards [accent].
  static Color bubbleBorder({bool focused = false}) {
    final line = Color.lerp(
      Color.lerp(bubbleFill, text, 0.12),
      accent.withValues(alpha: 1),
      0.03,
    )!;
    return focused ? Color.lerp(line, accent.withValues(alpha: 1), 0.2)! : line;
  }

  /// A shell command's colors (the terminal's ANSI yellow, magenta and
  /// cyan), as `AppColors.syntaxCommand` &co. give them on the desktop.
  static Color get syntaxCommand =>
      MdTheme.dark ? const Color(0xFFE5E510) : const Color(0xFFBF8803);
  static Color get syntaxString =>
      MdTheme.dark ? const Color(0xFFBC3FBC) : const Color(0xFFC235C2);
  static Color get syntaxOption =>
      MdTheme.dark ? const Color(0xFF11A8CD) : const Color(0xFF0E7C9C);
}

abstract final class AppFonts {
  /// The monospace the platform has (the desktop lets the user choose).
  static TextStyle uiCodeStyle(double size) => TextStyle(
    fontFamily: 'monospace',
    fontSize: size,
  );

  static TextStyle codeStyle(double size) => uiCodeStyle(size);

  /// As the desktop's `AppFonts.mono`: the family code styles use.
  static String get mono => 'monospace';

  /// What code falls back on after [mono]; the platform's own here.
  static List<String> get monoFallbacks => const [];
}

/// The VS Code color keys the markdown widgets ask for ([themeColors] on
/// the desktop), for what the phone draws.
Color _themeColor(String id) => switch (id) {
  'textSeparator.foreground' => AppColors.textFaint,
  'chat.requestBorder' => AppColors.partBorder,
  'textCodeBlock.background' => MdTheme.dark
      ? const Color(0xFF0D0D0D)
      : const Color(0xFFF0F0F0),
  // VS Code's chrome keys the ported item widgets ask for (Dark Modern's,
  // beside Light Modern's where they differ).
  'focusBorder' =>
    MdTheme.dark ? const Color(0xFF007FD4) : const Color(0xFF0090F1),
  'testing.iconPassed' => AppColors.added,
  'testing.iconFailed' => AppColors.removed,
  'errorForeground' =>
    MdTheme.dark ? const Color(0xFFF48771) : const Color(0xFFE51400),
  'notificationsWarningIcon.foreground' => MdTheme.dark
      ? const Color(0xFFCCA700)
      : const Color(0xFFBF8803),
  'symbolIcon.eventForeground' => MdTheme.dark
      ? const Color(0xFFD9A343)
      : const Color(0xFFB07C24),
  'charts.green' =>
    MdTheme.dark ? const Color(0xFF89D185) : const Color(0xFF388A34),
  'charts.blue' =>
    MdTheme.dark ? const Color(0xFF3794FF) : const Color(0xFF1B81CB),
  'chat.linesAddedForeground' => AppColors.added,
  'chat.linesRemovedForeground' => AppColors.removed,
  'chat.thinkingShimmer' => MdTheme.dark
      ? const Color(0xCCFFFFFF)
      : const Color(0xCC000000),
  'scrollbarSlider.background' => MdTheme.dark
      ? const Color(0x66797979)
      : const Color(0x66646464),
  'scrollbarSlider.hoverBackground' => MdTheme.dark
      ? const Color(0xB3646464)
      : const Color(0xA6646464),
  'scrollbarSlider.activeBackground' => MdTheme.dark
      ? const Color(0x66BFBFBF)
      : const Color(0x66000000),
  _ => AppColors.partBorder,
};

/// Called as `themeColors['id']` in the ported widgets.
const MdThemeColors themeColors = MdThemeColors();

class MdThemeColors {
  const MdThemeColors();

  Color operator [](String id) => _themeColor(id);
}
