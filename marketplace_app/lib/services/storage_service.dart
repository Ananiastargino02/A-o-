import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

/// Upload de fotos (pedido, orcamento, foto da loja, chat).
class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final _uuid = const Uuid();

  Future<String> uploadFoto({
    required File arquivo,
    required String pasta,
  }) async {
    final nome = '${_uuid.v4()}${_extensao(arquivo.path)}';
    final ref = _storage.ref().child('$pasta/$nome');
    final task = await ref.putFile(arquivo);
    return task.ref.getDownloadURL();
  }

  Future<String> uploadFotoPedido(File arquivo, String pedidoId) =>
      uploadFoto(arquivo: arquivo, pasta: 'pedidos/$pedidoId');

  Future<String> uploadFotoOrcamento(File arquivo, String orcamentoId) =>
      uploadFoto(arquivo: arquivo, pasta: 'orcamentos/$orcamentoId');

  Future<String> uploadLogoLoja(File arquivo, String lojaId) =>
      uploadFoto(arquivo: arquivo, pasta: 'lojas/$lojaId');

  Future<String> uploadFotoChat(File arquivo, String chatId) =>
      uploadFoto(arquivo: arquivo, pasta: 'chats/$chatId');

  String _extensao(String path) {
    final i = path.lastIndexOf('.');
    return i == -1 ? '.jpg' : path.substring(i);
  }
}
