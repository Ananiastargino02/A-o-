/// Base de carros do mercado BR (marca -> modelos -> geracoes por ano).
/// Nao e exaustiva de proposito: cobre os mais comuns; a gente vai adicionando.
/// Use os helpers marcas(), modelosDe(), versoesPara().

class CarGen {
  final String nome; // ex.: "G5"
  final int ini, fim; // faixa de anos (fim = 9999 se ainda em linha)
  const CarGen(this.nome, this.ini, this.fim);
}

class CarModel {
  final String nome; // ex.: "Gol"
  final int ini, fim;
  final List<CarGen> geracoes; // vazio = sem geracoes conhecidas
  const CarModel(this.nome, this.ini, this.fim, [this.geracoes = const []]);
}

class CarBrand {
  final String nome;
  final List<CarModel> modelos;
  const CarBrand(this.nome, this.modelos);
}

const int _hj = 9999;

const List<CarBrand> carDb = [
  CarBrand('Volkswagen', [
    CarModel('Gol', 1980, _hj, [
      CarGen('G1 (quadrado)', 1980, 1994),
      CarGen('G2 (bola)', 1994, 1999),
      CarGen('G3', 1999, 2005),
      CarGen('G4', 2005, 2014),
      CarGen('G5', 2008, 2012),
      CarGen('G6', 2012, 2016),
      CarGen('G7', 2016, _hj),
    ]),
    CarModel('Voyage', 2008, _hj, [CarGen('G5', 2008, 2012), CarGen('G6', 2012, 2016), CarGen('G7', 2016, _hj)]),
    CarModel('Fox', 2003, 2021),
    CarModel('Polo', 2002, _hj, [CarGen('Hatch (antigo)', 2002, 2015), CarGen('MQB', 2017, _hj)]),
    CarModel('Virtus', 2018, _hj),
    CarModel('Saveiro', 1982, _hj, [CarGen('G5', 2009, 2013), CarGen('G6/G7', 2013, _hj)]),
    CarModel('Golf', 1994, 2019, [CarGen('MK4', 1999, 2006), CarGen('MK5', 2006, 2009), CarGen('MK6', 2009, 2013), CarGen('MK7', 2013, 2019)]),
    CarModel('T-Cross', 2019, _hj),
    CarModel('Nivus', 2020, _hj),
    CarModel('Jetta', 2006, _hj),
    CarModel('Amarok', 2010, _hj),
    CarModel('Up!', 2014, 2021),
    CarModel('Parati', 1982, 2013),
  ]),
  CarBrand('Fiat', [
    CarModel('Uno', 1984, _hj, [CarGen('Mille', 1990, 2013), CarGen('Novo Uno', 2010, _hj)]),
    CarModel('Palio', 1996, 2017, [CarGen('G1', 1996, 2001), CarGen('G2', 2001, 2004), CarGen('G3', 2004, 2011), CarGen('Novo', 2011, 2017)]),
    CarModel('Siena', 1997, 2016, [CarGen('EL', 1997, 2007), CarGen('Grand Siena', 2012, 2016)]),
    CarModel('Strada', 1998, _hj, [CarGen('1a ger', 1998, 2013), CarGen('2a ger', 2014, 2020), CarGen('Nova', 2020, _hj)]),
    CarModel('Argo', 2017, _hj),
    CarModel('Cronos', 2018, _hj),
    CarModel('Mobi', 2016, _hj),
    CarModel('Toro', 2016, _hj),
    CarModel('Pulse', 2021, _hj),
    CarModel('Fastback', 2022, _hj),
    CarModel('Idea', 2005, 2016),
    CarModel('Punto', 2007, 2017),
    CarModel('Doblo', 2001, 2022),
  ]),
  CarBrand('Chevrolet', [
    CarModel('Onix', 2012, _hj, [CarGen('1a ger', 2012, 2019), CarGen('Plus/2a ger', 2019, _hj)]),
    CarModel('Prisma', 2006, 2019, [CarGen('1a ger', 2006, 2012), CarGen('2a ger', 2013, 2019)]),
    CarModel('Celta', 2000, 2015),
    CarModel('Corsa', 1994, 2012, [CarGen('Wind/Classic', 1994, 2002), CarGen('Corsa novo', 2002, 2012)]),
    CarModel('Classic', 2003, 2016),
    CarModel('Cruze', 2011, _hj, [CarGen('1a ger', 2011, 2016), CarGen('2a ger', 2016, _hj)]),
    CarModel('Tracker', 2013, _hj, [CarGen('1a ger', 2013, 2019), CarGen('2a ger', 2020, _hj)]),
    CarModel('Spin', 2012, _hj),
    CarModel('S10', 1995, _hj),
    CarModel('Montana', 2003, _hj),
    CarModel('Cobalt', 2011, 2020),
    CarModel('Agile', 2009, 2014),
    CarModel('Astra', 1998, 2011),
    CarModel('Vectra', 1993, 2011),
  ]),
  CarBrand('Ford', [
    CarModel('Ka', 1997, 2021, [CarGen('1a ger', 1997, 2007), CarGen('2a ger', 2008, 2014), CarGen('3a ger', 2014, 2021)]),
    CarModel('Fiesta', 1996, 2019, [CarGen('Hatch antigo', 1996, 2013), CarGen('New Fiesta', 2013, 2019)]),
    CarModel('Focus', 2000, 2019),
    CarModel('EcoSport', 2003, 2021, [CarGen('1a ger', 2003, 2012), CarGen('2a ger', 2012, 2021)]),
    CarModel('Ranger', 1995, _hj),
    CarModel('Fusion', 2006, 2020),
    CarModel('Courier', 1998, 2013),
  ]),
  CarBrand('Honda', [
    CarModel('Civic', 1992, _hj, [
      CarGen('7a ger', 2001, 2006),
      CarGen('8a ger', 2006, 2011),
      CarGen('9a ger', 2012, 2016),
      CarGen('10a ger', 2016, 2021),
      CarGen('11a ger', 2022, _hj),
    ]),
    CarModel('Fit', 2003, 2021, [CarGen('1a ger', 2003, 2008), CarGen('2a ger', 2009, 2014), CarGen('3a ger', 2015, 2021)]),
    CarModel('City', 2009, _hj),
    CarModel('HR-V', 2015, _hj),
    CarModel('CR-V', 1997, _hj),
    CarModel('WR-V', 2017, _hj),
  ]),
  CarBrand('Toyota', [
    CarModel('Corolla', 1993, _hj, [
      CarGen('9a ger', 2003, 2008),
      CarGen('10a ger', 2008, 2014),
      CarGen('11a ger', 2014, 2019),
      CarGen('12a ger', 2019, _hj),
    ]),
    CarModel('Etios', 2012, 2021),
    CarModel('Yaris', 2018, _hj),
    CarModel('Hilux', 1997, _hj),
    CarModel('Corolla Cross', 2021, _hj),
    CarModel('SW4', 2005, _hj),
  ]),
  CarBrand('Hyundai', [
    CarModel('HB20', 2012, _hj, [CarGen('1a ger', 2012, 2019), CarGen('2a ger', 2019, _hj)]),
    CarModel('Creta', 2017, _hj),
    CarModel('Azera', 2007, 2018, [CarGen('TG', 2007, 2011), CarGen('HG', 2012, 2018)]),
    CarModel('Tucson', 2005, _hj),
    CarModel('ix35', 2010, 2021),
    CarModel('i30', 2009, 2016),
    CarModel('Elantra', 2011, 2020),
  ]),
  CarBrand('Renault', [
    CarModel('Sandero', 2007, _hj, [CarGen('1a ger', 2007, 2014), CarGen('2a ger', 2014, _hj)]),
    CarModel('Logan', 2007, _hj),
    CarModel('Duster', 2011, _hj),
    CarModel('Kwid', 2017, _hj),
    CarModel('Captur', 2017, _hj),
    CarModel('Oroch', 2015, _hj),
    CarModel('Clio', 1999, 2016),
    CarModel('Stepway', 2009, _hj),
  ]),
  CarBrand('Nissan', [
    CarModel('March', 2011, 2022),
    CarModel('Versa', 2011, _hj),
    CarModel('Kicks', 2016, _hj),
    CarModel('Frontier', 2002, _hj),
    CarModel('Sentra', 2007, _hj),
  ]),
  CarBrand('Jeep', [
    CarModel('Renegade', 2015, _hj),
    CarModel('Compass', 2017, _hj),
    CarModel('Commander', 2021, _hj),
  ]),
  CarBrand('Peugeot', [
    CarModel('206', 1999, 2010),
    CarModel('207', 2008, 2015),
    CarModel('208', 2013, _hj),
    CarModel('2008', 2015, _hj),
  ]),
  CarBrand('Citroen', [
    CarModel('C3', 2003, _hj),
    CarModel('C4', 2009, _hj),
    CarModel('Aircross', 2010, _hj),
  ]),
  CarBrand('Mitsubishi', [
    CarModel('Lancer', 2008, 2017),
    CarModel('ASX', 2011, _hj),
    CarModel('L200', 1999, _hj),
    CarModel('Pajero', 1998, _hj),
  ]),
];

// ---------------- helpers ----------------
List<String> marcas() => [for (final b in carDb) b.nome];

List<CarModel> modelosDe(String marca) {
  final b = carDb.where((x) => x.nome.toLowerCase() == marca.toLowerCase());
  return b.isEmpty ? const [] : b.first.modelos;
}

/// Acha o modelo em qualquer marca (quando o usuario digita so o modelo).
CarModel? acharModelo(String marca, String modelo) {
  final lista = marca.isNotEmpty ? modelosDe(marca) : [for (final b in carDb) ...b.modelos];
  for (final m in lista) {
    if (m.nome.toLowerCase() == modelo.toLowerCase()) return m;
  }
  return null;
}

/// Versoes/geracoes de um modelo VALIDAS num ano (vazio = sem geracoes conhecidas).
List<String> versoesPara(String marca, String modelo, int ano) {
  final m = acharModelo(marca, modelo);
  if (m == null || m.geracoes.isEmpty) return const [];
  return [
    for (final g in m.geracoes)
      if (ano <= 0 || (ano >= g.ini && ano <= g.fim)) '${g.nome}  (${g.ini}-${g.fim == 9999 ? "hoje" : g.fim})'
  ];
}
