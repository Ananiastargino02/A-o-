import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/repair.dart';

/// Persistencia dos consertos (metadados no shared_preferences, fotos em arquivo).
class RepairStore {
  static const _kRepairs = 'repairs_v1';

  Future<List<RepairRecord>> load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kRepairs);
    if (s == null) return [];
    try {
      final List list = jsonDecode(s);
      final recs = list.map((e) => RepairRecord.fromJson(e)).toList();
      recs.sort((a, b) => b.data.compareTo(a.data)); // mais recente primeiro
      return recs;
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<RepairRecord> recs) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kRepairs, jsonEncode(recs.map((e) => e.toJson()).toList()));
  }

  Future<void> upsert(RepairRecord r) async {
    final recs = await load();
    final i = recs.indexWhere((e) => e.id == r.id);
    if (i >= 0) {
      recs[i] = r;
    } else {
      recs.add(r);
    }
    await _saveAll(recs);
  }

  Future<void> remove(RepairRecord r) async {
    final recs = await load();
    recs.removeWhere((e) => e.id == r.id);
    await _saveAll(recs);
    // apaga as fotos do arquivo
    for (final f in r.fotos) {
      try {
        final file = File(f);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  /// Copia a foto capturada/escolhida para a pasta do app e devolve o caminho salvo.
  Future<String> savePhoto(String origem) async {
    final dir = await getApplicationDocumentsDirectory();
    final pasta = Directory('${dir.path}/consertos_fotos');
    if (!await pasta.exists()) await pasta.create(recursive: true);
    final ext = origem.contains('.') ? origem.split('.').last : 'jpg';
    final nome = '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final destino = File('${pasta.path}/$nome');
    await File(origem).copy(destino.path);
    return destino.path;
  }
}
