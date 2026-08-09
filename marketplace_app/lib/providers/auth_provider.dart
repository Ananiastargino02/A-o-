import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../models/loja_model.dart';
import 'services_providers.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// Documento de perfil (users/{uid}) do usuario logado. `null` enquanto nao
/// existir ainda -> indica que o cadastro (escolha de perfil) precisa
/// acontecer.
final currentUserModelProvider = StreamProvider<UserModel?>((ref) {
  final authState = ref.watch(authStateProvider);
  final uid = authState.value?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).watchUser(uid);
});

/// Documento da loja do lojista logado (null se ainda nao cadastrou a loja
/// ou se o usuario e cliente).
final currentLojaProvider = StreamProvider<LojaModel?>((ref) {
  final authState = ref.watch(authStateProvider);
  final uid = authState.value?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).watchLojaPorUserId(uid);
});
