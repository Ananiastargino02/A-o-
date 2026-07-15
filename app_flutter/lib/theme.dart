import 'package:flutter/material.dart';

/// Paleta e tema do VEICAN — visual moderno (navy profundo + acentos vibrantes),
/// nada de preto chapado. Os nomes de cor sao os mesmos de antes (compatibilidade).
class VColors {
  // fundo em gradiente (topo -> base)
  static const bg = Color(0xFF0A0F1E);     // base
  static const bg2 = Color(0xFF111A33);    // topo do gradiente (azul mais vivo)
  static const card = Color(0xFF161F38);   // superficie dos cartoes
  static const cardHi = Color(0xFF1E2A49);
  static const line = Color(0xFF2A3556);

  // acentos vibrantes
  static const cyan = Color(0xFF22D3EE);
  static const blue = Color(0xFF3B82F6);
  static const violet = Color(0xFF8B5CF6);
  static const green = Color(0xFF34D399);
  static const amber = Color(0xFFFBBF24);
  static const orange = Color(0xFFFB923C);
  static const red = Color(0xFFF43F5E);
  static const pink = Color(0xFFEC4899);

  static const textHi = Color(0xFFF1F5F9);
  static const textDim = Color(0xFF9FB0CC);
  static const textFaint = Color(0xFF64748B);

  /// Gradiente de fundo padrao do app.
  static const scaffoldGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [bg2, bg],
  );
}

/// Container com o gradiente de fundo do app (use como `body`).
class VBackground extends StatelessWidget {
  final Widget child;
  const VBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: VColors.scaffoldGradient),
      child: child,
    );
  }
}

ThemeData veicanTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: VColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: VColors.cyan,
      secondary: VColors.violet,
      surface: VColors.card,
      error: VColors.red,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: VColors.textHi,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    ),
    cardTheme: CardThemeData(
      color: VColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: VColors.line),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: VColors.card,
      indicatorColor: VColors.cyan.withValues(alpha: 0.16),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 11, color: VColors.textDim),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: VColors.cyan,
        foregroundColor: const Color(0xFF05122B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
      ),
    ),
  );
}
