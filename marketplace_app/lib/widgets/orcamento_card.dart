import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_text_styles.dart';
import '../core/constants/app_config.dart';
import '../core/utils/formatters.dart';
import '../models/orcamento_model.dart';
import '../models/loja_model.dart';
import 'status_chip.dart';

/// Card de orcamento recebido, mostrado na tela de orcamentos do cliente.
class OrcamentoCard extends StatelessWidget {
  final OrcamentoModel orcamento;
  final LojaModel? loja;
  final double? distanciaKm;
  final VoidCallback onTap;

  const OrcamentoCard({
    super.key,
    required this.orcamento,
    required this.loja,
    required this.distanciaKm,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.amberSoft,
                backgroundImage: loja?.logoUrl != null ? CachedNetworkImageProvider(loja!.logoUrl!) : null,
                child: loja?.logoUrl == null
                    ? const Icon(Icons.store, color: AppColors.amber)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            loja?.nomeLoja ?? 'Loja',
                            style: AppTextStyles.bodyBold,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          Formatters.currency(orcamento.preco),
                          style: AppTextStyles.h3,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (distanciaKm != null) ...[
                          const Icon(Icons.location_on, size: 13, color: AppColors.textSecondary),
                          const SizedBox(width: 2),
                          Text(Formatters.km(distanciaKm!), style: AppTextStyles.caption),
                          const SizedBox(width: 8),
                        ],
                        StatusChip(
                          label: orcamento.condicao.label,
                          tom: orcamento.condicao == CondicaoPeca.nova ? ChipTom.verde : ChipTom.ambar,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        StatusChip(label: orcamento.entrega.label, tom: ChipTom.azul),
                        StatusChip(label: orcamento.garantia.label, tom: ChipTom.cinza),
                        StatusChip(
                          label: '⚡ Respondeu em ${orcamento.tempoRespostaMin} min',
                          tom: ChipTom.verde,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
