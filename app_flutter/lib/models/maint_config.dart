/// Configuracao de manutencao MANTIDA PELO APP (por carro). Aqui ficam os 10
/// itens com o intervalo (km/dias) editavel, a ultima troca, as NUMERACOES que
/// o usuario anota (oleo, correia, oleo do cambio) e a base p/ a ESTIMATIVA de
/// quando cada item vai vencer (pela media de rodagem).

class MaintItemCfg {
  int intervaloKm; // 0 = so por tempo
  int intervaloDias; // 0 = so por km
  int kmUltima; // odometro na ultima troca
  DateTime? dataUltima; // data da ultima troca

  MaintItemCfg({
    this.intervaloKm = 0,
    this.intervaloDias = 0,
    this.kmUltima = 0,
    this.dataUltima,
  });

  Map<String, dynamic> toJson() => {
        'ik': intervaloKm,
        'id': intervaloDias,
        'ku': kmUltima,
        'du': dataUltima?.toIso8601String(),
      };

  factory MaintItemCfg.fromJson(Map<String, dynamic> j) => MaintItemCfg(
        intervaloKm: (j['ik'] ?? 0) as int,
        intervaloDias: (j['id'] ?? 0) as int,
        kmUltima: (j['ku'] ?? 0) as int,
        dataUltima: j['du'] != null ? DateTime.tryParse(j['du']) : null,
      );
}

class MaintConfig {
  /// Ordem FIXA dos 10 itens (os 5 primeiros batem com os indices do VEICAN).
  static const List<String> nomes = [
    'Oleo do Motor',
    'Filtro de Ar',
    'Vela',
    'Oleo do Cambio',
    'Correia Dentada',
    'Pneu',
    'Filtro de Combustivel',
    'Bomba d\'Agua',
    'Pastilha de Freio',
    'Oleo de Freio',
  ];

  List<MaintItemCfg> itens;

  // Numeracoes que o usuario anota (pra saber o que comprar).
  String numOleoMotor;
  String numCorreia;
  String numOleoCambio;

  MaintConfig({
    required this.itens,
    this.numOleoMotor = '',
    this.numCorreia = '',
    this.numOleoCambio = '',
  });

  /// Padroes de fabrica (km comuns; o usuario muda o que quiser no app).
  factory MaintConfig.padrao() => MaintConfig(itens: [
        MaintItemCfg(intervaloKm: 10000, intervaloDias: 180), // oleo motor
        MaintItemCfg(intervaloKm: 10000), // filtro ar
        MaintItemCfg(intervaloKm: 40000), // vela
        MaintItemCfg(intervaloKm: 80000), // oleo cambio
        MaintItemCfg(intervaloKm: 60000, intervaloDias: 1460), // correia (4 anos)
        MaintItemCfg(intervaloKm: 50000), // pneu
        MaintItemCfg(intervaloKm: 15000), // filtro combustivel
        MaintItemCfg(intervaloKm: 40000), // bomba d'agua (= correia)
        MaintItemCfg(intervaloKm: 40000), // pastilha de freio
        MaintItemCfg(intervaloKm: 60000, intervaloDias: 730), // oleo de freio (2 anos)
      ]);

  Map<String, dynamic> toJson() => {
        'itens': itens.map((e) => e.toJson()).toList(),
        'nOleo': numOleoMotor,
        'nCorreia': numCorreia,
        'nCambio': numOleoCambio,
      };

  factory MaintConfig.fromJson(Map<String, dynamic> j) {
    final base = MaintConfig.padrao();
    try {
      final List list = j['itens'] ?? [];
      for (int i = 0; i < list.length && i < base.itens.length; i++) {
        base.itens[i] = MaintItemCfg.fromJson(list[i]);
      }
    } catch (_) {}
    base.numOleoMotor = j['nOleo'] ?? '';
    base.numCorreia = j['nCorreia'] ?? '';
    base.numOleoCambio = j['nCambio'] ?? '';
    return base;
  }
}

/// Resultado do calculo de um item (percentual + estimativa de vencimento).
class MaintStatus {
  final int indice;
  final String nome;
  final int intervaloKm;
  final int intervaloDias;
  final int kmRestante; // quanto falta de km (pode ser negativo = vencido)
  final int? diasRestantes; // por km (media de rodagem) OU por tempo, o que vier antes
  final DateTime? dataPrevista;
  final int percentual; // 0..100+ (o maior entre km e tempo)

  MaintStatus({
    required this.indice,
    required this.nome,
    required this.intervaloKm,
    required this.intervaloDias,
    required this.kmRestante,
    required this.diasRestantes,
    required this.dataPrevista,
    required this.percentual,
  });

  bool get vencido => percentual >= 100;
  bool get proximo => percentual >= 80 && percentual < 100;

  /// Calcula o status de um item dado o km atual, a data de hoje e a media km/dia.
  static MaintStatus calcular({
    required int indice,
    required MaintItemCfg item,
    required int kmAtual,
    required double kmPorDia,
  }) {
    final agora = DateTime.now();
    // ----- por KM -----
    int pctKm = 0;
    int kmRest = 0;
    if (item.intervaloKm > 0) {
      final rodado = kmAtual - item.kmUltima;
      kmRest = item.intervaloKm - rodado;
      pctKm = ((rodado / item.intervaloKm) * 100).round();
    }
    // ----- por TEMPO -----
    int pctTempo = 0;
    int? diasPorTempo;
    DateTime? dataPorTempo;
    if (item.intervaloDias > 0 && item.dataUltima != null) {
      final decorridos = agora.difference(item.dataUltima!).inDays;
      diasPorTempo = item.intervaloDias - decorridos;
      dataPorTempo = item.dataUltima!.add(Duration(days: item.intervaloDias));
      pctTempo = ((decorridos / item.intervaloDias) * 100).round();
    }
    // ----- estimativa por rodagem (km restante -> dias) -----
    int? diasPorKm;
    DateTime? dataPorKm;
    if (item.intervaloKm > 0 && kmPorDia > 0.1) {
      diasPorKm = (kmRest / kmPorDia).round();
      dataPorKm = agora.add(Duration(days: diasPorKm.clamp(-3650, 3650)));
    }
    // ----- o que vence PRIMEIRO (menor data) -----
    DateTime? dataPrev;
    int? diasRest;
    if (dataPorKm != null && dataPorTempo != null) {
      if (dataPorKm.isBefore(dataPorTempo)) {
        dataPrev = dataPorKm;
        diasRest = diasPorKm;
      } else {
        dataPrev = dataPorTempo;
        diasRest = diasPorTempo;
      }
    } else {
      dataPrev = dataPorKm ?? dataPorTempo;
      diasRest = diasPorKm ?? diasPorTempo;
    }
    return MaintStatus(
      indice: indice,
      nome: MaintConfig.nomes[indice],
      intervaloKm: item.intervaloKm,
      intervaloDias: item.intervaloDias,
      kmRestante: kmRest,
      diasRestantes: diasRest,
      dataPrevista: dataPrev,
      percentual: pctKm > pctTempo ? pctKm : pctTempo,
    );
  }
}
