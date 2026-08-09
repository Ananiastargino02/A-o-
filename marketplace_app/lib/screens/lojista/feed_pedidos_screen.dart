import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_config.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../providers/lojista_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_chip.dart';
import 'detalhe_pedido_screen.dart';

class FeedPedidosScreen extends ConsumerWidget {
  const FeedPedidosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(feedPedidosLojistaProvider);

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
      body: feedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (pedidos) {
          if (pedidos.isEmpty) {
            return const EmptyState(
              icone: Icons.inbox_outlined,
              titulo: 'Nenhum pedido na sua área',
              subtitulo: 'Assim que alguém pedir uma peça perto de você, aparece aqui.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: pedidos.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final item = pedidos[i];
              final novo = DateTime.now().difference(item.pedido.criadoEm).inMinutes < 30;
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => DetalhePedidoScreen(pedidoId: item.pedido.id)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (novo) ...[
                              const StatusChip(label: 'Novo', tom: ChipTom.verde),
                              const SizedBox(width: 8),
                            ],
                            Expanded(child: Text(item.pedido.peca, style: AppTextStyles.h3)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(item.pedido.veiculoResumo, style: AppTextStyles.bodySecondary),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.location_on, size: 15, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(Formatters.km(item.distanciaKm), style: AppTextStyles.caption),
                            const SizedBox(width: 14),
                            const Icon(Icons.schedule, size: 15, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(timeago.format(item.pedido.criadoEm, locale: 'pt_BR'), style: AppTextStyles.caption),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
