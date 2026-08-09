import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';

/// Ondas concentricas em ambar pulsando a partir de um centro escuro que
/// mostra o raio de busca atual (km). Usado na tela de "radar" enquanto o
/// pedido aguarda orcamentos.
class RadarAnimation extends StatefulWidget {
  final double raioKm;
  final int lojasNotificadas;

  const RadarAnimation({
    super.key,
    required this.raioKm,
    required this.lojasNotificadas,
  });

  @override
  State<RadarAnimation> createState() => _RadarAnimationState();
}

class _RadarAnimationState extends State<RadarAnimation> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 260,
          height: 260,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                painter: _RadarPainter(progress: _controller.value),
                child: Center(
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: const BoxDecoration(
                      color: AppColors.topBarDark,
                      shape: BoxShape.circle,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.raioKm.toStringAsFixed(0),
                          style: AppTextStyles.h2.copyWith(color: AppColors.white),
                        ),
                        Text(
                          'km',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '${widget.lojasNotificadas} lojas notificadas',
          style: AppTextStyles.bodyBold,
        ),
      ],
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;

  _RadarPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.width / 2;

    for (var i = 0; i < 3; i++) {
      final onda = (progress + i / 3) % 1.0;
      final raio = maxRadius * onda;
      final opacidade = (1 - onda).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = AppColors.amber.withValues(alpha: opacidade * 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(center, raio, paint);
    }

    final fillPaint = Paint()..color = AppColors.amberSoft;
    canvas.drawCircle(center, maxRadius * 0.42, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) => oldDelegate.progress != progress;
}
