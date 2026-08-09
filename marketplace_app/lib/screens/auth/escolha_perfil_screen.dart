import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import 'cadastro_cliente_screen.dart';
import 'cadastro_lojista_screen.dart';

class EscolhaPerfilScreen extends StatelessWidget {
  const EscolhaPerfilScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Como você quer usar?', style: AppTextStyles.h1),
              const SizedBox(height: 8),
              Text(
                'Escolha o tipo de conta. Dá pra criar as duas depois, com telefones diferentes.',
                style: AppTextStyles.bodySecondary,
              ),
              const SizedBox(height: 28),
              _OpcaoPerfil(
                titulo: 'Sou cliente',
                subtitulo: 'Quero pedir orçamentos de peças',
                icone: Icons.person_search,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CadastroClienteScreen()),
                ),
              ),
              const SizedBox(height: 14),
              _OpcaoPerfil(
                titulo: 'Sou lojista',
                subtitulo: 'Quero receber pedidos e vender',
                icone: Icons.storefront,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CadastroLojistaScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpcaoPerfil extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final IconData icone;
  final VoidCallback onTap;

  const _OpcaoPerfil({
    required this.titulo,
    required this.subtitulo,
    required this.icone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(color: AppColors.amberSoft, shape: BoxShape.circle),
                child: Icon(icone, color: AppColors.amber, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: AppTextStyles.h3),
                    const SizedBox(height: 2),
                    Text(subtitulo, style: AppTextStyles.bodySecondary),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
