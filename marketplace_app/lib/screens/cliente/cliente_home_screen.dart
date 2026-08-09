import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_config.dart';
import '../../core/constants/app_text_styles.dart';
import '../../providers/pedidos_provider.dart';
import '../../widgets/pedido_card.dart';
import '../../widgets/empty_state.dart';
import 'novo_pedido_screen.dart';
import 'pedido_detalhe_router.dart';
import 'pedidos_list_screen.dart';

class ClienteHomeScreen extends ConsumerWidget {
  const ClienteHomeScreen({super.key});

  static const _iconesPorId = {
    'directions_car': Icons.directions_car,
    'construction': Icons.construction,
    'devices': Icons.devices,
    'chair': Icons.chair,
    'pets': Icons.pets,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedidosAsync = ref.watch(meusPedidosProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(AppConfig.appName),
            const SizedBox(width: 4),
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(bottom: 6),
              decoration: const BoxDecoration(color: AppColors.amber, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Categorias', style: AppTextStyles.h3),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: AppConfig.categorias.map((cat) => _CategoriaCard(categoria: cat)).toList(),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Seus pedidos', style: AppTextStyles.h3),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PedidosListScreen()),
                ),
                child: const Text('Ver todos'),
              ),
            ],
          ),
          pedidosAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Erro ao carregar pedidos: $e'),
            data: (pedidos) {
              if (pedidos.isEmpty) {
                return const EmptyState(
                  icone: Icons.search,
                  titulo: 'Nenhum pedido ainda',
                  subtitulo: 'Toque em "Peças automotivas" pra pedir seu primeiro orçamento.',
                );
              }
              final recentes = pedidos.take(3).toList();
              return Column(
                children: recentes
                    .map((p) => Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: PedidoCard(
                            pedido: p,
                            onTap: () => abrirDetalheDoPedido(context, p),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CategoriaCard extends StatelessWidget {
  final CategoriaInfo categoria;

  const _CategoriaCard({required this.categoria});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: categoria.ativa
            ? () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NovoPedidoScreen()),
                )
            : null,
        child: Opacity(
          opacity: categoria.ativa ? 1 : 0.5,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(
                  ClienteHomeScreen._iconesPorId[categoria.icone] ?? Icons.category,
                  color: AppColors.amber,
                ),
                Text(categoria.nome, style: AppTextStyles.bodyBold),
                if (!categoria.ativa)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDEEF1),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text('Em breve', style: AppTextStyles.caption),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
