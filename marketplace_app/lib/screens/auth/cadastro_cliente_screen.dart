import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_config.dart';
import '../../core/constants/app_text_styles.dart';
import '../../providers/services_providers.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_toast.dart';

class CadastroClienteScreen extends ConsumerStatefulWidget {
  const CadastroClienteScreen({super.key});

  @override
  ConsumerState<CadastroClienteScreen> createState() => _CadastroClienteScreenState();
}

class _CadastroClienteScreenState extends ConsumerState<CadastroClienteScreen> {
  final _nomeController = TextEditingController();
  bool _salvando = false;

  Future<void> _salvar() async {
    if (_nomeController.text.trim().isEmpty) {
      AppToast.mostrar('Digite seu nome.');
      return;
    }
    setState(() => _salvando = true);

    final locationService = ref.read(locationServiceProvider);
    await locationService.garantirPermissao();

    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) return;

    await ref.read(firestoreServiceProvider).criarOuAtualizarUser(user.uid, {
      'tipo': TipoUsuario.cliente.name,
      'nome': _nomeController.text.trim(),
      'telefone': user.phoneNumber ?? '',
      'criadoEm': DateTime.now(),
    });

    await ref.read(fcmServiceProvider).inicializar(user.uid);

    setState(() => _salvando = false);
    // A navegacao para a Home do cliente acontece via RootGate observando
    // currentUserModelProvider.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete seu cadastro')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Qual seu nome?', style: AppTextStyles.h2),
            const SizedBox(height: 14),
            TextField(
              controller: _nomeController,
              decoration: const InputDecoration(hintText: 'Nome completo'),
            ),
            const SizedBox(height: 10),
            Text(
              'Vamos pedir sua localização pra encontrar lojas perto de você.',
              style: AppTextStyles.bodySecondary,
            ),
            const Spacer(),
            AppButton(
              label: 'Continuar',
              onPressed: _salvar,
              loading: _salvando,
              estilo: AppButtonEstilo.destaque,
            ),
          ],
        ),
      ),
    );
  }
}
