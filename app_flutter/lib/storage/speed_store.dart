import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'car_scope.dart';

/// Guarda a VELOCIDADE MAXIMA de cada dia (km/h), pra montar o historico
/// e o recorde. Chave = "yyyy-MM-dd", valor = maior velocidade do dia.
/// Os dados sao POR CARRO (CarScope).
class SpeedStore {
  static String get _k => CarScope.key('speed_daily_v1');
  Map<String, int> _daily = {};
  bool _loaded = false;

  /// Zera o cache em memoria (usar ao TROCAR de carro).
  void reset() {
    _daily = {};
    _loaded = false;
  }

  Future<void> _ensure() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_k);
    if (s != null) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        _daily = m.map((k, v) => MapEntry(k, (v as num).toInt()));
      } catch (_) {}
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, jsonEncode(_daily));
  }

  static String chaveDia(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Registra a velocidade atual. Retorna true se o maximo do dia AUMENTOU
  /// (so grava no disco quando muda -> pouca escrita).
  Future<bool> record(int v) async {
    if (v <= 0) return false;
    await _ensure();
    final hoje = chaveDia(DateTime.now());
    final atual = _daily[hoje] ?? 0;
    if (v > atual) {
      _daily[hoje] = v;
      await _save();
      return true;
    }
    return false;
  }

  Future<Map<String, int>> daily() async {
    await _ensure();
    return Map.from(_daily);
  }

  Future<int> maxHoje() async {
    await _ensure();
    return _daily[chaveDia(DateTime.now())] ?? 0;
  }

  /// Recorde de todos os tempos: (velocidade, data).
  Future<MapEntry<int, DateTime>?> recorde() async {
    await _ensure();
    if (_daily.isEmpty) return null;
    String melhorK = _daily.keys.first;
    int melhorV = _daily[melhorK]!;
    _daily.forEach((k, v) {
      if (v > melhorV) {
        melhorV = v;
        melhorK = k;
      }
    });
    return MapEntry(melhorV, DateTime.parse(melhorK));
  }

  Future<void> limpar() async {
    _daily = {};
    _loaded = true;
    await _save();
  }

  /// Junta o historico vindo do aparelho (comando SPEEDHIST): linhas "AAAAMMDD:vel".
  /// Pega o MAIOR entre o do aparelho e o local, por dia. Retorna quantos dias mudaram.
  Future<int> mergeDevice(String resp) async {
    await _ensure();
    int mudou = 0;
    for (final linha in resp.split('\n')) {
      final l = linha.trim();
      if (!l.contains(':')) continue;
      final p = l.split(':');
      final aaaammdd = int.tryParse(p[0]);
      final vel = int.tryParse(p[1]);
      if (aaaammdd == null || vel == null || vel <= 0) continue;
      if (aaaammdd < 20000101) continue; // ignora o cabecalho "SPEEDHIST n"
      final ano = aaaammdd ~/ 10000;
      final mes = (aaaammdd ~/ 100) % 100;
      final dia = aaaammdd % 100;
      final key =
          '$ano-${mes.toString().padLeft(2, '0')}-${dia.toString().padLeft(2, '0')}';
      if (vel > (_daily[key] ?? 0)) {
        _daily[key] = vel;
        mudou++;
      }
    }
    if (mudou > 0) await _save();
    return mudou;
  }
}

/// Um ponto do grafico (rotulo + velocidade + data de referencia).
class SpeedPoint {
  final String rotulo;
  final int velocidade;
  final DateTime ref;
  SpeedPoint(this.rotulo, this.velocidade, this.ref);
}

/// Agregacoes pro grafico (dia / mes / ano) a partir do mapa diario.
class SpeedAgg {
  /// Ultimos [n] dias (com ou sem dado -> 0), do mais antigo pro mais novo.
  static List<SpeedPoint> porDia(Map<String, int> daily, {int n = 14}) {
    final hoje = DateTime.now();
    final out = <SpeedPoint>[];
    for (int i = n - 1; i >= 0; i--) {
      final d = DateTime(hoje.year, hoje.month, hoje.day).subtract(Duration(days: i));
      final v = daily[SpeedStore.chaveDia(d)] ?? 0;
      out.add(SpeedPoint('${d.day}/${d.month}', v, d));
    }
    return out;
  }

  /// Maximo por mes (ultimos [n] meses).
  static List<SpeedPoint> porMes(Map<String, int> daily, {int n = 12}) {
    final byMonth = <String, int>{};
    daily.forEach((k, v) {
      final p = k.split('-'); // yyyy-MM-dd
      final chave = '${p[0]}-${p[1]}';
      if (v > (byMonth[chave] ?? 0)) byMonth[chave] = v;
    });
    final hoje = DateTime.now();
    const meses = ['', 'jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
    final out = <SpeedPoint>[];
    for (int i = n - 1; i >= 0; i--) {
      final d = DateTime(hoje.year, hoje.month - i, 1);
      final chave = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      out.add(SpeedPoint('${meses[d.month]}/${d.year % 100}', byMonth[chave] ?? 0, d));
    }
    return out;
  }

  /// Maximo por ano.
  static List<SpeedPoint> porAno(Map<String, int> daily) {
    final byYear = <String, int>{};
    daily.forEach((k, v) {
      final ano = k.split('-')[0];
      if (v > (byYear[ano] ?? 0)) byYear[ano] = v;
    });
    final anos = byYear.keys.toList()..sort();
    return anos
        .map((a) => SpeedPoint(a, byYear[a]!, DateTime(int.parse(a))))
        .toList();
  }
}
