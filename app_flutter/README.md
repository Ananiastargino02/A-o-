# VEICAN — App (Flutter)

App Android (e pronto para iOS) que conecta no VEICAN por **Bluetooth (BLE)** e mostra
o painel ao vivo, manutenção e diagnóstico (falhas). Um único código gera Android **e** iOS.

- **Android:** você gera o APK agora, no Windows, **sem Mac**.
- **iOS:** o código já está pronto — só precisa de um Mac (ou serviço em nuvem, ex.: Codemagic)
  na hora de **gerar/publicar** o app da Apple.

---

## 1. Instalar o Flutter (uma vez)

1. Baixe o Flutter SDK: https://docs.flutter.dev/get-started/install/windows
2. Instale o **Android Studio** (vem com o Android SDK e o emulador).
3. No terminal, rode `flutter doctor` e resolva o que aparecer com ❌
   (aceite as licenças com `flutter doctor --android-licenses`).

## 2. Gerar as pastas de plataforma

Este projeto tem só o código (`lib/` e `pubspec.yaml`). As pastas `android/` e `ios/`
são geradas pelo Flutter. Dentro da pasta `app_flutter`:

```bash
flutter create --platforms=android,ios --org com.veican .
flutter pub get
```

> `flutter create` **não sobrescreve** os arquivos que já existem (o seu `lib/` e o
> `pubspec.yaml` ficam intactos) — ele só cria o que falta (android/, ios/, etc.).

## 3. Permissões de Bluetooth (Android)

Abra `android/app/src/main/AndroidManifest.xml` e **adicione**, logo acima da tag
`<application ...>`, estas linhas:

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<!-- Compatibilidade com Android 11 ou anterior -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
```

Para as **fotos dos consertos** (câmera/galeria), adicione também, dentro do
`<application ...>`, ou junto das permissões acima:

```xml
<uses-feature android:name="android.hardware.camera" android:required="false" />
```

No `android/app/build.gradle`, garanta `minSdkVersion 21` (ou maior).

> O `image_picker` usa o app de câmera/galeria do sistema, então no Android
> normalmente não precisa de permissão de CAMERA em tempo de execução.

## 4. Rodar / gerar o APK

Celular Android no cabo com **depuração USB** ligada:

```bash
flutter run                 # roda no celular pra testar
flutter build apk --release # gera o APK final
```

O APK sai em `build/app/outputs/flutter-apk/app-release.apk`.
Copie pro celular e instale (ative "instalar de fontes desconhecidas").

## 5. iOS (quando tiver Mac)

O código já está pronto. No Mac:

1. Abra `ios/Runner/Info.plist` e adicione:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>O VEICAN usa Bluetooth para ler os dados do seu carro.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>O VEICAN usa Bluetooth para ler os dados do seu carro.</string>
<key>NSCameraUsageDescription</key>
<string>Usado para fotografar os consertos do carro.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Usado para anexar fotos aos consertos.</string>
```

2. `flutter build ios` / abrir no Xcode para assinar e publicar.

> Sem Mac dá pra compilar iOS via nuvem (ex.: **Codemagic**, **GitHub Actions com runner macOS**).

---

## Como funciona (protocolo)

O app fala com o firmware pelo **Nordic UART Service (NUS)**:

- Nome anunciado: **VEICAN**
- Service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
- Write (app→aparelho) `6E400002-...`
- Notify (aparelho→app) `6E400003-...`

Comandos usados:

| Comando | Resposta |
|---|---|
| `STATUS` | `km=.. bat=..V rpm=.. temp=.. vel=.. comb=.. motor=..h..m proto=.. estado=..` |
| `MANUT LIST` | uma linha por item: `i:nome pct% int=..km/..d` |
| `MANUT RESET <n>` | `OK: ...` |
| `MANUT KM <n> <km>` / `MANUT DIAS <n> <dias>` | `OK: ...` |
| `DTC LER` | `DTC <n>` + uma linha por código |
| `DTC APAGAR` | `DTC apagados` / `Falha ao apagar` |
| `ODORESET`, `VOLTCAL <v>`, `KMCAL <r> <m>` | `OK: ...` |

## Estrutura

```
lib/
  main.dart               # app + navegacao (5 abas)
  theme.dart              # tema escuro (painel automotivo)
  ble/ble_service.dart    # nucleo BLE (scan, conexao, comandos, fila) + historico RPM
  models/                 # LiveData, CarProfile, MaintItem/Record, RepairRecord
  storage/                # local_store (perfil/manutencao) + repair_store (consertos+fotos)
  widgets/rpm_chart.dart  # grafico de RPM ao vivo (fl_chart)
  screens/                # scan, dashboard, manutencao, consertos, dtc, perfil
```

**Abas:** Painel · Manutenção · **Consertos** · Falhas · Carro.

- **Painel:** dados ao vivo em **4 estilos que o usuário escolhe** (Cartões, Esportivo
  com medidores circulares, Minimalista, Cockpit neon) — botão de ajuste ⚙️ abre a
  tela de seleção com prévia. Inclui **gráfico de RPM em tempo real** e card de
  **velocidade** (atual / máx. do dia / recorde) que abre o **Histórico de Velocidade**.
- **Consumo de combustível:** ícone ⛽ na barra do Painel abre os **gráficos de consumo**.
  Como o aparelho manda o **km do hodômetro** e o **nível do tanque (%)**, o consumo é
  **estimado**: litros = (% gasto ÷ 100) × capacidade do tanque; **km/L** = km ÷ litros.
  Mostra **média de km/L**, **autonomia estimada**, gráfico de **km/L por dia/mês** e de
  **nível do tanque** ao longo dos dias. A **capacidade do tanque** é configurável (toque no
  card "TANQUE"). Reabastecimento é detectado quando o nível sobe.
- **Histórico de Velocidade:** grava a **velocidade máxima de cada dia** (enquanto o app
  está conectado) e mostra em **gráfico por Dia / Mês / Ano**, com o **recorde de todos os
  tempos e a data**. Ex.: "atingiu 150 km/h em 12 de julho de 2026".
- **Consertos:** o usuário documenta cada revisão/reparo (título, descrição, data,
  km, custo, oficina) e anexa **fotos** (câmera ou galeria). Fica tudo salvo no celular.

Perfil do carro, histórico de manutenção e os consertos (com fotos) ficam salvos
**no celular** (shared_preferences + arquivos locais), **separados por carro**
(`CarScope`): ao **trocar de carro** na aba "Carro", tudo é zerado e recomeça —
os dados de um carro nunca embolam com o outro.

## Modo Frota (empresas)

Na aba **Carro → Modo Frota**: para quem tem **vários carros** (ex.: uma empresa
com 10 carros). O **patrão** cadastra todos os carros e acompanha a frota inteira
(km, temperatura, combustível, online/offline, última atualização). Cada
**motorista** escolhe o carro que dirige e o app **envia o retrato do carro**
(snapshot) automaticamente enquanto conectado no Bluetooth.

**Sincronização — arquitetura pronta pra nuvem:** a camada de sync é abstrata
(`lib/fleet/fleet_sync.dart`). Hoje roda com **`LocalFleetSync`** (tudo no
celular; ideal para "um celular gerencia vários carros"). Para o patrão ver os
carros de **motoristas em celulares diferentes**, é só implementar o
**`CloudFleetSync`** (esqueleto já pronto: Firebase/Supabase/API própria) e
registrar em `FleetService.usarBackend(...)` — **nenhuma tela precisa mudar**.
