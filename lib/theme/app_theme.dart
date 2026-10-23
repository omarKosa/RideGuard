import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppColors {
  static const background = Color(0xFF0A0E21);
  static const backgroundMid = Color(0xFF1A1A2E);
  static const backgroundEnd = Color(0xFF16213E);
  static const surface = Color(0xFF1D1E33);
  static const red = Color(0xFFFF4B4B);
  static const redDeep = Color(0xFFFF2E2E);
  static const cyan = Color(0xFF00D9FF);
  static const amber = Color(0xFFFFAB00);
  static const green = Color(0xFF2ED47A);
  static const textMuted = Colors.white54;
  static const textFaint = Colors.white38;
  static const border = Colors.white10;
}

abstract final class AppText {
  static TextStyle display(double size, {Color color = Colors.white}) =>
      GoogleFonts.orbitron(
        fontSize: size,
        fontWeight: FontWeight.bold,
        color: color,
      );

  static TextStyle body(
    double size, {
    Color color = Colors.white,
    FontWeight weight = FontWeight.w500,
  }) => GoogleFonts.rajdhani(fontSize: size, color: color, fontWeight: weight);

  static TextStyle label(double size, {Color color = AppColors.textMuted}) =>
      GoogleFonts.rajdhani(
        fontSize: size,
        color: color,
        fontWeight: FontWeight.bold,
        letterSpacing: 2,
      );
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.red,
      secondary: AppColors.cyan,
      surface: AppColors.surface,
      error: AppColors.red,
    ),
  );
  return base.copyWith(
    // google_fonts' *TextTheme helpers target the decoupled material_ui
    // package; applying the family keeps us on flutter/material types.
    textTheme: base.textTheme.apply(
      fontFamily: GoogleFonts.rajdhani().fontFamily,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: AppText.display(16),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      labelStyle: AppText.body(16, color: AppColors.textMuted),
      helperStyle: AppText.body(13, color: AppColors.textFaint),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.cyan),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      contentTextStyle: AppText.body(14, weight: FontWeight.w600),
    ),
  );
}
