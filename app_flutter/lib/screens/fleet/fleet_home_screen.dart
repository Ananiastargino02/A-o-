import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../fleet/fleet_service.dart';
import '../../models/fleet_vehicle.dart';
import '../../theme.dart';
import 'fleet_vehicle_screen.dart';

/// Porta de entrada da FROTA: se nao configurado -> setup; senao overview
/// (patrao ve todos os carros) ou tela do motorista.
class FleetHomeScreen extends StatelessWidget {
  const FleetHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fleet = context.watch<FleetService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('FROTA'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            tooltip: 'Configurar frota',
            onPressed: () => _abrirSetup(context),
          ),
        ],
      ),
      body: VBackground(
        child: (!fleet.ativo || fleet.fleetId.isEmpty)
            ? _Intro(onConfig: () => _abrirSetup(context))
            : (fleet.role == FleetRole.patrao
                ? _PatraoView(fleet)
                : _MotoristaView(fleet)),
      ),
      floatingActionButton: (fleet.ativo && fleet.role == FleetRole.patrao)
          ? FloatingActionButton.extended(
              backgroundColor: VColors.cyan,
              foregroundColor: const Color(0xFF05122B),
              onPressed: () => _editarVeiculo(context, fleet, null),
              icon: const Icon(Icons.add),
              label: const Text('Carro'),
            )
          : null,
    );
  }

  void _abrirSetup(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const FleetSetupScreen()));
  }

  static void _editarVeiculo(BuildContext context, FleetService fleet, FleetVehicle? v) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: VColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditVehicleSheet(fleet: fleet, original: v),
    );
  }
}

class _Intro extends StatelessWidget {
  final VoidCallback onConfig;
  const _Intro({required this.onConfig});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_shipping_outlined, size: 64, color: VColors.cyan),
            const SizedBox(height: 16),
            const Text('Modo Frota',
                style: TextStyle(color: VColors.textHi, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text(
              'Cadastre todos os carros da empresa. O patrao acompanha a frota '
              'inteira; cada motorista atualiza o carro dele pelo Bluetooth.',
              textAlign: TextAlign.center,
              style: TextStyle(color: VColors.textDim, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onConfig,
              icon: const Icon(Icons.tune),
              label: const Text('CONFIGURAR FROTA'),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------- PATRAO: overview de todos os carros --------------------
class _PatraoView extends StatelessWidget {
  final FleetService fleet;
  const _PatraoView(this.fleet);

  @override
  Widget build(BuildContext context) {
    if (fleet.carregando) {
      return const Center(child: CircularProgressIndicator(color: VColors.cyan));
    }
    if (fleet.veiculos.isEmpty) {
      return const Center(
        child: Text('Nenhum carro na frota.\nToque em "+ Carro" para cadastrar.',
            textAlign: TextAlign.center, style: TextStyle(color: VColors.textFaint)),
      );
    }
    return RefreshIndicator(
      color: VColors.cyan,
      onRefresh: fleet.recarregar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        children: [
          _resumo(),
          const SizedBox(height: 12),
          for (final v in fleet.veiculos) _card(context, v),
        ],
      ),
    );
  }

  Widget _resumo() {
    final online = fleet.veiculos.where((v) => v.online).length;
    return Row(
      children: [
        Expanded(child: _mini('CARROS', '${fleet.veiculos.length}', VColors.cyan)),
        const SizedBox(width: 12),
        Expanded(child: _mini('ONLINE', '$online', VColors.green)),
        const SizedBox(width: 12),
        Expanded(child: _mini('OFFLINE', '${fleet.veiculos.length - online}', VColors.textFaint)),
      ],
    );
  }

  Widget _mini(String rot, String val, Color cor) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: VColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: VColors.line),
        ),
        child: Column(children: [
          Text(val, style: TextStyle(color: cor, fontSize: 24, fontWeight: FontWeight.bold)),
          Text(rot, style: const TextStyle(color: VColors.textFaint, fontSize: 10, letterSpacing: 1)),
        ]),
      );

  Widget _card(BuildContext context, FleetVehicle v) {
    final s = v.snapshot;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: (v.online ? VColors.green : VColors.textFaint).withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.directions_car,
              color: v.online ? VColors.green : VColors.textFaint, size: 22),
        ),
        title: Text(v.titulo.isEmpty ? '(sem nome)' : v.titulo,
            style: const TextStyle(color: VColors.textHi, fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (v.placa.isNotEmpty || v.motorista.isNotEmpty)
              Text([if (v.placa.isNotEmpty) v.placa, if (v.motorista.isNotEmpty) v.motorista].join(' · '),
                  style: const TextStyle(color: VColors.textDim, fontSize: 12)),
            const SizedBox(height: 2),
            Text(
              s == null
                  ? 'Sem dados ainda'
                  : '${s.km} km · ${s.temp}°C · comb ${s.combustivel >= 0 ? "${s.combustivel}%" : "--"} · ${_ha(v.idade)}',
              style: const TextStyle(color: VColors.textFaint, fontSize: 12),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, color: VColors.textFaint),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => FleetVehicleScreen(vehicleId: v.id))),
      ),
    );
  }

  static String _ha(Duration? d) {
    if (d == null) return 'nunca reportou';
    if (d.inMinutes < 1) return 'agora';
    if (d.inMinutes < 60) return 'ha ${d.inMinutes} min';
    if (d.inHours < 24) return 'ha ${d.inHours} h';
    return 'ha ${d.inDays} d';
  }
}

// -------------------- MOTORISTA: escolhe e atualiza o carro dele --------------------
class _MotoristaView extends StatelessWidget {
  final FleetService fleet;
  const _MotoristaView(this.fleet);

  @override
  Widget build(BuildContext context) {
    if (fleet.veiculos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('O patrao ainda nao cadastrou os carros da frota.',
              textAlign: TextAlign.center, style: TextStyle(color: VColors.textFaint)),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('QUAL CARRO VOCE ESTA DIRIGINDO?',
            style: TextStyle(color: VColors.textDim, letterSpacing: 1.5, fontSize: 13)),
        const SizedBox(height: 4),
        const Text('O app vai enviar os dados desse carro pela frota automaticamente.',
            style: TextStyle(color: VColors.textFaint, fontSize: 12)),
        const SizedBox(height: 12),
        for (final v in fleet.veiculos)
          RadioListTile<String>(
            value: v.id,
            groupValue: fleet.myVehicleId,
            onChanged: (id) => fleet.definirMeuVeiculo(id),
            activeColor: VColors.cyan,
            title: Text(v.titulo.isEmpty ? '(sem nome)' : v.titulo,
                style: const TextStyle(color: VColors.textHi)),
            subtitle: v.placa.isNotEmpty
                ? Text(v.placa, style: const TextStyle(color: VColors.textFaint))
                : null,
          ),
        const SizedBox(height: 16),
        if (fleet.meuVeiculo != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: VColors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: VColors.green.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              const Icon(Icons.cloud_upload_outlined, color: VColors.green),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Enviando "${fleet.meuVeiculo!.titulo}" para a frota enquanto conectado no Bluetooth.',
                  style: const TextStyle(color: VColors.textHi, fontSize: 13),
                ),
              ),
            ]),
          ),
      ],
    );
  }
}

// -------------------- Setup (modo/papel/id da frota) --------------------
class FleetSetupScreen extends StatefulWidget {
  const FleetSetupScreen({super.key});
  @override
  State<FleetSetupScreen> createState() => _FleetSetupScreenState();
}

class _FleetSetupScreenState extends State<FleetSetupScreen> {
  late bool _on;
  late FleetRole _role;
  late TextEditingController _id;

  @override
  void initState() {
    super.initState();
    final f = context.read<FleetService>();
    _on = f.ativo;
    _role = f.role;
    _id = TextEditingController(text: f.fleetId);
  }

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backend = context.read<FleetService>().sync;
    return Scaffold(
      appBar: AppBar(title: const Text('CONFIGURAR FROTA')),
      body: VBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SwitchListTile(
              value: _on,
              onChanged: (v) => setState(() => _on = v),
              activeColor: VColors.cyan,
              title: const Text('Ativar modo Frota', style: TextStyle(color: VColors.textHi)),
              subtitle: const Text('Gerencia varios carros de uma empresa',
                  style: TextStyle(color: VColors.textFaint)),
            ),
            const SizedBox(height: 8),
            const Text('SEU PAPEL', style: TextStyle(color: VColors.textDim, letterSpacing: 1.5, fontSize: 13)),
            RadioListTile<FleetRole>(
              value: FleetRole.patrao,
              groupValue: _role,
              onChanged: (v) => setState(() => _role = v!),
              activeColor: VColors.cyan,
              title: const Text('Patrao (dono da frota)', style: TextStyle(color: VColors.textHi)),
              subtitle: const Text('Ve e gerencia todos os carros',
                  style: TextStyle(color: VColors.textFaint)),
            ),
            RadioListTile<FleetRole>(
              value: FleetRole.motorista,
              groupValue: _role,
              onChanged: (v) => setState(() => _role = v!),
              activeColor: VColors.cyan,
              title: const Text('Motorista', style: TextStyle(color: VColors.textHi)),
              subtitle: const Text('Atualiza so o carro que ele dirige',
                  style: TextStyle(color: VColors.textFaint)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _id,
              style: const TextStyle(color: VColors.textHi),
              decoration: InputDecoration(
                labelText: 'Codigo da frota (ex.: nome da empresa)',
                helperText: 'O mesmo codigo no celular do patrao e dos motoristas',
                filled: true,
                fillColor: VColors.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: VColors.cardHi,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(backend.compartilha ? Icons.cloud_done : Icons.phone_android,
                    size: 18, color: VColors.textDim),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sincronizacao: ${backend.nome}.'
                    '${backend.compartilha ? "" : " (Entre celulares diferentes so com a nuvem, mais pra frente.)"}',
                    style: const TextStyle(color: VColors.textFaint, fontSize: 12),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () async {
                await context.read<FleetService>().configurar(ligado: _on, papel: _role, id: _id.text);
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.check),
              label: const Text('SALVAR'),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------- Sheet de cadastro/edicao de veiculo --------------------
class _EditVehicleSheet extends StatefulWidget {
  final FleetService fleet;
  final FleetVehicle? original;
  const _EditVehicleSheet({required this.fleet, this.original});
  @override
  State<_EditVehicleSheet> createState() => _EditVehicleSheetState();
}

class _EditVehicleSheetState extends State<_EditVehicleSheet> {
  late TextEditingController _apelido, _placa, _marca, _modelo, _ano, _motorista;

  @override
  void initState() {
    super.initState();
    final v = widget.original;
    _apelido = TextEditingController(text: v?.apelido ?? '');
    _placa = TextEditingController(text: v?.placa ?? '');
    _marca = TextEditingController(text: v?.marca ?? '');
    _modelo = TextEditingController(text: v?.modelo ?? '');
    _ano = TextEditingController(text: v?.ano ?? '');
    _motorista = TextEditingController(text: v?.motorista ?? '');
  }

  @override
  void dispose() {
    for (final c in [_apelido, _placa, _marca, _modelo, _ano, _motorista]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.original == null ? 'Novo carro' : 'Editar carro',
              style: const TextStyle(color: VColors.textHi, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _campo(_apelido, 'Apelido (ex.: Carro 1)'),
          _campo(_placa, 'Placa'),
          Row(children: [
            Expanded(child: _campo(_marca, 'Marca')),
            const SizedBox(width: 10),
            Expanded(child: _campo(_modelo, 'Modelo')),
          ]),
          Row(children: [
            Expanded(child: _campo(_ano, 'Ano', numero: true)),
            const SizedBox(width: 10),
            Expanded(child: _campo(_motorista, 'Motorista')),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            if (widget.original != null)
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: VColors.red, side: const BorderSide(color: VColors.red)),
                  onPressed: () async {
                    await widget.fleet.removerVeiculo(widget.original!.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Excluir'),
                ),
              ),
            if (widget.original != null) const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () async {
                  final v = widget.original ?? FleetVehicle(id: widget.fleet.novoId());
                  v.apelido = _apelido.text.trim();
                  v.placa = _placa.text.trim();
                  v.marca = _marca.text.trim();
                  v.modelo = _modelo.text.trim();
                  v.ano = _ano.text.trim();
                  v.motorista = _motorista.text.trim();
                  await widget.fleet.salvarVeiculo(v);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Salvar'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _campo(TextEditingController c, String label, {bool numero = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: numero ? TextInputType.number : TextInputType.text,
          style: const TextStyle(color: VColors.textHi),
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: VColors.bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
}
