import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble/ble_service.dart';
import '../models/maintenance.dart';
import '../storage/local_store.dart';
import '../theme.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});
  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  final _store = LocalStore();
  List<MaintItem> _itens = [];
  List<MaintRecord> _hist = [];
  bool _carregando = true;
  bool _offline = false;   // mostrando dados guardados (sem conexao)

  @override
  void initState() {
    super.initState();
    _recarregar();
  }

  Future<void> _recarregar() async {
    setState(() => _carregando = true);
    final ble = context.read<BleService>();
    String texto = '';
    bool offline = false;
    if (ble.conectado) {
      texto = await ble.enviar('MANUT LIST');
      if (texto.trim().isNotEmpty) {
        await _store.saveManutCache(texto);   // atualiza o cache quando online
      }
    }
    if (texto.trim().isEmpty) {
      texto = await _store.loadManutCache();   // offline: usa o ultimo guardado
      offline = true;
    }
    final itens = <MaintItem>[];
    for (final linha in texto.split('\n')) {
      final m = MaintItem.parse(linha);
      if (m != null) itens.add(m);
    }
    final hist = await _store.loadHistory();
    if (!mounted) return;
    setState(() {
      _itens = itens;
      _hist = hist;
      _offline = offline && itens.isNotEmpty;
      _carregando = false;
    });
  }

  Future<void> _resetar(MaintItem item) async {
    final ok = await _confirmar('Resetar ${item.nome}?',
        'Isso zera o contador e registra a manutencao no historico.');
    if (ok != true) return;
    final ble = context.read<BleService>();
    final resp = await ble.enviar('MANUT RESET ${item.indice}');
    // salva no historico local
    final km = ble.live?.km ?? 0;
    await _store.addHistory(MaintRecord(item: item.nome, data: DateTime.now(), km: km));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(resp.isEmpty ? '${item.nome} resetado' : resp),
        backgroundColor: VColors.cardHi));
    _recarregar();
  }

  Future<void> _editarIntervalo(MaintItem item) async {
    final kmCtrl = TextEditingController(text: item.intervaloKm.toString());
    final diasCtrl = TextEditingController(
        text: item.intervaloDias > 0 ? item.intervaloDias.toString() : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: VColors.card,
        title: Text('Intervalo · ${item.nome}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: kmCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Intervalo (km)'),
            ),
            TextField(
              controller: diasCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Intervalo (dias, opcional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    final ble = context.read<BleService>();
    final km = int.tryParse(kmCtrl.text) ?? item.intervaloKm;
    final dias = int.tryParse(diasCtrl.text) ?? 0;
    await ble.enviar('MANUT KM ${item.indice} $km');
    if (dias > 0) await ble.enviar('MANUT DIAS ${item.indice} $dias');
    _recarregar();
  }

  Future<bool?> _confirmar(String titulo, String msg) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: VColors.card,
          title: Text(titulo),
          content: Text(msg),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirmar')),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MANUTENCAO'),
        actions: [
          IconButton(onPressed: _recarregar, icon: const Icon(Icons.refresh, size: 20)),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: VColors.cyan))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_offline)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: VColors.amber.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: VColors.amber.withValues(alpha: 0.5)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.history, color: VColors.amber, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('Dados guardados (sem conexao). Conecte para atualizar.',
                            style: TextStyle(color: VColors.textHi, fontSize: 12)),
                      ),
                    ]),
                  ),
                if (_itens.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: VColors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: VColors.line, width: 1.4),
                    ),
                    child: const Text(
                        'Sem dados de manutencao ainda.\nConecte no VEICAN uma vez para carregar e guardar.',
                        textAlign: TextAlign.center, style: TextStyle(color: VColors.textFaint)),
                  ),
                ..._itens.map(_itemCard),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text('HISTORICO',
                        style: TextStyle(color: VColors.textDim, letterSpacing: 2, fontSize: 13)),
                    const Spacer(),
                    if (_hist.isNotEmpty)
                      TextButton(
                          onPressed: () async {
                            final ok = await _confirmar(
                                'Limpar historico?', 'Apaga o historico salvo no celular.');
                            if (ok == true) {
                              await _store.clearHistory();
                              _recarregar();
                            }
                          },
                          child: const Text('Limpar')),
                  ],
                ),
                if (_hist.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Nenhuma manutencao registrada ainda.',
                        style: TextStyle(color: VColors.textFaint)),
                  )
                else
                  ..._hist.map(_histTile),
              ],
            ),
    );
  }

  Widget _itemCard(MaintItem item) {
    final cor = item.vencido
        ? VColors.red
        : (item.proximo ? VColors.amber : VColors.blue);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(item.nome,
                        style: TextStyle(
                            color: cor, fontSize: 16, fontWeight: FontWeight.w600))),
                Text(item.vencido ? 'VENCIDO' : '${item.percentual}%',
                    style: TextStyle(color: cor, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (item.percentual / 100).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: VColors.cardHi,
                color: cor,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                    'A cada ${item.intervaloKm} km'
                    '${item.intervaloDias > 0 ? " / ${item.intervaloDias} dias" : ""}',
                    style: const TextStyle(color: VColors.textFaint, fontSize: 12)),
                const Spacer(),
                TextButton(
                    onPressed: () => _editarIntervalo(item), child: const Text('Intervalo')),
                FilledButton(
                    onPressed: () => _resetar(item), child: const Text('Resetar')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _histTile(MaintRecord r) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.check_circle_outline, color: VColors.green, size: 20),
      title: Text(r.item, style: const TextStyle(color: VColors.textHi)),
      subtitle: Text('${r.dataFmt}  ·  ${r.km} km',
          style: const TextStyle(color: VColors.textFaint, fontSize: 12)),
    );
  }
}
