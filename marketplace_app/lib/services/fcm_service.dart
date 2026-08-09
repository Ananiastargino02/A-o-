import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'firestore_service.dart';

/// Push notifications (Cloud Messaging). O envio propriamente dito acontece
/// nas Cloud Functions (ver firebase/functions); este service so cuida de
/// permissao, obtencao/atualizacao do token e listeners de foreground.
class FcmService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirestoreService _firestore;

  FcmService(this._firestore);

  Future<void> inicializar(String userId) async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    final token = await _messaging.getToken();
    if (token != null) {
      await _firestore.atualizarFcmToken(userId, token);
    }

    _messaging.onTokenRefresh.listen((novoToken) {
      _firestore.atualizarFcmToken(userId, novoToken);
    });

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('Push recebido em foreground: ${message.notification?.title}');
    });
  }

  Stream<RemoteMessage> get onMessageOpenedApp => FirebaseMessaging.onMessageOpenedApp;
}
