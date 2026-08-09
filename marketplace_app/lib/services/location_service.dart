import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationService {
  Future<bool> garantirPermissao() async {
    var permissao = await Geolocator.checkPermission();
    if (permissao == LocationPermission.denied) {
      permissao = await Geolocator.requestPermission();
    }
    if (permissao == LocationPermission.deniedForever) return false;
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    return permissao == LocationPermission.always || permissao == LocationPermission.whileInUse;
  }

  Future<Position> posicaoAtual() {
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  /// Converte um endereco em lat/lng (usado no cadastro do lojista).
  Future<Location?> geocodificar(String endereco) async {
    try {
      final resultados = await locationFromAddress('$endereco, Brasil');
      return resultados.isEmpty ? null : resultados.first;
    } catch (_) {
      return null;
    }
  }
}
