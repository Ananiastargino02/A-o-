const admin = require('firebase-admin');
const { geohashQueryBounds, distanceBetween } = require('geofire-common');

const db = () => admin.firestore();

/**
 * Busca lojas que atendem `categoria` e estao dentro de `raioKm` do ponto
 * `centro` ({latitude, longitude}). Usa geohash query bounds (geofire-common)
 * pra nao varrer a colecao inteira, e filtra a distancia exata (haversine)
 * no resultado, porque o bounding box do geohash e aproximado.
 */
async function lojasNoRaio(centro, raioKm, categoria) {
  const centroTuple = [centro.latitude, centro.longitude];
  const bounds = geohashQueryBounds(centroTuple, raioKm * 1000);

  const snaps = await Promise.all(
    bounds.map(([inicio, fim]) =>
      db
        .collection('lojas')
        .where('categorias', 'array-contains', categoria)
        .orderBy('geohash')
        .startAt(inicio)
        .endAt(fim)
        .get(),
    ),
  );

  const vistos = new Map();
  for (const snap of snaps) {
    for (const doc of snap.docs) {
      if (vistos.has(doc.id)) continue;
      const data = doc.data();
      const gp = data.geopoint;
      if (!gp) continue;
      const distanciaKm = distanceBetween([gp.latitude, gp.longitude], centroTuple);
      if (distanciaKm <= raioKm) {
        vistos.set(doc.id, { id: doc.id, distanciaKm, ...data });
      }
    }
  }
  return Array.from(vistos.values());
}

module.exports = { lojasNoRaio, distanceBetween };
