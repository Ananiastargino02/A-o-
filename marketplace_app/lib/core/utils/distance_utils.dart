import 'dart:math';

/// Calculo de distancia entre coordenadas (formula de Haversine).
class DistanceUtils {
  DistanceUtils._();

  static double km({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    const raioTerraKm = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return raioTerraKm * c;
  }

  static double _toRad(double deg) => deg * (pi / 180);
}
