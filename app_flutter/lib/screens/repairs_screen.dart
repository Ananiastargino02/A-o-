import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../ble/ble_service.dart';
import '../models/repair.dart';
import '../storage/repair_store.dart';
import '../theme.dart';

/// Aba "Consertos": lista dos consertos/revisoes documentados pelo usuario.
class RepairsScreen extends StatefulWidget {
  const RepairsScreen({super.key});
  @override
  State<RepairsScreen> createState() => _RepairsScreenState();
}

class _RepairsScreenState extends State<RepairsScreen> {
  final _store = RepairStore();
  List<RepairRecord> _lista = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _recarregar();
  }

  Future<void> _recarregar() async {
    final l = await _store.load();
    if (!mounted) return;
    setState(() {
      _lista = l;
      _carregando = false;
    });
  }

  Future<void> _abrirEditor([RepairRecord? existente]) async {
    final kmAtual = context.read<BleService>().live?.km ?? 0;
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RepairEditor(registro: existente, kmSugerido: kmAtual),
      ),
    );
    if (salvou == true) _recarregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CONSERTOS')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: VColors.cyan,
        foregroundColor: Colors.black,
        onPressed: () => _abrirEditor(),
        icon: const Icon(Icons.add),
        label: const Text('NOVO'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator(color: VColors.cyan))
          : _lista.isEmpty
              ? _vazio()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                  itemCount: _lista.length,
                  itemBuilder: (_, i) => _card(_lista[i]),
                ),
    );
  }

  Widget _vazio() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.handyman_outlined, size: 64, color: VColors.textFaint),
          const SizedBox(height: 14),
          const Text('Nenhum conserto documentado',
              style: TextStyle(color: VColors.textDim, fontSize: 16)),
          const SizedBox(height: 6),
          const Text('Toque em NOVO para registrar uma revisao ou reparo\ncom descricao, km e fotos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: VColors.textFaint, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _card(RepairRecord r) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final mudou = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => RepairDetail(registro: r)),
          );
          if (mudou == true) _recarregar();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _thumb(r),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.titulo.isEmpty ? '(sem titulo)' : r.titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: VColors.textHi, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('${r.dataFmt}  ·  ${r.km} km',
                        style: const TextStyle(color: VColors.textDim, fontSize: 12)),
                    if (r.descricao.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(r.descricao,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: VColors.textFaint, fontSize: 13)),
                    ],
                    if (r.custoFmt.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(r.custoFmt,
                          style: const TextStyle(color: VColors.green, fontSize: 13)),
                    ],
                  ],
                ),
              ),
              if (r.fotos.length > 1)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Row(children: [
                    const Icon(Icons.photo_library_outlined, size: 14, color: VColors.textFaint),
                    Text(' ${r.fotos.length}',
                        style: const TextStyle(color: VColors.textFaint, fontSize: 12)),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb(RepairRecord r) {
    if (r.fotos.isEmpty) {
      return Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: VColors.cardHi,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.build, color: VColors.textFaint),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.file(File(r.fotos.first),
          width: 64, height: 64, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
                width: 64, height: 64, color: VColors.cardHi,
                child: const Icon(Icons.broken_image, color: VColors.textFaint),
              )),
    );
  }
}

// ============================================================
//  DETALHE
// ============================================================
class RepairDetail extends StatelessWidget {
  final RepairRecord registro;
  const RepairDetail({super.key, required this.registro});

  @override
  Widget build(BuildContext context) {
    final r = registro;
    return Scaffold(
      appBar: AppBar(
        title: Text(r.titulo.isEmpty ? 'Conserto' : r.titulo),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final mudou = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => RepairEditor(registro: r, kmSugerido: r.km)),
              );
              if (mudou == true && context.mounted) Navigator.pop(context, true);
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: VColors.red),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: VColors.card,
                  title: const Text('Excluir conserto?'),
                  content: const Text('Isso apaga o registro e as fotos.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                    FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: VColors.red, foregroundColor: Colors.white),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Excluir')),
                  ],
                ),
              );
              if (ok == true) {
                await RepairStore().remove(r);
                if (context.mounted) Navigator.pop(context, true);
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _linha(Icons.calendar_today_outlined, 'Data', r.dataFmt),
          _linha(Icons.speed_outlined, 'Quilometragem', '${r.km} km'),
          if (r.oficina.isNotEmpty) _linha(Icons.store_outlined, 'Oficina', r.oficina),
          if (r.custoFmt.isNotEmpty) _linha(Icons.attach_money, 'Custo', r.custoFmt),
          if (r.descricao.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('DESCRICAO',
                style: TextStyle(color: VColors.textDim, letterSpacing: 2, fontSize: 12)),
            const SizedBox(height: 6),
            Text(r.descricao, style: const TextStyle(color: VColors.textHi, height: 1.4)),
          ],
          if (r.fotos.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('FOTOS',
                style: TextStyle(color: VColors.textDim, letterSpacing: 2, fontSize: 12)),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final f in r.fotos)
                  GestureDetector(
                    onTap: () => _verFoto(context, f),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(File(f), fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(color: VColors.cardHi, child: const Icon(Icons.broken_image))),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _linha(IconData ic, String label, String valor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(ic, size: 18, color: VColors.textDim),
          const SizedBox(width: 10),
          Text('$label: ', style: const TextStyle(color: VColors.textDim)),
          Expanded(child: Text(valor, style: const TextStyle(color: VColors.textHi))),
        ]),
      );

  void _verFoto(BuildContext context, String path) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(8),
        child: InteractiveViewer(
          child: Image.file(File(path)),
        ),
      ),
    );
  }
}

// ============================================================
//  EDITOR (novo/editar)
// ============================================================
class RepairEditor extends StatefulWidget {
  final RepairRecord? registro;
  final int kmSugerido;
  const RepairEditor({super.key, this.registro, this.kmSugerido = 0});
  @override
  State<RepairEditor> createState() => _RepairEditorState();
}

class _RepairEditorState extends State<RepairEditor> {
  final _store = RepairStore();
  final _titulo = TextEditingController();
  final _desc = TextEditingController();
  final _km = TextEditingController();
  final _custo = TextEditingController();
  final _oficina = TextEditingController();
  late DateTime _data;
  final List<String> _fotos = [];
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final r = widget.registro;
    if (r != null) {
      _titulo.text = r.titulo;
      _desc.text = r.descricao;
      _km.text = r.km.toString();
      _custo.text = r.custo > 0 ? r.custo.toStringAsFixed(2) : '';
      _oficina.text = r.oficina;
      _data = r.data;
      _fotos.addAll(r.fotos);
    } else {
      _data = DateTime.now();
      if (widget.kmSugerido > 0) _km.text = widget.kmSugerido.toString();
    }
  }

  Future<void> _addFoto(ImageSource src) async {
    try {
      final x = await ImagePicker().pickImage(source: src, imageQuality: 70, maxWidth: 1600);
      if (x == null) return;
      final salvo = await _store.savePhoto(x.path);
      setState(() => _fotos.add(salvo));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Falha na foto: $e'), backgroundColor: VColors.red));
      }
    }
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    final r = widget.registro ??
        RepairRecord(id: DateTime.now().millisecondsSinceEpoch.toString());
    r.titulo = _titulo.text.trim();
    r.descricao = _desc.text.trim();
    r.data = _data;
    r.km = int.tryParse(_km.text) ?? 0;
    r.custo = double.tryParse(_custo.text.replaceAll(',', '.')) ?? 0;
    r.oficina = _oficina.text.trim();
    r.fotos = List.from(_fotos);
    await _store.upsert(r);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.registro == null ? 'Novo conserto' : 'Editar'),
        actions: [
          TextButton(
            onPressed: _salvando ? null : _salvar,
            child: const Text('SALVAR', style: TextStyle(color: VColors.cyan)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _campo(_titulo, 'Titulo (ex.: Troca de oleo)', Icons.title),
          _campo(_desc, 'Descricao / servicos feitos', Icons.notes, linhas: 4),
          Row(children: [
            Expanded(child: _campo(_km, 'Quilometragem', Icons.speed, numero: true)),
            const SizedBox(width: 12),
            Expanded(child: _campo(_custo, 'Custo (R\$)', Icons.attach_money, numero: true)),
          ]),
          _campo(_oficina, 'Oficina / responsavel', Icons.store_outlined),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_outlined, color: VColors.textDim),
            title: const Text('Data'),
            trailing: Text(
                '${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}',
                style: const TextStyle(color: VColors.cyan)),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _data,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (d != null) setState(() => _data = d);
            },
          ),
          const SizedBox(height: 16),
          const Text('FOTOS DO CONSERTO',
              style: TextStyle(color: VColors.textDim, letterSpacing: 2, fontSize: 12)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < _fotos.length; i++) _fotoTile(i),
              _addBtn(),
            ],
          ),
          const SizedBox(height: 30),
          FilledButton.icon(
            onPressed: _salvando ? null : _salvar,
            icon: const Icon(Icons.save_outlined),
            label: Text(_salvando ? 'Salvando...' : 'SALVAR CONSERTO'),
          ),
        ],
      ),
    );
  }

  Widget _fotoTile(int i) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(File(_fotos[i]), width: 90, height: 90, fit: BoxFit.cover),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: () => setState(() => _fotos.removeAt(i)),
            child: Container(
              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 18, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _addBtn() {
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        backgroundColor: VColors.card,
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: VColors.cyan),
                title: const Text('Tirar foto'),
                onTap: () {
                  Navigator.pop(context);
                  _addFoto(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: VColors.cyan),
                title: const Text('Escolher da galeria'),
                onTap: () {
                  Navigator.pop(context);
                  _addFoto(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
      child: Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          color: VColors.cardHi,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: VColors.line),
        ),
        child: const Icon(Icons.add_a_photo_outlined, color: VColors.textDim),
      ),
    );
  }

  Widget _campo(TextEditingController c, String label, IconData icon,
      {bool numero = false, int linhas = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: numero
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        maxLines: linhas,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: linhas == 1 ? Icon(icon, color: VColors.textDim) : null,
          alignLabelWithHint: true,
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

  @override
  void dispose() {
    _titulo.dispose();
    _desc.dispose();
    _km.dispose();
    _custo.dispose();
    _oficina.dispose();
    super.dispose();
  }
}
