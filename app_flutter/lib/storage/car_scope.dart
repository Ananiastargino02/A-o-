import 'package:shared_preferences/shared_preferences.dart';

/// Escopo do CARRO ATIVO.
///
/// Tudo que o app salva (perfil, manutencao, consertos, velocidade, consumo)
/// usa uma chave que termina com o ID do carro ativo. Ao TROCAR de carro, gera
/// um ID novo e apaga os dados do anterior -> os dados nunca "embolam" entre
/// carros; fica so o do carro cadastrado.
class CarScope {
  static const _kActive = 'active_car_id';
  static String _id = 'default';

  static String get id => _id;

  /// Carrega o carro ativo (cria um ID na primeira vez). Chame no boot do app.
  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    var id = p.getString(_kActive);
    if (id == null || id.isEmpty) {
      id = _novoId();
      await p.setString(_kActive, id);
    }
    _id = id;
  }

  /// Prefixo/etiqueta do carro numa chave base.
  static String key(String base) => '${base}__$_id';

  static String _novoId() =>
      'c${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

  /// Troca para um carro NOVO: apaga TODOS os dados do carro atual
  /// (chaves terminadas em __<id>) e ativa um ID novo e vazio.
  static Future<void> trocarCarro() async {
    final p = await SharedPreferences.getInstance();
    final sufixo = '__$_id';
    for (final k in p.getKeys().where((k) => k.endsWith(sufixo)).toList()) {
      await p.remove(k);
    }
    final novo = _novoId();
    await p.setString(_kActive, novo);
    _id = novo;
  }
}
