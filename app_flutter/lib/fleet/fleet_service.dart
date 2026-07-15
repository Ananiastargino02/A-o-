import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fleet_vehicle.dart';
import 'fleet_sync.dart';

enum FleetRole { patrao, motorista }

/// Estado da FROTA. Guarda o modo (frota ligada?), o papel (patrao/motorista),
/// o id da frota e a lista de veiculos — sempre via [FleetSync] (local hoje,
/// nuvem depois). Nenhuma tela conhece o backend; so fala com este servico.
class FleetService extends ChangeNotifier {
  static const _kOn = 'fleet_on';
  static const _kRole = 'fleet_role';
  static const _kId = 'fleet_id';
  static const _kMyVehicle = 'fleet_my_vehicle';

  // Backend de sincronizacao. Troque por CloudFleetSync(...) quando alugar o servidor.
  FleetSync _sync = LocalFleetSync();
  FleetSync get sync => _sync;

  bool ativo = false; // modo frota ligado
  FleetRole role = FleetRole.patrao;
  String fleetId = '';
  String? myVehicleId; // (motorista) qual carro este celular atualiza

  List<FleetVehicle> veiculos = [];
  bool carregando = false;

  /// Troca o backend (ex.: para nuvem) sem mexer nas telas.
  void usarBackend(FleetSync s) {
    _sync = s;
    notifyListeners();
  }

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    ativo = p.getBool(_kOn) ?? false;
    role = (p.getString(_kRole) == 'motorista') ? FleetRole.motorista : FleetRole.patrao;
    fleetId = p.getString(_kId) ?? '';
    myVehicleId = p.getString(_kMyVehicle);
    if (ativo && fleetId.isNotEmpty) await recarregar();
  }

  Future<void> _persistir() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOn, ativo);
    await p.setString(_kRole, role == FleetRole.motorista ? 'motorista' : 'patrao');
    await p.setString(_kId, fleetId);
    if (myVehicleId != null) {
      await p.setString(_kMyVehicle, myVehicleId!);
    } else {
      await p.remove(_kMyVehicle);
    }
  }

  Future<void> configurar({
    required bool ligado,
    required FleetRole papel,
    required String id,
  }) async {
    ativo = ligado;
    role = papel;
    fleetId = id.trim();
    await _persistir();
    if (ativo && fleetId.isNotEmpty) {
      await recarregar();
    } else {
      veiculos = [];
      notifyListeners();
    }
  }

  Future<void> recarregar() async {
    if (fleetId.isEmpty) return;
    carregando = true;
    notifyListeners();
    veiculos = await _sync.carregar(fleetId);
    veiculos.sort((a, b) => a.titulo.toLowerCase().compareTo(b.titulo.toLowerCase()));
    carregando = false;
    notifyListeners();
  }

  Future<void> salvarVeiculo(FleetVehicle v) async {
    await _sync.salvarVeiculo(fleetId, v);
    await recarregar();
  }

  Future<void> removerVeiculo(String vehicleId) async {
    await _sync.removerVeiculo(fleetId, vehicleId);
    await recarregar();
  }

  Future<void> definirMeuVeiculo(String? vehicleId) async {
    myVehicleId = vehicleId;
    await _persistir();
    notifyListeners();
  }

  /// (Motorista) envia o retrato atual do carro para a frota.
  Future<void> reportar(VehicleSnapshot snap) async {
    if (!ativo || role != FleetRole.motorista) return;
    final id = myVehicleId;
    if (id == null || fleetId.isEmpty) return;
    await _sync.enviarSnapshot(fleetId, id, snap);
    // atualiza local para refletir na tela do proprio motorista
    final i = veiculos.indexWhere((e) => e.id == id);
    if (i >= 0) {
      veiculos[i].snapshot = snap;
      notifyListeners();
    }
  }

  FleetVehicle? get meuVeiculo {
    final id = myVehicleId;
    if (id == null) return null;
    for (final v in veiculos) {
      if (v.id == id) return v;
    }
    return null;
  }

  String novoId() => 'v${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
}
