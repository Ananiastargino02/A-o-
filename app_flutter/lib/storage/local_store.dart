import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/car_profile.dart';
import '../models/maintenance.dart';
import 'car_scope.dart';

/// Persistencia local no celular. Perfil e historico de manutencao sao POR CARRO
/// (CarScope). O ultimo aparelho conectado e global (do celular).
class LocalStore {
  static String get _kProfile => CarScope.key('car_profile');
  static String get _kHistory => CarScope.key('maint_history');
  static String get _kManut => CarScope.key('manut_cache');   // ultima MANUT LIST (offline)
  static const _kLastDevice = 'last_device_id';

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
