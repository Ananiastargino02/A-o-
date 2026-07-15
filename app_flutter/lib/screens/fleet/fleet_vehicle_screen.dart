import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../fleet/fleet_service.dart';
import '../../models/fleet_vehicle.dart';
import '../../theme.dart';

/// Detalhe de UM carro da frota (o que o patrao ve ao tocar num carro).
/// Mostra o ultimo retrato enviado pelo motorista.
class FleetVehicleScreen extends StatelessWidget {
  final String vehicleId;
  const FleetVehicleScreen({super.key, required this.vehicleId});

  @override
  Widget build(BuildContext context) {
    final fleet = context.watch<FleetService>();
    FleetVehicle? v;
    for (final e in fleet.veiculos) {
      if (e.id == vehicleId) v = e;
    }
    if (v == null) {
      return const Scaffold(body: Center(child: Text('Carro removido.')));
    }
    final s = v.snapshot;
    return Scaffold(
      appBar: AppBar(title: Text(v.titulo.isEmpty ? 'CARRO' : v.titulo.toUpperCase())),
      body: VBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _cabecalho(v),
            const SizedBox(height: 16),
            if (s == null)
              _semDados()
            else ...[
              _statusLinha(v),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.6,
                children: [
                  _tile('ODOMETRO', '${s.km}', 'km', Icons.route, VColors.violet),
                  _tile('RPM', '${s.rpm}', '', Icons.speed, VColors.cyan),
                  _tile('VELOCIDADE', '${s.velocidade}', 'km/h', Icons.directions_car, VColors.blue),
                  _tile('TEMPERATURA', '${s.temp}', '°C', Icons.thermostat,
                      s.temp > 100 ? VColors.orange : VColors.green),
                  _tile('COMBUSTIVEL', s.combustivel >= 0 ? '${s.combustivel}' : '--', '%',
                      Icons.local_gas_station, VColors.amber),
                  _tile('BATERIA', s.bateria.toStringAsFixed(1), 'V', Icons.bolt, VColors.green),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cabecalho(FleetVehicle v) {
    final linhas = [
      if (v.placa.isNotEmpty) 'Placa: ${v.placa}',
      if (v.marca.isNotEmpty || v.modelo.isNotEmpty) '${v.marca} ${v.modelo} ${v.ano}'.trim(),
      if (v.motorista.isNotEmpty) 'Motorista: ${v.motorista}',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VColors.line),
      ),
      child: Row(children: [
        const Icon(Icons.directions_car, color: VColors.cyan, size: 34),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: linhas.isEmpty
                ? [const Text('Sem detalhes', style: TextStyle(color: VColors.textFaint))]
                : linhas
                    .map((t) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(t, style: const TextStyle(color: VColors.textDim))))
                    .toList(),
          ),
        ),
      ]),
    );
  }

  Widget _statusLinha(FleetVehicle v) {
    final on = v.online;
    return Row(children: [
      Icon(on ? Icons.circle : Icons.circle_outlined,
          color: on ? VColors.green : VColors.textFaint, size: 12),
      const SizedBox(width: 8),
      Text(on ? 'Online' : 'Offline',
          style: TextStyle(color: on ? VColors.green : VColors.textFaint, fontWeight: FontWeight.w600)),
      const Spacer(),
      Text(_ha(v.idade), style: const TextStyle(color: VColors.textFaint, fontSize: 12)),
    ]);
  }

  Widget _semDados() => Container(
        height: 160,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: VColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: VColors.line),
        ),
        child: const Text('Este carro ainda nao enviou dados.\nO motorista precisa conectar no Bluetooth.',
            textAlign: TextAlign.center, style: TextStyle(color: VColors.textFaint)),
      );

  Widget _tile(String label, String valor, String un, IconData ic, Color cor) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: VColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cor.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Icon(ic, color: cor, size: 16),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: VColors.textDim, fontSize: 10, letterSpacing: 1)),
            ]),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(valor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cor, fontSize: 26, fontWeight: FontWeight.bold)),
                ),
                if (un.isNotEmpty) ...[
                  const SizedBox(width: 3),
                  Text(un, style: const TextStyle(color: VColors.textFaint, fontSize: 12)),
                ],
              ],
            ),
          ],
        ),
      );

  static String _ha(Duration? d) {
    if (d == null) return 'nunca reportou';
    if (d.inMinutes < 1) return 'atualizado agora';
    if (d.inMinutes < 60) return 'ha ${d.inMinutes} min';
    if (d.inHours < 24) return 'ha ${d.inHours} h';
    return 'ha ${d.inDays} d';
  }
}
