import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_config.dart';

class ChatModel {
  final String id;
  final String pedidoId;
  final String orcamentoId;
  final String clienteId;
  final String lojaId;
  final StatusChat status;
  final String? ultimaMensagem;
  final DateTime? ultimaMensagemEm;
  final DateTime criadoEm;

  const ChatModel({
    required this.id,
    required this.pedidoId,
    required this.orcamentoId,
    required this.clienteId,
    required this.lojaId,
    required this.status,
    this.ultimaMensagem,
    this.ultimaMensagemEm,
    required this.criadoEm,
  });

  factory ChatModel.fromMap(String id, Map<String, dynamic> map) {
    return ChatModel(
      id: id,
      pedidoId: map['pedidoId'] ?? '',
      orcamentoId: map['orcamentoId'] ?? '',
      clienteId: map['clienteId'] ?? '',
      lojaId: map['lojaId'] ?? '',
      status: map['status'] == 'fechado' ? StatusChat.fechado : StatusChat.ativo,
      ultimaMensagem: map['ultimaMensagem'],
      ultimaMensagemEm: (map['ultimaMensagemEm'] as Timestamp?)?.toDate(),
      criadoEm: (map['criadoEm'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'pedidoId': pedidoId,
        'orcamentoId': orcamentoId,
        'clienteId': clienteId,
        'lojaId': lojaId,
        'status': status.name,
        'ultimaMensagem': ultimaMensagem,
        'ultimaMensagemEm': FieldValue.serverTimestamp(),
        'criadoEm': FieldValue.serverTimestamp(),
      };
}
