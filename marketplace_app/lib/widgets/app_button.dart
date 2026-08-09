import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';

enum AppButtonEstilo { primario, positivo, destaque, perigoOutline, outline }

/// Botao padrao do app. Estilos:
/// - primario: fundo escuro, texto branco
/// - positivo: fundo verde (acao positiva)
/// - destaque: fundo ambar, texto escuro (CTA)
/// - perigoOutline: branco com borda vermelha ("Não tenho")
/// - outline: branco com borda neutra
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonEstilo estilo;
  final bool loading;
  final IconData? icone;
  final bool fullWidth;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.estilo = AppButtonEstilo.primario,
    this.loading = false,
    this.icone,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (estilo) {
      AppButtonEstilo.primario => (AppColors.textPrimary, AppColors.white, null),
      AppButtonEstilo.positivo => (AppColors.green, AppColors.white, null),
      AppButtonEstilo.destaque => (AppColors.amber, AppColors.textPrimary, null),
      AppButtonEstilo.perigoOutline => (AppColors.white, AppColors.red, AppColors.red),
      AppButtonEstilo.outline => (AppColors.white, AppColors.textPrimary, AppColors.cardBorder),
    };

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: border != null ? BorderSide(color: border, width: 1.5) : BorderSide.none,
          ),
        ),
        child: loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icone != null) ...[Icon(icone, size: 18), const SizedBox(width: 8)],
                  Text(label, style: AppTextStyles.button.copyWith(color: fg)),
                ],
              ),
      ),
    );
  }
}
