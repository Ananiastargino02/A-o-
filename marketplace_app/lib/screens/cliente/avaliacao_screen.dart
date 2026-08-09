import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_text_styles.dart';
import '../../models/avaliacao_model.dart';
import '../../providers/services_providers.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/star_rating.dart';

class AvaliacaoScreen extends ConsumerStatefulWidget {
  final String lojaId;
  final String pedidoId;
  final String nomeLoja;

  const AvaliacaoScreen({
    super.key,
    required this.lojaId,
    required this.pedidoId,
    required this.nomeLoja,
  });

  @override
  ConsumerState<AvaliacaoScreen> createState() => _AvaliacaoScreenState();
}

class _AvaliacaoScreenState extends ConsumerState<AvaliacaoScreen> {
  int _estrelas = 5;
  final _comentarioController = TextEditingController();
  bool _enviando = false;

  Future<void> _enviar() async {
    final uid = ref.read(authServiceProvider).currentUser?.uid;
    if (uid == null) return;

    setState(() => _enviando = true);

    await ref.read(firestoreServiceProvider).criarAvaliacao(
          AvaliacaoModel(
            id: '',
            lojaId: widget.lojaId,
            clienteId: uid,
            pedidoId: widget.pedidoId,
            estrelas: _estrelas,
            comentario: _comentarioController.text.trim().isEmpty ? null : _comentarioController.text.trim(),
            criadoEm: DateTime.now(),
          ),
        );

    if (!mounted) return;
    AppToast.mostrar('Valeu pela avaliação!');
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Como foi?')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('Negócio fechado! 🎉', style: AppTextStyles.h2),
            const SizedBox(height: 6),
            Text('Avalie a ${widget.nomeLoja}', style: AppTextStyles.bodySecondary),
            const SizedBox(height: 24),
            StarRating(value: _estrelas, onChanged: (v) => setState(() => _estrelas = v)),
            const SizedBox(height: 24),
            TextField(
              controller: _comentarioController,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Comentário (opcional)'),
            ),
            const SizedBox(height: 24),
            AppButton(
              label: 'Enviar avaliação',
              onPressed: _enviar,
              loading: _enviando,
              estilo: AppButtonEstilo.positivo,
            ),
            TextButton(
              onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('Pular'),
            ),
          ],
        ),
      ),
    );
  }
}
