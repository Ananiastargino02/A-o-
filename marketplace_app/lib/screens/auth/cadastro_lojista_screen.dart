import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart' show GeoPoint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_config.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/cnpj_validator.dart';
import '../../core/utils/geo_helper.dart';
import '../../models/loja_model.dart';
import '../../providers/services_providers.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/foto_picker_field.dart';

class CadastroLojistaScreen extends ConsumerStatefulWidget {
  const CadastroLojistaScreen({super.key});

  @override
  ConsumerState<CadastroLojistaScreen> createState() => _CadastroLojistaScreenState();
}

class _CadastroLojistaScreenState extends ConsumerState<CadastroLojistaScreen> {
  final _nomeController = TextEditingController();
  final _nomeLojaController = TextEditingController();
  final _cnpjController = TextEditingController();
  final _enderecoController = TextEditingController();
  double _raioKm = 10;
  File? _logo;
  bool _salvando = false;

  final Set<String> _categoriasSelecionadas = {AppConfig.categoriaPecasAutomotivas};

  Future<void> _salvar() async {
    if (_nomeController.text.trim().isEmpty ||
        _nomeLojaController.text.trim().isEmpty ||
        _enderecoController.text.trim().isEmpty) {
      AppToast.mostrar('Preencha todos os campos.');
      return;
    }
    if (!CnpjValidator.isValid(_cnpjController.text)) {
      AppToast.mostrar('CNPJ inválido. Confira o número.');
      return;
    }

    setState(() => _salvando = true);

    final localizacao = await ref.read(locationServiceProvider).geocodificar(_enderecoController.text.trim());
    if (localizacao == null) {
      setState(() => _salvando = false);
      AppToast.mostrar('Não encontramos esse endereço. Confira e tente de novo.');
      return;
    }

    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) return;

    await ref.read(firestoreServiceProvider).criarOuAtualizarUser(user.uid, {
      'tipo': TipoUsuario.lojista.name,
      'nome': _nomeController.text.trim(),
      'telefone': user.phoneNumber ?? '',
      'criadoEm': DateTime.now(),
    });

    final geopoint = GeoPoint(localizacao.latitude, localizacao.longitude);
    final loja = LojaModel(
      id: '',
      userId: user.uid,
      nomeLoja: _nomeLojaController.text.trim(),
      cnpj: CnpjValidator.stripFormatting(_cnpjController.text),
      endereco: _enderecoController.text.trim(),
      geopoint: geopoint,
      geohash: GeoHelper.geohashDe(geopoint),
      raioKm: _raioKm,
      categorias: _categoriasSelecionadas.toList(),
      criadoEm: DateTime.now(),
    );

    final lojaId = await ref.read(firestoreServiceProvider).criarLoja(loja);

    if (_logo != null) {
      final url = await ref.read(storageServiceProvider).uploadLogoLoja(_logo!, lojaId);
      await ref.read(firestoreServiceProvider).atualizarLogoLoja(lojaId, url);
    }

    await ref.read(fcmServiceProvider).inicializar(user.uid);

    setState(() => _salvando = false);
    // Navegacao para o app do lojista acontece via RootGate.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastro da loja')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Seus dados', style: AppTextStyles.h3),
          const SizedBox(height: 10),
          TextField(
            controller: _nomeController,
            decoration: const InputDecoration(hintText: 'Seu nome'),
          ),
          const SizedBox(height: 20),
          Text('Dados da loja', style: AppTextStyles.h3),
          const SizedBox(height: 10),
          TextField(
            controller: _nomeLojaController,
            decoration: const InputDecoration(hintText: 'Nome da loja'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _cnpjController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'CNPJ (só números ou formatado)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _enderecoController,
            decoration: const InputDecoration(hintText: 'Endereço completo (rua, número, bairro, cidade)'),
          ),
          const SizedBox(height: 20),
          Text('Raio de atendimento: ${_raioKm.round()} km', style: AppTextStyles.h3),
          Slider(
            value: _raioKm,
            min: 1,
            max: 50,
            divisions: 49,
            activeColor: AppColors.amber,
            label: '${_raioKm.round()} km',
            onChanged: (v) => setState(() => _raioKm = v),
          ),
          const SizedBox(height: 10),
          Text('Categorias que você atende', style: AppTextStyles.h3),
          const SizedBox(height: 10),
          ...AppConfig.categorias.map(
            (cat) => CheckboxListTile(
              value: _categoriasSelecionadas.contains(cat.id),
              onChanged: cat.ativa
                  ? (checked) {
                      setState(() {
                        if (checked == true) {
                          _categoriasSelecionadas.add(cat.id);
                        } else {
                          _categoriasSelecionadas.remove(cat.id);
                        }
                      });
                    }
                  : null,
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.amber,
              title: Text(cat.nome, style: AppTextStyles.body),
              subtitle: cat.ativa ? null : const Text('Em breve'),
            ),
          ),
          const SizedBox(height: 10),
          Text('Logo da loja', style: AppTextStyles.h3),
          const SizedBox(height: 10),
          FotoPickerField(arquivo: _logo, onChanged: (f) => setState(() => _logo = f)),
          const SizedBox(height: 24),
          AppButton(
            label: 'Criar loja',
            onPressed: _salvar,
            loading: _salvando,
            estilo: AppButtonEstilo.destaque,
          ),
        ],
      ),
    );
  }
}
