# Setup do Firebase — APPNAME

Passo a passo pra deixar o backend funcionando do zero. Leva uns 20-30 min.

## 1. Criar o projeto no Firebase

1. Acesse https://console.firebase.google.com e clique em **Adicionar projeto**.
2. Dê um nome (pode ser o mesmo placeholder `APPNAME` por enquanto).
3. Pode desativar o Google Analytics se não for usar agora (dá pra ligar depois).

## 2. Ativar Authentication (login por telefone)

1. No menu lateral, **Build > Authentication > Get started**.
2. Aba **Sign-in method** > ative **Phone**.
3. Em produção, o Firebase pede números de teste ou verificação por
   reCAPTCHA/SafetyNet (Android) e APNs (iOS) — configure conforme os
   avisos do próprio console antes de testar em dispositivo físico.
4. (Opcional pra desenvolvimento) Adicione números de teste em
   **Phone numbers for testing** pra não gastar SMS de verdade.

## 3. Ativar o Cloud Firestore

1. **Build > Firestore Database > Criar banco de dados**.
2. Escolha a região mais próxima dos seus usuários (ex: `southamerica-east1`
   pra Brasil).
3. Comece em modo de produção (as regras deste repo já cobrem o acesso
   necessário — ver `firebase/firestore.rules`).

## 4. Ativar o Cloud Storage

1. **Build > Storage > Get started**.
2. Mesma região do Firestore, de preferência.

## 5. Ativar o Cloud Messaging (push)

1. **Build > Cloud Messaging** — já vem ativado ao criar o projeto.
2. Android: nenhuma chave extra é necessária além do
   `google-services.json` (passo 7).
3. iOS: gere uma **APNs Authentication Key** no Apple Developer Portal
   (Certificates, Identifiers & Profiles > Keys) e faça upload em
   **Project settings > Cloud Messaging > Apple app configuration**.

## 6. Instalar as ferramentas

```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
firebase login
```

## 7. Conectar o app Flutter ao projeto

Na raiz de `marketplace_app/`:

```bash
flutterfire configure --project=<seu-project-id>
```

Isso gera `lib/firebase_options.dart` de verdade (substitui o placeholder),
além de baixar automaticamente `android/app/google-services.json` e
`ios/Runner/GoogleService-Info.plist`.

Se ainda não rodou `flutter create` pra gerar os projetos nativos completos,
veja `docs/NATIVE_SCAFFOLD.md` antes deste passo.

## 8. Deploy das regras, índices e Cloud Functions

Todo o backend fica em `firebase/` (rules, indexes, functions). Rode os
comandos a partir dessa pasta:

```bash
cd firebase
firebase use --add          # selecione o project id criado no passo 1
cd functions && npm install && cd ..
firebase deploy --only firestore:rules,firestore:indexes,storage:rules,functions
```

Isso publica:
- `firestore.rules` / `storage.rules` — regras de segurança
- `firestore.indexes.json` — índices compostos exigidos pelas queries do app
- `functions/` — `onPedidoCriado`, `expandirRaioPedidos`, `onOrcamentoCriado`,
  `onMensagemCriada`, `onAvaliacaoCriada`, `obterMetricasLoja`

> `expandirRaioPedidos` é uma função agendada (Cloud Scheduler). O primeiro
> deploy cria o job automaticamente; confirme em **Cloud Scheduler** no
> Google Cloud Console se ele aparece rodando a cada 10 minutos.

## 9. Popular dados de exemplo (opcional, pra testar)

```bash
cd firebase/seed
npm install
# baixe uma chave de service account (Configurações do projeto > Contas de
# serviço > Gerar nova chave privada) e salve como service-account.json
# nesta pasta (não é versionado).
npm run seed
```

Isso cria 5 lojas fictícias em Duque de Caxias/RJ e 3 pedidos de exemplo —
ver `firebase/seed/seed.js`.

## 10. Rodar o app

```bash
cd marketplace_app
flutter pub get
flutter run
```

## Troca de nome (placeholder → nome final)

Busque e substitua (case-sensitive) em todo o projeto:
- `APPNAME` → nome de exibição
- `appname` → nome do pacote Dart / slug
- `com.appname.app` → application id (Android) / bundle id (iOS)

Depois disso, rode `flutterfire configure` de novo se o nome do app no
Firebase também mudar.
