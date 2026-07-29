import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../ble/ble_service.dart';
import '../models/maintenance.dart';
import '../models/maint_config.dart';
import '../storage/local_store.dart';
import '../theme.dart';

/// Manutencao MANTIDA PELO APP (por carro): 10 itens com km/dias editaveis,
/// numeracoes (oleo/correia/oleo cambio), historico e ESTIMATIVA de quando vence
/// (pela media de rodagem). Usa o odometro ao vivo do VEICAN.
class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});
  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  final _store = LocalStore();
  MaintConfig _cfg = MaintConfig.padrao();
  List<MaintRecord> _hist = [];
  int _kmAtual = 0;
  double _kmDia = 0;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _recarregar();
  }

  Future<void> _recarregar() async {
    setState(() => _carregando = true);
    final ble = context.read<BleService>();
    final cfg = await _store.loadMaintConfig();
    int km;
    if (ble.conectado && (ble.live?.km ?? 0) > 0) {
      km = ble.live!.km;
      await _store.registrarKm(km); // alimenta a media de rodagem
    } else {
      km = await _store.ultimoKm();
    }
    final kmDia = await _store.kmPorDia();
    final hist = await _store.loadHistory();
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      _kmAtual = km;
      _kmDia = kmDia;
      _hist = hist;
      _carregando = false;
    });
  }

  List<MaintStatus> get _status => [
        for (int i = 0; i < _cfg.itens.length; i++)
          MaintStatus.calcular(indice: i, item: _cfg.itens[i], kmAtual: _kmAtual, kmPorDia: _kmDia),
      ];

  Future<void> _salvar() async => _store.saveMaintConfig(_cfg);

  Future<void> _editarIntervalo(int i) async {
    final ble = context.read<BleService>();
    final it = _cfg.itens[i];
    final kmCtrl = TextEditingController(text: it.intervaloKm > 0 ? it.intervaloKm.toString() : '');
    final diasCtrl = TextEditingController(text: it.intervaloDias > 0 ? it.intervaloDias.toString() : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: VColors.card,
        title: Text('Intervalo · ${MaintConfig.nomes[i]}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: kmCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Trocar a cada (km)')),
          TextField(controller: diasCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Ou a cada (dias, opcional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    it.intervaloKm = int.tryParse(kmCtrl.text) ?? 0;
    it.intervaloDias = int.tryParse(diasCtrl.text) ?? 0;
    await _salvar();
    // manda pro aparelho tambem (os itens que ele conhece); fora da faixa ele ignora
    if (ble.conectado) {
      await ble.enviar('MANUT KM $i ${it.intervaloKm}');
      if (it.intervaloDias > 0) await ble.enviar('MANUT DIAS $i ${it.intervaloDias}');
    }
    _recarregar();
  }

  Future<void> _resetar(int i) async {
    final ble = context.read<BleService>();
    final ok = await _confirmar('Registrar troca · ${MaintConfig.nomes[i]}?',
        'Marca que foi feita AGORA ($_kmAtual km) e zera o contador.');
    if (ok != true) return;
    _cfg.itens[i].kmUltima = _kmAtual;
    _cfg.itens[i].dataUltima = DateTime.now();
    await _salvar();
    await _store.addHistory(MaintRecord(item: MaintConfig.nomes[i], data: DateTime.now(), km: _kmAtual));
    if (ble.conectado) await ble.enviar('MANUT RESET $i');
    _recarregar();
  }

  Future<void> _editarNumeracoes() async {
    final oleo = TextEditingController(text: _cfg.numOleoMotor);
    final correia = TextEditingController(text: _cfg.numCorreia);
    final cambio = TextEditingController(text: _cfg.numOleoCambio);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: VColors.card,
        title: const Text('Numeracoes (o que comprar)'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: oleo, decoration: const InputDecoration(labelText: 'Oleo do motor (ex.: 5W30 SN)')),
            TextField(controller: correia, decoration: const InputDecoration(labelText: 'Correia dentada (numeracao)')),
            TextField(controller: cambio, decoration: const InputDecoration(labelText: 'Oleo do cambio (numeracao)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    _cfg.numOleoMotor = oleo.text.trim();
    _cfg.numCorreia = correia.text.trim();
    _cfg.numOleoCambio = cambio.text.trim();
    await _salvar();
    setState(() {});
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
        actions: [IconButton(onPressed: _recarregar, icon: const Icon(Icons.refresh, size: 20))],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: VColors.cyan))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _resumo(),
                const SizedBox(height: 12),
                ..._status.map(_itemCard),
                const SizedBox(height: 8),
                _numeracoesCard(),
                const SizedBox(height: 20),
                Row(children: [
                  const Text('HISTORICO', style: TextStyle(color: VColors.textDim, letterSpacing: 2, fontSize: 13)),
                  const Spacer(),
                  if (_hist.isNotEmpty)
                    TextButton(
                        onPressed: () async {
                          final ok = await _confirmar('Limpar historico?', 'Apaga o historico salvo no celular.');
                          if (ok == true) {
                            await _store.clearHistory();
                            _recarregar();
                          }
                        },
                        child: const Text('Limpar')),
                ]),
                if (_hist.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Nenhuma manutencao registrada ainda.', style: TextStyle(color: VColors.textFaint)),
                  )
                else
                  ..._hist.map(_histTile),
              ],
            ),
    );
  }

  Widget _resumo() {
    final txtKm = _kmAtual > 0 ? '$_kmAtual km' : '-- km';
    final txtRod = _kmDia > 0.1 ? '~${(_kmDia * 7).round()} km/semana' : 'rode um pouco p/ estimar';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VColors.line, width: 1.2),
      ),
      child: Row(children: [
        const Icon(Icons.route, color: VColors.violet, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ODOMETRO  $txtKm', style: const TextStyle(color: VColors.textHi, fontWeight: FontWeight.w700)),
            Text('Media de rodagem: $txtRod', style: const TextStyle(color: VColors.textFaint, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  Widget _itemCard(MaintStatus s) {
    final cor = s.vencido ? VColors.red : (s.proximo ? VColors.amber : VColors.blue);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(s.nome, style: TextStyle(color: cor, fontSize: 16, fontWeight: FontWeight.w600))),
            Text(s.vencido ? 'VENCIDO' : '${s.percentual}%', style: TextStyle(color: cor, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (s.percentual / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: VColors.cardHi,
              color: cor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
              'A cada ${s.intervaloKm > 0 ? "${s.intervaloKm} km" : ""}'
              '${s.intervaloKm > 0 && s.intervaloDias > 0 ? " / " : ""}'
              '${s.intervaloDias > 0 ? "${s.intervaloDias} dias" : ""}',
              style: const TextStyle(color: VColors.textFaint, fontSize: 12)),
          const SizedBox(height: 4),
          _estimativa(s, cor),
          const SizedBox(height: 6),
          Row(children: [
            const Spacer(),
            TextButton(onPressed: () => _editarIntervalo(s.indice), child: const Text('Intervalo')),
            FilledButton(onPressed: () => _resetar(s.indice), child: const Text('Troquei')),
          ]),
        ]),
      ),
    );
  }

  /// Linha de estimativa: "Estimativa: faltam X km · ~Y semanas · DD/MM/AAAA"
  Widget _estimativa(MaintStatus s, Color cor) {
    if (s.vencido) {
      return Row(children: [
        const Icon(Icons.warning_amber_rounded, color: VColors.red, size: 16),
        const SizedBox(width: 6),
        const Text('Vencido — fazer o quanto antes', style: TextStyle(color: VColors.red, fontSize: 12)),
      ]);
    }
    final partes = <String>[];
    if (s.intervaloKm > 0 && s.kmRestante > 0) partes.add('faltam ${s.kmRestante} km');
    if (s.diasRestantes != null && s.diasRestantes! > 0) {
      final sem = (s.diasRestantes! / 7).round();
      partes.add(sem >= 1 ? '~$sem sem' : '${s.diasRestantes} dias');
    }
    if (s.dataPrevista != null) partes.add('prev. ${DateFormat('dd/MM/yyyy').format(s.dataPrevista!)}');
    if (partes.isEmpty) return const SizedBox.shrink();
    return Row(children: [
      const Icon(Icons.event_available, color: VColors.textDim, size: 15),
      const SizedBox(width: 6),
      Expanded(child: Text(partes.join(' · '), style: const TextStyle(color: VColors.textDim, fontSize: 12))),
    ]);
  }

  Widget _numeracoesCard() {
    Widget linha(String rot, String val) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 92, child: Text(rot, style: const TextStyle(color: VColors.textFaint, fontSize: 12))),
            Expanded(child: Text(val.isEmpty ? '—' : val, style: TextStyle(color: val.isEmpty ? VColors.textFaint : VColors.textHi, fontSize: 13, fontWeight: FontWeight.w600))),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.receipt_long, color: VColors.cyan, size: 18),
            const SizedBox(width: 8),
            const Text('NUMERACOES (o que comprar)', style: TextStyle(color: VColors.textDim, fontSize: 12, letterSpacing: 1)),
            const Spacer(),
            TextButton(onPressed: _editarNumeracoes, child: const Text('Editar')),
          ]),
          const SizedBox(height: 4),
          linha('Oleo motor', _cfg.numOleoMotor),
          linha('Correia', _cfg.numCorreia),
          linha('Oleo cambio', _cfg.numOleoCambio),
        ]),
      ),
    );
  }

  Widget _histTile(MaintRecord r) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.check_circle_outline, color: VColors.green, size: 20),
      title: Text(r.item, style: const TextStyle(color: VColors.textHi)),
      subtitle: Text('${r.dataFmt}  ·  ${r.km} km', style: const TextStyle(color: VColors.textFaint, fontSize: 12)),
    );
  }
}
