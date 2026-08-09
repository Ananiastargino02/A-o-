import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_config.dart';
import '../../core/constants/app_text_styles.dart';
import '../../providers/chat_provider.dart';
import '../../providers/lojista_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_chip.dart';
import '../chat/chat_screen.dart';

class VendasScreen extends ConsumerWidget {
  const VendasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatsAsync = ref.watch(meusChatsLojistaProvider);
    final metricasAsync = ref.watch(metricasDoMesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Vendas')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Seu mês', style: AppTextStyles.h3),
          const SizedBox(height: 10),
          metricasAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Erro: $e'),
            data: (metricas) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 2.2,
                  children: [
                    _Metrica(label: 'Pedidos recebidos', valor: metricas['pedidosRecebidos'] ?? 0),
                    _Metrica(label: 'Orçamentos enviados', valor: metricas['orcamentosEnviados'] ?? 0),
                    _Metrica(label: 'Chats abertos', valor: metricas['chatsAbertos'] ?? 0),
                    _Metrica(label: 'Vendas confirmadas', valor: metricas['vendasConfirmadas'] ?? 0),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Chats', style: AppTextStyles.h3),
          const SizedBox(height: 10),
          chatsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Erro: $e'),
            data: (chats) {
              if (chats.isEmpty) {
                return const EmptyState(
                  icone: Icons.chat_bubble_outline,
                  titulo: 'Nenhum chat aberto',
                  subtitulo: 'Quando um cliente abrir um chat com você, aparece aqui.',
                );
              }
              return Column(
                children: chats.map((chat) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat.id)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        StatusChip(
                                          label: chat.status == StatusChat.ativo ? 'Ativo' : 'Venda',
                                          tom: chat.status == StatusChat.ativo ? ChipTom.azul : ChipTom.verde,
                                        ),
                                        const SizedBox(width: 8),
                                        if (chat.ultimaMensagemEm != null)
                                          Text(
                                            timeago.format(chat.ultimaMensagemEm!, locale: 'pt_BR'),
                                            style: AppTextStyles.caption,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      chat.ultimaMensagem?.isNotEmpty == true
                                          ? chat.ultimaMensagem!
                                          : 'Chat iniciado pelo cliente',
                                      style: AppTextStyles.body,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: AppColors.grey),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Metrica extends StatelessWidget {
  final String label;
  final int valor;

  const _Metrica({required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('$valor', style: AppTextStyles.h1),
        Text(label, style: AppTextStyles.bodySecondary),
      ],
    );
  }
}
