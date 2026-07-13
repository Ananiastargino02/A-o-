import 'package:flutter/material.dart';
import '../../ble/ble_service.dart';
import '../../models/live_data.dart';
import '../../theme.dart';
import '../../widgets/dash_common.dart';
import '../../widgets/rpm_chart.dart';
import '../speed_history_screen.dart';

/// Painel 1 — CARTOES: informativo, tudo organizado em cartoes.
class DashCards extends StatelessWidget {
  final LiveData d;
  final BleService ble;
  const DashCards(this.d, this.ble, {super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _rpmGauge(),
        const SizedBox(height: 12),
        RpmChart(dados: ble.rpmHist),
        const SizedBox(height: 12),
        _speedCard(context),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: StatTile(label: 'VELOCIDADE', valor: '${d.velocidade}', unidade: 'km/h', cor: VColors.cyan)),
          const SizedBox(width: 12),
          Expanded(child: StatTile(label: 'TEMPERATURA', valor: '${d.temp}', unidade: '°C', cor: corTemp(d.temp))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: StatTile(label: 'COMBUSTIVEL', valor: '${d.combustivel}', unidade: '%', cor: corComb(d.combustivel))),
          const SizedBox(width: 12),
          Expanded(child: StatTile(label: 'BATERIA', valor: d.bateria.toStringAsFixed(1), unidade: 'V', cor: corBateria(d))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: StatTile(label: 'ODOMETRO', valor: '${d.km}', unidade: 'km', cor: VColors.textHi)),
          const SizedBox(width: 12),
          Expanded(child: StatTile(label: 'HORAS MOTOR', valor: '${d.motorHoras}h${d.motorMin.toString().padLeft(2, '0')}', unidade: '', cor: VColors.textHi)),
        ]),
      ],
    );
  }

  Widget _rpmGauge() {
    final frac = (d.rpm / 8000).clamp(0.0, 1.0);
    final red = d.rpm >= 6000;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: VColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('RPM', style: TextStyle(color: VColors.textDim, letterSpacing: 2, fontSize: 12)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${d.rpm}',
                  style: TextStyle(
                      fontSize: 52, fontWeight: FontWeight.bold, color: red ? VColors.red : VColors.cyan)),
              const SizedBox(width: 6),
              const Text('rpm', style: TextStyle(color: VColors.textFaint)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 12,
              backgroundColor: VColors.cardHi,
              color: red ? VColors.red : VColors.blue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _speedCard(BuildContext context) {
    final dataRec = ble.speedRecordeData != null
        ? '${ble.speedRecordeData!.day.toString().padLeft(2, '0')}/${ble.speedRecordeData!.month.toString().padLeft(2, '0')}/${ble.speedRecordeData!.year}'
        : '--';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SpeedHistoryScreen())),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: VColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: VColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: const [
              Icon(Icons.show_chart, size: 16, color: VColors.textDim),
              SizedBox(width: 6),
              Text('VELOCIDADE', style: TextStyle(color: VColors.textDim, letterSpacing: 2, fontSize: 12)),
              Spacer(),
              Text('Historico ', style: TextStyle(color: VColors.cyan, fontSize: 12)),
              Icon(Icons.chevron_right, size: 16, color: VColors.cyan),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              _mini('AGORA', '${d.velocidade}', VColors.cyan),
              _div(),
              _mini('MAX HOJE', '${ble.speedMaxHoje}', VColors.amber),
              _div(),
              _mini('RECORDE', '${ble.speedRecorde}', VColors.red, sub: dataRec),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _mini(String label, String valor, Color cor, {String? sub}) => Expanded(
        child: Column(children: [
          Text(label, style: const TextStyle(color: VColors.textFaint, fontSize: 10)),
          const SizedBox(height: 4),
          Text(valor, style: TextStyle(color: cor, fontSize: 24, fontWeight: FontWeight.bold)),
          const Text('km/h', style: TextStyle(color: VColors.textFaint, fontSize: 10)),
          if (sub != null) Text(sub, style: const TextStyle(color: VColors.textFaint, fontSize: 10)),
        ]),
      );

  Widget _div() => Container(width: 1, height: 44, color: VColors.line);
}
