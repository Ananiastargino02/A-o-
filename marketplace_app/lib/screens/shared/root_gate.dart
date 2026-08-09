import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_config.dart';
import '../../providers/auth_provider.dart';
import '../auth/login_screen.dart';
import '../auth/escolha_perfil_screen.dart';
import '../cliente/cliente_shell.dart';
import '../lojista/lojista_shell.dart';
import 'splash_screen.dart';

/// Decide qual tela mostrar de acordo com o estado de autenticacao e de
/// cadastro do usuario logado.
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => const SplashScreen(),
      error: (_, __) => const LoginScreen(),
      data: (user) {
        if (user == null) return const LoginScreen();

        final userModelAsync = ref.watch(currentUserModelProvider);
        return userModelAsync.when(
          loading: () => const SplashScreen(),
          error: (_, __) => const SplashScreen(),
          data: (userModel) {
            if (userModel == null) return const EscolhaPerfilScreen();
            if (userModel.tipo == TipoUsuario.cliente) return const ClienteShell();
            return const LojistaShell();
          },
        );
      },
    );
  }
}
