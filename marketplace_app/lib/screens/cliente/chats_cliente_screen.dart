import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../core/constants/app_text_styles.dart';
import '../../core/constants/app_config.dart';
import '../../providers/chat_provider.dart';
import '../../providers/lojista_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_chip.dart';
import '../chat/chat_screen.dart';

class ChatsClienteScreen extends ConsumerWidget {
  const ChatsClienteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatsAsync = ref.watch(meusChatsClienteProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Seus chats')),
      body: chatsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (chats) {
          if (chats.isEmpty) {
            return const EmptyState(
              icone: Icons.chat_bubble_outline,
              titulo: 'Nenhum chat aberto',
              subtitulo: 'Quando você tocar num orçamento, o chat com a loja aparece aqui.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: chats.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final chat = chats[i];
              final lojaAsync = ref.watch(lojaPorIdProvider(chat.lojaId));
              return Card(
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
                                  Expanded(
                                    child: Text(
                                      lojaAsync.value?.nomeLoja ?? 'Loja',
                                      style: AppTextStyles.bodyBold,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  StatusChip(
                                    label: chat.status == StatusChat.ativo ? 'Ativo' : 'Venda',
                                    tom: chat.status == StatusChat.ativo ? ChipTom.azul : ChipTom.verde,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                chat.ultimaMensagem?.isNotEmpty == true
                                    ? chat.ultimaMensagem!
                                    : 'Diga oi pra loja 👋',
                                style: AppTextStyles.bodySecondary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (chat.ultimaMensagemEm != null)
                          Text(
                            timeago.format(chat.ultimaMensagemEm!, locale: 'pt_BR'),
                            style: AppTextStyles.caption,
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
