/// Perfil do carro (salvo localmente no celular).
class CarProfile {
  String nome;
  String marca;
  String modelo;
  String ano;
  int kmAtual;

  CarProfile({
    this.nome = '',
    this.marca = '',
    this.modelo = '',
    this.ano = '',
    this.kmAtual = 0,
  });

  bool get vazio => nome.isEmpty && marca.isEmpty && modelo.isEmpty;

  Map<String, dynamic> toJson() => {
        'nome': nome,
        'marca': marca,
        'modelo': modelo,
        'ano': ano,
        'kmAtual': kmAtual,
      };

  factory CarProfile.fromJson(Map<String, dynamic> j) => CarProfile(
        nome: j['nome'] ?? '',
        marca: j['marca'] ?? '',
        modelo: j['modelo'] ?? '',
        ano: j['ano'] ?? '',
        kmAtual: j['kmAtual'] ?? 0,
      );
}
