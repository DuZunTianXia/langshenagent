import 'package:flutter/material.dart';

import '../main.dart';
import 'home_page.dart';
import 'md/md_theme.dart';

/// The app's theme, in LangshenAgent's colors (the desktop's `AppColors`, as the
/// default VS Code themes have them).
class BaoApp extends StatelessWidget {
  const BaoApp({super.key});

  static ThemeData _theme({required bool dark}) {
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
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.bubbleFill,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: AppColors.partBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surfaceRaised,
      ),
      dividerTheme: DividerThemeData(color: AppColors.partBorder, thickness: 1),
      textTheme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
      ).textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bubbleFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.partBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.partBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.accent),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
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
        textStyle: TextStyle(color: AppColors.text),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
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
    return MaterialApp(
      title: '宝码',
      debugShowCheckedModeBanner: false,
      theme: _theme(dark: false),
      darkTheme: _theme(dark: true),
      home: state.ready
          ? const HomePage()
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}
