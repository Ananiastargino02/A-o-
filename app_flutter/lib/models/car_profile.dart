/// Perfil do carro (salvo localmente no celular).
class CarProfile {
  String nome;
  String marca;
  String modelo;
  String versao; // geracao/versao escolhida na base (ex.: "G5 (2008-2012)")
  String ano;
  int kmAtual;

  CarProfile({
    this.nome = '',
    this.marca = '',
    this.modelo = '',
    this.versao = '',
    this.ano = '',
    this.kmAtual = 0,
  });

  bool get vazio => nome.isEmpty && marca.isEmpty && modelo.isEmpty;

  Map<String, dynamic> toJson() => {
        'nome': nome,
        'marca': marca,
        'modelo': modelo,
        'versao': versao,
        'ano': ano,
        'kmAtual': kmAtual,
      };

  factory CarProfile.fromJson(Map<String, dynamic> j) => CarProfile(
        nome: j['nome'] ?? '',
        marca: j['marca'] ?? '',
        modelo: j['modelo'] ?? '',
        versao: j['versao'] ?? '',
        ano: j['ano'] ?? '',
        kmAtual: j['kmAtual'] ?? 0,
      );
}
