const admin = require('firebase-admin');
admin.initializeApp();

const { onPedidoCriado, expandirRaioPedidos } = require('./src/raioExpansion');
const { onOrcamentoCriado, onMensagemCriada } = require('./src/notifications');
const { onAvaliacaoCriada, obterMetricasLoja } = require('./src/metrics');

exports.onPedidoCriado = onPedidoCriado;
exports.expandirRaioPedidos = expandirRaioPedidos;
exports.onOrcamentoCriado = onOrcamentoCriado;
exports.onMensagemCriada = onMensagemCriada;
exports.onAvaliacaoCriada = onAvaliacaoCriada;
exports.obterMetricasLoja = obterMetricasLoja;
