import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Tipografia: Archivo. Titulos peso 800 com stretch expandido, corpo 400/600.
class AppTextStyles {
  AppTextStyles._();

  static TextStyle _archivo({
    required double size,
    required FontWeight weight,
    Color color = AppColors.textPrimary,
    double? letterSpacing,
  }) {
    return GoogleFonts.archivo(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      fontVariations: const [FontVariation('wdth', 115)],
    );
  }

  static TextStyle h1 = _archivo(size: 28, weight: FontWeight.w800, letterSpacing: 0.2);
  static TextStyle h2 = _archivo(size: 22, weight: FontWeight.w800, letterSpacing: 0.2);
  static TextStyle h3 = _archivo(size: 18, weight: FontWeight.w800, letterSpacing: 0.1);

  static TextStyle bodyBold = GoogleFonts.archivo(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle body = GoogleFonts.archivo(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static TextStyle bodySecondary = GoogleFonts.archivo(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static TextStyle caption = GoogleFonts.archivo(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );

  static TextStyle button = GoogleFonts.archivo(
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );
}
