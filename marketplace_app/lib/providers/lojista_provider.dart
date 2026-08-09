import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_config.dart';
import '../core/utils/distance_utils.dart';
import '../models/pedido_model.dart';
import '../models/loja_model.dart';
import 'services_providers.dart';
import 'auth_provider.dart';

class PedidoComDistancia {
  final PedidoModel pedido;
  final double distanciaKm;
  const PedidoComDistancia({required this.pedido, required this.distanciaKm});
}

/// Feed do lojista: pedidos abertos da categoria, dentro do raio de
/// atendimento da loja, que ela ainda nao recusou. Mais recentes primeiro.
final feedPedidosLojistaProvider = StreamProvider<List<PedidoComDistancia>>((ref) async* {
  final loja = ref.watch(currentLojaProvider).value;
  if (loja == null) {
    yield [];
    return;
  }

  await for (final pedidos in ref
      .watch(firestoreServiceProvider)
      .watchPedidosAbertosPorCategoria(AppConfig.categoriaPecasAutomotivas)) {
    final filtrados = pedidos.where((p) => !p.recusadoPor.contains(loja.id)).map((p) {
      final distancia = DistanceUtils.km(
        lat1: loja.lat,
        lng1: loja.lng,
        lat2: p.lat,
        lng2: p.lng,
      );
      return PedidoComDistancia(pedido: p, distanciaKm: distancia);
    }).where((pd) => pd.distanciaKm <= loja.raioKm).toList()
      ..sort((a, b) => b.pedido.criadoEm.compareTo(a.pedido.criadoEm));
    yield filtrados;
  }
});

final lojaPorIdProvider = FutureProvider.family<LojaModel?, String>((ref, lojaId) {
  return ref.watch(firestoreServiceProvider).getLoja(lojaId);
});

/// Chama a Cloud Function `obterMetricasLoja` (ver firebase/functions/src/metrics.js).
final metricasDoMesProvider = FutureProvider<Map<String, int>>((ref) async {
  final loja = ref.watch(currentLojaProvider).value;
  if (loja == null) {
    return {
      'pedidosRecebidos': 0,
      'orcamentosEnviados': 0,
      'chatsAbertos': 0,
      'vendasConfirmadas': 0,
    };
  }
  return ref.watch(functionsServiceProvider).obterMetricasLoja();
});
