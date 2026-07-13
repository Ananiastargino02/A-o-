import 'package:flutter/material.dart';
import '../../ble/ble_service.dart';
import '../../models/live_data.dart';
import '../../theme.dart';
import '../../widgets/dash_common.dart';

/// Painel 4 — COCKPIT: mosaico de tiles com brilho neon, estilo dashboard gamer.
class DashCockpit extends StatelessWidget {
  final LiveData d;
  final BleService ble;
  const DashCockpit(this.d, this.ble, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _rpmBar(),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.55,
          children: [
            NeonTile(label: 'VELOCIDADE', valor: '${d.velocidade}', unidade: 'km/h', cor: VColors.cyan, icone: Icons.speed),
            NeonTile(label: 'TEMP MOTOR', valor: '${d.temp}', unidade: '°C', cor: corTemp(d.temp), icone: Icons.thermostat),
            NeonTile(label: 'COMBUSTIVEL', valor: '${d.combustivel}', unidade: '%', cor: corComb(d.combustivel), icone: Icons.local_gas_station),
            NeonTile(label: 'BATERIA', valor: d.bateria.toStringAsFixed(1), unidade: 'V', cor: corBateria(d), icone: Icons.bolt),
            NeonTile(label: 'ODOMETRO', valor: '${d.km}', unidade: 'km', cor: const Color(0xFF7C4DFF), icone: Icons.route),
            NeonTile(label: 'MOTOR', valor: '${d.motorHoras}h${d.motorMin.toString().padLeft(2, '0')}', unidade: '', cor: const Color(0xFF00E676), icone: Icons.timer_outlined),
          ],
        ),
      ],
    );
  }

  Widget _rpmBar() {
    const segs = 24;
    final ativos = ((d.rpm / 8000) * segs).clamp(0, segs).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VColors.cyan.withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: VColors.cyan.withValues(alpha: 0.15), blurRadius: 16, spreadRadius: 1)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('RPM', style: TextStyle(color: VColors.textDim, letterSpacing: 3, fontSize: 12)),
            const Spacer(),
            Text('${d.rpm}',
                style: TextStyle(
                    color: d.rpm >= 6000 ? VColors.red : VColors.cyan,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: d.rpm >= 6000 ? VColors.red : VColors.cyan, blurRadius: 12)])),
          ]),
          const SizedBox(height: 12),
          Row(
            children: [
              for (int i = 0; i < segs; i++)
                Expanded(
                  child: Container(
                    height: 22,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: i < ativos ? _corSeg(i, segs) : const Color(0xFF16202F),
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: i < ativos
                          ? [BoxShadow(color: _corSeg(i, segs).withValues(alpha: 0.7), blurRadius: 6)]
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _corSeg(int i, int total) {
    final f = i / total;
    if (f > 0.75) return VColors.red;
    if (f > 0.55) return VColors.amber;
    return VColors.cyan;
  }
}
