import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';

class EmptyState extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String? subtitulo;

  const EmptyState({
    super.key,
    required this.icone,
    required this.titulo,
    this.subtitulo,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(color: AppColors.amberSoft, shape: BoxShape.circle),
              child: Icon(icone, size: 36, color: AppColors.amber),
            ),
            const SizedBox(height: 16),
            Text(titulo, style: AppTextStyles.h3, textAlign: TextAlign.center),
            if (subtitulo != null) ...[
              const SizedBox(height: 6),
              Text(subtitulo!, style: AppTextStyles.bodySecondary, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
