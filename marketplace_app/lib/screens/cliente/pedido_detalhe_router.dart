import 'package:flutter/material.dart';
import '../../models/pedido_model.dart';
import 'orcamentos_screen.dart';

/// Decide para onde ir ao tocar num pedido: pedidos recem-abertos e sem
/// nenhum orcamento vao para a tela de orcamentos, que ja mostra o radar
/// compacto no topo enquanto aguarda; e o proprio destino final quando os
/// orcamentos comecam a chegar.
void abrirDetalheDoPedido(BuildContext context, PedidoModel pedido) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => OrcamentosScreen(pedidoId: pedido.id)),
  );
}
