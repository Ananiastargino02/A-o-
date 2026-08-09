import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../providers/services_providers.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_toast.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String telefoneE164;
  final String verificationId;

  const OtpScreen({super.key, required this.telefoneE164, required this.verificationId});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _codigoController = TextEditingController();
  bool _confirmando = false;

  Future<void> _confirmar() async {
    if (_codigoController.text.trim().length < 6) {
      AppToast.mostrar('Digite o código de 6 dígitos.');
      return;
    }
    setState(() => _confirmando = true);
    try {
      await ref.read(authServiceProvider).confirmarCodigo(
            verificationId: widget.verificationId,
            smsCode: _codigoController.text.trim(),
          );
      // A navegacao acontece automaticamente via authStateProvider -> RootGate.
    } catch (_) {
      AppToast.mostrar('Código incorreto. Tente de novo.');
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.topBarDark,
      appBar: AppBar(backgroundColor: AppColors.topBarDark, elevation: 0),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Confirme o código', style: AppTextStyles.h1.copyWith(color: AppColors.white)),
            const SizedBox(height: 8),
            Text(
              'Enviamos um SMS para ${Formatters.phoneDisplay(widget.telefoneE164)}',
              style: AppTextStyles.body.copyWith(color: AppColors.white.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _codigoController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              style: AppTextStyles.h2,
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: AppColors.white,
                hintText: '000000',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 20),
            AppButton(
              label: 'Confirmar',
              onPressed: _confirmar,
              loading: _confirmando,
              estilo: AppButtonEstilo.destaque,
            ),
          ],
        ),
      ),
    );
  }
}
