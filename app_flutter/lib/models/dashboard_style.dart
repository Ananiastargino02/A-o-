import 'package:flutter/material.dart';

/// Os 4 estilos de painel principal que o usuario pode escolher.
enum DashboardStyle { cards, sport, minimal, cockpit }

extension DashboardStyleX on DashboardStyle {
  String get nome => switch (this) {
        DashboardStyle.cards => 'Cartoes',
        DashboardStyle.sport => 'Esportivo',
        DashboardStyle.minimal => 'Minimalista',
        DashboardStyle.cockpit => 'Cockpit',
      };

  String get descricao => switch (this) {
        DashboardStyle.cards => 'Informativo e organizado, com todos os dados em cartoes.',
        DashboardStyle.sport => 'Medidores circulares grandes de RPM e velocidade.',
        DashboardStyle.minimal => 'Limpo e elegante: a velocidade em destaque total.',
        DashboardStyle.cockpit => 'Estilo cockpit, mosaico de tiles com brilho neon.',
      };

  IconData get icone => switch (this) {
        DashboardStyle.cards => Icons.dashboard_outlined,
        DashboardStyle.sport => Icons.speed,
        DashboardStyle.minimal => Icons.filter_center_focus,
        DashboardStyle.cockpit => Icons.grid_view,
      };

  String get chave => name;

  static DashboardStyle fromChave(String? s) =>
      DashboardStyle.values.firstWhere((e) => e.name == s,
          orElse: () => DashboardStyle.cards);
}
