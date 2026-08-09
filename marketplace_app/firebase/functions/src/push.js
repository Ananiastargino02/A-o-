const admin = require('firebase-admin');

const db = () => admin.firestore();

/**
 * Envia uma push notification (FCM) para um usuario, buscando o fcmToken
 * salvo em users/{userId}. Silencioso se o usuario nao tiver token (ainda
 * nao abriu o app ou negou notificacoes).
 */
async function enviarPushParaUsuario(userId, { title, body, data } = {}) {
  if (!userId) return;
  const userDoc = await db().collection('users').doc(userId).get();
  const token = userDoc.data()?.fcmToken;
  if (!token) return;

  try {
    await admin.messaging().send({
      token,
      notification: { title, body },
      data: Object.fromEntries(
        Object.entries(data || {}).map(([k, v]) => [k, String(v)]),
      ),
      android: { priority: 'high' },
      apns: { payload: { aps: { sound: 'default' } } },
    });
  } catch (err) {
    console.error(`Falha ao enviar push para ${userId}:`, err.message);
  }
}

module.exports = { enviarPushParaUsuario };
