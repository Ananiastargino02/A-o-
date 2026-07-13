import 'package:flutter/material.dart';
import '../models/live_data.dart';
import '../theme.dart';

/// Cor da bateria conforme o estado (ligado/desligado e faixa de tensao).
Color corBateria(LiveData d) {
  if (d.bateria <= 0) return VColors.textDim;
  if (d.ligado) {
    if (d.bateria > 14.6) return VColors.orange; // sobrecarga
    if (d.bateria < 13.0) return VColors.red; // alternador
    return VColors.green;
  }
  return d.bateria < 12.0 ? VColors.red : VColors.green;
}

Color corTemp(int t) => t > 100 ? VColors.orange : VColors.green;
Color corComb(int c) => c <= 15 ? VColors.red : VColors.amber;

/// Cartao de estatistica simples (usado no painel Cartoes).
class StatTile extends StatelessWidget {
  final String label, valor, unidade;
  final Color cor;
  const StatTile(
      {super.key,
      required this.label,
      required this.valor,
      required this.unidade,
      required this.cor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: VColors.textDim, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(valor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: cor)),
              ),
              if (unidade.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(unidade, style: const TextStyle(color: VColors.textFaint, fontSize: 13)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Tile com brilho neon (usado no painel Cockpit).
class NeonTile extends StatelessWidget {
  final String label, valor, unidade;
  final Color cor;
  final IconData icone;
  const NeonTile(
      {super.key,
      required this.label,
      required this.valor,
      required this.unidade,
      required this.cor,
      required this.icone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0F18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withValues(alpha: 0.6), width: 1.4),
        boxShadow: [
          BoxShadow(color: cor.withValues(alpha: 0.22), blurRadius: 14, spreadRadius: 1),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Icon(icone, size: 15, color: cor),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(color: cor.withValues(alpha: 0.9), fontSize: 11, letterSpacing: 1)),
          ]),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(valor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [Shadow(color: cor, blurRadius: 12)])),
              ),
              if (unidade.isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(unidade, style: const TextStyle(color: VColors.textFaint, fontSize: 12)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
