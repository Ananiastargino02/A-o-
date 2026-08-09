import 'package:cloud_firestore/cloud_firestore.dart';

class LojaModel {
  final String id;
  final String userId;
  final String nomeLoja;
  final String cnpj;
  final String endereco;
  final GeoPoint geopoint;
  final String geohash;
  final double raioKm;
  final List<String> categorias;
  final String? logoUrl;
  final double avaliacaoMedia;
  final int totalAvaliacoes;
  // Modelo preparado para monetizacao futura por creditos de chat.
  // Sem cobranca ativa nesta versao.
  final int creditos;
  final DateTime criadoEm;

  const LojaModel({
    required this.id,
    required this.userId,
    required this.nomeLoja,
    required this.cnpj,
    required this.endereco,
    required this.geopoint,
    required this.geohash,
    required this.raioKm,
    required this.categorias,
    this.logoUrl,
    this.avaliacaoMedia = 0,
    this.totalAvaliacoes = 0,
    this.creditos = 0,
    required this.criadoEm,
  });

  double get lat => geopoint.latitude;
  double get lng => geopoint.longitude;

  factory LojaModel.fromMap(String id, Map<String, dynamic> map) {
    return LojaModel(
      id: id,
      userId: map['userId'] ?? '',
      nomeLoja: map['nomeLoja'] ?? '',
      cnpj: map['cnpj'] ?? '',
      endereco: map['endereco'] ?? '',
      geopoint: map['geopoint'] as GeoPoint? ?? const GeoPoint(0, 0),
      geohash: map['geohash'] ?? '',
      raioKm: (map['raioKm'] ?? 10).toDouble(),
      categorias: List<String>.from(map['categorias'] ?? []),
      logoUrl: map['logoUrl'],
      avaliacaoMedia: (map['avaliacaoMedia'] ?? 0).toDouble(),
      totalAvaliacoes: map['totalAvaliacoes'] ?? 0,
      creditos: map['creditos'] ?? 0,
      criadoEm: (map['criadoEm'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'nomeLoja': nomeLoja,
        'cnpj': cnpj,
        'endereco': endereco,
        'geopoint': geopoint,
        'geohash': geohash,
        'raioKm': raioKm,
        'categorias': categorias,
        'logoUrl': logoUrl,
        'avaliacaoMedia': avaliacaoMedia,
        'totalAvaliacoes': totalAvaliacoes,
        'creditos': creditos,
        'criadoEm': FieldValue.serverTimestamp(),
      };
}
