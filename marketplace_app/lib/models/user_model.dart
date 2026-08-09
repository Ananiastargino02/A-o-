import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_config.dart';

class UserModel {
  final String id;
  final TipoUsuario tipo;
  final String nome;
  final String telefone;
  final String? fcmToken;
  final DateTime criadoEm;

  const UserModel({
    required this.id,
    required this.tipo,
    required this.nome,
    required this.telefone,
    this.fcmToken,
    required this.criadoEm,
  });

  factory UserModel.fromMap(String id, Map<String, dynamic> map) {
    return UserModel(
      id: id,
      tipo: map['tipo'] == 'lojista' ? TipoUsuario.lojista : TipoUsuario.cliente,
      nome: map['nome'] ?? '',
      telefone: map['telefone'] ?? '',
      fcmToken: map['fcmToken'],
      criadoEm: (map['criadoEm'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'tipo': tipo.name,
        'nome': nome,
        'telefone': telefone,
        'fcmToken': fcmToken,
        'criadoEm': FieldValue.serverTimestamp(),
      };
}
