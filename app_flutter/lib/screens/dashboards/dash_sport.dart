import 'package:flutter/material.dart';
import '../../ble/ble_service.dart';
import '../../models/live_data.dart';
import '../../theme.dart';
import '../../widgets/circular_gauge.dart';
import '../../widgets/dash_common.dart';

/// Painel 2 — ESPORTIVO: medidores circulares grandes de RPM e velocidade.
class DashSport extends StatelessWidget {
  final LiveData d;
  final BleService ble;
  const DashSport(this.d, this.ble, {super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final g = (c.maxWidth * 0.62).clamp(180.0, 300.0);
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          children: [
            CircularGauge(
              value: d.rpm.toDouble(),
              max: 8000,
              centro: '${d.rpm}',
              unidade: 'RPM',
              rotulo: 'MOTOR',
              cor: VColors.cyan,
              redFrom: 6000,
              size: g,
            ),
            const SizedBox(height: 24),
            CircularGauge(
              value: d.velocidade.toDouble(),
              max: 240,
              centro: '${d.velocidade}',
              unidade: 'km/h',
              rotulo: 'VELOCIDADE',
              cor: VColors.blue,
              redFrom: 140,
              size: g * 0.82,
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                _pill(Icons.thermostat, '${d.temp}°', 'temp', corTemp(d.temp)),
                const SizedBox(width: 10),
                _pill(Icons.local_gas_station, '${d.combustivel}%', 'comb', corComb(d.combustivel)),
                const SizedBox(width: 10),
                _pill(Icons.bolt, '${d.bateria.toStringAsFixed(1)}V', 'bat', corBateria(d)),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _pill(IconData ic, String valor, String label, Color cor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: VColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cor.withValues(alpha: 0.35)),
        ),
        child: Column(children: [
          Icon(ic, color: cor, size: 22),
          const SizedBox(height: 6),
          Text(valor, style: TextStyle(color: cor, fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: VColors.textFaint, fontSize: 11)),
        ]),
      ),
    );
  }
}
