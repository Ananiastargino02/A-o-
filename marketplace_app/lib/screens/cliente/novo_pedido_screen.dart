import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_config.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/data/vehicles_data.dart';
import '../../core/utils/geo_helper.dart';
import '../../models/pedido_model.dart';
import '../../providers/location_provider.dart';
import '../../providers/services_providers.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/foto_picker_field.dart';
import 'radar_screen.dart';

class NovoPedidoScreen extends ConsumerStatefulWidget {
  const NovoPedidoScreen({super.key});

  @override
  ConsumerState<NovoPedidoScreen> createState() => _NovoPedidoScreenState();
}

class _NovoPedidoScreenState extends ConsumerState<NovoPedidoScreen> {
  String? _marca;
  String? _modelo;
  int? _ano;
  final _pecaController = TextEditingController();
  final _detalhesController = TextEditingController();
  File? _foto;
  bool _enviando = false;

  Future<void> _enviar() async {
    if (_marca == null || _modelo == null || _ano == null || _pecaController.text.trim().isEmpty) {
      AppToast.mostrar('Preencha marca, modelo, ano e a peça que você precisa.');
      return;
    }

    setState(() => _enviando = true);

    final posicao = await ref.read(currentPositionProvider.future);
    if (posicao == null) {
      setState(() => _enviando = false);
      AppToast.mostrar('Precisamos da sua localização pra encontrar lojas perto de você.');
      return;
    }

    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) return;

    final pedidoId = ref.read(firestoreServiceProvider).novoPedidoId();

    String? fotoUrl;
    if (_foto != null) {
      fotoUrl = await ref.read(storageServiceProvider).uploadFotoPedido(_foto!, pedidoId);
    }

    final geopoint = GeoPoint(posicao.latitude, posicao.longitude);
    final pedido = PedidoModel(
      id: pedidoId,
      clienteId: user.uid,
      categoria: AppConfig.categoriaPecasAutomotivas,
      marca: _marca!,
      modelo: _modelo!,
      ano: _ano!,
      peca: _pecaController.text.trim(),
      detalhes: _detalhesController.text.trim().isEmpty ? null : _detalhesController.text.trim(),
      fotoUrl: fotoUrl,
      geopoint: geopoint,
      geohash: GeoHelper.geohashDe(geopoint),
      status: StatusPedido.aberto,
      raioAtual: AppConfig.raiosExpansaoKm.first,
      lojasNotificadas: 0,
      criadoEm: DateTime.now(),
    );

    await ref.read(firestoreServiceProvider).criarPedidoComId(pedidoId, pedido);

    if (!mounted) return;
    setState(() => _enviando = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => RadarScreen(pedidoId: pedidoId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final marcas = VehiclesData.marcas;
    final modelos = _marca == null ? <String>[] : VehiclesData.modelosDe(_marca!);

    return Scaffold(
      appBar: AppBar(title: const Text('Novo pedido')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Seu veículo', style: AppTextStyles.h3),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _marca,
            decoration: const InputDecoration(hintText: 'Marca'),
            items: marcas.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
            onChanged: (v) => setState(() {
              _marca = v;
              _modelo = null;
            }),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _modelo,
            decoration: const InputDecoration(hintText: 'Modelo'),
            items: modelos.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
            onChanged: _marca == null ? null : (v) => setState(() => _modelo = v),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: _ano,
            decoration: const InputDecoration(hintText: 'Ano'),
            items: VehiclesData.anos.map((a) => DropdownMenuItem(value: a, child: Text('$a'))).toList(),
            onChanged: (v) => setState(() => _ano = v),
          ),
          const SizedBox(height: 20),
          Text('O que você precisa', style: AppTextStyles.h3),
          const SizedBox(height: 10),
          TextField(
            controller: _pecaController,
            decoration: const InputDecoration(hintText: 'Peça que você precisa (ex: retrovisor esquerdo)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _detalhesController,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Detalhes (opcional)'),
          ),
          const SizedBox(height: 16),
          FotoPickerField(arquivo: _foto, onChanged: (f) => setState(() => _foto = f)),
          const SizedBox(height: 24),
          AppButton(
            label: 'Enviar pedido',
            onPressed: _enviar,
            loading: _enviando,
            estilo: AppButtonEstilo.destaque,
            icone: Icons.send,
          ),
        ],
      ),
    );
  }
}
