# VEICAN — Preparar OTA (atualização no campo) — v7

O v7 já deixa o aparelho **pronto pra OTA** (atualizar sem fio depois). O serviço
de OTA em si (baixar o binário por BLE/Wi-Fi) vem numa etapa futura — mas a
**estrutura tem que estar gravada AGORA**, antes de mandar as unidades pra rua.

## Por que agora e não depois

OTA precisa de **duas partições de app** (app0/app1). Um aparelho gravado com a
partição antiga (um app só) **não consegue receber OTA** — ele precisaria de uma
gravação física por USB pra virar OTA-capaz. Ou seja: se as 200 unidades saírem
sem isto, perde-se justamente a capacidade de consertar no campo. Por isso entra
no v7.

## O que já está no v7

- `partitions.csv` (na pasta do sketch, ao lado do `.ino`) com app0/app1 + área
  de dados (`spiffs`) pra flash interna.
- `FIRMWARE_VERSION "7.0.0"` — aparece na tela **Sistema** (canto superior
  direito) e no banner do Serial no boot. É por essa string que o OTA vai
  comparar versões antes de atualizar.

## Como gravar (uma vez, por USB)

1. Confirme que o `partitions.csv` está **na mesma pasta do `.ino`** (o core
   ESP32 do Arduino usa ele automaticamente).
2. Em **Tools** no Arduino IDE:
   - **Board:** ESP32 Wrover Module (ou "ESP32 Dev Module")
   - **Flash Size:** 8MB (64Mb)
   - **Partition Scheme:** deixe em qualquer opção — o `partitions.csv` da pasta
     tem prioridade. (Se sua versão do core ignorar o arquivo, escolha
     *"Custom"* e ele passa a usar o `partitions.csv`.)
3. Grave normalmente por USB.

> A partição `nvs` fica no mesmo lugar do padrão (0x9000), então **odômetro,
> calibrações e preferências já salvas são preservados**. A EEPROM externa
> (I2C) não é tocada.

## Verificar

- No boot, o Serial mostra `==== VEICAN firmware v7.0.0 ====`.
- Na tela **Sistema**, canto superior direito: `VEICAN v7.0.0`.

## Espaço

- **app0 e app1:** ~3,2 MB cada (sobra bastante; o firmware atual é bem menor).
- **spiffs (dados na flash):** 1,5 MB — guarda o histórico de eventos e as
  amostras de bateria do v7 (bloco 3 em diante).

## Quando o OTA "de verdade" chegar

Com essa base pronta, o serviço de atualização só precisa: receber o `.bin` novo,
gravar no slot ocioso (`esp_ota_*` / `Update.h`), marcar como boot e reiniciar. Se
o novo não subir direito, o ESP32 volta sozinho pro slot anterior (rollback). Sem
recall, sem tirar o aparelho do carro.
