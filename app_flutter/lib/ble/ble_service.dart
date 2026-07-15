import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/live_data.dart';
import '../storage/speed_store.dart';
import '../storage/consumption_store.dart';
import '../storage/car_scope.dart';
import '../storage/local_store.dart';

/// UUIDs do Nordic UART Service (NUS) — devem casar com o firmware do VEICAN.
class VUuids {
  static final service = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
  static final rx = Guid('6E400002-B5A3-F393-E0A9-E50E24DCCA9E'); // app -> aparelho (write)
  static final tx = Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E'); // aparelho -> app (notify)
  static const deviceName = 'VEICAN';
}

enum VConn { desconectado, procurando, conectando, conectado }

/// Um VEICAN encontrado no scan (para a lista de escolha).
class VeicanDevice {
  final String id; // remoteId (MAC no Android)
  final String nome;
  VeicanDevice(this.id, this.nome);
}

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
  StreamSubscription? _scanSub;

  final _localStore = LocalStore();
  final List<VeicanDevice> encontrados = [];   // lista do scan (p/ escolher)
  String? dispositivoSalvo;                     // ultimo VEICAN escolhido (reconecta nele)
  bool get temDispositivoSalvo => dispositivoSalvo != null;
  bool _scanning = false;                       // trava scan concorrente
  bool _userDesconectou = false;                // desconexao pedida pelo usuario
  Timer? _reconnectTimer;

  // fila de comandos: 1 por vez (o firmware nao processa paralelo)
  final _fila = <_Req>[];
  _Req? _atual;
  final _buffer = StringBuffer();
  Timer? _respTimer;

  bool get conectado => conn == VConn.conectado;
  String get deviceId => _device?.remoteId.str ?? '';

  // ---------------- Scan + conexao ----------------

  /// Chamado no boot: carrega o ultimo aparelho e tenta reconectar nele sozinho.
  Future<void> iniciar() async {
    final id = await _localStore.lastDeviceId();
    dispositivoSalvo = (id != null && id.isNotEmpty) ? id : null;
    notifyListeners();
    if (dispositivoSalvo != null) _autoReconnect();
  }

  /// Esquece o aparelho salvo (para instalar/testar em outro VEICAN) e volta pro
  /// scan. Usa quando troca o aparelho fisico.
  Future<void> esquecerDispositivo() async {
    await desconectar();
    dispositivoSalvo = null;
    await _localStore.saveLastDeviceId('');
    encontrados.clear();
    _userDesconectou = false;
    _setConn(VConn.desconectado);
  }

  /// (compat) mantem o nome antigo: escaneia e conecta.
  Future<void> conectar() => escanear();

  /// Escaneia por VEICAN — casa por UUID do SERVICO (mais confiavel que o nome,
  /// que o Android as vezes nao recebe) OU por nome. Junta TODOS numa lista.
  /// Se achar 1 -> conecta direto. Se achar varios -> a tela mostra a lista.
  Future<void> escanear({Duration timeout = const Duration(seconds: 12)}) async {
    if (_scanning || FlutterBluePlus.isScanningNow) return;   // (7) nao escaneia duplicado
    erro = null;
    _userDesconectou = false;
    encontrados.clear();
    _setConn(VConn.procurando);
    try {
      if (await FlutterBluePlus.isSupported == false) {
        throw 'Bluetooth nao suportado neste aparelho';
      }
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        try { await FlutterBluePlus.turnOn(); } catch (_) {}
      }
      _scanning = true;
      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        for (final r in results) {
          final advName = r.advertisementData.advName.trim();
          final platformName = r.device.platformName.trim();
          final nome = advName.isNotEmpty ? advName : platformName;
          final porServico =
              r.advertisementData.serviceUuids.any((u) => u == VUuids.service); // (1)
          final porNome =
              nome.toUpperCase().contains(VUuids.deviceName.toUpperCase());
          if (!porServico && !porNome) continue;
          final id = r.device.remoteId.str;
          if (encontrados.any((e) => e.id == id)) continue;
          encontrados.add(VeicanDevice(id, nome.isEmpty ? 'VEICAN' : nome));
          notifyListeners();
        }
      });
      await FlutterBluePlus.startScan(timeout: timeout);
      await Future.delayed(timeout);
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
      _scanning = false;

      if (encontrados.isEmpty) {
        erro = 'Nenhum VEICAN encontrado. Ligue o carro e deixe o aparelho perto.';
        _setConn(VConn.desconectado);
      } else if (encontrados.length == 1) {
        await conectarA(encontrados.first.id);          // 1 so -> conecta direto
      } else {
        _setConn(VConn.desconectado);                    // varios -> UI mostra a lista
        notifyListeners();
      }
    } catch (e) {
      _scanning = false;
      await _scanSub?.cancel();
      erro = e.toString();
      _setConn(VConn.desconectado);
    }
  }

  /// Conecta num aparelho especifico (por id), com ATE 3 tentativas e timeout
  /// maior. Salva o id como "o meu VEICAN" para reconectar nele depois.
  Future<void> conectarA(String deviceId) async {
    _userDesconectou = false;
    _cancelReconnect();
    erro = null;
    // se um scan estiver rolando, para antes de conectar
    if (FlutterBluePlus.isScanningNow) {
      try { await FlutterBluePlus.stopScan(); } catch (_) {}
    }
    await _scanSub?.cancel();
    _scanning = false;
    final dev = BluetoothDevice.fromId(deviceId);
    for (int tentativa = 1; tentativa <= 3; tentativa++) {   // (3)(6) ate 3 tentativas
      try {
        _setConn(VConn.conectando);
        await _conectarDevice(dev);
        dispositivoSalvo = deviceId;
        await _localStore.saveLastDeviceId(deviceId);        // (5) guarda o aparelho
        return;
      } catch (e) {
        erro = 'Tentativa $tentativa: $e';
        notifyListeners();
        try { await dev.disconnect(); } catch (_) {}
        if (tentativa < 3) await Future.delayed(Duration(seconds: 2 * tentativa)); // backoff
      }
    }
    _setConn(VConn.desconectado);
    if (temDispositivoSalvo) _autoReconnect();               // segue tentando em background (8)
  }

  Future<void> _conectarDevice(BluetoothDevice d) async {
    _device = d;
    _connSub?.cancel();
    _connSub = d.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) _onDisconnected();
    });

    await d.connect(timeout: const Duration(seconds: 25), autoConnect: false); // (2) tempo maior
    try { await d.requestMtu(200); } catch (_) {}

    final servicos = await d.discoverServices();
    _rx = null; _tx = null;
    for (final s in servicos) {
      if (s.uuid == VUuids.service) {
        for (final c in s.characteristics) {
          if (c.uuid == VUuids.rx) _rx = c;
          if (c.uuid == VUuids.tx) _tx = c;
        }
      }
    }
    if (_rx == null || _tx == null) {
      try { await d.disconnect(); } catch (_) {}
      throw 'Servico do VEICAN nao encontrado';
    }

    await _tx!.setNotifyValue(true);
    _txSub?.cancel();
    _txSub = _tx!.onValueReceived.listen(_onDados);

    _setConn(VConn.conectado);
    await _syncSpeedDevice();
    await _carregarRecordes();
    _startPolling();
  }

  /// Caiu a conexao. Se NAO foi o usuario, mantem o painel com o ultimo dado e
  /// tenta reconectar sozinho no aparelho salvo. (4)(7)(8)
  void _onDisconnected() {
    _stopPolling();
    _txSub?.cancel();
    _rx = null;
    _tx = null;
    if (_userDesconectou) {
      _setConn(VConn.desconectado);
    } else {
      _setConn(VConn.procurando);   // "reconectando" — nao limpa a live
      if (temDispositivoSalvo) _autoReconnect();
    }
  }

  // Reconexao automatica: de tempos em tempos tenta o aparelho salvo. (8)
  void _autoReconnect() {
    if (_reconnectTimer != null) return;
    _reconnectTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
      if (conectado || _userDesconectou || dispositivoSalvo == null) {
        _cancelReconnect();
        return;
      }
      if (_scanning || FlutterBluePlus.isScanningNow) return; // (7) sem scan concorrente
      try {
        _setConn(VConn.conectando);
        await _conectarDevice(BluetoothDevice.fromId(dispositivoSalvo!));
        _cancelReconnect();
      } catch (_) {
        _setConn(VConn.procurando);   // tenta de novo no proximo tick
      }
    });
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
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

  /// Desconexao PEDIDA pelo usuario: para de reconectar e mantem o ultimo dado
  /// no painel (nao volta pra tela de scan). (9)
  Future<void> desconectar() async {
    _userDesconectou = true;
    _cancelReconnect();
    final d = _device;
    _stopPolling();
    _txSub?.cancel();
    _connSub?.cancel();
    _respTimer?.cancel();
    for (final r in _fila) {
      if (!r.completer.isCompleted) r.completer.complete('');
    }
    _fila.clear();
    if (_atual != null && !_atual!.completer.isCompleted) _atual!.completer.complete('');
    _atual = null;
    _rx = null;
    _tx = null;
    _setConn(VConn.desconectado);   // 'live' fica preservada de proposito
    if (d != null) {
      try { await d.disconnect(); } catch (_) {}
    }
  }

  /// Reconecta manualmente (botao no painel): usa o aparelho salvo, senao escaneia.
  Future<void> reconectar() async {
    _userDesconectou = false;
    if (temDispositivoSalvo) {
      await conectarA(dispositivoSalvo!);
    } else {
      await escanear();
    }
  }

  void _limpar() {
    _stopPolling();
    _cancelReconnect();
    _scanSub?.cancel();
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

  /// Troca de carro: apaga os dados do carro atual e comeca um novo do zero
  /// (velocidade, consumo, consertos, manutencao e perfil ficam separados).
  Future<void> trocarCarro() async {
    await CarScope.trocarCarro();
    speedStore.reset();
    consumoStore.reset();
    speedMaxHoje = 0;
    speedRecorde = 0;
    speedRecordeData = null;
    rpmHist.clear();
    notifyListeners();
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
