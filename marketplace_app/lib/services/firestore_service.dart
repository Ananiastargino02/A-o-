import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/loja_model.dart';
import '../models/pedido_model.dart';
import '../models/orcamento_model.dart';
import '../models/chat_model.dart';
import '../models/mensagem_model.dart';
import '../models/avaliacao_model.dart';
import '../core/constants/app_config.dart';

/// Ponto unico de acesso ao Firestore. Mantem as colecoes e as regras de
/// leitura/escrita organizadas num so lugar (ver tambem firebase/firestore.rules).
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _lojas => _db.collection('lojas');
  CollectionReference<Map<String, dynamic>> get _pedidos => _db.collection('pedidos');
  CollectionReference<Map<String, dynamic>> get _orcamentos => _db.collection('orcamentos');
  CollectionReference<Map<String, dynamic>> get _chats => _db.collection('chats');
  CollectionReference<Map<String, dynamic>> get _avaliacoes => _db.collection('avaliacoes');

  // ---------------- users ----------------

  Future<void> criarOuAtualizarUser(String id, Map<String, dynamic> data) {
    return _users.doc(id).set(data, SetOptions(merge: true));
  }

  Future<UserModel?> getUser(String id) async {
    final doc = await _users.doc(id).get();
    if (!doc.exists) return null;
    return UserModel.fromMap(doc.id, doc.data()!);
  }

  Stream<UserModel?> watchUser(String id) {
    return _users.doc(id).snapshots().map(
          (doc) => doc.exists ? UserModel.fromMap(doc.id, doc.data()!) : null,
        );
  }

  Future<void> atualizarFcmToken(String userId, String token) {
    return _users.doc(userId).update({'fcmToken': token});
  }

  // ---------------- lojas ----------------

  Future<String> criarLoja(LojaModel loja) async {
    final ref = await _lojas.add(loja.toMap());
    return ref.id;
  }

  Future<void> atualizarLogoLoja(String lojaId, String url) {
    return _lojas.doc(lojaId).update({'logoUrl': url});
  }

  Stream<LojaModel?> watchLojaPorUserId(String userId) {
    return _lojas.where('userId', isEqualTo: userId).limit(1).snapshots().map(
          (snap) => snap.docs.isEmpty ? null : LojaModel.fromMap(snap.docs.first.id, snap.docs.first.data()),
        );
  }

  Future<LojaModel?> getLoja(String lojaId) async {
    final doc = await _lojas.doc(lojaId).get();
    if (!doc.exists) return null;
    return LojaModel.fromMap(doc.id, doc.data()!);
  }

  /// Lojas que atendem uma categoria (usado para telas administrativas /
  /// listagem). O filtro fino por raio de atendimento e feito no client
  /// (ver [FirestoreService.watchPedidosAbertosPorCategoria] e o provider do
  /// lojista, que comparam a distancia Haversine com `loja.raioKm`).
  Stream<List<LojaModel>> watchLojasPorCategoria(String categoria) {
    return _lojas
        .where('categorias', arrayContains: categoria)
        .snapshots()
        .map((snap) => snap.docs.map((d) => LojaModel.fromMap(d.id, d.data())).toList());
  }

  // ---------------- pedidos ----------------

  Future<String> criarPedido(PedidoModel pedido) async {
    final ref = await _pedidos.add(pedido.toMap());
    return ref.id;
  }

  /// Usado quando o id do pedido precisa ser conhecido antes de criar o
  /// documento (ex: upload da foto do pedido usa o id como pasta).
  String novoPedidoId() => _pedidos.doc().id;

  Future<void> criarPedidoComId(String id, PedidoModel pedido) {
    return _pedidos.doc(id).set(pedido.toMap());
  }

  Stream<PedidoModel?> watchPedido(String pedidoId) {
    return _pedidos.doc(pedidoId).snapshots().map(
          (doc) => doc.exists ? PedidoModel.fromMap(doc.id, doc.data()!) : null,
        );
  }

  Stream<List<PedidoModel>> watchPedidosDoCliente(String clienteId) {
    return _pedidos
        .where('clienteId', isEqualTo: clienteId)
        .orderBy('criadoEm', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => PedidoModel.fromMap(d.id, d.data())).toList());
  }

  /// Feed do lojista: pedidos abertos dentro do raio de atendimento da loja,
  /// que ele ainda nao recusou. O filtro geografico fino e feito no client
  /// apos a query por categoria+status (Firestore nao faz geo-query composta
  /// nativamente sem o indice do geoflutterfire).
  Stream<List<PedidoModel>> watchPedidosAbertosPorCategoria(String categoria) {
    return _pedidos
        .where('categoria', isEqualTo: categoria)
        .where('status', isEqualTo: StatusPedido.aberto.name)
        .orderBy('criadoEm', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => PedidoModel.fromMap(d.id, d.data())).toList());
  }

  Future<void> recusarPedido(String pedidoId, String lojaId) {
    return _pedidos.doc(pedidoId).update({
      'recusadoPor': FieldValue.arrayUnion([lojaId]),
    });
  }

  Future<void> fecharPedido(String pedidoId) {
    return _pedidos.doc(pedidoId).update({'status': StatusPedido.fechado.name});
  }

  Future<void> reabrirPedido(String pedidoId) {
    return _pedidos.doc(pedidoId).update({
      'status': StatusPedido.aberto.name,
      'raioAtual': AppConfig.raiosExpansaoKm.first,
      'criadoEm': FieldValue.serverTimestamp(),
      'expiraEm': Timestamp.fromDate(
        DateTime.now().add(Duration(hours: AppConfig.horasParaExpirarPedido)),
      ),
      'recusadoPor': [],
    });
  }

  // ---------------- orcamentos ----------------

  Future<String> criarOrcamento(OrcamentoModel orcamento) async {
    final ref = await _orcamentos.add(orcamento.toMap());
    return ref.id;
  }

  Stream<List<OrcamentoModel>> watchOrcamentosDoPedido(String pedidoId) {
    return _orcamentos
        .where('pedidoId', isEqualTo: pedidoId)
        .orderBy('criadoEm', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) => OrcamentoModel.fromMap(d.id, d.data())).toList());
  }

  Stream<List<OrcamentoModel>> watchOrcamentosDaLoja(String lojaId) {
    return _orcamentos
        .where('lojaId', isEqualTo: lojaId)
        .orderBy('criadoEm', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => OrcamentoModel.fromMap(d.id, d.data())).toList());
  }

  // ---------------- chats ----------------

  Future<String> criarChat(ChatModel chat) async {
    final existente = await _chats
        .where('pedidoId', isEqualTo: chat.pedidoId)
        .where('lojaId', isEqualTo: chat.lojaId)
        .limit(1)
        .get();
    if (existente.docs.isNotEmpty) return existente.docs.first.id;
    final ref = await _chats.add(chat.toMap());
    return ref.id;
  }

  Stream<ChatModel?> watchChat(String chatId) {
    return _chats.doc(chatId).snapshots().map(
          (doc) => doc.exists ? ChatModel.fromMap(doc.id, doc.data()!) : null,
        );
  }

  Stream<List<ChatModel>> watchChatsDoCliente(String clienteId) {
    return _chats
        .where('clienteId', isEqualTo: clienteId)
        .orderBy('ultimaMensagemEm', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => ChatModel.fromMap(d.id, d.data())).toList());
  }

  Stream<List<ChatModel>> watchChatsDaLoja(String lojaId) {
    return _chats
        .where('lojaId', isEqualTo: lojaId)
        .orderBy('ultimaMensagemEm', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => ChatModel.fromMap(d.id, d.data())).toList());
  }

  Future<void> fecharChat(String chatId) {
    return _chats.doc(chatId).update({'status': StatusChat.fechado.name});
  }

  Future<void> enviarMensagem(String chatId, MensagemModel msg) async {
    await _chats.doc(chatId).collection('mensagens').add(msg.toMap());
    await _chats.doc(chatId).update({
      'ultimaMensagem': msg.texto ?? (msg.fotoUrl != null ? '📷 Foto' : ''),
      'ultimaMensagemEm': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<MensagemModel>> watchMensagens(String chatId) {
    return _chats
        .doc(chatId)
        .collection('mensagens')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) => MensagemModel.fromMap(d.id, d.data())).toList());
  }

  // ---------------- avaliacoes ----------------

  Future<void> criarAvaliacao(AvaliacaoModel avaliacao) async {
    await _avaliacoes.add(avaliacao.toMap());
  }

  Stream<List<AvaliacaoModel>> watchAvaliacoesDaLoja(String lojaId) {
    return _avaliacoes
        .where('lojaId', isEqualTo: lojaId)
        .orderBy('criadoEm', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AvaliacaoModel.fromMap(d.id, d.data())).toList());
  }

}
