import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/pedidos_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/pedido_card.dart';
import 'pedido_detalhe_router.dart';

class PedidosListScreen extends ConsumerWidget {
  const PedidosListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedidosAsync = ref.watch(meusPedidosProvider);

    final body = pedidosAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Erro: $e')),
      data: (pedidos) {
        if (pedidos.isEmpty) {
          return const EmptyState(
            icone: Icons.receipt_long_outlined,
            titulo: 'Nenhum pedido ainda',
            subtitulo: 'Seus pedidos de orçamento aparecem aqui.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: pedidos.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => PedidoCard(
            pedido: pedidos[i],
            onTap: () => abrirDetalheDoPedido(context, pedidos[i]),
          ),
        );
      },
    );

    return Scaffold(appBar: AppBar(title: const Text('Seus pedidos')), body: body);
  }
}
