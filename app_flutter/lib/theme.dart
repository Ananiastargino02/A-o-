import 'package:flutter/material.dart';

/// Paleta e tema do VEICAN — visual CLARO e moderno (fundo claro, cartoes
/// brancos com borda, acentos vibrantes). Os nomes de cor sao os mesmos de
/// antes (compatibilidade) — mudar os valores aqui vira o app inteiro.
class VColors {
  // fundo claro em gradiente (topo -> base)
  static const bg = Color(0xFFEDF1F8);     // base (cinza-azulado claro)
  static const bg2 = Color(0xFFF7FAFF);    // topo do gradiente (quase branco)
  static const card = Color(0xFFFFFFFF);   // cartoes brancos
  static const cardHi = Color(0xFFEAF0F9);
  static const line = Color(0xFFC6D2E4);   // borda visivel

  // acentos vibrantes (tom mais forte p/ contrastar no branco)
  static const cyan = Color(0xFF0891B2);
  static const blue = Color(0xFF2563EB);
  static const violet = Color(0xFF7C3AED);
  static const green = Color(0xFF16A34A);
  static const amber = Color(0xFFD97706);
  static const orange = Color(0xFFEA580C);
  static const red = Color(0xFFE11D48);
  static const pink = Color(0xFFDB2777);

  static const textHi = Color(0xFF15203A);   // texto escuro (titulos/valores)
  static const textDim = Color(0xFF4B5B76);
  static const textFaint = Color(0xFF8593A8);

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
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: VColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: VColors.cyan,
      secondary: VColors.violet,
      surface: VColors.card,
      onSurface: VColors.textHi,
      error: VColors.red,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: VColors.textHi,
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
        side: const BorderSide(color: VColors.line, width: 1.4),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: VColors.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: VColors.cyan.withValues(alpha: 0.16),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 11, color: VColors.textDim),
      ),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: VColors.card),
    listTileTheme: const ListTileThemeData(
      textColor: VColors.textHi,
      iconColor: VColors.textDim,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: VColors.blue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
      ),
    ),
  );
}
