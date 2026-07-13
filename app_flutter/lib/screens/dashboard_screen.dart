import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble/ble_service.dart';
import '../models/dashboard_style.dart';
import '../state/app_settings.dart';
import '../theme.dart';
import 'dashboards/dash_cards.dart';
import 'dashboards/dash_sport.dart';
import 'dashboards/dash_minimal.dart';
import 'dashboards/dash_cockpit.dart';
import 'dashboard_picker_screen.dart';

/// Aba "Painel": mostra o estilo escolhido pelo usuario.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    final estilo = context.watch<AppSettings>().dash;
    final d = ble.live;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PAINEL'),
        actions: [
          IconButton(
            tooltip: 'Escolher painel',
            icon: const Icon(Icons.tune, size: 20),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DashboardPickerScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.bluetooth_connected, color: VColors.green, size: 20),
            onPressed: () => _confirmarDesconectar(context, ble),
          ),
        ],
      ),
      body: d == null
          ? const Center(child: CircularProgressIndicator(color: VColors.cyan))
          : switch (estilo) {
              DashboardStyle.cards => DashCards(d, ble),
              DashboardStyle.sport => DashSport(d, ble),
              DashboardStyle.minimal => DashMinimal(d, ble),
              DashboardStyle.cockpit => DashCockpit(d, ble),
            },
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
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
