import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'services_providers.dart';

/// Posicao atual do usuario. Recarregue com `ref.invalidate(currentPositionProvider)`.
final currentPositionProvider = FutureProvider<Position?>((ref) async {
  final service = ref.watch(locationServiceProvider);
  final permitido = await service.garantirPermissao();
  if (!permitido) return null;
  return service.posicaoAtual();
});
