import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Springy bounce curve matching the prototype's
/// cubic-bezier(0.34, 1.56, 0.64, 1) `--ease-bounce`.
const Cubic kEaseBounce = Cubic(0.34, 1.56, 0.64, 1);

/// `--ease-smooth` cubic-bezier(0.25, 0.46, 0.45, 0.94).
const Cubic kEaseSmooth = Cubic(0.25, 0.46, 0.45, 0.94);

class AppTheme {
  AppTheme._();

  /// Baloo 2 — headings, headwords, numbers, buttons.
  static TextStyle baloo({
    double size = 16,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double? height,
    double? letterSpacing,
  }) =>
      GoogleFonts.baloo2(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.ink,
        height: height,
        letterSpacing: letterSpacing,
      );

  /// Quicksand — body, inputs, descriptions.
  static TextStyle quick({
    double size = 16,
    FontWeight weight = FontWeight.w600,
    Color? color,
    double? height,
  }) =>
      GoogleFonts.quicksand(
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.ink,
        height: height,
      );

  static ThemeData themeData() {
    final brightness = AppColors.dark ? Brightness.dark : Brightness.light;
    // Base the text theme on the right brightness so framework-default-styled
    // text (dialog titles, snackbars, hints) is light-on-dark in dark mode.
    final base = ThemeData(brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.violet,
        primary: AppColors.coral,
        surface: AppColors.white,
        brightness: brightness,
      ),
      textTheme: GoogleFonts.quicksandTextTheme(base.textTheme),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
  }
}
