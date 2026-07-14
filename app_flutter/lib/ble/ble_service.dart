import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/live_data.dart';
import '../storage/speed_store.dart';
import '../storage/consumption_store.dart';

/// UUIDs do Nordic UART Service (NUS) — devem casar com o firmware do VEICAN.
class VUuids {
  static final service = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
  static final rx = Guid('6E400002-B5A3-F393-E0A9-E50E24DCCA9E'); // app -> aparelho (write)
  static final tx = Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E'); // aparelho -> app (notify)
  static const deviceName = 'VEICAN';
}

enum VConn { desconectado, procurando, conectando, conectado }

/// Servico central de Bluetooth. Uma unica instancia (Provider) cuida de:
/// escanear, conectar, mandar comandos e devolver as respostas.
///
/// O firmware manda a resposta em pedacos de 180 bytes e as linhas de STATUS/
/// MANUT vem de uma vez. Aqui a gente casa cada comando com a proxima resposta
/// (o firmware processa 1 comando por vez), com timeout.
class BleService extends ChangeNotifier {
  VConn conn = VConn.desconectado;
  String? erro;
  LiveData? live;

  /// Historico recente do RPM (p/ o grafico ao vivo). Guarda ~60 amostras.
  final List<double> rpmHist = [];
  static const int _maxHist = 60;

  /// Historico de consumo de combustivel (km/L e nivel do tanque por dia).
  final consumoStore = ConsumptionStore();

  /// Historico de velocidade (maxima por dia) + recorde.
  final speedStore = SpeedStore();
  int speedMaxHoje = 0;
  int speedRecorde = 0;
  DateTime? speedRecordeData;
  Timer? _pollTimer;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _rx;
  BluetoothCharacteristic? _tx;
  StreamSubscription? _txSub;
  StreamSubscription? _connSub;

  // fila de comandos: 1 por vez (o firmware nao processa paralelo)
  final _fila = <_Req>[];
  _Req? _atual;
  final _buffer = StringBuffer();
  Timer? _respTimer;

  bool get conectado => conn == VConn.conectado;
  String get deviceId => _device?.remoteId.str ?? '';

  // ---------------- Scan + conexao ----------------

  /// Escaneia e conecta no primeiro VEICAN encontrado.
  Future<void> conectar() async {
    erro = null;
    _setConn(VConn.procurando);
    try {
      if (await FlutterBluePlus.isSupported == false) {
        throw 'Bluetooth nao suportado neste aparelho';
      }
      // liga o adaptador se possivel (Android)
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {}
      }

      BluetoothDevice? achado;
      final sub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final advName = r.advertisementData.advName.trim();
          final platformName = r.device.platformName.trim();
          final nome = advName.isNotEmpty ? advName : platformName;

          debugPrint(
            'BLE encontrado: advName="$advName", '
            'platformName="$platformName", '
            'id=${r.device.remoteId}',
          );

          // casa por "contem" (ignora maiuscula/minuscula) -> robusto a espacos
          // e a variacoes de nome anunciado entre aparelhos.
          if (nome.toUpperCase().contains(VUuids.deviceName.toUpperCase())) {
            achado = r.device;
          }
        }
      });

      // scan aberto + filtro por NOME no listener (mais robusto que withServices,
      // que alguns aparelhos nao reportam de forma confiavel)
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
      // espera achar (ou o scan terminar)
      final fim = DateTime.now().add(const Duration(seconds: 12));
      while (achado == null && DateTime.now().isBefore(fim)) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      await FlutterBluePlus.stopScan();
      await sub.cancel();

      if (achado == null) {
        throw 'VEICAN nao encontrado. Ligue o carro e deixe o aparelho perto.';
      }
      await _conectarDevice(achado!);
    } catch (e) {
      erro = e.toString();
      _setConn(VConn.desconectado);
    }
  }

  Future<void> _conectarDevice(BluetoothDevice d) async {
    _setConn(VConn.conectando);
    _device = d;
    _connSub?.cancel();
    _connSub = d.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && conn != VConn.desconectado) {
        _limpar();
        _setConn(VConn.desconectado);
      }
    });

    await d.connect(timeout: const Duration(seconds: 15), autoConnect: false);
    // MTU maior ajuda respostas grandes (Android)
    try {
      await d.requestMtu(200);
    } catch (_) {}

    final servicos = await d.discoverServices();
    for (final s in servicos) {
      if (s.uuid == VUuids.service) {
        for (final c in s.characteristics) {
          if (c.uuid == VUuids.rx) _rx = c;
          if (c.uuid == VUuids.tx) _tx = c;
        }
      }
    }
    if (_rx == null || _tx == null) {
      await d.disconnect();
      throw 'Servico do VEICAN nao encontrado';
    }

    await _tx!.setNotifyValue(true);
    _txSub = _tx!.onValueReceived.listen(_onDados);

    _setConn(VConn.conectado);
    await _syncSpeedDevice();   // puxa o historico gravado no aparelho
    await _carregarRecordes();
    _startPolling();
  }

  /// Ao conectar, puxa o historico de velocidade do aparelho (SPEEDHIST) e junta
  /// com o local -> registra ate os passeios sem o celular por perto.
  Future<void> _syncSpeedDevice() async {
    try {
      final r = await enviar('SPEEDHIST', timeout: const Duration(seconds: 6));
      if (r.contains(':')) {
        final n = await speedStore.mergeDevice(r);
        if (n > 0) debugPrint('[SPEED] sincronizados $n dias do aparelho');
      }
    } catch (_) {}
  }

  // ---------------- Polling automatico (roda enquanto conectado) ----------------

  void _startPolling() {
    _pollTimer?.cancel();
    // le o STATUS ~1x/seg sozinho -> grava velocidade e alimenta os graficos
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      atualizarStatus();
    });
    atualizarStatus(); // primeira leitura imediata
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _carregarRecordes() async {
    speedMaxHoje = await speedStore.maxHoje();
    final rec = await speedStore.recorde();
    if (rec != null) {
      speedRecorde = rec.key;
      speedRecordeData = rec.value;
    }
    notifyListeners();
  }

  Future<void> desconectar() async {
    final d = _device;
    _limpar();
    _setConn(VConn.desconectado);
    if (d != null) {
      try {
        await d.disconnect();
      } catch (_) {}
    }
  }

  void _limpar() {
    _stopPolling();
    _txSub?.cancel();
    _connSub?.cancel();
    _respTimer?.cancel();
    for (final r in _fila) {
      if (!r.completer.isCompleted) r.completer.complete('');
    }
    _fila.clear();
    if (_atual != null && !_atual!.completer.isCompleted) {
      _atual!.completer.complete('');
    }
    _atual = null;
    _buffer.clear();
    _rx = null;
    _tx = null;
    _device = null;
    live = null;
  }

  // ---------------- Comandos ----------------

  /// Envia um comando e espera a resposta (string). Uma fila serializa tudo.
  Future<String> enviar(String cmd, {Duration timeout = const Duration(seconds: 7)}) {
    if (!conectado || _rx == null) return Future.value('');
    final req = _Req(cmd, timeout);
    _fila.add(req);
    _tentarProximo();
    return req.completer.future;
  }

  void _tentarProximo() {
    if (_atual != null || _fila.isEmpty || _rx == null) return;
    _atual = _fila.removeAt(0);
    _buffer.clear();
    final bytes = utf8.encode(_atual!.cmd);
    _rx!.write(bytes, withoutResponse: false).catchError((_) {
      _finalizar('');
    });
    _respTimer?.cancel();
    _respTimer = Timer(_atual!.timeout, () => _finalizar(_buffer.toString()));
  }

  void _onDados(List<int> data) {
    final texto = utf8.decode(data, allowMalformed: true);
    _buffer.write(texto);
    // reinicia um timer curto: assume que a resposta terminou apos ~350ms de silencio
    _respTimer?.cancel();
    _respTimer = Timer(const Duration(milliseconds: 350), () {
      _finalizar(_buffer.toString());
    });
  }

  void _finalizar(String resp) {
    _respTimer?.cancel();
    final req = _atual;
    _atual = null;
    if (req != null && !req.completer.isCompleted) {
      req.completer.complete(resp.trim());
    }
    _tentarProximo();
  }

  /// Atualiza os dados ao vivo (chamado periodicamente pela tela).
  Future<void> atualizarStatus() async {
    final r = await enviar('STATUS');
    if (r.isNotEmpty && r.contains('rpm=')) {
      live = LiveData.parse(r);
      rpmHist.add(live!.rpm.toDouble());
      if (rpmHist.length > _maxHist) rpmHist.removeAt(0);

      // registra a velocidade no historico (grava so quando o maximo do dia sobe)
      final v = live!.velocidade;
      if (v > 0) {
        if (v > speedMaxHoje) speedMaxHoje = v;
        final mudou = await speedStore.record(v);
        if (mudou && v > speedRecorde) {
          speedRecorde = v;
          speedRecordeData = DateTime.now();
        }
      }

      // registra o consumo (km do hodometro + nivel do tanque) -> graficos de km/L
      await consumoStore.record(live!.km, live!.combustivel);

      notifyListeners();
    }
  }

  // ---------------- helpers ----------------

  void _setConn(VConn c) {
    conn = c;
    notifyListeners();
  }

  @override
  void dispose() {
    _limpar();
    super.dispose();
  }
}

class _Req {
  final String cmd;
  final Duration timeout;
  final completer = Completer<String>();
  _Req(this.cmd, this.timeout);
}
