// GERADO PARA SUBSTITUICAO: este arquivo e um placeholder.
//
// Rode `flutterfire configure` na raiz do projeto (depois de criar o
// projeto no Firebase Console e ativar Auth/Firestore/Storage/FCM - ver
// docs/FIREBASE_SETUP.md) para gerar a versao real com as chaves do seu
// projeto. O comando sobrescreve este arquivo automaticamente.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('APPNAME não tem build web nesta versão.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Plataforma não suportada: $defaultTargetPlatform');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'SUBSTITUA_COM_FLUTTERFIRE_CONFIGURE',
    appId: 'SUBSTITUA_COM_FLUTTERFIRE_CONFIGURE',
    messagingSenderId: 'SUBSTITUA_COM_FLUTTERFIRE_CONFIGURE',
    projectId: 'SUBSTITUA_COM_FLUTTERFIRE_CONFIGURE',
    storageBucket: 'SUBSTITUA_COM_FLUTTERFIRE_CONFIGURE',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'SUBSTITUA_COM_FLUTTERFIRE_CONFIGURE',
    appId: 'SUBSTITUA_COM_FLUTTERFIRE_CONFIGURE',
    messagingSenderId: 'SUBSTITUA_COM_FLUTTERFIRE_CONFIGURE',
    projectId: 'SUBSTITUA_COM_FLUTTERFIRE_CONFIGURE',
    storageBucket: 'SUBSTITUA_COM_FLUTTERFIRE_CONFIGURE',
    iosBundleId: 'com.appname.app',
  );
}
