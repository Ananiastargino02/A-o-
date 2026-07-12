import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble/ble_service.dart';
import '../theme.dart';

class DtcScreen extends StatefulWidget {
  const DtcScreen({super.key});
  @override
  State<DtcScreen> createState() => _DtcScreenState();
}

class _DtcScreenState extends State<DtcScreen> {
  bool _lendo = false;
  bool _leu = false;
  List<String> _codigos = [];

  Future<void> _ler() async {
    setState(() {
      _lendo = true;
    });
    final ble = context.read<BleService>();
    final r = await ble.enviar('DTC LER', timeout: const Duration(seconds: 9));
    final linhas = r.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final codigos = <String>[];
    for (final l in linhas) {
      if (l.startsWith('DTC ')) continue; // cabecalho "DTC N"
      if (l.toLowerCase().contains('nenhum')) continue;
      if (l.toLowerCase().contains('timeout')) continue;
      codigos.add(l);
    }
    if (!mounted) return;
    setState(() {
      _lendo = false;
      _leu = true;
      _codigos = codigos;
    });
  }

  Future<void> _apagar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: VColors.card,
        title: const Text('Apagar codigos?'),
        content: const Text(
            'Isso apaga os codigos de falha da ECU.\n\n'
            'ATENCAO: os monitores de emissao podem ser reiniciados. '
            'Faca com o veiculo PARADO e o motor em marcha lenta.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: VColors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true) return;

    // bloqueia se o carro estiver em movimento
    final ble = context.read<BleService>();
    final v = ble.live?.velocidade ?? 0;
    if (v > 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nao apague com o carro em movimento.'),
          backgroundColor: VColors.red));
      return;
    }
    setState(() => _lendo = true);
    final r = await ble.enviar('DTC APAGAR', timeout: const Duration(seconds: 9));
    if (!mounted) return;
    setState(() => _lendo = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.isEmpty ? 'Comando enviado' : r), backgroundColor: VColors.cardHi));
    _ler();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FALHAS (DTC)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _lendo ? null : _ler,
                  icon: const Icon(Icons.search),
                  label: const Text('LER'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: VColors.cardHi, foregroundColor: VColors.textHi),
                  onPressed: _lendo || !_leu ? null : _apagar,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('APAGAR'),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            Expanded(child: _corpo()),
          ],
        ),
      ),
    );
  }

  Widget _corpo() {
    if (_lendo) {
      return const Center(child: CircularProgressIndicator(color: VColors.cyan));
    }
    if (!_leu) {
      return const Center(
        child: Text('Toque em LER para buscar os codigos de falha.',
            textAlign: TextAlign.center, style: TextStyle(color: VColors.textDim)),
      );
    }
    if (_codigos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.check_circle_outline, color: VColors.green, size: 56),
            SizedBox(height: 12),
            Text('Nenhum codigo de falha',
                style: TextStyle(color: VColors.green, fontSize: 16)),
          ],
        ),
      );
    }
    return ListView(
      children: [
        Text('${_codigos.length} codigo(s) encontrado(s)',
            style: const TextStyle(color: VColors.amber, fontSize: 13)),
        const SizedBox(height: 10),
        ..._codigos.map((c) {
          final partes = c.split(RegExp(r'\s+'));
          final cod = partes.isNotEmpty ? partes.first : c;
          final desc = partes.length > 1 ? partes.sublist(1).join(' ') : '';
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const Icon(Icons.warning_amber, color: VColors.amber),
              title: Text(cod,
                  style: const TextStyle(
                      color: VColors.textHi, fontWeight: FontWeight.bold, letterSpacing: 1)),
              subtitle: desc.isEmpty
                  ? null
                  : Text(desc, style: const TextStyle(color: VColors.textDim)),
            ),
          );
        }),
      ],
    );
  }
}
