import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Registra o CONSUMO de combustivel a partir do hodometro (km) e do nivel do
/// tanque (%) que o aparelho manda no STATUS.
///
/// O VEICAN nao le vazao direta, entao o consumo e ESTIMADO:
///   litros gastos = (% de tanque gasto / 100) x capacidade do tanque
///   km/L          = km rodados / litros gastos
///
/// Reabastecimento e detectado quando o nivel SOBE (nesse passo nao conta gasto).
class ConsumptionStore {
  static const _kDaily = 'consumo_daily_v1';
  static const _kState = 'consumo_state_v1';
  static const _kTank = 'consumo_tank_l';

  final Map<String, _Dia> _daily = {};
  int _lastKm = -1;
  int _lastFuel = -1;
  double tankLiters = 50; // capacidade do tanque em litros (editavel)
  bool _loaded = false;

  Future<void> _ensure() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kDaily);
    if (s != null) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        _daily
          ..clear()
          ..addAll(m.map((k, v) => MapEntry(k, _Dia.fromJson(v as Map<String, dynamic>))));
      } catch (_) {}
    }
    final st = p.getString(_kState);
    if (st != null) {
      try {
        final m = jsonDecode(st) as Map<String, dynamic>;
        _lastKm = (m['km'] as num?)?.toInt() ?? -1;
        _lastFuel = (m['fuel'] as num?)?.toInt() ?? -1;
      } catch (_) {}
    }
    tankLiters = p.getDouble(_kTank) ?? 50;
    _loaded = true;
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kDaily, jsonEncode(_daily.map((k, v) => MapEntry(k, v.toJson()))));
    await p.setString(_kState, jsonEncode({'km': _lastKm, 'fuel': _lastFuel}));
  }

  static String chaveDia(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> carregar() => _ensure();

  Future<void> setTank(double litros) async {
    await _ensure();
    tankLiters = litros.clamp(20, 200).toDouble();
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kTank, tankLiters);
  }

  /// Alimenta com uma leitura (km do hodometro, nivel do tanque %). Grava so
  /// quando algo muda de verdade -> pouca escrita (o app le ~1x/seg).
  Future<void> record(int km, int fuel) async {
    await _ensure();
    if (km <= 0 || fuel < 0) return;
    final hoje = chaveDia(DateTime.now());
    final dia = _daily.putIfAbsent(hoje, () => _Dia());
    bool mudou = false;

    if (_lastKm >= 0 && _lastFuel >= 0) {
      final dkm = km - _lastKm;
      final dfuel = fuel - _lastFuel; // > 0 => abasteceu
      // distancia: aceita so avanco plausivel (rejeita reset/glitch do hodometro)
      if (dkm > 0 && dkm < 500) {
        dia.km += dkm;
        mudou = true;
      }
      // gasto: so quando NAO abasteceu e a queda e plausivel (<=25% num passo)
      if (dfuel <= 1) {
        final gasto = _lastFuel - fuel;
        if (gasto > 0 && gasto <= 25) {
          dia.fuelPct += gasto;
          mudou = true;
        }
      }
    }
    if (dia.level != fuel) {
      dia.level = fuel;
      mudou = true;
    }

    _lastKm = km;
    _lastFuel = fuel;
    if (mudou) await _save();
  }

  Future<void> limpar() async {
    _daily.clear();
    _lastKm = -1;
    _lastFuel = -1;
    _loaded = true;
    await _save();
  }

  // -------- consultas p/ os graficos --------

  /// km/L de cada um dos ultimos [n] dias (0 onde nao houve dado suficiente).
  Future<List<ConsumoPoint>> kmPorLitroDia({int n = 14}) async {
    await _ensure();
    final hoje = DateTime.now();
    final out = <ConsumoPoint>[];
    for (int i = n - 1; i >= 0; i--) {
      final d = DateTime(hoje.year, hoje.month, hoje.day).subtract(Duration(days: i));
      final dia = _daily[chaveDia(d)];
      out.add(ConsumoPoint('${d.day}/${d.month}', _kmL(dia), d));
    }
    return out;
  }

  /// km/L por mes (ultimos [n] meses).
  Future<List<ConsumoPoint>> kmPorLitroMes({int n = 6}) async {
    await _ensure();
    const meses = ['', 'jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
    final hoje = DateTime.now();
    final out = <ConsumoPoint>[];
    for (int i = n - 1; i >= 0; i--) {
      final ref = DateTime(hoje.year, hoje.month - i, 1);
      double km = 0, litros = 0;
      _daily.forEach((k, v) {
        final p = k.split('-');
        if (int.parse(p[0]) == ref.year && int.parse(p[1]) == ref.month) {
          km += v.km;
          litros += v.fuelPct / 100 * tankLiters;
        }
      });
      final kmL = litros > 0.2 ? km / litros : 0.0;
      out.add(ConsumoPoint('${meses[ref.month]}/${ref.year % 100}', kmL, ref));
    }
    return out;
  }

  /// Nivel do tanque (%) de cada um dos ultimos [n] dias (ultima leitura do dia).
  Future<List<ConsumoPoint>> nivelDia({int n = 14}) async {
    await _ensure();
    final hoje = DateTime.now();
    final out = <ConsumoPoint>[];
    for (int i = n - 1; i >= 0; i--) {
      final d = DateTime(hoje.year, hoje.month, hoje.day).subtract(Duration(days: i));
      final dia = _daily[chaveDia(d)];
      out.add(ConsumoPoint('${d.day}/${d.month}', (dia?.level ?? 0).toDouble(), d));
    }
    return out;
  }

  /// Resumo geral: media km/L, total de km e de litros considerados.
  Future<ConsumoResumo> resumo() async {
    await _ensure();
    double km = 0, litros = 0;
    _daily.forEach((_, d) {
      km += d.km;
      litros += d.fuelPct / 100 * tankLiters;
    });
    final media = litros > 0.2 ? km / litros : 0.0;
    return ConsumoResumo(media, km, litros, tankLiters);
  }

  double _kmL(_Dia? d) {
    if (d == null) return 0;
    final litros = d.fuelPct / 100 * tankLiters;
    if (litros < 0.05) return 0;
    return d.km / litros;
  }
}

class _Dia {
  double km = 0;       // km rodados no dia
  double fuelPct = 0;  // % de tanque gasto no dia
  int level = 0;       // ultimo nivel do tanque no dia (%)
  _Dia();
  _Dia.fromJson(Map<String, dynamic> j)
      : km = (j['km'] as num?)?.toDouble() ?? 0,
        fuelPct = (j['f'] as num?)?.toDouble() ?? 0,
        level = (j['l'] as num?)?.toInt() ?? 0;
  Map<String, dynamic> toJson() => {'km': km, 'f': fuelPct, 'l': level};
}

/// Ponto de grafico (rotulo + valor + data de referencia).
class ConsumoPoint {
  final String rotulo;
  final double valor;
  final DateTime ref;
  ConsumoPoint(this.rotulo, this.valor, this.ref);
}

class ConsumoResumo {
  final double mediaKmL;
  final double totalKm;
  final double totalLitros;
  final double tankLiters;
  ConsumoResumo(this.mediaKmL, this.totalKm, this.totalLitros, this.tankLiters);

  /// Autonomia estimada (km) para um nivel de tanque atual (%).
  double autonomia(int fuelPct) {
    if (mediaKmL <= 0 || fuelPct <= 0) return 0;
    return mediaKmL * (fuelPct / 100 * tankLiters);
  }
}
