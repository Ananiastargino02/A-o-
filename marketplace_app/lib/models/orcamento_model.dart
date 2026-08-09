import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_config.dart';

class OrcamentoModel {
  final String id;
  final String pedidoId;
  final String lojaId;
  final double preco;
  final CondicaoPeca condicao;
  final String marcaPeca;
  final TipoEntrega entrega;
  final Garantia garantia;
  final String? fotoUrl;
  final int tempoRespostaMin;
  final DateTime criadoEm;

  const OrcamentoModel({
    required this.id,
    required this.pedidoId,
    required this.lojaId,
    required this.preco,
    required this.condicao,
    required this.marcaPeca,
    required this.entrega,
    required this.garantia,
    this.fotoUrl,
    required this.tempoRespostaMin,
    required this.criadoEm,
  });

  factory OrcamentoModel.fromMap(String id, Map<String, dynamic> map) {
    return OrcamentoModel(
      id: id,
      pedidoId: map['pedidoId'] ?? '',
      lojaId: map['lojaId'] ?? '',
      preco: (map['preco'] ?? 0).toDouble(),
      condicao: CondicaoPecaX.fromString(map['condicao'] ?? ''),
      marcaPeca: map['marcaPeca'] ?? '',
      entrega: TipoEntregaX.fromString(map['entrega'] ?? ''),
      garantia: GarantiaX.fromString(map['garantia'] ?? ''),
      fotoUrl: map['fotoUrl'],
      tempoRespostaMin: map['tempoRespostaMin'] ?? 0,
      criadoEm: (map['criadoEm'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'pedidoId': pedidoId,
        'lojaId': lojaId,
        'preco': preco,
        'condicao': condicao.name,
        'marcaPeca': marcaPeca,
        'entrega': entrega.name,
        'garantia': garantia.name,
        'fotoUrl': fotoUrl,
        'tempoRespostaMin': tempoRespostaMin,
        'criadoEm': FieldValue.serverTimestamp(),
      };
}
