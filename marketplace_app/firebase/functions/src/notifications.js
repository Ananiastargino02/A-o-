const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const { enviarPushParaUsuario } = require('./push');

const db = () => admin.firestore();

/**
 * Ao criar um orcamento: recalcula tempoRespostaMin no servidor (evita
 * depender do relogio do celular do lojista) e avisa o cliente.
 */
const onOrcamentoCriado = onDocumentCreated('orcamentos/{orcamentoId}', async (event) => {
  const snap = event.data;
  if (!snap) return;
  const orcamento = snap.data();

  const pedidoDoc = await db().collection('pedidos').doc(orcamento.pedidoId).get();
  if (!pedidoDoc.exists) return;
  const pedido = pedidoDoc.data();

  const criadoPedido = pedido.criadoEm?.toDate?.();
  const criadoOrcamento = orcamento.criadoEm?.toDate?.() ?? new Date();
  if (criadoPedido) {
    const tempoRespostaMin = Math.max(0, Math.round((criadoOrcamento - criadoPedido) / 60000));
    await snap.ref.update({ tempoRespostaMin });
  }

  const lojaDoc = await db().collection('lojas').doc(orcamento.lojaId).get();
  const nomeLoja = lojaDoc.data()?.nomeLoja ?? 'Uma loja';

  await enviarPushParaUsuario(pedido.clienteId, {
    title: 'Novo orçamento recebido! 💰',
    body: `${nomeLoja} respondeu seu pedido de "${pedido.peca}"`,
    data: { tipo: 'novo_orcamento', pedidoId: orcamento.pedidoId },
  });
});

/**
 * Ao enviar mensagem no chat: avisa a outra parte (cliente <-> lojista).
 */
const onMensagemCriada = onDocumentCreated('chats/{chatId}/mensagens/{mensagemId}', async (event) => {
  const snap = event.data;
  if (!snap) return;
  const mensagem = snap.data();

  const chatDoc = await db().collection('chats').doc(event.params.chatId).get();
  if (!chatDoc.exists) return;
  const chat = chatDoc.data();

  const souCliente = mensagem.remetenteId === chat.clienteId;
  let destinatarioUserId;
  let remetenteNome = 'Alguém';

  if (souCliente) {
    const lojaDoc = await db().collection('lojas').doc(chat.lojaId).get();
    destinatarioUserId = lojaDoc.data()?.userId;
    const clienteDoc = await db().collection('users').doc(chat.clienteId).get();
    remetenteNome = clienteDoc.data()?.nome ?? 'Cliente';
  } else {
    destinatarioUserId = chat.clienteId;
    const lojaDoc = await db().collection('lojas').doc(chat.lojaId).get();
    remetenteNome = lojaDoc.data()?.nomeLoja ?? 'Loja';
  }

  await enviarPushParaUsuario(destinatarioUserId, {
    title: remetenteNome,
    body: mensagem.texto || '📷 Enviou uma foto',
    data: { tipo: 'nova_mensagem', chatId: event.params.chatId },
  });
});

module.exports = { onOrcamentoCriado, onMensagemCriada };
