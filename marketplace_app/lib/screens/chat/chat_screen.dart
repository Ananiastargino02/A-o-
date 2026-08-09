import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_config.dart';
import '../../core/constants/app_text_styles.dart';
import '../../models/mensagem_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/lojista_provider.dart';
import '../../providers/services_providers.dart';
import '../../widgets/app_toast.dart';
import '../cliente/avaliacao_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String chatId;

  const ChatScreen({super.key, required this.chatId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textoController = TextEditingController();
  final _scrollController = ScrollController();
  bool _enviando = false;
  bool _fechandoNegocio = false;

  Future<void> _enviarTexto() async {
    final texto = _textoController.text.trim();
    if (texto.isEmpty) return;
    final uid = ref.read(authServiceProvider).currentUser?.uid;
    if (uid == null) return;

    _textoController.clear();
    await ref.read(firestoreServiceProvider).enviarMensagem(
          widget.chatId,
          MensagemModel(id: '', texto: texto, remetenteId: uid, timestamp: DateTime.now()),
        );
  }

  Future<void> _enviarFoto() async {
    final uid = ref.read(authServiceProvider).currentUser?.uid;
    if (uid == null) return;
    final picker = ImagePicker();
    final foto = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (foto == null) return;

    setState(() => _enviando = true);
    final url = await ref.read(storageServiceProvider).uploadFotoChat(File(foto.path), widget.chatId);
    await ref.read(firestoreServiceProvider).enviarMensagem(
          widget.chatId,
          MensagemModel(id: '', fotoUrl: url, remetenteId: uid, timestamp: DateTime.now()),
        );
    if (mounted) setState(() => _enviando = false);
  }

  Future<void> _fecharNegocio() async {
    final chat = ref.read(chatProvider(widget.chatId)).value;
    if (chat == null) return;

    setState(() => _fechandoNegocio = true);
    final firestore = ref.read(firestoreServiceProvider);
    await firestore.fecharChat(widget.chatId);
    await firestore.fecharPedido(chat.pedidoId);
    final loja = await ref.read(lojaPorIdProvider(chat.lojaId).future);

    if (!mounted) return;
    setState(() => _fechandoNegocio = false);
    AppToast.mostrar('Negócio fechado!');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AvaliacaoScreen(
          lojaId: chat.lojaId,
          pedidoId: chat.pedidoId,
          nomeLoja: loja?.nomeLoja ?? 'loja',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _textoController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authStateProvider).value?.uid;
    final chatAsync = ref.watch(chatProvider(widget.chatId));
    final mensagensAsync = ref.watch(mensagensProvider(widget.chatId));

    final chat = chatAsync.value;
    final souCliente = chat != null && uid == chat.clienteId;
    final lojaAsync = chat == null ? null : ref.watch(lojaPorIdProvider(chat.lojaId));

    return Scaffold(
      appBar: AppBar(
        title: Text(lojaAsync?.value?.nomeLoja ?? 'Chat'),
        actions: [
          if (souCliente && chat != null && chat.status == StatusChat.ativo)
            TextButton(
              onPressed: _fechandoNegocio ? null : _fecharNegocio,
              child: Text(
                'Negócio fechado',
                style: AppTextStyles.button.copyWith(color: AppColors.green),
              ),
            ),
        ],
      ),
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Expanded(
            child: mensagensAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: $e')),
              data: (mensagens) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                  }
                });
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(14),
                  itemCount: mensagens.length,
                  itemBuilder: (context, i) => _Balao(mensagem: mensagens[i], minhaMensagem: mensagens[i].remetenteId == uid),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _enviando ? null : _enviarFoto,
                    icon: const Icon(Icons.add_photo_alternate_outlined, color: AppColors.textSecondary),
                  ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: TextField(
                        controller: _textoController,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Digite uma mensagem',
                          border: InputBorder.none,
                          isCollapsed: true,
                        ).copyWith(contentPadding: const EdgeInsets.symmetric(vertical: 12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: AppColors.textPrimary,
                    child: IconButton(
                      onPressed: _enviarTexto,
                      icon: const Icon(Icons.send, color: AppColors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Balao extends StatelessWidget {
  final MensagemModel mensagem;
  final bool minhaMensagem;

  const _Balao({required this.mensagem, required this.minhaMensagem});

  @override
  Widget build(BuildContext context) {
    final bg = minhaMensagem ? AppColors.topBarDark : AppColors.card;
    final fg = minhaMensagem ? AppColors.white : AppColors.textPrimary;

    return Align(
      alignment: minhaMensagem ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: minhaMensagem ? null : Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (mensagem.fotoUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(imageUrl: mensagem.fotoUrl!, width: 200, fit: BoxFit.cover),
              ),
            if (mensagem.texto != null && mensagem.texto!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(mensagem.texto!, style: AppTextStyles.body.copyWith(color: fg)),
              ),
            const SizedBox(height: 3),
            Text(
              DateFormat.Hm().format(mensagem.timestamp),
              style: AppTextStyles.caption.copyWith(
                color: minhaMensagem ? AppColors.white.withValues(alpha: 0.6) : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
