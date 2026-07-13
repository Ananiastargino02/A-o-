import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble/ble_service.dart';
import '../models/live_data.dart';
import '../theme.dart';
import '../widgets/rpm_chart.dart';
import 'speed_history_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // O BleService faz o polling do STATUS sozinho enquanto conectado.
    final ble = context.watch<BleService>();
    final d = ble.live;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PAINEL'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth_connected, color: VColors.green, size: 20),
            onPressed: () => _confirmarDesconectar(context, ble),
          ),
        ],
      ),
      body: d == null
          ? const Center(child: CircularProgressIndicator(color: VColors.cyan))
          : RefreshIndicator(
              color: VColors.cyan,
              onRefresh: () => ble.atualizarStatus(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _RpmGauge(rpm: d.rpm),
                  const SizedBox(height: 12),
                  RpmChart(dados: ble.rpmHist),
                  const SizedBox(height: 12),
                  _SpeedCard(
                    velAtual: d.velocidade,
                    maxHoje: ble.speedMaxHoje,
                    recorde: ble.speedRecorde,
                    recordeData: ble.speedRecordeData,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SpeedHistoryScreen())),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                        child: _Stat(
                            label: 'VELOCIDADE',
                            valor: '${d.velocidade}',
                            unidade: 'km/h',
                            cor: VColors.cyan)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _Stat(
                            label: 'TEMPERATURA',
                            valor: '${d.temp}',
                            unidade: '°C',
                            cor: d.temp > 100 ? VColors.orange : VColors.green)),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: _Stat(
                            label: 'COMBUSTIVEL',
                            valor: '${d.combustivel}',
                            unidade: '%',
                            cor: d.combustivel <= 15 ? VColors.red : VColors.amber)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _Stat(
                            label: 'BATERIA',
                            valor: d.bateria.toStringAsFixed(1),
                            unidade: 'V',
                            cor: _corBateria(d))),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: _Stat(
                            label: 'ODOMETRO',
                            valor: '${d.km}',
                            unidade: 'km',
                            cor: VColors.textHi)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _Stat(
                            label: 'HORAS MOTOR',
                            valor: '${d.motorHoras}h${d.motorMin.toString().padLeft(2, '0')}',
                            unidade: '',
                            cor: VColors.textHi)),
                  ]),
                  const SizedBox(height: 16),
                  _rodape(d),
                ],
              ),
            ),
    );
  }

  Color _corBateria(LiveData d) {
    if (d.bateria <= 0) return VColors.textDim;
    if (d.ligado) {
      if (d.bateria > 14.6) return VColors.orange; // sobrecarga
      if (d.bateria < 13.0) return VColors.red; // alternador
      return VColors.green;
    }
    return d.bateria < 12.0 ? VColors.red : VColors.green;
  }

  Widget _rodape(LiveData d) {
    final ligado = d.standby ? 'STANDBY' : (d.ligado ? 'MOTOR LIGADO' : 'MOTOR DESLIGADO');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: VColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VColors.line),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(ligado, style: const TextStyle(color: VColors.textDim, fontSize: 12)),
          Text('Protocolo ${d.proto}',
              style: const TextStyle(color: VColors.textFaint, fontSize: 12)),
        ],
      ),
    );
  }

  void _confirmarDesconectar(BuildContext context, BleService ble) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: VColors.card,
        title: const Text('Desconectar?'),
        content: const Text('Encerrar a conexao com o VEICAN.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () {
                Navigator.pop(context);
                ble.desconectar();
              },
              child: const Text('Desconectar')),
        ],
      ),
    );
  }
}

/// "Mostrador" de RPM: barra grande + numero.
class _RpmGauge extends StatelessWidget {
  final int rpm;
  const _RpmGauge({required this.rpm});

  @override
  Widget build(BuildContext context) {
    const maxRpm = 8000;
    final frac = (rpm / maxRpm).clamp(0.0, 1.0);
    final redline = rpm >= 6000;
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
          const Text('RPM',
              style: TextStyle(color: VColors.textDim, letterSpacing: 2, fontSize: 12)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$rpm',
                  style: TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.bold,
                      color: redline ? VColors.red : VColors.cyan)),
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
              color: redline ? VColors.red : VColors.blue,
            ),
          ),
          const SizedBox(height: 4),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0', style: TextStyle(color: VColors.textFaint, fontSize: 10)),
              Text('8000', style: TextStyle(color: VColors.textFaint, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, valor, unidade;
  final Color cor;
  const _Stat(
      {required this.label, required this.valor, required this.unidade, required this.cor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: VColors.textDim, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(valor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold, color: cor)),
              ),
              if (unidade.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(unidade, style: const TextStyle(color: VColors.textFaint, fontSize: 13)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Card de velocidade: atual, maxima do dia e recorde. Abre o historico.
class _SpeedCard extends StatelessWidget {
  final int velAtual, maxHoje, recorde;
  final DateTime? recordeData;
  final VoidCallback onTap;
  const _SpeedCard(
      {required this.velAtual,
      required this.maxHoje,
      required this.recorde,
      required this.recordeData,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dataRec = recordeData != null
        ? '${recordeData!.day.toString().padLeft(2, '0')}/${recordeData!.month.toString().padLeft(2, '0')}/${recordeData!.year}'
        : '--';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
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
            Row(
              children: [
                const Icon(Icons.show_chart, size: 16, color: VColors.textDim),
                const SizedBox(width: 6),
                const Text('VELOCIDADE',
                    style: TextStyle(color: VColors.textDim, letterSpacing: 2, fontSize: 12)),
                const Spacer(),
                const Text('Historico ',
                    style: TextStyle(color: VColors.cyan, fontSize: 12)),
                const Icon(Icons.chevron_right, size: 16, color: VColors.cyan),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _mini('AGORA', '$velAtual', VColors.cyan),
                _div(),
                _mini('MAX HOJE', '$maxHoje', VColors.amber),
                _div(),
                _mini('RECORDE', '$recorde', VColors.red, sub: dataRec),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _mini(String label, String valor, Color cor, {String? sub}) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: VColors.textFaint, fontSize: 10)),
          const SizedBox(height: 4),
          Text(valor,
              style: TextStyle(color: cor, fontSize: 24, fontWeight: FontWeight.bold)),
          const Text('km/h', style: TextStyle(color: VColors.textFaint, fontSize: 10)),
          if (sub != null)
            Text(sub, style: const TextStyle(color: VColors.textFaint, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _div() => Container(width: 1, height: 44, color: VColors.line);
}
