import 'package:cloud_firestore/cloud_firestore.dart';

class MensagemModel {
  final String id;
  final String? texto;
  final String? fotoUrl;
  final String remetenteId;
  final DateTime timestamp;
  final bool lida;

  const MensagemModel({
    required this.id,
    this.texto,
    this.fotoUrl,
    required this.remetenteId,
    required this.timestamp,
    this.lida = false,
  });

  factory MensagemModel.fromMap(String id, Map<String, dynamic> map) {
    return MensagemModel(
      id: id,
      texto: map['texto'],
      fotoUrl: map['fotoUrl'],
      remetenteId: map['remetenteId'] ?? '',
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lida: map['lida'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'texto': texto,
        'fotoUrl': fotoUrl,
        'remetenteId': remetenteId,
        'timestamp': FieldValue.serverTimestamp(),
        'lida': lida,
      };
}
