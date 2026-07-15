import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fleet_vehicle.dart';

/// Camada de SINCRONIZACAO da frota (a "tomada" onde a nuvem vai plugar).
///
/// Hoje roda com [LocalFleetSync] (tudo no proprio celular). Quando o servidor
/// for alugado, e so criar um [CloudFleetSync] de verdade e trocar o backend em
/// [FleetService] — nenhuma tela precisa mudar.
abstract class FleetSync {
  /// Nome curto do backend (aparece nas config).
  String get nome;

  /// true se este backend compartilha dados entre celulares (nuvem).
  bool get compartilha;

  Future<List<FleetVehicle>> carregar(String fleetId);
  Future<void> salvarVeiculo(String fleetId, FleetVehicle v);
  Future<void> removerVeiculo(String fleetId, String vehicleId);

  /// Motorista envia o retrato atual do carro dele.
  Future<void> enviarSnapshot(String fleetId, String vehicleId, VehicleSnapshot s);

  /// Stream ao vivo (so a nuvem implementa; local devolve null).
  Stream<List<FleetVehicle>>? observar(String fleetId) => null;
}

/// Backend LOCAL: guarda a frota no proprio celular (SharedPreferences).
/// Funciona 100% hoje para: "um celular gerencia varios carros".
/// Entre celulares diferentes NAO compartilha (isso e a nuvem, mais pra frente).
class LocalFleetSync implements FleetSync {
  @override
  String get nome => 'Local (neste celular)';
  @override
  bool get compartilha => false;

  String _k(String fleetId) => 'fleet_${fleetId}_vehicles';

  @override
  Future<List<FleetVehicle>> carregar(String fleetId) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_k(fleetId));
    if (s == null) return [];
    try {
      final List list = jsonDecode(s);
      return list.map((e) => FleetVehicle.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _salvarTodos(String fleetId, List<FleetVehicle> vs) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k(fleetId), jsonEncode(vs.map((e) => e.toJson()).toList()));
  }

  @override
  Future<void> salvarVeiculo(String fleetId, FleetVehicle v) async {
    final vs = await carregar(fleetId);
    final i = vs.indexWhere((e) => e.id == v.id);
    if (i >= 0) {
      vs[i] = v;
    } else {
      vs.add(v);
    }
    await _salvarTodos(fleetId, vs);
  }

  @override
  Future<void> removerVeiculo(String fleetId, String vehicleId) async {
    final vs = await carregar(fleetId);
    vs.removeWhere((e) => e.id == vehicleId);
    await _salvarTodos(fleetId, vs);
  }

  @override
  Future<void> enviarSnapshot(String fleetId, String vehicleId, VehicleSnapshot s) async {
    final vs = await carregar(fleetId);
    final i = vs.indexWhere((e) => e.id == vehicleId);
    if (i < 0) return;
    vs[i].snapshot = s;
    await _salvarTodos(fleetId, vs);
  }

  @override
  Stream<List<FleetVehicle>>? observar(String fleetId) => null;
}

/// Backend NUVEM — ESQUELETO pronto para o dia em que o servidor for alugado.
///
/// Basta implementar os metodos com o servico escolhido (ex.: Firebase
/// Firestore, Supabase, ou uma API REST propria) e registrar em [FleetService].
/// A estrutura de dados ja esta pronta: uma colecao "fleets/{fleetId}/vehicles"
/// onde cada doc e um [FleetVehicle] (com o snapshot embutido).
///
/// Enquanto nao estiver configurado, [FleetService] usa o [LocalFleetSync].
class CloudFleetSync implements FleetSync {
  final String baseUrl; // ex.: URL da API ou projeto Firebase
  final String? token; // credencial/login
  CloudFleetSync({required this.baseUrl, this.token});

  @override
  String get nome => 'Nuvem ($baseUrl)';
  @override
  bool get compartilha => true;

  Never _naoConfig() => throw UnimplementedError(
      'CloudFleetSync ainda nao implementado. Alugue o servidor e implemente '
      'carregar/salvar/remover/enviarSnapshot/observar aqui.');

  @override
  Future<List<FleetVehicle>> carregar(String fleetId) async => _naoConfig();
  @override
  Future<void> salvarVeiculo(String fleetId, FleetVehicle v) async => _naoConfig();
  @override
  Future<void> removerVeiculo(String fleetId, String vehicleId) async => _naoConfig();
  @override
  Future<void> enviarSnapshot(String fleetId, String vehicleId, VehicleSnapshot s) async =>
      _naoConfig();
  @override
  Stream<List<FleetVehicle>>? observar(String fleetId) => null;
}
