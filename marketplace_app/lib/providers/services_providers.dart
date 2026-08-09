import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import '../services/fcm_service.dart';
import '../services/location_service.dart';
import '../services/functions_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final firestoreServiceProvider = Provider<FirestoreService>((ref) => FirestoreService());

final storageServiceProvider = Provider<StorageService>((ref) => StorageService());

final locationServiceProvider = Provider<LocationService>((ref) => LocationService());

final fcmServiceProvider = Provider<FcmService>((ref) {
  return FcmService(ref.watch(firestoreServiceProvider));
});

final functionsServiceProvider = Provider<FunctionsService>((ref) => FunctionsService());
