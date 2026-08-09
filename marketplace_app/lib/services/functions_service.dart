import 'package:cloud_functions/cloud_functions.dart';

/// Chamadas para as Cloud Functions callable (ver firebase/functions).
class FunctionsService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Metricas do card "Seu mês" (feed_pedidos/vendas_screen). Calculadas no
  /// servidor pela Cloud Function `obterMetricasLoja`.
  Future<Map<String, int>> obterMetricasLoja() async {
    final resultado = await _functions.httpsCallable('obterMetricasLoja').call();
    final data = Map<String, dynamic>.from(resultado.data as Map);
    return data.map((key, value) => MapEntry(key, (value as num).toInt()));
  }
}
