const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
const { lojasNoRaio } = require('./geo');
const { enviarPushParaUsuario } = require('./push');
const { RAIOS_KM, MINUTOS_PARA_EXPANDIR, MINIMO_ORCAMENTOS, HORAS_PARA_EXPIRAR } = require('./config');

const db = () => admin.firestore();

function textoPush(pedido) {
  return {
    title: 'Novo pedido perto de você',
    body: `${pedido.marca} ${pedido.modelo} ${pedido.ano} · ${pedido.peca}`,
  };
}

/**
 * Ao criar um pedido, notifica as lojas dentro do primeiro raio (5km).
 */
const onPedidoCriado = onDocumentCreated('pedidos/{pedidoId}', async (event) => {
  const snap = event.data;
  if (!snap) return;
  const pedido = snap.data();
  const pedidoId = event.params.pedidoId;

  const raioInicial = RAIOS_KM[0];
  const lojas = await lojasNoRaio(pedido.geopoint, raioInicial, pedido.categoria);

  await snap.ref.update({
    raioAtual: raioInicial,
    lojasNotificadas: lojas.length,
    lojasJaNotificadas: lojas.map((l) => l.id),
  });

  const { title, body } = textoPush(pedido);
  await Promise.all(
    lojas.map((loja) =>
      enviarPushParaUsuario(loja.userId, { title, body, data: { tipo: 'novo_pedido', pedidoId } }),
    ),
  );
});

/**
 * Roda periodicamente: expande o raio de pedidos abertos com menos de
 * MINIMO_ORCAMENTOS respostas a cada MINUTOS_PARA_EXPANDIR, e expira
 * pedidos com mais de HORAS_PARA_EXPIRAR sem resposta suficiente.
 */
const expandirRaioPedidos = onSchedule('every 10 minutes', async () => {
  const agora = Date.now();
  const abertosSnap = await db().collection('pedidos').where('status', '==', 'aberto').get();

  for (const doc of abertosSnap.docs) {
    const pedido = doc.data();
    const criadoEm = pedido.criadoEm?.toDate?.() ?? new Date();
    const idadeMin = (agora - criadoEm.getTime()) / 60000;

    if (idadeMin >= HORAS_PARA_EXPIRAR * 60) {
      await doc.ref.update({ status: 'expirado' });
      continue;
    }

    const indiceAtual = RAIOS_KM.indexOf(pedido.raioAtual);
    if (indiceAtual === -1 || indiceAtual === RAIOS_KM.length - 1) continue;

    const janelasPassadas = Math.floor(idadeMin / MINUTOS_PARA_EXPANDIR);
    if (janelasPassadas <= indiceAtual) continue;

    const orcamentosSnap = await db().collection('orcamentos').where('pedidoId', '==', doc.id).get();
    if (orcamentosSnap.size >= MINIMO_ORCAMENTOS) continue;

    const novoRaio = RAIOS_KM[indiceAtual + 1];
    const lojas = await lojasNoRaio(pedido.geopoint, novoRaio, pedido.categoria);
    const jaNotificadas = new Set(pedido.lojasJaNotificadas || []);
    const novas = lojas.filter((l) => !jaNotificadas.has(l.id));

    await doc.ref.update({
      raioAtual: novoRaio,
      lojasNotificadas: lojas.length,
      lojasJaNotificadas: lojas.map((l) => l.id),
    });

    const { title, body } = textoPush(pedido);
    await Promise.all(
      novas.map((loja) =>
        enviarPushParaUsuario(loja.userId, { title, body, data: { tipo: 'novo_pedido', pedidoId: doc.id } }),
      ),
    );
  }
});

module.exports = { onPedidoCriado, expandirRaioPedidos };
