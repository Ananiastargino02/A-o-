import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_config.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/distance_utils.dart';
import '../../models/chat_model.dart';
import '../../models/loja_model.dart';
import '../../models/orcamento_model.dart';
import '../../providers/location_provider.dart';
import '../../providers/lojista_provider.dart';
import '../../providers/pedidos_provider.dart';
import '../../providers/services_providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/orcamento_card.dart';
import '../chat/chat_screen.dart';

class OrcamentosScreen extends ConsumerWidget {
  final String pedidoId;

  const OrcamentosScreen({super.key, required this.pedidoId});

  Future<void> _abrirChat(BuildContext context, WidgetRef ref, OrcamentoModel orcamento) async {
    final pedido = ref.read(pedidoProvider(pedidoId)).value;
    final uid = ref.read(firestoreServiceProvider);
    if (pedido == null) return;

    final chat = ChatModel(
      id: '',
      pedidoId: pedidoId,
      orcamentoId: orcamento.id,
      clienteId: pedido.clienteId,
      lojaId: orcamento.lojaId,
      status: StatusChat.ativo,
      criadoEm: DateTime.now(),
    );
    final chatId = await uid.criarChat(chat);
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orcamentosAsync = ref.watch(orcamentosDoPedidoProvider(pedidoId));
    final pedidoAsync = ref.watch(pedidoProvider(pedidoId));
    final ordenacao = ref.watch(ordenacaoOrcamentosProvider);
    final posicaoAsync = ref.watch(currentPositionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orçamentos recebidos'),
        actions: [
          PopupMenuButton<OrdenacaoOrcamentos>(
            icon: const Icon(Icons.sort),
            onSelected: (v) => ref.read(ordenacaoOrcamentosProvider.notifier).state = v,
            itemBuilder: (context) => const [
              PopupMenuItem(value: OrdenacaoOrcamentos.menorPreco, child: Text('Menor preço')),
              PopupMenuItem(value: OrdenacaoOrcamentos.maisPerto, child: Text('Mais perto')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          pedidoAsync.maybeWhen(
            data: (pedido) {
              if (pedido == null) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                color: AppColors.amberSoft,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  '${pedido.veiculoResumo} · ${pedido.peca}',
                  style: AppTextStyles.bodyBold,
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
          Expanded(
            child: orcamentosAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: $e')),
              data: (orcamentos) {
                if (orcamentos.isEmpty) {
                  return const EmptyState(
                    icone: Icons.hourglass_empty,
                    titulo: 'Aguardando orçamentos',
                    subtitulo: 'As lojas da sua região foram notificadas. Assim que responderem, aparece aqui.',
                  );
                }

                final posicao = posicaoAsync.value;

                return FutureBuilder<List<_OrcamentoComLoja>>(
                  future: _carregarLojas(ref, orcamentos),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    var lista = snapshot.data!;

                    if (ordenacao == OrdenacaoOrcamentos.menorPreco) {
                      lista.sort((a, b) => a.orcamento.preco.compareTo(b.orcamento.preco));
                    } else {
                      lista.sort((a, b) {
                        final da = a.distanciaKm ?? double.infinity;
                        final db = b.distanciaKm ?? double.infinity;
                        return da.compareTo(db);
                      });
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: lista.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final item = lista[i];
                        final distancia = posicao == null || item.loja == null
                            ? null
                            : DistanceUtils.km(
                                lat1: posicao.latitude,
                                lng1: posicao.longitude,
                                lat2: item.loja!.lat,
                                lng2: item.loja!.lng,
                              );
                        return OrcamentoCard(
                          orcamento: item.orcamento,
                          loja: item.loja,
                          distanciaKm: distancia ?? item.distanciaKm,
                          onTap: () => _abrirChat(context, ref, item.orcamento),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<List<_OrcamentoComLoja>> _carregarLojas(WidgetRef ref, List<OrcamentoModel> orcamentos) async {
    final resultado = <_OrcamentoComLoja>[];
    for (final orcamento in orcamentos) {
      final loja = await ref.read(lojaPorIdProvider(orcamento.lojaId).future);
      resultado.add(_OrcamentoComLoja(orcamento: orcamento, loja: loja, distanciaKm: null));
    }
    return resultado;
  }
}

class _OrcamentoComLoja {
  final OrcamentoModel orcamento;
  final LojaModel? loja;
  final double? distanciaKm;

  _OrcamentoComLoja({required this.orcamento, required this.loja, required this.distanciaKm});
}
