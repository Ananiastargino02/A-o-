/**
 * Popula o Firestore com dados de exemplo pra testar o APPNAME:
 * 5 lojas ficticias em Duque de Caxias/RJ e 3 pedidos de exemplo.
 *
 * Uso:
 *   1. Baixe uma chave de conta de servico do projeto Firebase
 *      (Configurações do projeto > Contas de serviço > Gerar nova chave
 *      privada) e salve como firebase/seed/service-account.json
 *      (NAO versione esse arquivo - ja esta no .gitignore).
 *   2. cd firebase/seed && npm install && npm run seed
 *
 * Os "users" criados aqui usam ids ficticios (nao correspondem a contas
 * reais do Firebase Auth) - servem pra popular listas/feeds durante o
 * desenvolvimento, nao pra logar como esses usuarios.
 */
const admin = require('firebase-admin');
const { geohashForLocation } = require('geofire-common');

admin.initializeApp({
  credential: admin.credential.cert(require('./service-account.json')),
});

const db = admin.firestore();

function geo(lat, lng) {
  return {
    geopoint: new admin.firestore.GeoPoint(lat, lng),
    geohash: geohashForLocation([lat, lng]),
  };
}

const CATEGORIA = 'pecas_automotivas';

const lojas = [
  {
    id: 'loja_seed_1',
    userId: 'user_seed_lojista_1',
    nomeLoja: 'Auto Peças Caxias Centro',
    cnpj: '12345678000190',
    endereco: 'Av. Presidente Vargas, 100 - Centro, Duque de Caxias - RJ',
    raioKm: 15,
    lat: -22.7856,
    lng: -43.3117,
  },
  {
    id: 'loja_seed_2',
    userId: 'user_seed_lojista_2',
    nomeLoja: 'Peças & Cia Jardim Primavera',
    cnpj: '23456789000181',
    endereco: 'Rua das Flores, 45 - Jardim Primavera, Duque de Caxias - RJ',
    raioKm: 10,
    lat: -22.7756,
    lng: -43.3057,
  },
  {
    id: 'loja_seed_3',
    userId: 'user_seed_lojista_3',
    nomeLoja: 'Desmanche Parque Lafaiete',
    cnpj: '34567890000172',
    endereco: 'Rua Ipê, 200 - Parque Lafaiete, Duque de Caxias - RJ',
    raioKm: 20,
    lat: -22.7920,
    lng: -43.3210,
  },
  {
    id: 'loja_seed_4',
    userId: 'user_seed_lojista_4',
    nomeLoja: 'Turbo Peças 25 de Agosto',
    cnpj: '45678901000163',
    endereco: 'Av. 25 de Agosto, 800 - 25 de Agosto, Duque de Caxias - RJ',
    raioKm: 8,
    lat: -22.7650,
    lng: -43.2950,
  },
  {
    id: 'loja_seed_5',
    userId: 'user_seed_lojista_5',
    nomeLoja: 'Xerém Auto Peças',
    cnpj: '56789012000154',
    endereco: 'Estrada de Xerém, 1500 - Xerém, Duque de Caxias - RJ',
    raioKm: 25,
    lat: -22.7500,
    lng: -43.3800,
  },
];

const pedidos = [
  {
    id: 'pedido_seed_1',
    clienteId: 'user_seed_cliente_1',
    marca: 'Volkswagen',
    modelo: 'Gol',
    ano: 2015,
    peca: 'Retrovisor esquerdo',
    detalhes: 'Quebrou a base, precisa trocar o conjunto todo.',
    lat: -22.7800,
    lng: -43.3100,
  },
  {
    id: 'pedido_seed_2',
    clienteId: 'user_seed_cliente_2',
    marca: 'Fiat',
    modelo: 'Uno',
    ano: 2012,
    peca: 'Amortecedor dianteiro',
    detalhes: 'Par de amortecedores dianteiros, carro balançando muito.',
    lat: -22.7830,
    lng: -43.3050,
  },
  {
    id: 'pedido_seed_3',
    clienteId: 'user_seed_cliente_3',
    marca: 'Chevrolet',
    modelo: 'Onix',
    ano: 2019,
    peca: 'Farol direito',
    detalhes: null,
    lat: -22.7780,
    lng: -43.3150,
  },
];

async function seed() {
  const batch = db.batch();

  for (const loja of lojas) {
    batch.set(db.collection('users').doc(loja.userId), {
      tipo: 'lojista',
      nome: `Dono(a) ${loja.nomeLoja}`,
      telefone: '+5521999990000',
      fcmToken: null,
      criadoEm: admin.firestore.FieldValue.serverTimestamp(),
    });

    batch.set(db.collection('lojas').doc(loja.id), {
      userId: loja.userId,
      nomeLoja: loja.nomeLoja,
      cnpj: loja.cnpj,
      endereco: loja.endereco,
      ...geo(loja.lat, loja.lng),
      raioKm: loja.raioKm,
      categorias: [CATEGORIA],
      logoUrl: null,
      avaliacaoMedia: 4.5,
      totalAvaliacoes: 12,
      creditos: 0,
      criadoEm: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  for (const pedido of pedidos) {
    batch.set(db.collection('users').doc(pedido.clienteId), {
      tipo: 'cliente',
      nome: `Cliente Exemplo ${pedido.id.slice(-1)}`,
      telefone: '+5521988880000',
      fcmToken: null,
      criadoEm: admin.firestore.FieldValue.serverTimestamp(),
    });

    batch.set(db.collection('pedidos').doc(pedido.id), {
      clienteId: pedido.clienteId,
      categoria: CATEGORIA,
      marca: pedido.marca,
      modelo: pedido.modelo,
      ano: pedido.ano,
      peca: pedido.peca,
      detalhes: pedido.detalhes,
      fotoUrl: null,
      ...geo(pedido.lat, pedido.lng),
      status: 'aberto',
      raioAtual: 5,
      lojasNotificadas: 0,
      lojasJaNotificadas: [],
      recusadoPor: [],
      criadoEm: admin.firestore.FieldValue.serverTimestamp(),
      expiraEm: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 48 * 60 * 60 * 1000)),
    });
  }

  await batch.commit();
  console.log(`Seed concluido: ${lojas.length} lojas e ${pedidos.length} pedidos criados.`);
  console.log('Dica: se as Cloud Functions estiverem deployadas, elas so notificam lojas em');
  console.log('pedidos NOVOS (trigger onCreate) - pedidos de seed ja entram com raioAtual: 5.');
  console.log('Rode a funcao expandirRaioPedidos manualmente ou espere o schedule pra testar a expansao.');
}

seed().catch((err) => {
  console.error('Erro ao rodar o seed:', err);
  process.exit(1);
});
