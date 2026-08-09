import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_config.dart';
import '../../core/constants/app_text_styles.dart';
import '../../providers/services_providers.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_toast.dart';
import 'otp_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _telefoneController = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _telefoneController.dispose();
    super.dispose();
  }

  String get _digitos => _telefoneController.text.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _enviarCodigo() async {
    if (_digitos.length < 10) {
      AppToast.mostrar('Digite um telefone valido com DDD.');
      return;
    }
    setState(() => _enviando = true);
    final telefoneE164 = '+55$_digitos';

    await ref.read(authServiceProvider).enviarCodigoSms(
      telefoneE164: telefoneE164,
      onCodeSent: (verificationId) {
        setState(() => _enviando = false);
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OtpScreen(
              telefoneE164: telefoneE164,
              verificationId: verificationId,
            ),
          ),
        );
      },
      onAutoVerified: (user) {
        setState(() => _enviando = false);
      },
      onError: (erro) {
        setState(() => _enviando = false);
        AppToast.mostrar(erro);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.topBarDark,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                AppConfig.appName,
                style: AppTextStyles.h1.copyWith(color: AppColors.white, fontSize: 32),
              ),
              const SizedBox(height: 8),
              Text(
                'Entre com seu número de celular pra continuar.',
                style: AppTextStyles.body.copyWith(color: AppColors.white.withValues(alpha: 0.8)),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Text('🇧🇷 +55', style: AppTextStyles.bodyBold),
                    const SizedBox(width: 10),
                    Container(width: 1, height: 24, color: AppColors.cardBorder),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _telefoneController,
                        keyboardType: TextInputType.phone,
                        style: AppTextStyles.body,
                        decoration: const InputDecoration(
                          hintText: '(21) 99999-9999',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              AppButton(
                label: 'Receber código por SMS',
                onPressed: _enviarCodigo,
                loading: _enviando,
                estilo: AppButtonEstilo.destaque,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
