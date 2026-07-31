# Gerar o app VEICAN sem Mac (Android + iPhone na nuvem)

Você desenvolve no Windows normalmente. A compilação do iPhone roda num **Mac na
nuvem** (Codemagic) — você não precisa ter Mac.

---

## PASSO 0 (uma vez) — enviar as pastas android/ e ios/ pro repositório

Elas têm as **permissões de Bluetooth** e a config de build. Hoje estão só na sua
máquina. No terminal, **dentro da pasta do projeto** (onde fica `app_flutter`):

```bash
git pull                      # pega o .gitignore novo e o codemagic.yaml
git add app_flutter/android app_flutter/ios
git commit -m "Sobe android/ios (permissoes BLE) p/ build na nuvem"
git push
```

> Se o `git add` reclamar que estão ignoradas, rode com `-f`:
> `git add -f app_flutter/android app_flutter/ios`

Confere se o `AndroidManifest.xml` tem as permissões de Bluetooth. Se não tiver,
adicione dentro de `app_flutter/android/app/src/main/AndroidManifest.xml`, antes de
`<application>`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.BLUETOOTH"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>
```

E no `app_flutter/ios/Runner/Info.plist` (dentro do `<dict>`):

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>O VEICAN usa Bluetooth para se conectar ao aparelho do carro.</string>
```

---

## PASSO 1 — criar conta no Codemagic e ligar o repositório

1. Entra em **https://codemagic.io** e cria conta (dá pra logar com o GitHub).
2. **Add application** → escolhe o repositório do VEICAN.
3. Ele detecta o `codemagic.yaml` sozinho. Aparecem 2 workflows:
   - **VEICAN Android (APK)**
   - **VEICAN iOS (IPA)**

---

## PASSO 2 — Android (funciona JÁ, sem conta nenhuma)

1. Roda o workflow **VEICAN Android (APK)** (botão *Start new build*).
2. Ao terminar (~5 min), baixa o **`app-release.apk`** no painel.
3. Manda pro celular Android e instala (precisa liberar "instalar de fontes
   desconhecidas"). Pronto — app rodando no Android.

---

## PASSO 3 — iPhone (precisa da conta Apple Developer)

Pra gerar o app de iPhone, a Apple exige:

1. **Conta Apple Developer** — US$ 99/ano em https://developer.apple.com (isso é
   inevitável em qualquer tecnologia, RN ou Flutter).
2. **Registrar um Bundle ID** no site da Apple (ex.: `com.veican.app`). Use o
   mesmo que está no `codemagic.yaml` (`bundle_identifier`).
3. No Codemagic: **Teams → Integrations → App Store Connect** → cria uma *API key*
   na App Store Connect e cola no Codemagic. Isso deixa ele **assinar** o app
   sozinho (o `xcode-project use-profiles` do yaml usa isso).
4. Escolhe o tipo de distribuição no `codemagic.yaml`:
   - `ad_hoc` → instala em iPhones **cadastrados** (você registra o UDID do
     aparelho na Apple). Bom pra teste.
   - `app_store` → sobe pro **TestFlight/App Store**.
5. Roda o workflow **VEICAN iOS (IPA)**. Ao terminar, baixa o `.ipa`
   (ad_hoc) ou ele já sobe pro TestFlight (app_store).

---

## Resumo
- **Android:** já dá pra gerar e instalar hoje, de graça, sem Mac.
- **iPhone:** dá pra gerar sem Mac também, mas precisa da conta Apple (US$ 99/ano)
  ligada no Codemagic. A compilação roda no Mac da nuvem.
- **Não precisa reescrever nada** — é o mesmo app Flutter que a gente já fez.
