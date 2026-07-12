import 'package:flutter/material.dart';

/// Paleta e tema do VEICAN (escuro, estilo painel automotivo).
class VColors {
  static const bg = Color(0xFF05070D);
  static const card = Color(0xFF0E1622);
  static const cardHi = Color(0xFF16202F);
  static const line = Color(0xFF1E2A3A);
  static const cyan = Color(0xFF00E5FF);
  static const blue = Color(0xFF00B0FF);
  static const green = Color(0xFF4CAF50);
  static const amber = Color(0xFFFFC107);
  static const red = Color(0xFFFF1744);
  static const orange = Color(0xFFFF9800);
  static const textHi = Color(0xFFECEFF1);
  static const textDim = Color(0xFF90A4AE);
  static const textFaint = Color(0xFF5A6B7A);
}

ThemeData veicanTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: VColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: VColors.cyan,
      secondary: VColors.blue,
      surface: VColors.card,
      error: VColors.red,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: VColors.bg,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: VColors.textHi,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      ),
    ),
    cardTheme: CardThemeData(
      color: VColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: VColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: VColors.cyan,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
  );
}
