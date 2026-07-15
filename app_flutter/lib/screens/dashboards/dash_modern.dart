import 'package:flutter/material.dart';
import '../../ble/ble_service.dart';
import '../../models/live_data.dart';
import '../../theme.dart';
import '../../widgets/circular_gauge.dart';
import '../../widgets/rpm_chart.dart';
import '../../widgets/temp_gauge.dart';
import '../../widgets/dash_common.dart';

/// Painel MODERNO (padrao): conta-giro grande ao vivo, velocidade em destaque,
/// tiles de temperatura/combustivel/bateria e grafico de RPM em tempo real.
class DashModern extends StatelessWidget {
  final LiveData d;
  final BleService ble;
  const DashModern(this.d, this.ble, {super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final g = (c.maxWidth * 0.66).clamp(200.0, 320.0);
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _liveHeader(),
          const SizedBox(height: 8),

          // Conta-giro (hero) num cartao com borda
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: VColors.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: (d.rpm >= 6000 ? VColors.red : VColors.cyan).withValues(alpha: 0.55),
                  width: 1.6),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 6)),
              ],
            ),
            child: Center(
              child: CircularGauge(
                value: d.rpm.toDouble(),
                max: 8000,
                centro: '${d.rpm}',
                unidade: 'RPM  x1',
                rotulo: 'CONTA-GIRO',
                cor: VColors.cyan,
                redFrom: 6000,
                size: g,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Velocidade em destaque
          _speedCard(context),
          const SizedBox(height: 14),

          // Temperatura: valor em graus + indicador de nivel (igual no carro)
          TempGauge(d.temp),
          const SizedBox(height: 12),

          // Tiles ao vivo
          Row(
            children: [
              Expanded(child: _tile(Icons.local_gas_station, d.combustivel >= 0 ? '${d.combustivel}' : '--', '%', 'COMBUSTIVEL', corComb(d.combustivel))),
              const SizedBox(width: 12),
              Expanded(child: _tile(d.ligado ? Icons.bolt : Icons.battery_full, d.bateria.toStringAsFixed(1), 'V', d.ligado ? 'ALTERNADOR' : 'BATERIA', corBateria(d))),
            ],
          ),
          const SizedBox(height: 12),
          _tile(Icons.route, '${d.km}', 'km', 'ODOMETRO', VColors.violet),
          const SizedBox(height: 16),

          // RPM ao vivo (grafico)
          RpmChart(dados: ble.rpmHist),
        ],
      );
    });
  }

  Widget _liveHeader() {
    final online = ble.conectado;
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: online ? VColors.green : VColors.textFaint,
            shape: BoxShape.circle,
            boxShadow: online
                ? [BoxShadow(color: VColors.green.withValues(alpha: 0.7), blurRadius: 8)]
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Text(online ? 'AO VIVO' : 'SEM SINAL',
            style: TextStyle(
                color: online ? VColors.green : VColors.textFaint,
                fontSize: 12,
                letterSpacing: 2,
                fontWeight: FontWeight.w700)),
        const Spacer(),
        Text(d.estado,
            style: const TextStyle(color: VColors.textFaint, fontSize: 12, letterSpacing: 1)),
      ],
    );
  }

  Widget _speedCard(BuildContext context) {
    final vermelho = d.velocidade >= 120;
    final cor = vermelho ? VColors.red : VColors.blue;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cor.withValues(alpha: 0.18), VColors.card],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cor.withValues(alpha: 0.55), width: 1.6),
      ),
      child: Row(
        children: [
          Icon(Icons.speed, color: cor, size: 34),
          const SizedBox(width: 14),
          const Text('VELOCIDADE',
              style: TextStyle(color: VColors.textDim, fontSize: 13, letterSpacing: 1.5)),
          const Spacer(),
          Text('${d.velocidade}',
              style: TextStyle(color: cor, fontSize: 52, fontWeight: FontWeight.w800, height: 1.0)),
          const SizedBox(width: 6),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('km/h', style: TextStyle(color: VColors.textFaint, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _tile(IconData ic, String valor, String unidade, String label, Color cor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cor.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(ic, color: cor, size: 18),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: VColors.textDim, fontSize: 10, letterSpacing: 1)),
          ]),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(valor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: cor)),
              ),
              const SizedBox(width: 3),
              Text(unidade, style: const TextStyle(color: VColors.textFaint, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}
