import 'package:flutter/material.dart';
import '../../ble/ble_service.dart';
import '../../models/live_data.dart';
import '../../theme.dart';
import '../../widgets/dash_common.dart';

/// Painel 3 — MINIMALISTA: a velocidade gigante no centro, o resto discreto.
class DashMinimal extends StatelessWidget {
  final LiveData d;
  final BleService ble;
  const DashMinimal(this.d, this.ble, {super.key});

  @override
  Widget build(BuildContext context) {
    final redline = d.rpm >= 6000;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        children: [
          const Spacer(flex: 2),
          // velocidade gigante
          Text('${d.velocidade}',
              style: const TextStyle(
                  fontSize: 150,
                  height: 0.95,
                  fontWeight: FontWeight.w200,
                  color: VColors.textHi)),
          const Text('km/h', style: TextStyle(color: VColors.textDim, fontSize: 20, letterSpacing: 4)),
          const SizedBox(height: 40),
          // RPM como barra fina
          Row(children: [
            Text('${d.rpm}',
                style: TextStyle(
                    color: redline ? VColors.red : VColors.cyan,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (d.rpm / 8000).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: VColors.cardHi,
                  color: redline ? VColors.red : VColors.cyan,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text('rpm', style: TextStyle(color: VColors.textFaint, fontSize: 12)),
          ]),
          const Spacer(flex: 3),
          // 3 infos discretas
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _mini(Icons.thermostat, '${d.temp}°C', corTemp(d.temp)),
              _mini(Icons.local_gas_station, '${d.combustivel}%', corComb(d.combustivel)),
              _mini(Icons.bolt, '${d.bateria.toStringAsFixed(1)}V', corBateria(d)),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _mini(IconData ic, String valor, Color cor) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ic, size: 18, color: cor),
          const SizedBox(width: 6),
          Text(valor, style: TextStyle(color: cor, fontSize: 17, fontWeight: FontWeight.w500)),
        ],
      );
}
