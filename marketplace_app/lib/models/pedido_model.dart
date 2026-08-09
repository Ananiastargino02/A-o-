import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_config.dart';

class PedidoModel {
  final String id;
  final String clienteId;
  final String categoria;
  final String marca;
  final String modelo;
  final int ano;
  final String peca;
  final String? detalhes;
  final String? fotoUrl;
  final GeoPoint geopoint;
  final String geohash;
  final StatusPedido status;
  final double raioAtual;
  final int lojasNotificadas;
  final List<String> recusadoPor;
  final DateTime criadoEm;
  final DateTime? expiraEm;

  const PedidoModel({
    required this.id,
    required this.clienteId,
    required this.categoria,
    required this.marca,
    required this.modelo,
    required this.ano,
    required this.peca,
    this.detalhes,
    this.fotoUrl,
    required this.geopoint,
    required this.geohash,
    required this.status,
    required this.raioAtual,
    required this.lojasNotificadas,
    this.recusadoPor = const [],
    required this.criadoEm,
    this.expiraEm,
  });

  double get lat => geopoint.latitude;
  double get lng => geopoint.longitude;

  String get veiculoResumo => '$marca $modelo $ano';

  factory PedidoModel.fromMap(String id, Map<String, dynamic> map) {
    return PedidoModel(
      id: id,
      clienteId: map['clienteId'] ?? '',
      categoria: map['categoria'] ?? AppConfig.categoriaPecasAutomotivas,
      marca: map['marca'] ?? '',
      modelo: map['modelo'] ?? '',
      ano: map['ano'] ?? 0,
      peca: map['peca'] ?? '',
      detalhes: map['detalhes'],
      fotoUrl: map['fotoUrl'],
      geopoint: map['geopoint'] as GeoPoint? ?? const GeoPoint(0, 0),
      geohash: map['geohash'] ?? '',
      status: StatusPedido.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => StatusPedido.aberto,
      ),
      raioAtual: (map['raioAtual'] ?? AppConfig.raiosExpansaoKm.first).toDouble(),
      lojasNotificadas: map['lojasNotificadas'] ?? 0,
      recusadoPor: List<String>.from(map['recusadoPor'] ?? []),
      criadoEm: (map['criadoEm'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiraEm: (map['expiraEm'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'clienteId': clienteId,
        'categoria': categoria,
        'marca': marca,
        'modelo': modelo,
        'ano': ano,
        'peca': peca,
        'detalhes': detalhes,
        'fotoUrl': fotoUrl,
        'geopoint': geopoint,
        'geohash': geohash,
        'status': status.name,
        'raioAtual': raioAtual,
        'lojasNotificadas': lojasNotificadas,
        'recusadoPor': recusadoPor,
        'criadoEm': FieldValue.serverTimestamp(),
        'expiraEm': Timestamp.fromDate(
          DateTime.now().add(Duration(hours: AppConfig.horasParaExpirarPedido)),
        ),
      };
}
