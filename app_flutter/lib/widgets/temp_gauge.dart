import 'package:flutter/material.dart';
import '../theme.dart';

/// Temperatura da agua: valor em GRAUS + um indicador de NIVEL vertical estilo
/// medidor de carro (termometro com C embaixo e H em cima).
class TempGauge extends StatelessWidget {
  final int temp; // °C (0 quando offline)
  const TempGauge(this.temp, {super.key});

  // faixa do medidor: 40°C (fundo) .. 120°C (topo)
  static const _min = 40.0;
  static const _max = 120.0;

  Color get _cor {
    if (temp >= 110) return VColors.red;
    if (temp >= 100) return VColors.orange;
    if (temp >= 60) return VColors.green;
    return VColors.blue; // frio
  }

  String get _estado {
    if (temp <= 0) return '--';
    if (temp >= 110) return 'MUITO QUENTE';
    if (temp >= 100) return 'QUENTE';
    if (temp >= 60) return 'NORMAL';
    return 'FRIO';
  }

  double get _nivel => ((temp - _min) / (_max - _min)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final cor = _cor;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: VColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withValues(alpha: 0.55), width: 1.6),
      ),
      child: Row(
        children: [
          // valor em graus + estado
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.thermostat, color: cor, size: 20),
                  const SizedBox(width: 6),
                  const Text('TEMPERATURA',
                      style: TextStyle(color: VColors.textDim, fontSize: 11, letterSpacing: 1)),
                ]),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(temp <= 0 ? '--' : '$temp',
                        style: TextStyle(color: cor, fontSize: 48, fontWeight: FontWeight.w800, height: 1.0)),
                    const SizedBox(width: 4),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('°C', style: TextStyle(color: VColors.textFaint, fontSize: 18)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(_estado,
                    style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // medidor de nivel (termometro) — igual no carro
          _termometro(cor),
        ],
      ),
    );
  }

  Widget _termometro(Color cor) {
    const h = 128.0;
    return SizedBox(
      width: 58,
      height: h + 18,
      child: Column(
        children: [
          Text('H', style: TextStyle(color: VColors.red.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // marcas laterais
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(
                      5, (_) => Container(width: 6, height: 2, color: VColors.line)),
                ),
                const SizedBox(width: 6),
                // tubo do termometro
                Container(
                  width: 20,
                  decoration: BoxDecoration(
                    color: VColors.cardHi,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: VColors.line, width: 1.2),
                  ),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: temp <= 0 ? 0.02 : _nivel.clamp(0.04, 1.0),
                      widthFactor: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [cor.withValues(alpha: 0.65), cor],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const SizedBox(width: 6),
              ],
            ),
          ),
          const SizedBox(height: 2),
          const Text('C', style: TextStyle(color: VColors.blue, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
