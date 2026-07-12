import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble/ble_service.dart';
import '../theme.dart';

/// Tela inicial: conectar ao VEICAN por Bluetooth.
class ScanScreen extends StatelessWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    final procurando =
        ble.conn == VConn.procurando || ble.conn == VConn.conectando;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Icon(Icons.directions_car, size: 88, color: VColors.cyan),
              const SizedBox(height: 16),
              const Text('VEICAN',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                      color: VColors.textHi)),
              const SizedBox(height: 8),
              const Text('Painel · Manutencao · Diagnostico',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: VColors.textDim, letterSpacing: 1)),
              const Spacer(),
              if (procurando) ...[
                const Center(child: CircularProgressIndicator(color: VColors.cyan)),
                const SizedBox(height: 16),
                Text(
                    ble.conn == VConn.procurando
                        ? 'Procurando o VEICAN...'
                        : 'Conectando...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: VColors.textDim)),
              ] else
                FilledButton.icon(
                  onPressed: () => ble.conectar(),
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('CONECTAR'),
                ),
              if (ble.erro != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: VColors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: VColors.red.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: VColors.red, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(ble.erro!,
                              style: const TextStyle(color: VColors.textHi, fontSize: 13))),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Dica: ligue o carro e mantenha o celular perto do aparelho.',
                textAlign: TextAlign.center,
                style: TextStyle(color: VColors.textFaint, fontSize: 12),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
