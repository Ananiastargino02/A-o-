import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble/ble_service.dart';
import '../models/car_profile.dart';
import '../storage/local_store.dart';
import '../theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _store = LocalStore();
  final _nome = TextEditingController();
  final _marca = TextEditingController();
  final _modelo = TextEditingController();
  final _ano = TextEditingController();
  bool _carregado = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final c = await _store.loadProfile();
    _nome.text = c.nome;
    _marca.text = c.marca;
    _modelo.text = c.modelo;
    _ano.text = c.ano;
    if (mounted) setState(() => _carregado = true);
  }

  Future<void> _salvar() async {
    final c = CarProfile(
      nome: _nome.text.trim(),
      marca: _marca.text.trim(),
      modelo: _modelo.text.trim(),
      ano: _ano.text.trim(),
      kmAtual: context.read<BleService>().live?.km ?? 0,
    );
    await _store.saveProfile(c);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil salvo'), backgroundColor: VColors.cardHi));
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _nome.dispose();
    _marca.dispose();
    _modelo.dispose();
    _ano.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    if (!_carregado) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: VColors.cyan)));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('MEU CARRO')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _campo(_nome, 'Nome / apelido', Icons.badge_outlined),
          _campo(_marca, 'Marca', Icons.factory_outlined),
          _campo(_modelo, 'Modelo', Icons.directions_car_outlined),
          _campo(_ano, 'Ano', Icons.calendar_today_outlined, numero: true),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _salvar,
            icon: const Icon(Icons.save_outlined),
            label: const Text('SALVAR'),
          ),
          const SizedBox(height: 28),
          const Text('APARELHO',
              style: TextStyle(color: VColors.textDim, letterSpacing: 2, fontSize: 13)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.bluetooth_connected, color: VColors.green),
                  title: const Text('VEICAN conectado'),
                  subtitle: Text('Odometro: ${ble.live?.km ?? "--"} km',
                      style: const TextStyle(color: VColors.textFaint)),
                ),
                const Divider(height: 1, color: VColors.line),
                ListTile(
                  leading: const Icon(Icons.link_off, color: VColors.red),
                  title: const Text('Desconectar'),
                  onTap: () => ble.desconectar(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _campo(TextEditingController c, String label, IconData icon, {bool numero = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: numero ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: VColors.textDim),
          filled: true,
          fillColor: VColors.card,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: VColors.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: VColors.line),
          ),
        ),
      ),
    );
  }
}
