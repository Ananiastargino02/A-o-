import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import 'feed_pedidos_screen.dart';
import 'vendas_screen.dart';

class LojistaShell extends ConsumerStatefulWidget {
  const LojistaShell({super.key});

  @override
  ConsumerState<LojistaShell> createState() => _LojistaShellState();
}

class _LojistaShellState extends ConsumerState<LojistaShell> {
  int _index = 0;

  static const _telas = [
    FeedPedidosScreen(),
    VendasScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final lojaAsync = ref.watch(currentLojaProvider);

    return lojaAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Erro: $e'))),
      data: (loja) {
        if (loja == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(
          body: IndexedStack(index: _index, children: _telas),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _index,
            onTap: (i) => setState(() => _index = i),
            selectedItemColor: AppColors.textPrimary,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.inbox_outlined), activeIcon: Icon(Icons.inbox), label: 'Pedidos'),
              BottomNavigationBarItem(icon: Icon(Icons.storefront_outlined), activeIcon: Icon(Icons.storefront), label: 'Vendas'),
            ],
          ),
        );
      },
    );
  }
}
