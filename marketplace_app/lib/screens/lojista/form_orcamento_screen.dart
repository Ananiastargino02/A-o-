import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_config.dart';
import '../../core/constants/app_text_styles.dart';
import '../../models/orcamento_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pedidos_provider.dart';
import '../../providers/services_providers.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/foto_picker_field.dart';

class FormOrcamentoScreen extends ConsumerStatefulWidget {
  final String pedidoId;

  const FormOrcamentoScreen({super.key, required this.pedidoId});

  @override
  ConsumerState<FormOrcamentoScreen> createState() => _FormOrcamentoScreenState();
}

class _FormOrcamentoScreenState extends ConsumerState<FormOrcamentoScreen> {
  final _precoController = TextEditingController();
  final _marcaPecaController = TextEditingController();
  CondicaoPeca _condicao = CondicaoPeca.usada;
  TipoEntrega _entrega = TipoEntrega.retirada;
  Garantia _garantia = Garantia.semGarantia;
  File? _foto;
  bool _enviando = false;

  Future<void> _enviar() async {
    final preco = double.tryParse(_precoController.text.replaceAll(',', '.'));
    if (preco == null || preco <= 0) {
      AppToast.mostrar('Digite um preço válido.');
      return;
    }
    if (_marcaPecaController.text.trim().isEmpty) {
      AppToast.mostrar('Digite a marca da peça.');
      return;
    }

    final loja = ref.read(currentLojaProvider).value;
    final pedido = ref.read(pedidoProvider(widget.pedidoId)).value;
    if (loja == null || pedido == null) return;

    setState(() => _enviando = true);

    String? fotoUrl;
    final firestore = ref.read(firestoreServiceProvider);
    final orcamentoId = firestore.novoPedidoId();
    if (_foto != null) {
      fotoUrl = await ref.read(storageServiceProvider).uploadFotoOrcamento(_foto!, orcamentoId);
    }

    final tempoRespostaMin = DateTime.now().difference(pedido.criadoEm).inMinutes;

    await firestore.criarOrcamento(
      OrcamentoModel(
        id: orcamentoId,
        pedidoId: widget.pedidoId,
        lojaId: loja.id,
        preco: preco,
        condicao: _condicao,
        marcaPeca: _marcaPecaController.text.trim(),
        entrega: _entrega,
        garantia: _garantia,
        fotoUrl: fotoUrl,
        tempoRespostaMin: tempoRespostaMin < 0 ? 0 : tempoRespostaMin,
        criadoEm: DateTime.now(),
      ),
    );

    if (!mounted) return;
    setState(() => _enviando = false);
    AppToast.mostrar('Orçamento enviado!');
    Navigator.of(context).pop();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fazer orçamento')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Preço', style: AppTextStyles.h3),
          const SizedBox(height: 10),
          TextField(
            controller: _precoController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: const InputDecoration(prefixText: 'R\$ ', hintText: '0,00'),
          ),
          const SizedBox(height: 20),
          Text('Condição', style: AppTextStyles.h3),
          const SizedBox(height: 10),
          SegmentedButton<CondicaoPeca>(
            segments: CondicaoPeca.values
                .map((c) => ButtonSegment(value: c, label: Text(c.label)))
                .toList(),
            selected: {_condicao},
            onSelectionChanged: (v) => setState(() => _condicao = v.first),
          ),
          const SizedBox(height: 20),
          Text('Marca da peça', style: AppTextStyles.h3),
          const SizedBox(height: 10),
          TextField(
            controller: _marcaPecaController,
            decoration: const InputDecoration(hintText: 'Ex: Original, TRW, Bosch...'),
          ),
          const SizedBox(height: 20),
          Text('Entrega', style: AppTextStyles.h3),
          const SizedBox(height: 10),
          ...TipoEntrega.values.map(
            (e) => RadioListTile<TipoEntrega>(
              value: e,
              groupValue: _entrega,
              onChanged: (v) => setState(() => _entrega = v!),
              contentPadding: EdgeInsets.zero,
              title: Text(e.label),
            ),
          ),
          const SizedBox(height: 10),
          Text('Garantia', style: AppTextStyles.h3),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: Garantia.values
                .map((g) => ChoiceChip(
                      label: Text(g.label),
                      selected: _garantia == g,
                      onSelected: (_) => setState(() => _garantia = g),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),
          Text('Foto da peça (opcional)', style: AppTextStyles.h3),
          const SizedBox(height: 10),
          FotoPickerField(arquivo: _foto, onChanged: (f) => setState(() => _foto = f)),
          const SizedBox(height: 24),
          AppButton(
            label: 'Enviar orçamento',
            onPressed: _enviar,
            loading: _enviando,
            estilo: AppButtonEstilo.destaque,
          ),
        ],
      ),
    );
  }
}
