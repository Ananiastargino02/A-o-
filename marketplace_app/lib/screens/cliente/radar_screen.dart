import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../providers/pedidos_provider.dart';
import '../../widgets/radar_animation.dart';
import '../../widgets/app_button.dart';
import '../../widgets/orcamento_card.dart';
import '../../providers/lojista_provider.dart';
import 'orcamentos_screen.dart';

/// Tela mostrada logo apos o cliente enviar um pedido: ondas concentricas
/// com o raio de busca atual e, conforme chegam, cards de orcamento em
/// tempo real.
class RadarScreen extends ConsumerWidget {
  final String pedidoId;

  const RadarScreen({super.key, required this.pedidoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pedidoAsync = ref.watch(pedidoProvider(pedidoId));
    final orcamentosAsync = ref.watch(orcamentosDoPedidoProvider(pedidoId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Procurando lojas...'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => OrcamentosScreen(pedidoId: pedidoId)),
            ),
            child: const Text('Pular', style: TextStyle(color: AppColors.white)),
          ),
        ],
      ),
      body: pedidoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (pedido) {
          if (pedido == null) return const Center(child: Text('Pedido não encontrado.'));

          return Column(
            children: [
              const SizedBox(height: 24),
              RadarAnimation(raioKm: pedido.raioAtual, lojasNotificadas: pedido.lojasNotificadas),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'Assim que uma loja responder, o orçamento aparece aqui.',
                  style: AppTextStyles.bodySecondary,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: orcamentosAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => Text('Erro: $e'),
                  data: (orcamentos) {
                    if (orcamentos.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: orcamentos.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final orcamento = orcamentos[i];
                        final lojaAsync = ref.watch(lojaPorIdProvider(orcamento.lojaId));
                        return lojaAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                          data: (loja) => OrcamentoCard(
                            orcamento: orcamento,
                            loja: loja,
                            distanciaKm: null,
                            onTap: () => Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => OrcamentosScreen(pedidoId: pedidoId)),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: AppButton(
                  label: 'Ver todos os orçamentos',
                  estilo: AppButtonEstilo.primario,
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => OrcamentosScreen(pedidoId: pedidoId)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
