import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';

/// Wrapper fino sobre geoflutterfire_plus so para gerar o geohash que
/// acompanha cada GeoPoint salvo (pedidos.geohash, lojas.geohash). As
/// queries de raio em si sao feitas com Haversine no client (telas) e com
/// `geofire-common` nas Cloud Functions - ver DistanceUtils e
/// firebase/functions/src/raioExpansion.js.
class GeoHelper {
  GeoHelper._();

  static String geohashDe(GeoPoint ponto) {
    return GeoFirePoint(ponto).geohash;
  }
}
