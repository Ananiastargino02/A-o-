import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../ble/ble_service.dart';
import '../data/car_db.dart';
import '../models/car_profile.dart';
import '../storage/local_store.dart';
import '../theme.dart';
import 'fleet/fleet_home_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _store = LocalStore();
  final _nome = TextEditingController();
  final _ano = TextEditingController();
  String _marca = '';
  String _modelo = '';
  String _versao = '';
  bool _carregado = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final c = await _store.loadProfile();
    _nome.text = c.nome;
    _ano.text = c.ano;
    _marca = c.marca;
    _modelo = c.modelo;
    _versao = c.versao;
    if (mounted) setState(() => _carregado = true);
  }

  Future<void> _salvar() async {
    final c = CarProfile(
      nome: _nome.text.trim(),
      marca: _marca.trim(),
      modelo: _modelo.trim(),
      versao: _versao.trim(),
      ano: _ano.text.trim(),
      kmAtual: context.read<BleService>().live?.km ?? 0,
    );
    await _store.saveProfile(c);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil salvo'), backgroundColor: VColors.cardHi));
    FocusScope.of(context).unfocus();
  }

  Future<void> _trocarCarro() async {
    final ble = context.read<BleService>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: VColors.card,
        title: const Text('Trocar de carro?'),
        content: const Text(
            'Isso apaga TODOS os dados do carro atual (perfil, manutencao, '
            'consertos, velocidade e consumo) e comeca um novo do zero.\n\n'
            'Use quando instalar o VEICAN em outro carro.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: VColors.amber, foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Trocar e zerar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ble.trocarCarro();
    _nome.clear();
    _ano.clear();
    setState(() {
      _marca = '';
      _modelo = '';
      _versao = '';
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Carro novo. Cadastre os dados do carro atual.'), backgroundColor: VColors.cardHi));
  }

  @override
  void dispose() {
    _nome.dispose();
    _ano.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    if (!_carregado) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: VColors.cyan)));
    }
    final ano = int.tryParse(_ano.text) ?? 0;
    final versoes = versoesPara(_marca, _modelo, ano);
    return Scaffold(
      appBar: AppBar(title: const Text('MEU CARRO')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _campo(_nome, 'Nome / apelido', Icons.badge_outlined),

          // ---- MARCA (autocomplete da base) ----
          _autocomplete(
            label: 'Marca',
            icon: Icons.factory_outlined,
            valorInicial: _marca,
            opcoes: (t) => marcas().where((m) => m.toLowerCase().contains(t.toLowerCase())),
            onTexto: (t) => setState(() => _marca = t),
            onEscolha: (s) => setState(() {
              _marca = s;
              _modelo = '';
              _versao = '';
            }),
          ),

          // ---- MODELO (autocomplete filtrado pela marca) ----
          _autocomplete(
            key: ValueKey('modelo_$_marca'),
            label: 'Modelo (ex.: Gol)',
            icon: Icons.directions_car_outlined,
            valorInicial: _modelo,
            opcoes: (t) {
              final base = _marca.isNotEmpty ? modelosDe(_marca).map((e) => e.nome) : [for (final b in carDb) ...b.modelos.map((e) => e.nome)];
              if (t.isEmpty) return base;
              return base.where((m) => m.toLowerCase().contains(t.toLowerCase()));
            },
            onTexto: (t) => setState(() {
              _modelo = t;
              _versao = '';
            }),
            onEscolha: (s) => setState(() {
              _modelo = s;
              _versao = '';
            }),
          ),

          _campo(_ano, 'Ano', Icons.calendar_today_outlined,
              numero: true, onChanged: (_) => setState(() => _versao = '')),

          // ---- VERSAO / GERACAO (aparece quando o modelo tem geracoes no ano) ----
          if (versoes.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 6, top: 2),
              child: Text('Escolha a versao desse ano:', style: TextStyle(color: VColors.textDim, fontSize: 12)),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in versoes)
                  ChoiceChip(
                    label: Text(v),
                    selected: _versao == v,
                    onSelected: (_) => setState(() => _versao = v),
                    selectedColor: VColors.cyan.withValues(alpha: 0.25),
                    labelStyle: TextStyle(color: _versao == v ? VColors.cyan : VColors.textHi, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ] else if (_versao.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text('Versao: $_versao', style: const TextStyle(color: VColors.cyan, fontSize: 13)),
            ),
          ],

          FilledButton.icon(onPressed: _salvar, icon: const Icon(Icons.save_outlined), label: const Text('SALVAR')),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _trocarCarro,
            style: OutlinedButton.styleFrom(
              foregroundColor: VColors.amber,
              side: const BorderSide(color: VColors.amber),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('TROCAR DE CARRO (zera tudo)'),
          ),
          const SizedBox(height: 28),
          const Text('EMPRESA / FROTA', style: TextStyle(color: VColors.textDim, letterSpacing: 2, fontSize: 13)),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.local_shipping_outlined, color: VColors.cyan),
              title: const Text('Modo Frota'),
              subtitle: const Text('Varios carros de uma empresa (patrao ve todos)', style: TextStyle(color: VColors.textFaint)),
              trailing: const Icon(Icons.chevron_right, color: VColors.textFaint),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FleetHomeScreen())),
            ),
          ),
          const SizedBox(height: 28),
          const Text('APARELHO', style: TextStyle(color: VColors.textDim, letterSpacing: 2, fontSize: 13)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(ble.conectado ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                      color: ble.conectado ? VColors.green : VColors.textFaint),
                  title: Text(ble.conectado
                      ? 'VEICAN conectado'
                      : (ble.conn == VConn.procurando || ble.conn == VConn.conectando)
                          ? 'Reconectando...'
                          : 'VEICAN desconectado'),
                  subtitle: Text('Odometro: ${ble.live?.km ?? "--"} km', style: const TextStyle(color: VColors.textFaint)),
                ),
                const Divider(height: 1, color: VColors.line),
                if (ble.conectado)
                  ListTile(leading: const Icon(Icons.link_off, color: VColors.amber), title: const Text('Desconectar'), onTap: () => ble.desconectar())
                else
                  ListTile(leading: const Icon(Icons.bluetooth_searching, color: VColors.cyan), title: const Text('Conectar'), onTap: () => ble.reconectar()),
                const Divider(height: 1, color: VColors.line),
                ListTile(
                  leading: const Icon(Icons.sync_alt, color: VColors.red),
                  title: const Text('Trocar aparelho'),
                  subtitle: const Text('Esquece este VEICAN e procura outro', style: TextStyle(color: VColors.textFaint)),
                  onTap: () => ble.esquecerDispositivo(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _autocomplete({
    Key? key,
    required String label,
    required IconData icon,
    required String valorInicial,
    required Iterable<String> Function(String) opcoes,
    required void Function(String) onTexto,
    required void Function(String) onEscolha,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Autocomplete<String>(
        key: key,
        initialValue: TextEditingValue(text: valorInicial),
        optionsBuilder: (v) => opcoes(v.text),
        onSelected: onEscolha,
        fieldViewBuilder: (context, controller, focusNode, onSubmit) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onTexto,
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: Icon(icon, color: VColors.textDim),
              filled: true,
              fillColor: VColors.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: VColors.line)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: VColors.line)),
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              color: VColors.card,
              elevation: 4,
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final o in options)
                      ListTile(
                        dense: true,
                        title: Text(o, style: const TextStyle(color: VColors.textHi)),
                        onTap: () => onSelected(o),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _campo(TextEditingController c, String label, IconData icon, {bool numero = false, void Function(String)? onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: numero ? TextInputType.number : TextInputType.text,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: VColors.textDim),
          filled: true,
          fillColor: VColors.card,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: VColors.line)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: VColors.line)),
        ),
      ),
    );
  }
}
