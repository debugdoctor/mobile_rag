import 'package:flutter/material.dart';

class AppColors {
  static const light = _Palette(
    text: Color(0xFF11181C),
    background: Color(0xFFFFFFFF),
    tint: Color(0xFF0A7EA4),
    icon: Color(0xFF687076),
    tabIconDefault: Color(0xFF687076),
    tabIconSelected: Color(0xFF0A7EA4),
    card: Color(0xFFF2F4F7),
    surface: Color(0xFFFFFFFF),
    muted: Color(0xFF667085),
    border: Color(0xFFE4E7EC),
    warning: Color(0xFFF79009),
    success: Color(0xFF16A34A),
  );

  static const dark = _Palette(
    text: Color(0xFFECEDEE),
    background: Color(0xFF151718),
    tint: Color(0xFFFFFFFF),
    icon: Color(0xFF9BA1A6),
    tabIconDefault: Color(0xFF9BA1A6),
    tabIconSelected: Color(0xFFFFFFFF),
    card: Color(0xFF1F2227),
    surface: Color(0xFF1C1F24),
    muted: Color(0xFF98A2B3),
    border: Color(0xFF2C2F36),
    warning: Color(0xFFFDB022),
    success: Color(0xFF22C55E),
  );
}

class AppTheme {
  static ThemeData light() => _buildTheme(AppColors.light, Brightness.light);

  static ThemeData dark() => _buildTheme(AppColors.dark, Brightness.dark);

  static ThemeData _buildTheme(_Palette palette, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: palette.tint,
      brightness: brightness,
      surface: palette.surface,
      onSurface: palette.text,
    );

    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      cardColor: palette.card,
      dividerColor: palette.border,
      textTheme: Typography.blackMountainView.apply(
        bodyColor: palette.text,
        displayColor: palette.text,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        foregroundColor: palette.text,
        elevation: 0,
        iconTheme: IconThemeData(color: palette.text),
      ),
      iconTheme: IconThemeData(color: palette.icon),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.tint, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.card,
        labelStyle: TextStyle(color: palette.text),
        shape: StadiumBorder(side: BorderSide(color: palette.border)),
      ),
    );
  }
}

class _Palette {
  const _Palette({
    required this.text,
    required this.background,
    required this.tint,
    required this.icon,
    required this.tabIconDefault,
    required this.tabIconSelected,
    required this.card,
    required this.surface,
    required this.muted,
    required this.border,
    required this.warning,
    required this.success,
  });

  final Color text;
  final Color background;
  final Color tint;
  final Color icon;
  final Color tabIconDefault;
  final Color tabIconSelected;
  final Color card;
  final Color surface;
  final Color muted;
  final Color border;
  final Color warning;
  final Color success;
}
