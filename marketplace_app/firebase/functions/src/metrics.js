const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { distanceBetween } = require('./geo');

const db = () => admin.firestore();

/**
 * Recalcula a media de avaliacoes da loja sempre que uma nova avaliacao
 * chega. Recontagem simples (sem incremento) - volume esperado e baixo o
 * suficiente pra isso ser barato.
 */
const onAvaliacaoCriada = onDocumentCreated('avaliacoes/{avaliacaoId}', async (event) => {
  const snap = event.data;
  if (!snap) return;
  const { lojaId } = snap.data();
  if (!lojaId) return;

  const todasSnap = await db().collection('avaliacoes').where('lojaId', '==', lojaId).get();
  const total = todasSnap.size;
  const soma = todasSnap.docs.reduce((acc, d) => acc + (d.data().estrelas || 0), 0);
  const media = total > 0 ? soma / total : 0;

  await db().collection('lojas').doc(lojaId).update({
    totalAvaliacoes: total,
    avaliacaoMedia: Math.round(media * 10) / 10,
  });
});

/**
 * Metricas do card "Seu mes" da tela de Vendas do lojista. Roda no
 * servidor pra reaproveitar a mesma logica de raio usada na notificacao
 * (lojasNoRaio) e nao expor a query completa de pedidos pro client.
 */
const obterMetricasLoja = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Faça login para ver as métricas.');
  }

  const lojaSnap = await db().collection('lojas').where('userId', '==', request.auth.uid).limit(1).get();
  if (lojaSnap.empty) {
    throw new HttpsError('not-found', 'Loja não encontrada para este usuário.');
  }
  const loja = { id: lojaSnap.docs[0].id, ...lojaSnap.docs[0].data() };

  const inicioMes = new Date();
  inicioMes.setDate(1);
  inicioMes.setHours(0, 0, 0, 0);
  const inicioMesTs = admin.firestore.Timestamp.fromDate(inicioMes);

  const [orcamentosSnap, chatsSnap, vendasSnap] = await Promise.all([
    db()
      .collection('orcamentos')
      .where('lojaId', '==', loja.id)
      .where('criadoEm', '>=', inicioMesTs)
      .get(),
    db()
      .collection('chats')
      .where('lojaId', '==', loja.id)
      .where('criadoEm', '>=', inicioMesTs)
      .get(),
    db()
      .collection('chats')
      .where('lojaId', '==', loja.id)
      .where('status', '==', 'fechado')
      .where('criadoEm', '>=', inicioMesTs)
      .get(),
  ]);

  let pedidosRecebidos = 0;
  for (const categoria of loja.categorias || []) {
    const abertosSnap = await db()
      .collection('pedidos')
      .where('categoria', '==', categoria)
      .where('criadoEm', '>=', inicioMesTs)
      .get();
    const dentroDoRaio = abertosSnap.docs.filter((doc) => {
      const p = doc.data();
      if (!p.geopoint) return false;
      const distancia = distanceBetween(
        [p.geopoint.latitude, p.geopoint.longitude],
        [loja.geopoint.latitude, loja.geopoint.longitude],
      );
      return distancia <= loja.raioKm;
    });
    pedidosRecebidos += dentroDoRaio.length;
  }

  return {
    pedidosRecebidos,
    orcamentosEnviados: orcamentosSnap.size,
    chatsAbertos: chatsSnap.size,
    vendasConfirmadas: vendasSnap.size,
  };
});

module.exports = { onAvaliacaoCriada, obterMetricasLoja };
