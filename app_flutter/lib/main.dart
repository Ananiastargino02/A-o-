import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme.dart';
import 'ble/ble_service.dart';
import 'state/app_settings.dart';
import 'storage/car_scope.dart';
import 'fleet/fleet_service.dart';
import 'models/fleet_vehicle.dart';
import 'screens/scan_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/maintenance_screen.dart';
import 'screens/repairs_screen.dart';
import 'screens/dtc_screen.dart';
import 'screens/profile_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CarScope.init();   // carrega o carro ativo (dados sao separados por carro)
  runApp(const VeicanApp());
}

class VeicanApp extends StatelessWidget {
  const VeicanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BleService()),
        ChangeNotifierProvider(create: (_) => AppSettings()),
        ChangeNotifierProvider(create: (_) => FleetService()..init()),
      ],
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
  BleService? _ble;
  DateTime? _ultReport;

  final _telas = const [
    DashboardScreen(),
    MaintenanceScreen(),
    RepairsScreen(),
    DtcScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Motorista da frota: envia o retrato do carro periodicamente (a cada ~20s)
    // enquanto conectado. (Local hoje; nuvem quando o servidor for plugado.)
    _ble = context.read<BleService>();
    _ble!.addListener(_reportarFrota);
  }

  void _reportarFrota() {
    if (!mounted) return;
    final ble = _ble;
    final d = ble?.live;
    if (ble == null || d == null) return;
    final agora = DateTime.now();
    if (_ultReport != null && agora.difference(_ultReport!).inSeconds < 20) return;
    _ultReport = agora;
    context.read<FleetService>().reportar(VehicleSnapshot(
          km: d.km,
          rpm: d.rpm,
          velocidade: d.velocidade,
          temp: d.temp,
          combustivel: d.combustivel,
          bateria: d.bateria,
          estado: d.estado,
          visto: agora,
        ));
  }

  @override
  void dispose() {
    _ble?.removeListener(_reportarFrota);
    super.dispose();
  }

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
              icon: Icon(Icons.handyman_outlined),
              selectedIcon: Icon(Icons.handyman, color: VColors.cyan),
              label: 'Consertos'),
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
