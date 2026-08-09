import 'package:cloud_firestore/cloud_firestore.dart';

class AvaliacaoModel {
  final String id;
  final String lojaId;
  final String clienteId;
  final String pedidoId;
  final int estrelas;
  final String? comentario;
  final DateTime criadoEm;

  const AvaliacaoModel({
    required this.id,
    required this.lojaId,
    required this.clienteId,
    required this.pedidoId,
    required this.estrelas,
    this.comentario,
    required this.criadoEm,
  });

  factory AvaliacaoModel.fromMap(String id, Map<String, dynamic> map) {
    return AvaliacaoModel(
      id: id,
      lojaId: map['lojaId'] ?? '',
      clienteId: map['clienteId'] ?? '',
      pedidoId: map['pedidoId'] ?? '',
      estrelas: map['estrelas'] ?? 0,
      comentario: map['comentario'],
      criadoEm: (map['criadoEm'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'lojaId': lojaId,
        'clienteId': clienteId,
        'pedidoId': pedidoId,
        'estrelas': estrelas,
        'comentario': comentario,
        'criadoEm': FieldValue.serverTimestamp(),
      };
}
