import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// Medidor circular (arco 270°) com preenchimento proporcional e numero no centro.
class CircularGauge extends StatelessWidget {
  final double value;
  final double max;
  final String centro;
  final String unidade;
  final String rotulo;
  final Color cor;
  final double size;
  final double? redFrom; // a partir daqui vira vermelho

  const CircularGauge({
    super.key,
    required this.value,
    required this.max,
    required this.centro,
    required this.unidade,
    required this.rotulo,
    required this.cor,
    this.size = 200,
    this.redFrom,
  });

  @override
  Widget build(BuildContext context) {
    final red = redFrom != null && value >= redFrom!;
    final corAtiva = red ? VColors.red : cor;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _GaugePainter(
              frac: (value / max).clamp(0.0, 1.0),
              cor: corAtiva,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(centro,
                  style: TextStyle(
                      fontSize: size * 0.24,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                      color: corAtiva)),
              Text(unidade,
                  style: TextStyle(color: VColors.textFaint, fontSize: size * 0.07)),
              const SizedBox(height: 2),
              Text(rotulo,
                  style: TextStyle(
                      color: VColors.textDim,
                      fontSize: size * 0.065,
                      letterSpacing: 2)),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double frac;
  final Color cor;
  _GaugePainter({required this.frac, required this.cor});

  static const double _start = 3 * math.pi / 4; // 135°
  static const double _sweep = 3 * math.pi / 2; // 270°

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final stroke = size.width * 0.075;
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final bg = Paint()
      ..color = VColors.cardHi
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, bg);

    if (frac > 0) {
      final fg = Paint()
        ..shader = SweepGradient(
          startAngle: _start,
          endAngle: _start + _sweep,
          colors: [cor.withValues(alpha: 0.5), cor],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, _start, _sweep * frac, false, fg);
    }

    // tracinhos da escala
    final tick = Paint()
      ..color = VColors.line
      ..strokeWidth = 2;
    for (int i = 0; i <= 10; i++) {
      final a = _start + _sweep * (i / 10);
      final r1 = radius - stroke / 2 - 2;
      final r2 = r1 - size.width * 0.03;
      canvas.drawLine(
        center + Offset(math.cos(a) * r1, math.sin(a) * r1),
        center + Offset(math.cos(a) * r2, math.sin(a) * r2),
        tick,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.frac != frac || old.cor != cor;
}
