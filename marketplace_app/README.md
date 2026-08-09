# APPNAME

Marketplace de cotação reversa: o cliente pede uma peça, lojistas próximos
respondem com orçamento, e os dois fecham negócio pelo chat dentro do app.
**O app não processa pagamento** — só intermedia o contato.

Categoria ativa nesta versão: **Peças automotivas**. As demais aparecem
como "Em breve" (desabilitadas) — ver `lib/core/constants/app_config.dart`.

> `APPNAME`/`appname` é um placeholder usado em todo o código pra facilitar
> a troca de nome depois — ver a seção "Troca de nome" em
> `docs/FIREBASE_SETUP.md`.

## Stack

- **Flutter** (Dart >=3.3), arquitetura em camadas com **Riverpod**
  (`lib/providers`) sobre serviços finos do Firebase (`lib/services`).
- **Firebase**: Auth (login por telefone/SMS), Cloud Firestore, Storage
  (fotos), Cloud Messaging (push), Cloud Functions (raio + notificações +
  métricas).
- **Geolocalização**: `geolocator` (posição do usuário) + `geoflutterfire_plus`
  (geohash) no client; `geofire-common` faz as geo-queries do lado das
  Cloud Functions.

## Estrutura

```
marketplace_app/
  lib/
    core/            # constantes, tema, utils, base de veículos BR
    models/           # classes de dados (Firestore <-> Dart)
    services/          # wrappers finos do Firebase (Auth, Firestore, Storage, FCM, Functions)
    providers/         # estado (Riverpod)
    screens/
      auth/             # login por telefone, cadastro cliente/lojista
      cliente/           # home, novo pedido, radar, orçamentos, chats, avaliação
      lojista/           # feed de pedidos, detalhe, form de orçamento, vendas
      chat/              # chat em tempo real
    widgets/            # componentes reutilizáveis (radar, chips, botões, cards)
  android/, ios/        # nativo (customizações — ver docs/NATIVE_SCAFFOLD.md)
  firebase/
    firestore.rules, storage.rules, firestore.indexes.json
    functions/          # Cloud Functions (Node.js)
    seed/               # dados de exemplo pra testar
  docs/
    FIREBASE_SETUP.md    # passo a passo completo do backend
    NATIVE_SCAFFOLD.md    # como gerar android/ios completos
```

## Rodando localmente

1. Siga `docs/FIREBASE_SETUP.md` do início ao fim (criar projeto, ativar
   serviços, `flutterfire configure`, deploy das rules/functions).
2. `flutter pub get`
3. `flutter run`

## Modelo de dados (Firestore)

| Coleção                    | Campos principais |
|-----------------------------|--------------------|
| `users`                     | `tipo`, `nome`, `telefone`, `fcmToken` |
| `lojas`                     | `userId`, `nomeLoja`, `cnpj`, `geopoint`, `geohash`, `raioKm`, `categorias[]`, `avaliacaoMedia`, `creditos` (préparado p/ monetização futura, sem cobrança ativa) |
| `pedidos`                   | `clienteId`, `categoria`, `marca/modelo/ano`, `peca`, `geopoint`, `status`, `raioAtual`, `lojasNotificadas`, `recusadoPor[]` |
| `orcamentos`                | `pedidoId`, `lojaId`, `preco`, `condicao`, `entrega`, `garantia`, `tempoRespostaMin` |
| `chats` (+ `mensagens`)     | `pedidoId`, `orcamentoId`, `clienteId`, `lojaId`, `status` |
| `avaliacoes`                | `lojaId`, `clienteId`, `pedidoId`, `estrelas`, `comentario` |

Regras de acesso completas em `firebase/firestore.rules`: cliente só lê os
próprios pedidos/chats; lojista só lê pedidos abertos e os próprios
orçamentos/chats.

## Lógica do raio

`pedidos` nasce com raio de 5 km. A cada 30 min sem pelo menos 3
orçamentos, a Cloud Function `expandirRaioPedidos` expande pra 10 → 20 →
40 km e notifica só as lojas novas dentro do raio. Sem resposta suficiente
em 48h, o pedido vira `expirado` (o cliente pode reabrir). Ver
`firebase/functions/src/raioExpansion.js`.

## Design system

Fonte Archivo (Google Fonts), fundo `#F3F4F6`, cards brancos com borda
`#E4E6EA`, destaque âmbar `#F7A500`, sucesso verde `#1E9E5A`, erro
vermelho `#D64545`, info azul `#2563EB`. Tudo centralizado em
`lib/core/constants` e `lib/core/theme` — não hardcode cores fora daí.
