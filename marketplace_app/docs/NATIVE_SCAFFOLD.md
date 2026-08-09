# Projetos nativos (Android/iOS)

Este repositório inclui os arquivos nativos que **precisam de customização**
(permissões, application id, nome do app, integração com Firebase). Os
demais arquivos de um projeto Flutter padrão (ícones, `Assets.xcassets`,
`Main.storyboard`, `LaunchScreen.storyboard`, `Runner.xcodeproj`, wrapper do
Gradle, etc.) são gerados automaticamente pela CLI do Flutter e não estão
versionados aqui para evitar arquivos binários/gerados desatualizados.

## Passo a passo

1. Com o Flutter SDK instalado, rode na raiz de `marketplace_app/`:

   ```bash
   flutter create --org com.appname --project-name appname --platforms=android,ios .
   ```

   Isso gera `android/` e `ios/` completos (incluindo o que falta: ícones,
   storyboards, `Runner.xcodeproj`, Gradle wrapper) **sem sobrescrever**
   `lib/`, `pubspec.yaml` nem os arquivos já customizados listados abaixo
   (o comando pula arquivos que já existem e são diferentes do template
   padrão — confira o diff antes de commitar).

2. Confirme que os arquivos abaixo (já incluídos neste repo) continuam
   como estão — eles têm as customizações do APPNAME:
   - `android/app/src/main/AndroidManifest.xml` (permissões + canal FCM)
   - `android/app/build.gradle` (applicationId, minSdk 23, plugin do Google Services)
   - `android/build.gradle` / `android/settings.gradle` (plugin `google-services`)
   - `android/app/src/main/kotlin/com/appname/app/MainActivity.kt`
   - `ios/Runner/Info.plist` (permissões de localização/câmera/galeria)
   - `ios/Runner/AppDelegate.swift` (inicialização do Firebase)
   - `ios/Podfile` (plataforma mínima 13.0)

3. Rode `flutterfire configure` (ver `docs/FIREBASE_SETUP.md`) para gerar
   `lib/firebase_options.dart` de verdade e baixar `google-services.json`
   (Android, em `android/app/`) e `GoogleService-Info.plist` (iOS, em
   `ios/Runner/`).

4. Troque o placeholder `APPNAME`/`appname`/`com.appname.app` por todo o
   projeto (código Dart, `android/app/build.gradle`, pacotes Kotlin,
   `Info.plist`, bundle id no Xcode) quando o nome final do app for
   definido.
