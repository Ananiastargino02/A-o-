import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pedidos_provider.dart';
import '../../providers/services_providers.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_toast.dart';
import 'form_orcamento_screen.dart';

class DetalhePedidoScreen extends ConsumerStatefulWidget {
  final String pedidoId;

  const DetalhePedidoScreen({super.key, required this.pedidoId});

  @override
  ConsumerState<DetalhePedidoScreen> createState() => _DetalhePedidoScreenState();
}

class _DetalhePedidoScreenState extends ConsumerState<DetalhePedidoScreen> {
  bool _recusando = false;

  Future<void> _naoTenho() async {
    final loja = ref.read(currentLojaProvider).value;
    if (loja == null) return;
    setState(() => _recusando = true);
    await ref.read(firestoreServiceProvider).recusarPedido(widget.pedidoId, loja.id);
    if (!mounted) return;
    AppToast.mostrar('Pedido removido do seu feed.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final pedidoAsync = ref.watch(pedidoProvider(widget.pedidoId));

    return Scaffold(
      appBar: AppBar(title: const Text('Detalhe do pedido')),
      body: pedidoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (pedido) {
          if (pedido == null) return const Center(child: Text('Pedido não encontrado.'));

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (pedido.fotoUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: CachedNetworkImage(
                          imageUrl: pedido.fotoUrl!,
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(pedido.peca, style: AppTextStyles.h1),
                    const SizedBox(height: 6),
                    Text(pedido.veiculoResumo, style: AppTextStyles.bodySecondary),
                    if (pedido.detalhes != null) ...[
                      const SizedBox(height: 16),
                      Text('Detalhes', style: AppTextStyles.h3),
                      const SizedBox(height: 6),
                      Text(pedido.detalhes!, style: AppTextStyles.body),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFE4E6EA))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        label: 'Não tenho',
                        estilo: AppButtonEstilo.perigoOutline,
                        loading: _recusando,
                        onPressed: _naoTenho,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        label: 'Tenho essa peça',
                        estilo: AppButtonEstilo.positivo,
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => FormOrcamentoScreen(pedidoId: pedido.id)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
