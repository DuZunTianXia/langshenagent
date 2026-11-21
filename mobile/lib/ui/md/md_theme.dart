import 'package:flutter/material.dart';

/// The colors and fonts LangshenAgent's chat draws markdown with, as the desktop's
/// `AppColors`/`AppFonts` give them from its theme — as it looks in the
/// default dark theme, a light set beside it (the phone has no themes).
abstract final class MdTheme {
  static bool dark = true;
}

/// VS Code Dark Modern's, beside Light Modern's where they differ.
abstract final class AppColors {
  // `sideBar.background` / `editorWidget.background` / `menu.background`.
  static Color get background =>
      MdTheme.dark ? const Color(0xFF1F1F1F) : const Color(0xFFF7F7F7);
  static Color get surface =>
      MdTheme.dark ? const Color(0xFF2D2D30) : const Color(0xFFE8E8E8);
  static Color get surfaceRaised =>
      MdTheme.dark ? const Color(0xFF3E3E42) : const Color(0xFFFFFFFF);

  /// `editor.background`: the conversation's surface, code blocks'.
  static Color get conversationSurface =>
      MdTheme.dark ? const Color(0xFF1F1F1F) : const Color(0xFFFFFFFF);
  static Color get code => conversationSurface;

  /// A bubble's fill: `agentsChatInput.background` over [code] — Dark
  /// Modern's is a light wash, Light's a dark one.
  static Color get bubbleFill =>
      MdTheme.dark ? const Color(0xFF2B2B2E) : const Color(0xFFECECF0);

  static Color get partBorder =>
      MdTheme.dark ? const Color(0xFF2B2B2B) : const Color(0xFFD4D4D4);
  static Color get border =>
      MdTheme.dark ? const Color(0xFF2B2B2B) : const Color(0xFFD4D4D4);
  static Color get borderStrong =>
      MdTheme.dark ? const Color(0xFF3C3C3C) : const Color(0xFFCECECE);

  static Color get textPrimary =>
      MdTheme.dark ? const Color(0xFFFFFFFF) : const Color(0xFF1F1F1F);
  static Color get text =>
      MdTheme.dark ? const Color(0xFFCCCCCC) : const Color(0xFF424242);
  static Color get textMuted =>
      MdTheme.dark ? const Color(0xFF9D9D9D) : const Color(0xFF6F6F6F);
  static Color get textFaint =>
      MdTheme.dark ? const Color(0xFF656565) : const Color(0xFF9E9E9E);

  /// The phone's own accent (the official app's green), where the desktop
  /// asks for `textLink.foreground`.
  static Color get accent =>
      MdTheme.dark ? const Color(0xFF2AAE67) : const Color(0xFF07C160);

  /// The user's own message bubble, as the official phone app's.
  static Color get userBubble =>
      MdTheme.dark ? const Color(0xFF1E4D33) : const Color(0xFF95EC69);

  /// Text on [userBubble]: near-black on the light green, near-white on
  /// the dark one.
  static Color get onUserBubble =>
      MdTheme.dark ? const Color(0xFFE8F5EE) : const Color(0xFF1A1A1A);

  static const claude = Color(0xFFD97857);

  /// `textPreformat.*`.
  static Color get inlineCode =>
      MdTheme.dark ? const Color(0xFFD7BA7D) : const Color(0xFF800000);
  static Color get inlineCodeBackground =>
      MdTheme.dark ? const Color(0x14FFFFFF) : const Color(0x1A000000);

  /// `gitDecoration.*` — diff greens and reds.
  static Color get added =>
      MdTheme.dark ? const Color(0xFF81B88B) : const Color(0xFF116329);
  static Color get addedBackground =>
      MdTheme.dark ? const Color(0x1F2EA043) : const Color(0x402EA043);
  static Color get removed =>
      MdTheme.dark ? const Color(0xFFC74E39) : const Color(0xFF82071E);
  static Color get removedBackground =>
      MdTheme.dark ? const Color(0x26F85149) : const Color(0x40F85149);

  /// `editorWarning.foreground`.
  static Color get caution =>
      MdTheme.dark ? const Color(0xFFFFA14D) : const Color(0xFFBF8803);

  /// `list.hoverBackground`.
  static Color get hover =>
      MdTheme.dark ? const Color(0xFF2A2D2E) : const Color(0xFFE8E8E8);

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
