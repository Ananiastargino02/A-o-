import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_model.dart';
import '../models/mensagem_model.dart';
import 'services_providers.dart';
import 'auth_provider.dart';

final meusChatsClienteProvider = StreamProvider<List<ChatModel>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value([]);
  return ref.watch(firestoreServiceProvider).watchChatsDoCliente(uid);
});

final meusChatsLojistaProvider = StreamProvider<List<ChatModel>>((ref) {
  final loja = ref.watch(currentLojaProvider).value;
  if (loja == null) return Stream.value([]);
  return ref.watch(firestoreServiceProvider).watchChatsDaLoja(loja.id);
});

final chatProvider = StreamProvider.family<ChatModel?, String>((ref, chatId) {
  return ref.watch(firestoreServiceProvider).watchChat(chatId);
});

final mensagensProvider = StreamProvider.family<List<MensagemModel>, String>((ref, chatId) {
  return ref.watch(firestoreServiceProvider).watchMensagens(chatId);
});
