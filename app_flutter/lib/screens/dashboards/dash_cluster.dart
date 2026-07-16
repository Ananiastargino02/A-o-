import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../ble/ble_service.dart';
import '../../models/live_data.dart';
import '../../theme.dart';
import '../../widgets/cluster_gauge.dart';
import '../../widgets/rpm_chart.dart';

/// Painel CLUSTER: dois mostradores estilo painel de carro. Esquerda = velocidade
/// (com combustivel E->F embaixo); direita = RPM (com temperatura C->H embaixo).
/// Fora: tensao, odometro e hora. Sem o carro no meio.
class DashCluster extends StatelessWidget {
  final LiveData d;
  final BleService ble;
  const DashCluster(this.d, this.ble, {super.key});

  Color _corTemp(int t) {
    if (t >= 110) return VColors.red;
    if (t >= 100) return VColors.orange;
    if (t >= 60) return VColors.green;
    return VColors.blue;
  }

  @override
  Widget build(BuildContext context) {
    final agora = DateTime.now();
    final corTemp = _corTemp(d.temp);
    final comb = d.combustivel >= 0 ? d.combustivel : 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: [
        // cabecalho: data | hora
        Row(
          children: [
            Text(DateFormat('dd MMM').format(agora),
                style: const TextStyle(color: VColors.textDim, fontSize: 13)),
            const Spacer(),
            Text(DateFormat('HH:mm').format(agora),
                style: const TextStyle(color: VColors.textHi, fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),

        // dois mostradores lado a lado
        LayoutBuilder(builder: (context, c) {
          final g = ((c.maxWidth - 12) / 2).clamp(150.0, 200.0);
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // ESQUERDA: velocidade + combustivel
              ClusterGauge(
                size: g,
                value: d.velocidade.toDouble(),
                max: 220,
                centro: '${d.velocidade}',
                unidade: 'km/h',
                cor: VColors.blue,
                redFrom: 140,
                subValue: comb.toDouble(),
                subMax: 100,
                subLabel: 'COMB',
                subEsq: 'E',
                subDir: 'F',
                subValorTxt: d.combustivel >= 0 ? '$comb%' : '--',
                subCor: comb <= 15 ? VColors.red : VColors.amber,
              ),
              // DIREITA: RPM + temperatura
              ClusterGauge(
                size: g,
                value: d.rpm.toDouble(),
                max: 8000,
                centro: (d.rpm / 1000).toStringAsFixed(1),
                unidade: 'x1000 rpm',
                cor: VColors.cyan,
                redFrom: 6000,
                subValue: (d.temp - 40).clamp(0, 80).toDouble(),
                subMax: 80,
                subLabel: 'TEMP',
                subEsq: 'C',
                subDir: 'H',
                subValorTxt: d.temp > 0 ? '${d.temp}°C' : '--',
                subCor: corTemp,
              ),
            ],
          );
        }),
        const SizedBox(height: 16),

        // fora: tensao + odometro + estado
        Row(
          children: [
            Expanded(child: _info(d.ligado ? Icons.bolt : Icons.battery_full,
                '${d.bateria.toStringAsFixed(1)}V', d.ligado ? 'ALTERNADOR' : 'BATERIA', VColors.green)),
            const SizedBox(width: 10),
            Expanded(child: _info(Icons.route, '${d.km}', 'KM', VColors.violet)),
            const SizedBox(width: 10),
            Expanded(child: _info(Icons.info_outline, d.estado, 'ESTADO', VColors.textDim)),
          ],
        ),
        const SizedBox(height: 16),
        RpmChart(dados: ble.rpmHist),
      ],
    );
  }

  Widget _info(IconData ic, String valor, String label, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: VColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Column(
        children: [
          Icon(ic, color: cor, size: 18),
          const SizedBox(height: 6),
          FittedBox(
            child: Text(valor,
                style: TextStyle(color: cor, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: VColors.textFaint, fontSize: 9, letterSpacing: 1)),
        ],
      ),
    );
  }
}
