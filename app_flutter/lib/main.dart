import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme.dart';
import 'ble/ble_service.dart';
import 'screens/scan_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/maintenance_screen.dart';
import 'screens/dtc_screen.dart';
import 'screens/profile_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VeicanApp());
}

class VeicanApp extends StatelessWidget {
  const VeicanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BleService(),
      child: MaterialApp(
        title: 'VEICAN',
        debugShowCheckedModeBanner: false,
        theme: veicanTheme(),
        home: const _Gate(),
      ),
    );
  }
}

/// Mostra a tela de conexao quando desconectado; senao, o app com abas.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    if (ble.conn == VConn.conectado) return const HomeShell();
    return const ScanScreen();
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  final _telas = const [
    DashboardScreen(),
    MaintenanceScreen(),
    DtcScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: _telas),
      bottomNavigationBar: NavigationBar(
        backgroundColor: VColors.card,
        indicatorColor: VColors.cyan.withValues(alpha: 0.15),
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.speed_outlined),
              selectedIcon: Icon(Icons.speed, color: VColors.cyan),
              label: 'Painel'),
          NavigationDestination(
              icon: Icon(Icons.build_outlined),
              selectedIcon: Icon(Icons.build, color: VColors.cyan),
              label: 'Manutencao'),
          NavigationDestination(
              icon: Icon(Icons.warning_amber_outlined),
              selectedIcon: Icon(Icons.warning_amber, color: VColors.cyan),
              label: 'Falhas'),
          NavigationDestination(
              icon: Icon(Icons.directions_car_outlined),
              selectedIcon: Icon(Icons.directions_car, color: VColors.cyan),
              label: 'Carro'),
        ],
      ),
    );
  }
}
