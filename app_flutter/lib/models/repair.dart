import 'package:intl/intl.dart';

/// Um conserto/revisao documentado pelo usuario (com fotos), salvo no celular.
class RepairRecord {
  final String id;
  String titulo;
  String descricao;
  DateTime data;
  int km;
  double custo;
  String oficina;
  List<String> fotos; // caminhos dos arquivos no celular

  RepairRecord({
    required this.id,
    this.titulo = '',
    this.descricao = '',
    DateTime? data,
    this.km = 0,
    this.custo = 0,
    this.oficina = '',
    List<String>? fotos,
  })  : data = data ?? DateTime.now(),
        fotos = fotos ?? [];

  String get dataFmt => DateFormat('dd/MM/yyyy').format(data);
  String get custoFmt =>
      custo > 0 ? 'R\$ ${custo.toStringAsFixed(2).replaceAll('.', ',')}' : '';

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'descricao': descricao,
        'data': data.toIso8601String(),
        'km': km,
        'custo': custo,
        'oficina': oficina,
        'fotos': fotos,
      };

  factory RepairRecord.fromJson(Map<String, dynamic> j) => RepairRecord(
        id: j['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        titulo: j['titulo'] ?? '',
        descricao: j['descricao'] ?? '',
        data: DateTime.tryParse(j['data'] ?? '') ?? DateTime.now(),
        km: j['km'] ?? 0,
        custo: (j['custo'] ?? 0).toDouble(),
        oficina: j['oficina'] ?? '',
        fotos: (j['fotos'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );
}
