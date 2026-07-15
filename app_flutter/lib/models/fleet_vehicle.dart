/// Um veiculo da FROTA e o ultimo retrato (snapshot) que o motorista enviou.
///
/// O snapshot e o que o patrao ve sem estar conectado no Bluetooth do carro:
/// os ultimos valores que o celular do motorista reportou.
class VehicleSnapshot {
  final int km;
  final int rpm;
  final int velocidade;
  final int temp;
  final int combustivel;
  final double bateria;
  final String estado;
  final DateTime? visto; // quando o motorista reportou pela ultima vez

  const VehicleSnapshot({
    this.km = 0,
    this.rpm = 0,
    this.velocidade = 0,
    this.temp = 0,
    this.combustivel = -1,
    this.bateria = 0,
    this.estado = '--',
    this.visto,
  });

  Map<String, dynamic> toJson() => {
        'km': km,
        'rpm': rpm,
        'vel': velocidade,
        'temp': temp,
        'comb': combustivel,
        'bat': bateria,
        'estado': estado,
        'visto': visto?.millisecondsSinceEpoch,
      };

  factory VehicleSnapshot.fromJson(Map<String, dynamic> j) => VehicleSnapshot(
        km: (j['km'] as num?)?.toInt() ?? 0,
        rpm: (j['rpm'] as num?)?.toInt() ?? 0,
        velocidade: (j['vel'] as num?)?.toInt() ?? 0,
        temp: (j['temp'] as num?)?.toInt() ?? 0,
        combustivel: (j['comb'] as num?)?.toInt() ?? -1,
        bateria: (j['bat'] as num?)?.toDouble() ?? 0,
        estado: j['estado'] ?? '--',
        visto: j['visto'] != null
            ? DateTime.fromMillisecondsSinceEpoch(j['visto'] as int)
            : null,
      );
}

class FleetVehicle {
  final String id; // unico dentro da frota
  String apelido;
  String placa;
  String marca;
  String modelo;
  String ano;
  String motorista; // nome do motorista responsavel
  VehicleSnapshot? snapshot;

  FleetVehicle({
    required this.id,
    this.apelido = '',
    this.placa = '',
    this.marca = '',
    this.modelo = '',
    this.ano = '',
    this.motorista = '',
    this.snapshot,
  });

  String get titulo => apelido.isNotEmpty
      ? apelido
      : [marca, modelo].where((s) => s.isNotEmpty).join(' ');

  /// Ha quanto tempo o motorista nao reporta (null = nunca).
  Duration? get idade {
    final v = snapshot?.visto;
    if (v == null) return null;
    return DateTime.now().difference(v);
  }

  /// true se o carro reportou nos ultimos 10 minutos (motorista "online").
  bool get online {
    final i = idade;
    return i != null && i.inMinutes < 10;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'apelido': apelido,
        'placa': placa,
        'marca': marca,
        'modelo': modelo,
        'ano': ano,
        'motorista': motorista,
        'snapshot': snapshot?.toJson(),
      };

  factory FleetVehicle.fromJson(Map<String, dynamic> j) => FleetVehicle(
        id: j['id'] as String,
        apelido: j['apelido'] ?? '',
        placa: j['placa'] ?? '',
        marca: j['marca'] ?? '',
        modelo: j['modelo'] ?? '',
        ano: j['ano'] ?? '',
        motorista: j['motorista'] ?? '',
        snapshot: j['snapshot'] != null
            ? VehicleSnapshot.fromJson(j['snapshot'] as Map<String, dynamic>)
            : null,
      );
}
