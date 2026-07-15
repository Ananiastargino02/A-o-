import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble/ble_service.dart';
import '../theme.dart';

/// Tela de CONEXAO (aberta pelo botao do painel): escaneia, lista os VEICAN
/// encontrados e deixa escolher. Fecha sozinha quando conecta.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  @override
  void initState() {
    super.initState();
    // comeca a procurar assim que abre
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ble = context.read<BleService>();
      if (!ble.conectado) ble.escanear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    // conectou -> volta pro painel sozinho
    if (ble.conectado) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      });
    }
    final procurando =
        ble.conn == VConn.procurando || ble.conn == VConn.conectando;

    return Scaffold(
      appBar: AppBar(title: const Text('CONECTAR')),
      body: VBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                const Icon(Icons.bluetooth_searching, size: 64, color: VColors.cyan),
                const SizedBox(height: 12),
                const Text('Procurando o VEICAN',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: VColors.textHi)),
                const SizedBox(height: 6),
                const Text('Ligue o carro e mantenha o celular perto do aparelho.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: VColors.textFaint, fontSize: 12)),
                const SizedBox(height: 20),
                if (ble.encontrados.isNotEmpty) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('SELECIONAR DISPOSITIVO',
                        style: TextStyle(color: VColors.textDim, letterSpacing: 1.5, fontSize: 12)),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final dev in ble.encontrados)
                          Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const Icon(Icons.memory, color: VColors.cyan),
                              title: Text(dev.nome, style: const TextStyle(color: VColors.textHi)),
                              subtitle: Text(dev.id,
                                  style: const TextStyle(color: VColors.textFaint, fontSize: 12)),
                              trailing: const Icon(Icons.chevron_right, color: VColors.textFaint),
                              onTap: () => ble.conectarA(dev.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                ] else
                  const Spacer(),
                if (procurando) ...[
                  const Center(child: CircularProgressIndicator(color: VColors.cyan)),
                  const SizedBox(height: 12),
                  Text(ble.conn == VConn.conectando ? 'Conectando...' : 'Procurando...',
                      textAlign: TextAlign.center, style: const TextStyle(color: VColors.textDim)),
                ] else
                  FilledButton.icon(
                    onPressed: () => ble.escanear(),
                    icon: const Icon(Icons.refresh),
                    label: Text(ble.encontrados.isEmpty ? 'PROCURAR' : 'PROCURAR DE NOVO'),
                  ),
                if (ble.erro != null && !procurando) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: VColors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: VColors.red.withValues(alpha: 0.4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: VColors.red, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(ble.erro!, style: const TextStyle(color: VColors.textHi, fontSize: 13))),
                    ]),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
