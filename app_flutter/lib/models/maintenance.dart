import 'package:intl/intl.dart';

/// Um item de manutencao lido do VEICAN (comando "MANUT LIST").
/// Linha: "0:Oleo 45% int=10000km/365d"
class MaintItem {
  final int indice;
  final String nome;
  final int percentual;
  final int intervaloKm;
  final int intervaloDias;

  MaintItem({
    required this.indice,
    required this.nome,
    required this.percentual,
    required this.intervaloKm,
    required this.intervaloDias,
  });

  bool get vencido => percentual >= 100;
  bool get proximo => percentual >= 80 && percentual < 100;

  static MaintItem? parse(String linha) {
    // "0:Oleo 45% int=10000km/365d"  (dias opcional)
    final m = RegExp(r'^(\d+):(.+?)\s+(\d+)%\s+int=(\d+)km(?:/(\d+)d)?')
        .firstMatch(linha.trim());
    if (m == null) return null;
    return MaintItem(
      indice: int.parse(m.group(1)!),
      nome: m.group(2)!.trim(),
      percentual: int.parse(m.group(3)!),
      intervaloKm: int.parse(m.group(4)!),
      intervaloDias: m.group(5) != null ? int.parse(m.group(5)!) : 0,
    );
  }
}

/// Um registro do historico de manutencao (salvo localmente a cada reset).
class MaintRecord {
  final String item;
  final DateTime data;
  final int km;
  final String obs;

  MaintRecord({
    required this.item,
    required this.data,
    required this.km,
    this.obs = '',
  });

  String get dataFmt => DateFormat('dd/MM/yyyy HH:mm').format(data);

  Map<String, dynamic> toJson() => {
        'item': item,
        'data': data.toIso8601String(),
        'km': km,
        'obs': obs,
      };

  factory MaintRecord.fromJson(Map<String, dynamic> j) => MaintRecord(
        item: j['item'] ?? '',
        data: DateTime.tryParse(j['data'] ?? '') ?? DateTime.now(),
        km: j['km'] ?? 0,
        obs: j['obs'] ?? '',
      );
}
