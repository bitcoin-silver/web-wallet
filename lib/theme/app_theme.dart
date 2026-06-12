import 'package:flutter/material.dart';

class AppTheme {
  static const primaryColor = Color(0xFFCED4DA);
  static const secondaryColor = Color(0xFF9EA7B3);
  static const backgroundColor = Color(0xFF0D1014);
  static const surfaceColor = Color(0xFF1D2228);
  static const accentColor = Color(0xFFE1E6EA);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: surfaceColor,
        onPrimary: backgroundColor,   // dark text ON light primary
        onSecondary: backgroundColor,
        onSurface: Colors.white,
        //onBackground: Colors.white, // default is white, so we can omit it, deprecated in favor of scaffoldBackgroundColor
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: primaryColor.withValues(alpha: 0.1), width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: backgroundColor, // dark text ON light button
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.2),
        labelStyle: const TextStyle(color: secondaryColor),
        hintStyle: TextStyle(color: primaryColor.withValues(alpha: 0.5)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
      ),
    );
  }
}