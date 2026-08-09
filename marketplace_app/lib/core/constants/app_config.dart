/// Configuracao geral do app.
///
/// "APPNAME" e um placeholder de proposito: troque por busca-e-substituicao
/// (case-sensitive) por todo o projeto quando o nome final for definido.
/// Nao use "APPNAME" em nenhum identificador de pacote/bundle sem revisar
/// os arquivos nativos em android/ e ios/ tambem.
class AppConfig {
  AppConfig._();

  static const String appName = 'APPNAME';
  static const String appNameLower = 'appname';
  static const String appTagline = 'Peca um orcamento. Feche na hora.';

  /// Categorias do marketplace. Apenas [categoriaPecasAutomotivas] esta
  /// ativa nesta versao; as demais aparecem desabilitadas com selo "Em breve".
  static const String categoriaPecasAutomotivas = 'pecas_automotivas';

  static const List<CategoriaInfo> categorias = [
    CategoriaInfo(
      id: categoriaPecasAutomotivas,
      nome: 'Peças automotivas',
      icone: 'directions_car',
      ativa: true,
    ),
    CategoriaInfo(
      id: 'construcao',
      nome: 'Material de construção',
      icone: 'construction',
      ativa: false,
    ),
    CategoriaInfo(
      id: 'eletronicos',
      nome: 'Eletrônicos',
      icone: 'devices',
      ativa: false,
    ),
    CategoriaInfo(
      id: 'moveis',
      nome: 'Móveis e decoração',
      icone: 'chair',
      ativa: false,
    ),
    CategoriaInfo(
      id: 'pet',
      nome: 'Pet shop',
      icone: 'pets',
      ativa: false,
    ),
  ];

  // Raios de busca (km) e regras de expansao usados tambem pela Cloud Function
  // `expandirRaioPedidos`. Mantenha os dois lados em sincronia se alterar.
  static const List<double> raiosExpansaoKm = [5, 10, 20, 40];
  static const int minutosParaExpandir = 30;
  static const int minimoOrcamentosParaNaoExpandir = 3;
  static const int horasParaExpirarPedido = 48;

  static const String moedaSimbolo = 'R\$';
}

class CategoriaInfo {
  final String id;
  final String nome;
  final String icone;
  final bool ativa;

  const CategoriaInfo({
    required this.id,
    required this.nome,
    required this.icone,
    required this.ativa,
  });
}

enum TipoUsuario { cliente, lojista }

enum StatusPedido { aberto, expirado, fechado }

enum StatusChat { ativo, fechado }

enum CondicaoPeca { nova, usada, recondicionada }

enum TipoEntrega { retirada, entrega, retiradaEEntrega }

enum Garantia { semGarantia, umMes, tresMeses, seisMeses }

extension CondicaoPecaX on CondicaoPeca {
  String get label => switch (this) {
        CondicaoPeca.nova => 'Nova',
        CondicaoPeca.usada => 'Usada',
        CondicaoPeca.recondicionada => 'Recondicionada',
      };

  static CondicaoPeca fromString(String v) => CondicaoPeca.values.firstWhere(
        (e) => e.name == v,
        orElse: () => CondicaoPeca.usada,
      );
}

extension TipoEntregaX on TipoEntrega {
  String get label => switch (this) {
        TipoEntrega.retirada => 'Só retirada',
        TipoEntrega.entrega => 'Só entrega',
        TipoEntrega.retiradaEEntrega => 'Retirada + entrega com taxa',
      };

  static TipoEntrega fromString(String v) => TipoEntrega.values.firstWhere(
        (e) => e.name == v,
        orElse: () => TipoEntrega.retirada,
      );
}

extension GarantiaX on Garantia {
  String get label => switch (this) {
        Garantia.semGarantia => 'Sem garantia',
        Garantia.umMes => '1 mês',
        Garantia.tresMeses => '3 meses',
        Garantia.seisMeses => '6 meses',
      };

  static Garantia fromString(String v) => Garantia.values.firstWhere(
        (e) => e.name == v,
        orElse: () => Garantia.semGarantia,
      );
}
