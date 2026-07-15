import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/dashboard_style.dart';

/// Configuracoes do app (por enquanto: o estilo do painel principal).
class AppSettings extends ChangeNotifier {
  static const _kDash = 'dash_style';

  DashboardStyle _dash = DashboardStyle.modern;
  DashboardStyle get dash => _dash;

  AppSettings() {
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _dash = DashboardStyleX.fromChave(p.getString(_kDash));
    notifyListeners();
  }

  Future<void> setDash(DashboardStyle s) async {
    _dash = s;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDash, s.chave);
  }
}
