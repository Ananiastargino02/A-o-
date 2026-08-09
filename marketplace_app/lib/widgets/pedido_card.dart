import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../core/constants/app_config.dart';
import '../core/utils/formatters.dart';
import '../models/pedido_model.dart';
import 'status_chip.dart';

/// Card de pedido usado na lista "Seus pedidos" (cliente).
class PedidoCard extends StatelessWidget {
  final PedidoModel pedido;
  final VoidCallback onTap;

  const PedidoCard({super.key, required this.pedido, required this.onTap});

  StatusChip get _statusChip => switch (pedido.status) {
        StatusPedido.aberto => const StatusChip(label: 'Em busca', tom: ChipTom.ambar, icone: Icons.radar),
        StatusPedido.fechado => const StatusChip(label: 'Fechado', tom: ChipTom.verde, icone: Icons.check_circle),
        StatusPedido.expirado => const StatusChip(label: 'Expirado', tom: ChipTom.cinza, icone: Icons.timer_off),
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(pedido.peca, style: AppTextStyles.h3)),
                  _statusChip,
                ],
              ),
              const SizedBox(height: 4),
              Text(pedido.veiculoResumo, style: AppTextStyles.bodySecondary),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.social_distance, size: 15, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text('Raio ${Formatters.km(pedido.raioAtual)}', style: AppTextStyles.caption),
                  const SizedBox(width: 14),
                  const Icon(Icons.store, size: 15, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text('${pedido.lojasNotificadas} lojas', style: AppTextStyles.caption),
                  const Spacer(),
                  Text(timeago.format(pedido.criadoEm, locale: 'pt_BR'), style: AppTextStyles.caption),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
