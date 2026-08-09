import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pedido_model.dart';
import '../models/orcamento_model.dart';
import 'services_providers.dart';
import 'auth_provider.dart';

/// Pedidos do cliente logado, mais recentes primeiro.
final meusPedidosProvider = StreamProvider<List<PedidoModel>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value([]);
  return ref.watch(firestoreServiceProvider).watchPedidosDoCliente(uid);
});

final pedidoProvider = StreamProvider.family<PedidoModel?, String>((ref, pedidoId) {
  return ref.watch(firestoreServiceProvider).watchPedido(pedidoId);
});

/// Orcamentos recebidos para um pedido, ordenados pela ordem de chegada.
/// A ordenacao por preco/distancia (pedida na tela de orcamentos) e feita
/// na UI, que tem acesso a lista completa em memoria.
final orcamentosDoPedidoProvider =
    StreamProvider.family<List<OrcamentoModel>, String>((ref, pedidoId) {
  return ref.watch(firestoreServiceProvider).watchOrcamentosDoPedido(pedidoId);
});

enum OrdenacaoOrcamentos { menorPreco, maisPerto }

final ordenacaoOrcamentosProvider =
    StateProvider<OrdenacaoOrcamentos>((ref) => OrdenacaoOrcamentos.menorPreco);
