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
              // Lista de VEICANs encontrados (quando ha mais de um, o usuario escolhe)
              if (ble.encontrados.isNotEmpty) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('SELECIONAR DISPOSITIVO',
                      style: TextStyle(color: VColors.textDim, letterSpacing: 1.5, fontSize: 12)),
                ),
                const SizedBox(height: 8),
                for (final dev in ble.encontrados)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.memory, color: VColors.cyan),
                      title: Text(dev.nome, style: const TextStyle(color: VColors.textHi)),
                      subtitle: Text(dev.id, style: const TextStyle(color: VColors.textFaint, fontSize: 12)),
                      trailing: const Icon(Icons.chevron_right, color: VColors.textFaint),
                      onTap: () => ble.conectarA(dev.id),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
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
                  onPressed: () => ble.escanear(),
                  icon: const Icon(Icons.bluetooth_searching),
                  label: Text(ble.encontrados.isEmpty ? 'CONECTAR' : 'PROCURAR DE NOVO'),
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
