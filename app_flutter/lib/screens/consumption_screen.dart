import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble/ble_service.dart';
import '../storage/consumption_store.dart';
import '../theme.dart';

enum _Metrica { consumo, nivel }
enum _Periodo { dia, mes }

/// Graficos de CONSUMO de combustivel: km/L por dia/mes e nivel do tanque.
class ConsumptionScreen extends StatefulWidget {
  const ConsumptionScreen({super.key});
  @override
  State<ConsumptionScreen> createState() => _ConsumptionScreenState();
}

class _ConsumptionScreenState extends State<ConsumptionScreen> {
  ConsumptionStore get _store => context.read<BleService>().consumoStore;

  _Metrica _metrica = _Metrica.consumo;
  _Periodo _periodo = _Periodo.dia;
  List<ConsumoPoint> _pontos = [];
  ConsumoResumo? _resumo;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final resumo = await _store.resumo();
    final pontos = await _pontosAtuais();
    if (!mounted) return;
    setState(() {
      _resumo = resumo;
      _pontos = pontos;
      _carregando = false;
    });
  }

  Future<List<ConsumoPoint>> _pontosAtuais() {
    if (_metrica == _Metrica.nivel) return _store.nivelDia(n: 14);
    return _periodo == _Periodo.dia
        ? _store.kmPorLitroDia(n: 14)
        : _store.kmPorLitroMes(n: 6);
  }

  Future<void> _recarregarPontos() async {
    final pontos = await _pontosAtuais();
    if (!mounted) return;
    setState(() => _pontos = pontos);
  }

  bool get _isNivel => _metrica == _Metrica.nivel;
  Color get _cor => _isNivel ? VColors.amber : VColors.green;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CONSUMO'),
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
                _resumoBanner(),
                const SizedBox(height: 16),
                _seletorMetrica(),
                if (!_isNivel) ...[
                  const SizedBox(height: 12),
                  _seletorPeriodo(),
                ],
                const SizedBox(height: 16),
                _grafico(),
                const SizedBox(height: 20),
                _lista(),
              ],
            ),
    );
  }

  // ---------- banner de resumo ----------
  Widget _resumoBanner() {
    final r = _resumo;
    final ble = context.watch<BleService>();
    final fuel = ble.live?.combustivel ?? 0;
    final media = (r != null && r.mediaKmL > 0) ? r.mediaKmL : null;
    final autonomia = (r != null) ? r.autonomia(fuel) : 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [VColors.green.withValues(alpha: 0.18), VColors.card],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VColors.green.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('MEDIA DE CONSUMO',
              style: TextStyle(color: VColors.textDim, letterSpacing: 1.5, fontSize: 12)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(media != null ? media.toStringAsFixed(1) : '--',
                  style: const TextStyle(
                      color: VColors.textHi, fontSize: 40, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              const Text('km/L', style: TextStyle(color: VColors.textFaint)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _mini('AUTONOMIA',
                    autonomia > 0 ? '${autonomia.round()} km' : '--',
                    Icons.route),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: _editarTanque,
                  child: _mini('TANQUE',
                      '${(r?.tankLiters ?? 50).round()} L  ✎', Icons.local_gas_station),
                ),
              ),
            ],
          ),
          if (media == null)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                  'Rode alguns km com o app conectado para a media aparecer.',
                  style: TextStyle(color: VColors.textFaint, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _mini(String rot, String val, IconData ic) {
    return Row(
      children: [
        Icon(ic, color: VColors.green, size: 18),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rot, style: const TextStyle(color: VColors.textFaint, fontSize: 10, letterSpacing: 1)),
            Text(val, style: const TextStyle(color: VColors.textHi, fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }

  // ---------- seletores ----------
  Widget _seletorMetrica() {
    return SegmentedButton<_Metrica>(
      segments: const [
        ButtonSegment(value: _Metrica.consumo, label: Text('Consumo km/L')),
        ButtonSegment(value: _Metrica.nivel, label: Text('Nivel do tanque')),
      ],
      selected: {_metrica},
      onSelectionChanged: (s) {
        setState(() => _metrica = s.first);
        _recarregarPontos();
      },
      style: _estiloSeg(),
    );
  }

  Widget _seletorPeriodo() {
    return SegmentedButton<_Periodo>(
      segments: const [
        ButtonSegment(value: _Periodo.dia, label: Text('Dia')),
        ButtonSegment(value: _Periodo.mes, label: Text('Mes')),
      ],
      selected: {_periodo},
      onSelectionChanged: (s) {
        setState(() => _periodo = s.first);
        _recarregarPontos();
      },
      style: _estiloSeg(),
    );
  }

  ButtonStyle _estiloSeg() => ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((st) =>
            st.contains(WidgetState.selected) ? VColors.cyan : VColors.card),
        foregroundColor: WidgetStateProperty.resolveWith((st) =>
            st.contains(WidgetState.selected) ? Colors.black : VColors.textDim),
      );

  // ---------- grafico ----------
  Widget _grafico() {
    final temDado = _pontos.any((p) => p.valor > 0);
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
    final maxV = _pontos.map((p) => p.valor).reduce((a, b) => a > b ? a : b);
    final topo = _isNivel ? 100.0 : ((maxV / 5).ceil() * 5 + 5).toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
      decoration: BoxDecoration(
        color: VColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VColors.line),
      ),
      child: SizedBox(
        height: 220,
        child: _isNivel ? _linha(topo) : _barras(topo),
      ),
    );
  }

  Widget _barras(double topo) {
    return BarChart(
      BarChartData(
        maxY: topo,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => const FlLine(color: VColors.line, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: _titulos(suffix: ''),
        barGroups: [
          for (int i = 0; i < _pontos.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: _pontos[i].valor,
                width: 14,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                color: VColors.green,
              ),
            ]),
        ],
      ),
    );
  }

  Widget _linha(double topo) {
    return LineChart(
      LineChartData(
        maxY: topo,
        minY: 0,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => const FlLine(color: VColors.line, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: _titulos(suffix: '%'),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (int i = 0; i < _pontos.length; i++)
                FlSpot(i.toDouble(), _pontos[i].valor),
            ],
            isCurved: true,
            color: VColors.amber,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: VColors.amber.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }

  FlTitlesData _titulos({required String suffix}) {
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 34,
          getTitlesWidget: (v, meta) => Text('${v.toInt()}$suffix',
              style: const TextStyle(color: VColors.textFaint, fontSize: 10)),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          getTitlesWidget: (v, meta) {
            final i = v.toInt();
            if (i < 0 || i >= _pontos.length) return const SizedBox();
            if (_pontos.length > 8 && i % 2 != 0) return const SizedBox();
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_pontos[i].rotulo,
                  style: const TextStyle(color: VColors.textFaint, fontSize: 9)),
            );
          },
        ),
      ),
    );
  }

  // ---------- lista ----------
  Widget _lista() {
    final pts = _pontos.where((p) => p.valor > 0).toList().reversed.toList();
    final titulo = _isNivel
        ? 'NIVEL DO TANQUE POR DIA'
        : (_periodo == _Periodo.dia ? 'CONSUMO POR DIA' : 'CONSUMO POR MES');
    final unidade = _isNivel ? '%' : ' km/L';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo,
            style: const TextStyle(color: VColors.textDim, letterSpacing: 2, fontSize: 13)),
        const SizedBox(height: 8),
        if (pts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Nada registrado ainda.', style: TextStyle(color: VColors.textFaint)),
          )
        else
          ...pts.map((p) => ListTile(
                dense: true,
                leading: Icon(_isNivel ? Icons.local_gas_station : Icons.eco,
                    color: _cor, size: 20),
                title: Text(_rotuloLongo(p), style: const TextStyle(color: VColors.textHi)),
                trailing: Text(
                    '${_isNivel ? p.valor.round() : p.valor.toStringAsFixed(1)}$unidade',
                    style: TextStyle(color: _cor, fontWeight: FontWeight.bold, fontSize: 16)),
              )),
      ],
    );
  }

  static const _meses = [
    '', 'janeiro', 'fevereiro', 'marco', 'abril', 'maio', 'junho',
    'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'
  ];

  String _rotuloLongo(ConsumoPoint p) {
    if (!_isNivel && _periodo == _Periodo.mes) {
      return '${_meses[p.ref.month]} de ${p.ref.year}';
    }
    return '${p.ref.day.toString().padLeft(2, '0')}/${p.ref.month.toString().padLeft(2, '0')}/${p.ref.year}';
  }

  // ---------- acoes ----------
  Future<void> _editarTanque() async {
    final ctrl = TextEditingController(text: (_resumo?.tankLiters ?? 50).round().toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: VColors.card,
        title: const Text('Capacidade do tanque'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: VColors.textHi),
          decoration: const InputDecoration(
            suffixText: 'litros',
            helperText: 'Usado para estimar litros e km/L',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok == true) {
      final litros = double.tryParse(ctrl.text.replaceAll(',', '.'));
      if (litros != null && litros >= 20) {
        await _store.setTank(litros);
        _carregar();
      }
    }
  }

  void _confirmarLimpar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: VColors.card,
        title: const Text('Limpar historico de consumo?'),
        content: const Text('Apaga todos os registros de consumo e nivel do tanque.'),
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
      _carregar();
    }
  }
}
