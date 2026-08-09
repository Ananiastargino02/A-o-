import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';

enum ChipTom { verde, ambar, cinza, azul, vermelho }

/// Chip arredondado (radius 99) para status: verde=respondido/nova,
/// ambar=novo/usada, cinza=neutro, azul=info.
class StatusChip extends StatelessWidget {
  final String label;
  final ChipTom tom;
  final IconData? icone;

  const StatusChip({
    super.key,
    required this.label,
    required this.tom,
    this.icone,
  });

  (Color, Color) get _cores => switch (tom) {
        ChipTom.verde => (AppColors.greenSoft, AppColors.green),
        ChipTom.ambar => (AppColors.amberSoft, AppColors.amber),
        ChipTom.cinza => (const Color(0xFFEDEEF1), AppColors.textSecondary),
        ChipTom.azul => (AppColors.blueSoft, AppColors.blue),
        ChipTom.vermelho => (AppColors.redSoft, AppColors.red),
      };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _cores;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[
            Icon(icone, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label, style: AppTextStyles.caption.copyWith(color: fg)),
        ],
      ),
    );
  }
}
