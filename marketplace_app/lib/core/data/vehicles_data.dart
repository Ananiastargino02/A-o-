/// Base simplificada de marcas/modelos das montadoras mais vendidas no Brasil.
/// Usada nos dropdowns de "Novo pedido". Anos vao de 1990 ate o ano atual + 1.
class VehiclesData {
  VehiclesData._();

  static final List<int> anos = List.generate(
    DateTime.now().year + 1 - 1990 + 1,
    (i) => DateTime.now().year + 1 - i,
  );

  static const Map<String, List<String>> marcasModelos = {
    'Volkswagen': [
      'Gol', 'Voyage', 'Polo', 'Virtus', 'T-Cross', 'Nivus', 'Saveiro',
      'Fox', 'Up!', 'Jetta', 'Golf', 'Amarok', 'Taos', 'Fusca',
    ],
    'Fiat': [
      'Uno', 'Palio', 'Argo', 'Mobi', 'Cronos', 'Toro', 'Strada',
      'Pulse', 'Fastback', 'Siena', 'Punto', 'Doblo', 'Fiorino',
    ],
    'Chevrolet': [
      'Onix', 'Onix Plus', 'Prisma', 'Celta', 'Corsa', 'Cruze',
      'Tracker', 'Spin', 'S10', 'Montana', 'Cobalt', 'Astra',
    ],
    'Hyundai': [
      'HB20', 'HB20S', 'Creta', 'Tucson', 'ix35', 'Santa Fe', 'Azera', 'i30',
    ],
    'Renault': [
      'Kwid', 'Sandero', 'Logan', 'Duster', 'Captur', 'Oroch', 'Fluence', 'Clio',
    ],
    'Toyota': [
      'Corolla', 'Corolla Cross', 'Yaris', 'Etios', 'Hilux', 'SW4', 'RAV4',
    ],
    'Honda': [
      'Civic', 'City', 'Fit', 'HR-V', 'WR-V', 'CR-V', 'Accord',
    ],
    'Ford': [
      'Ka', 'Ka Sedan', 'Fiesta', 'Focus', 'EcoSport', 'Ranger', 'Fusion', 'Edge',
    ],
    'Nissan': [
      'March', 'Versa', 'Sentra', 'Kicks', 'Frontier', 'Livina',
    ],
    'Jeep': [
      'Renegade', 'Compass', 'Commander', 'Wrangler', 'Cherokee',
    ],
  };

  static List<String> get marcas => marcasModelos.keys.toList();

  static List<String> modelosDe(String marca) => marcasModelos[marca] ?? [];
}
