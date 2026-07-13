import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble/ble_service.dart';
import '../storage/speed_store.dart';
import '../theme.dart';

enum _Periodo { dia, mes, ano }

class SpeedHistoryScreen extends StatefulWidget {
  const SpeedHistoryScreen({super.key});
  @override
  State<SpeedHistoryScreen> createState() => _SpeedHistoryScreenState();
}

class _SpeedHistoryScreenState extends State<SpeedHistoryScreen> {
  final _store = SpeedStore();
  Map<String, int> _daily = {};
  MapEntry<int, DateTime>? _recorde;
  _Periodo _periodo = _Periodo.dia;
  bool _carregando = true;

  static const _meses = [
    '', 'janeiro', 'fevereiro', 'marco', 'abril', 'maio', 'junho',
    'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'
  ];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final d = await _store.daily();
    final rec = await _store.recorde();
    if (!mounted) return;
    setState(() {
      _daily = d;
      _recorde = rec;
      _carregando = false;
    });
  }

  List<SpeedPoint> get _pontos {
    switch (_periodo) {
      case _Periodo.dia:
        return SpeedAgg.porDia(_daily, n: 14);
      case _Periodo.mes:
        return SpeedAgg.porMes(_daily, n: 12);
      case _Periodo.ano:
        return SpeedAgg.porAno(_daily);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VELOCIDADE'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Limpar historico',
            onPressed: _confirmarLimpar,
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: VColors.cyan))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _recordeBanner(),
                const SizedBox(height: 16),
                _toggle(),
                const SizedBox(height: 16),
                _grafico(),
                const SizedBox(height: 20),
                _listaTitulo(),
                const SizedBox(height: 8),
                ..._listaItens(),
              ],
            ),
    );
  }

  Widget _recordeBanner() {
    final r = _recorde;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [VColors.red.withValues(alpha: 0.20), VColors.card],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VColors.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: VColors.red, size: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('RECORDE DE VELOCIDADE',
                    style: TextStyle(color: VColors.textDim, letterSpacing: 1.5, fontSize: 12)),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(r != null ? '${r.key}' : '--',
                        style: const TextStyle(
                            color: VColors.textHi, fontSize: 40, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    const Text('km/h', style: TextStyle(color: VColors.textFaint)),
                  ],
                ),
                if (r != null)
                  Text(
                      'em ${r.value.day.toString().padLeft(2, '0')} de ${_meses[r.value.month]} de ${r.value.year}',
                      style: const TextStyle(color: VColors.textDim, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggle() {
    return SegmentedButton<_Periodo>(
      segments: const [
        ButtonSegment(value: _Periodo.dia, label: Text('Dia')),
        ButtonSegment(value: _Periodo.mes, label: Text('Mes')),
        ButtonSegment(value: _Periodo.ano, label: Text('Ano')),
      ],
      selected: {_periodo},
      onSelectionChanged: (s) => setState(() => _periodo = s.first),
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((st) =>
            st.contains(WidgetState.selected) ? VColors.cyan : VColors.card),
        foregroundColor: WidgetStateProperty.resolveWith((st) =>
            st.contains(WidgetState.selected) ? Colors.black : VColors.textDim),
      ),
    );
  }

  Widget _grafico() {
    final pts = _pontos;
    final temDado = pts.any((p) => p.velocidade > 0);
    if (!temDado) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: VColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: VColors.line),
        ),
        child: const Text('Sem dados ainda.\nDirija com o app conectado.',
            textAlign: TextAlign.center, style: TextStyle(color: VColors.textFaint)),
      );
    }
    final maxV = pts.map((p) => p.velocidade).reduce((a, b) => a > b ? a : b);
    final topo = ((maxV / 20).ceil() * 20 + 20).toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
      decoration: BoxDecoration(
        color: VColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VColors.line),
      ),
      child: SizedBox(
        height: 220,
        child: BarChart(
          BarChartData(
            maxY: topo,
            alignment: BarChartAlignment.spaceAround,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (v) => const FlLine(color: VColors.line, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  getTitlesWidget: (v, meta) => Text('${v.toInt()}',
                      style: const TextStyle(color: VColors.textFaint, fontSize: 10)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (i < 0 || i >= pts.length) return const SizedBox();
                    // em "dia" mostra so alguns rotulos p/ nao poluir
                    if (_periodo == _Periodo.dia && pts.length > 8 && i % 2 != 0) {
                      return const SizedBox();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(pts[i].rotulo,
                          style: const TextStyle(color: VColors.textFaint, fontSize: 9)),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (int i = 0; i < pts.length; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                    toY: pts[i].velocidade.toDouble(),
                    width: 14,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    color: pts[i].velocidade >= 120 ? VColors.red : VColors.cyan,
                  ),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listaTitulo() {
    const t = {
      _Periodo.dia: 'POR DIA',
      _Periodo.mes: 'POR MES',
      _Periodo.ano: 'POR ANO',
    };
    return Text('MAXIMA ${t[_periodo]}',
        style: const TextStyle(color: VColors.textDim, letterSpacing: 2, fontSize: 13));
  }

  List<Widget> _listaItens() {
    final pts = _pontos.where((p) => p.velocidade > 0).toList().reversed.toList();
    if (pts.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Nada registrado ainda.', style: TextStyle(color: VColors.textFaint)),
        )
      ];
    }
    return pts.map((p) {
      final cor = p.velocidade >= 120 ? VColors.red : VColors.textHi;
      return ListTile(
        dense: true,
        leading: Icon(Icons.speed, color: cor, size: 20),
        title: Text(_rotuloLongo(p), style: const TextStyle(color: VColors.textHi)),
        trailing: Text('${p.velocidade} km/h',
            style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 16)),
      );
    }).toList();
  }

  String _rotuloLongo(SpeedPoint p) {
    switch (_periodo) {
      case _Periodo.dia:
        return '${p.ref.day.toString().padLeft(2, '0')}/${p.ref.month.toString().padLeft(2, '0')}/${p.ref.year}';
      case _Periodo.mes:
        return '${_meses[p.ref.month]} de ${p.ref.year}';
      case _Periodo.ano:
        return '${p.ref.year}';
    }
  }

  void _confirmarLimpar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: VColors.card,
        title: const Text('Limpar historico de velocidade?'),
        content: const Text('Apaga todos os registros de velocidade (inclusive o recorde).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: VColors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Limpar')),
        ],
      ),
    );
    if (ok == true) {
      await _store.limpar();
      // zera os caches do servico tambem
      final ble = context.mounted ? context.read<BleService>() : null;
      ble?.speedMaxHoje = 0;
      ble?.speedRecorde = 0;
      ble?.speedRecordeData = null;
      _carregar();
    }
  }
}
