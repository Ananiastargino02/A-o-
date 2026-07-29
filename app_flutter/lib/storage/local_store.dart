import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/car_profile.dart';
import '../models/maintenance.dart';
import '../models/maint_config.dart';
import 'car_scope.dart';

/// Persistencia local no celular. Perfil e historico de manutencao sao POR CARRO
/// (CarScope). O ultimo aparelho conectado e global (do celular).
class LocalStore {
  static String get _kProfile => CarScope.key('car_profile');
  static String get _kHistory => CarScope.key('maint_history');
  static String get _kManut => CarScope.key('manut_cache');   // ultima MANUT LIST (offline)
  static String get _kMaintCfg => CarScope.key('maint_config');   // config de manutencao (por carro)
  static String get _kKmSamples => CarScope.key('km_samples');    // amostras odometro p/ media de rodagem
  static const _kLastDevice = 'last_device_id';

  // ---- configuracao de manutencao (10 itens, numeracoes) POR CARRO ----
  Future<MaintConfig> loadMaintConfig() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kMaintCfg);
    if (s == null) return MaintConfig.padrao();
    try {
      return MaintConfig.fromJson(jsonDecode(s));
    } catch (_) {
      return MaintConfig.padrao();
    }
  }

  Future<void> saveMaintConfig(MaintConfig c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kMaintCfg, jsonEncode(c.toJson()));
  }

  // ---- amostras do odometro (km + data) p/ estimar km/dia ----
  // Guarda no maximo 1 amostra por dia; mantem ~60 amostras (2 meses).
  Future<void> registrarKm(int km) async {
    if (km <= 0) return;
    final p = await SharedPreferences.getInstance();
    final List list = jsonDecode(p.getString(_kKmSamples) ?? '[]');
    final agoraMs = DateTime.now().millisecondsSinceEpoch;
    if (list.isNotEmpty) {
      final ult = list.last as Map;
      final ultMs = (ult['t'] ?? 0) as int;
      // so grava se passou >12h desde a ultima OU o km mudou bastante
      if (agoraMs - ultMs < 12 * 3600 * 1000 && ((ult['km'] ?? 0) as int) == km) return;
      if (agoraMs - ultMs < 12 * 3600 * 1000) list.removeLast(); // substitui a do dia
    }
    list.add({'km': km, 't': agoraMs});
    if (list.length > 60) list.removeRange(0, list.length - 60);
    await p.setString(_kKmSamples, jsonEncode(list));
  }

  /// Ultimo odometro conhecido (da ultima amostra), p/ ver offline.
  Future<int> ultimoKm() async {
    final p = await SharedPreferences.getInstance();
    final List list = jsonDecode(p.getString(_kKmSamples) ?? '[]');
    if (list.isEmpty) return 0;
    return ((list.last as Map)['km'] ?? 0) as int;
  }

  /// Media de km por dia (0 se ainda nao da pra estimar).
  Future<double> kmPorDia() async {
    final p = await SharedPreferences.getInstance();
    final List list = jsonDecode(p.getString(_kKmSamples) ?? '[]');
    if (list.length < 2) return 0;
    final prim = list.first as Map, ult = list.last as Map;
    final dKm = ((ult['km'] ?? 0) as int) - ((prim['km'] ?? 0) as int);
    final dMs = ((ult['t'] ?? 0) as int) - ((prim['t'] ?? 0) as int);
    final dias = dMs / (24 * 3600 * 1000);
    if (dias < 0.5 || dKm <= 0) return 0;
    return dKm / dias;
  }

  /// Guarda a ultima lista de manutencao (texto cru) p/ ver offline.
  Future<void> saveManutCache(String raw) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kManut, raw);
  }

  Future<String> loadManutCache() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kManut) ?? '';
  }

  Future<CarProfile> loadProfile() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kProfile);
    if (s == null) return CarProfile();
    try {
      return CarProfile.fromJson(jsonDecode(s));
    } catch (_) {
      return CarProfile();
    }
  }

  Future<void> saveProfile(CarProfile c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kProfile, jsonEncode(c.toJson()));
  }

  Future<List<MaintRecord>> loadHistory() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kHistory);
    if (s == null) return [];
    try {
      final List list = jsonDecode(s);
      final recs = list.map((e) => MaintRecord.fromJson(e)).toList();
      recs.sort((a, b) => b.data.compareTo(a.data)); // mais recente primeiro
      return recs;
    } catch (_) {
      return [];
    }
  }

  Future<void> addHistory(MaintRecord r) async {
    final list = await loadHistory();
    list.insert(0, r);
    if (list.length > 200) list.removeRange(200, list.length);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kHistory, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  Future<void> clearHistory() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kHistory);
  }

  Future<String?> lastDeviceId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kLastDevice);
  }

  Future<void> saveLastDeviceId(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLastDevice, id);
  }
}
