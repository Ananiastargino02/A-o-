import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/dashboard_style.dart';
import '../state/app_settings.dart';
import '../theme.dart';

/// Tela onde o usuario escolhe qual painel principal quer.
class DashboardPickerScreen extends StatelessWidget {
  const DashboardPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    return Scaffold(
      appBar: AppBar(title: const Text('ESCOLHER PAINEL')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Escolha o estilo do seu painel principal:',
              style: TextStyle(color: VColors.textDim)),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.78,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final estilo in DashboardStyle.values)
                _opcao(context, settings, estilo),
            ],
          ),
        ],
      ),
    );
  }

  Widget _opcao(BuildContext context, AppSettings settings, DashboardStyle estilo) {
    final selecionado = settings.dash == estilo;
    return GestureDetector(
      onTap: () {
        settings.setDash(estilo);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Painel "${estilo.nome}" selecionado'),
            backgroundColor: VColors.cardHi,
            duration: const Duration(milliseconds: 900)));
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: VColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selecionado ? VColors.cyan : VColors.line,
            width: selecionado ? 2 : 1,
          ),
          boxShadow: selecionado
              ? [BoxShadow(color: VColors.cyan.withValues(alpha: 0.25), blurRadius: 16)]
              : null,
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: VColors.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _preview(estilo),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(estilo.nome,
                      style: TextStyle(
                          color: selecionado ? VColors.cyan : VColors.textHi,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
                if (selecionado)
                  const Icon(Icons.check_circle, color: VColors.cyan, size: 18)
                else
                  const Icon(Icons.radio_button_unchecked, color: VColors.textFaint, size: 18),
              ],
            ),
            const SizedBox(height: 2),
            Text(estilo.descricao,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: VColors.textFaint, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  /// Mini ilustracao de cada estilo (so decorativa).
  Widget _preview(DashboardStyle e) {
    switch (e) {
      case DashboardStyle.modern:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: VColors.cyan, width: 5),
                  boxShadow: [BoxShadow(color: VColors.cyan.withValues(alpha: 0.5), blurRadius: 10)],
                ),
                child: const Center(
                    child: Text('3k', style: TextStyle(color: VColors.cyan, fontWeight: FontWeight.bold, fontSize: 13))),
              ),
              const SizedBox(height: 8),
              _bar(VColors.blue, 0.8, h: 8),
            ],
          ),
        );
      case DashboardStyle.cards:
        return Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _bar(VColors.cyan, 0.9, h: 10),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: _box(VColors.blue)),
                const SizedBox(width: 6),
                Expanded(child: _box(VColors.green)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: _box(VColors.amber)),
                const SizedBox(width: 6),
                Expanded(child: _box(VColors.red)),
              ]),
            ],
          ),
        );
      case DashboardStyle.sport:
        return Center(
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: VColors.cyan, width: 6),
            ),
            child: const Center(
                child: Text('88', style: TextStyle(color: VColors.cyan, fontWeight: FontWeight.bold))),
          ),
        );
      case DashboardStyle.minimal:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('120',
                  style: TextStyle(color: VColors.textHi, fontSize: 42, fontWeight: FontWeight.w200)),
              Text('km/h', style: TextStyle(color: VColors.textDim, fontSize: 10, letterSpacing: 3)),
            ],
          ),
        );
      case DashboardStyle.cockpit:
        return Padding(
          padding: const EdgeInsets.all(10),
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _neon(VColors.cyan),
              _neon(VColors.green),
              _neon(VColors.amber),
              _neon(const Color(0xFF7C4DFF)),
            ],
          ),
        );
    }
  }

  Widget _bar(Color c, double f, {double h = 8}) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: f, minHeight: h, backgroundColor: VColors.cardHi, color: c),
      );

  Widget _box(Color c) => Container(
        height: 22,
        decoration: BoxDecoration(
          color: VColors.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.withValues(alpha: 0.6)),
        ),
      );

  Widget _neon(Color c) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0A0F18),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.withValues(alpha: 0.7)),
          boxShadow: [BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 6)],
        ),
      );
}
