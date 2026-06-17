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
    Color color = AppColors.ink,
    double? height,
    double? letterSpacing,
  }) =>
      GoogleFonts.baloo2(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  /// Quicksand — body, inputs, descriptions.
  static TextStyle quick({
    double size = 16,
    FontWeight weight = FontWeight.w600,
    Color color = AppColors.ink,
    double? height,
  }) =>
      GoogleFonts.quicksand(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
      );

  static ThemeData themeData() {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.violet,
        primary: AppColors.coral,
        surface: AppColors.white,
      ),
      textTheme: GoogleFonts.quicksandTextTheme(),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
  }
}
