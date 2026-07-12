/// Dados ao vivo do carro, vindos do comando "STATUS" do VEICAN.
///
/// Formato da resposta (firmware):
///   km=123 bat=13.8V rpm=850 temp=90 vel=0 comb=74 motor=12h30m proto=11b/500k estado=OPERANDO
class LiveData {
  final int km;
  final double bateria; // V
  final int rpm;
  final int temp; // °C
  final int velocidade; // km/h
  final int combustivel; // %
  final int motorHoras;
  final int motorMin;
  final String proto; // ex.: 11b/500k
  final String estado; // OPERANDO / STANDBY
  final DateTime atualizadoEm;

  LiveData({
    this.km = 0,
    this.bateria = 0,
    this.rpm = 0,
    this.temp = 0,
    this.velocidade = 0,
    this.combustivel = 0,
    this.motorHoras = 0,
    this.motorMin = 0,
    this.proto = '--',
    this.estado = '--',
    DateTime? atualizadoEm,
  }) : atualizadoEm = atualizadoEm ?? DateTime.now();

  bool get ligado => rpm > 0;
  bool get standby => estado == 'STANDBY';

  /// Extrai um "chave=valor" de uma linha de STATUS.
  static String? _campo(String s, String chave) {
    final re = RegExp('$chave=([^\\s]+)');
    return re.firstMatch(s)?.group(1);
  }

  static int _int(String? v) => v == null ? 0 : (int.tryParse(v) ?? 0);
  static double _double(String? v) =>
      v == null ? 0 : (double.tryParse(v.replaceAll('V', '')) ?? 0);

  factory LiveData.parse(String s) {
    // motor=12h30m
    int mh = 0, mm = 0;
    final motor = _campo(s, 'motor');
    if (motor != null) {
      final m = RegExp(r'(\d+)h(\d+)m').firstMatch(motor);
      if (m != null) {
        mh = int.tryParse(m.group(1)!) ?? 0;
        mm = int.tryParse(m.group(2)!) ?? 0;
      }
    }
    return LiveData(
      km: _int(_campo(s, 'km')),
      bateria: _double(_campo(s, 'bat')),
      rpm: _int(_campo(s, 'rpm')),
      temp: _int(_campo(s, 'temp')),
      velocidade: _int(_campo(s, 'vel')),
      combustivel: _int(_campo(s, 'comb')),
      motorHoras: mh,
      motorMin: mm,
      proto: _campo(s, 'proto') ?? '--',
      estado: _campo(s, 'estado') ?? '--',
    );
  }
}
