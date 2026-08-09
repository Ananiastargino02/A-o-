import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  static final _currencyFormat = NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$',
    decimalDigits: 2,
  );

  static String currency(num value) => _currencyFormat.format(value);

  static String km(double value) {
    if (value < 1) return '${(value * 1000).round()} m';
    return '${value.toStringAsFixed(value < 10 ? 1 : 0)} km';
  }

  static String phoneDisplay(String e164) {
    // Espera formato +55DDXXXXXXXXX
    final digits = e164.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 12) return e164;
    final semPais = digits.substring(digits.length - 11);
    final ddd = semPais.substring(0, 2);
    final resto = semPais.substring(2);
    if (resto.length == 9) {
      return '($ddd) ${resto.substring(0, 5)}-${resto.substring(5)}';
    }
    return '($ddd) ${resto.substring(0, 4)}-${resto.substring(4)}';
  }

  static String tempoRelativoMin(int minutos) {
    if (minutos < 1) return 'menos de 1 min';
    if (minutos < 60) return '$minutos min';
    final horas = minutos ~/ 60;
    return '${horas}h${minutos % 60 > 0 ? ' ${minutos % 60}min' : ''}';
  }
}
