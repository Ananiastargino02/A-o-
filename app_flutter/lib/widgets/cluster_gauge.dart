import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// Medidor estilo painel de instrumentos (cluster): mostrador circular grande
/// com valor no centro (velocidade/RPM) e um ARCO menor embaixo com um segundo
/// dado (combustivel E->F ou temperatura C->H), igual ao painel de um carro.
class ClusterGauge extends StatelessWidget {
  final double value, max;      // principal (ex.: velocidade)
  final String centro, unidade; // "0" / "km/h"
  final Color cor;              // cor do arco principal
  final double? redFrom;        // vira vermelho a partir daqui

  final double subValue, subMax;  // secundario (combustivel/temperatura)
  final String subLabel;          // "COMB" / "TEMP"
  final String subEsq, subDir;    // "E"/"F"  ou  "C"/"H"
  final String subValorTxt;       // "72%" / "82°C"
  final Color subCor;

  final double size;

  const ClusterGauge({
    super.key,
    required this.value,
    required this.max,
    required this.centro,
    required this.unidade,
    required this.cor,
    required this.subValue,
    required this.subMax,
    required this.subLabel,
    required this.subEsq,
    required this.subDir,
    required this.subValorTxt,
    required this.subCor,
    this.redFrom,
    this.size = 180,
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
            painter: _ClusterPainter(
              frac: (value / max).clamp(0.0, 1.0),
              cor: corAtiva,
              subFrac: (subValue / subMax).clamp(0.0, 1.0),
              subCor: subCor,
            ),
          ),
          // valor principal (centro)
          Padding(
            padding: EdgeInsets.only(bottom: size * 0.12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(centro,
                    style: TextStyle(
                        fontSize: size * 0.26,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                        color: VColors.textHi)),
                Text(unidade,
                    style: TextStyle(color: VColors.textFaint, fontSize: size * 0.075)),
              ],
            ),
          ),
          // secundario (embaixo): rotulo + valor
          Positioned(
            bottom: size * 0.14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(subLabel,
                    style: TextStyle(color: subCor, fontSize: size * 0.06, letterSpacing: 1)),
                Text(subValorTxt,
                    style: TextStyle(color: subCor, fontSize: size * 0.085, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          // letras E/F ou C/H nas pontas do arco de baixo
          Positioned(
            left: size * 0.20,
            bottom: size * 0.055,
            child: Text(subEsq, style: TextStyle(color: subCor, fontSize: size * 0.06, fontWeight: FontWeight.bold)),
          ),
          Positioned(
            right: size * 0.20,
            bottom: size * 0.055,
            child: Text(subDir, style: TextStyle(color: subCor, fontSize: size * 0.06, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _ClusterPainter extends CustomPainter {
  final double frac, subFrac;
  final Color cor, subCor;
  _ClusterPainter({required this.frac, required this.cor, required this.subFrac, required this.subCor});

  // arco principal: 225° comecando embaixo-esquerda, deixando o vao embaixo p/ o sub
  static const double _start = 150 * math.pi / 180;  // graus
  static const double _sweep = 240 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final stroke = size.width * 0.055;
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // trilho de fundo
    final bg = Paint()
      ..color = VColors.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, bg);

    // arco ativo
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
      ..color = VColors.textFaint
      ..strokeWidth = 1.5;
    for (int i = 0; i <= 8; i++) {
      final a = _start + _sweep * (i / 8);
      final r1 = radius - stroke;
      final r2 = r1 - size.width * 0.035;
      canvas.drawLine(center + Offset(math.cos(a) * r1, math.sin(a) * r1),
          center + Offset(math.cos(a) * r2, math.sin(a) * r2), tick);
    }

    // ---- sub-arco (combustivel/temperatura) no VAO DE BAIXO do mostrador ----
    // o arco principal deixa um vao embaixo (30°..150°, passando por 90°=fundo).
    // desenhamos aqui, de 150° (baixo-esq) ate 30° (baixo-dir) passando pelo fundo.
    final subStroke = size.width * 0.045;
    final subRect = Rect.fromCircle(center: center, radius: radius - stroke * 1.4);
    const gapStart = 150 * math.pi / 180;    // baixo-esquerda (E / C)
    const gapSweep = -120 * math.pi / 180;   // negativo: passa pelo fundo ate baixo-direita (F / H)
    final subBg = Paint()
      ..color = VColors.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = subStroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(subRect, gapStart, gapSweep, false, subBg);
    if (subFrac > 0) {
      final subFg = Paint()
        ..color = subCor
        ..style = PaintingStyle.stroke
        ..strokeWidth = subStroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(subRect, gapStart, gapSweep * subFrac, false, subFg);
    }
  }

  @override
  bool shouldRepaint(_ClusterPainter old) =>
      old.frac != frac || old.subFrac != subFrac || old.cor != cor || old.subCor != subCor;
}
