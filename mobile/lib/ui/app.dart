import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import 'home_page.dart';
import 'md/md_theme.dart';

/// The app's theme, with refined obsidian-dark and airy-light palettes.
class BaoApp extends StatelessWidget {
  const BaoApp({super.key});

  static ThemeData _theme({required bool dark}) {
    // AppColors reads MdTheme.dark live; pin it to this theme's own
    // brightness while its colors are frozen into the ThemeData.
    MdTheme.dark = dark;
    final scheme = ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: AppColors.accent,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: Colors.white,
      error: AppColors.removed,
      onError: Colors.white,
      surface: AppColors.background,
      onSurface: AppColors.text,
      surfaceContainerHighest: AppColors.surfaceRaised,
      onSurfaceVariant: AppColors.textMuted,
      outline: AppColors.partBorder,
      outlineVariant: AppColors.border,
      surfaceContainer: AppColors.surface,
      inverseSurface: AppColors.text,
      onInverseSurface: AppColors.background,
      inversePrimary: AppColors.accent,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
      highlightColor: AppColors.accent.withValues(alpha: dark ? 0.08 : 0.06),
      splashColor: AppColors.accent.withValues(alpha: dark ? 0.10 : 0.08),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: AppColors.surfaceRaised,
                systemNavigationBarIconBrightness: Brightness.light,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: AppColors.surfaceRaised,
                systemNavigationBarIconBrightness: Brightness.dark,
              ),
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: AppColors.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceRaised,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.partBorder, width: 0.75),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surfaceRaised,
        dragHandleColor: AppColors.borderStrong,
        dragHandleSize: const Size(38, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.partBorder,
        thickness: 0.5,
      ),
      textTheme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
      ).textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bubbleFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.partBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.partBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.accent, width: 1.4),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceRaised,
        contentTextStyle: TextStyle(color: AppColors.text),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textMuted,
        indicatorColor: AppColors.accent,
        dividerColor: AppColors.partBorder,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: TextStyle(color: AppColors.text),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.textMuted,
        textColor: AppColors.text,
        subtitleTextStyle: TextStyle(color: AppColors.textMuted),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final systemDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final effectiveDark = switch (state.themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => systemDark,
    };
    // The colors the themes below freeze at their build read this; it must
    // be the active brightness here already — waiting for HomePage's
    // build leaves the first frame's frozen theme colors on the wrong side.
    MdTheme.dark = effectiveDark;
    final light = _theme(dark: false);
    final dark = _theme(dark: true);
    // _theme leaves MdTheme.dark on its own brightness; restore the active one
    // for the widgets below that read AppColors live.
    MdTheme.dark = effectiveDark;
    return MaterialApp(
      title: '宝码',
      debugShowCheckedModeBanner: false,
      themeMode: state.themeMode,
      theme: light,
      darkTheme: dark,
      home: state.ready ? const HomePage() : const _BootSplash(),
    );
  }
}

class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final systemDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    MdTheme.dark = switch (state.themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => systemDark,
    };
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/branding/app_icon.png',
                width: 80,
                height: 80,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
