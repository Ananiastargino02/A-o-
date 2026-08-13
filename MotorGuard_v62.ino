// ============================================================
//  MOTOR GUARD v6.0 - Painel cockpit
//  - Velocidade CENTRALIZADA com barra que sobe, faz uma curva
//    leve no topo e segue reta (nao e arco, e curva suave).
//  - RPM como barra digital com marcas + redline.
//  - Embaixo: BATERIA, ALTERNADOR, TEMPERATURA, COMBUSTIVEL.
//  - Tudo com dado REAL (os mesmos da taskCAN). Pinos/CAN/EEPROM/
//    RTC/DTC/sleep/tarefas: IDENTICOS ao v5.2.
//
//  CORRECOES NESTA REVISAO:
//  1. Calibração ADC: Ajuste fino do divisor (39k/10k) e voltcal
//  2. Navegação: Modo "visualização" (apenas passar páginas) vs "edição" (dentro da página)
//  3. Página Diagnóstico: Agora consegue navegar para próxima página
//  4. Página Manutenção: Entra apenas com MENU; navega com ANT/PRX; reset com MENU longpress
//  5. Alertas: Apenas mostra se item REALMENTE vencido (>= 100%)
//  6. Hodômetro: Conta APENAS quando velocidade > 0 (não baseado em RPM)
//  7. Fundo: Padrão visual moderno em vez de preto puro
//
//  CORRECOES v6.3 (esta revisao):
//  A. Manutencao nao mostra mais "VENC." falso depois do ZERAR TUDO
//     (protege underflow quando km_atual < km_ultima).
//  B. Temperatura nao mostra mais -1C em leitura falha (sentinela de
//     erro do lerPID_int passou de -1 para -1000, fora da faixa valida).
//  C. Alerta de SOBRECARGA do alternador: passa a disparar com tensao
//     ACIMA de 14.5V (era 15.0V) sustentada por mais de 3s (era 4s).
//  D. CAN nao "para de ler" no carro: com o motor ligado, falha de
//     leitura e tratada como congestionamento do barramento e a ultima
//     leitura e mantida (so zera RPM/vel quando a tensao confirma que o
//     alternador parou). Tambem 1 retry rapido no RPM.
//  E. Ajuste de data valida o dia do mes (com ano bissexto): nao deixa
//     mais escolher 31/04, 29/02 em ano nao bissexto, etc. Ao mudar o
//     mes/ano o dia e reajustado automaticamente.
//
//  ATENCAO: aparelho consome bateria do carro mesmo desligado!
// ============================================================

#define LGFX_USE_V1
#include <LovyanGFX.hpp>
#include <lvgl.h>
#include <SPI.h>
#include <Wire.h>
#include <RTClib.h>
#include "driver/twai.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/semphr.h"
#include "esp_sleep.h"
#include "esp_system.h"
#include "driver/rtc_io.h"
#include "rom/rtc.h"
// BLE via NimBLE-Arduino (h2zero): ~30-50 KB de RAM a menos que o Bluedroid.
// O Bluedroid nao cabia (so ~90 KB livres -> crash LoadProhibited no boot).
#include <NimBLEDevice.h>
#include <Preferences.h>   // NVS interna do ESP32 (historico de velocidade)
#include <LittleFS.h>      // flash interna (v7): historico de eventos + tendencia de bateria

// Declaracoes antecipadas de structs usadas em assinaturas de funcao. O Arduino
// gera os prototipos logo apos os #include (antes da definicao real), entao sem
// isto da "'OdoSlot' has not been declared" ao compilar.
struct OdoSlot;
struct DtcInfo;   // banco de DTC (infoDTC devolve const DtcInfo*)
struct FsHdr;     // header dos arquivos LittleFS (fsSaveAtomic/fsLoadValid)
struct Evento;    // historico de eventos (evtGet recebe Evento&)
void evtRegistrar(uint8_t tipo, int16_t v, const char* cod);

// (fontes agora sao do LVGL: montserrat 14/28/40)

// ============================================================
//  Pinos
// ============================================================
#define TFT_CS     5
#define TFT_DC     2
#define TFT_RST    4
#define TFT_PWR    25    // REV3: liga a alimentacao do display (MOSFET). ATIVO BAIXO = liga
#define CAN_TX_PIN GPIO_NUM_26
#define CAN_RX_PIN GPIO_NUM_27
#define VW_CLUSTER_REQ 0x714
#define VW_DID_FUEL    0x2206
#define VW_DID_RANGE   0x2297
#define TANQUE_VW_L    60
#define BTN_ANT    13
#define BTN_MENU   14
#define BTN_PRX    19
#define BTN_ENTER  32    // REV3: 4o botao (OK/confirmar)
#define DEBOUNCE_MS 50

// ===== REV3: pinos reservados p/ K-line (ISO 9141/KWP) e RTC INT =====
// (o transceiver e o hardware ja existem na placa; o protocolo K-line no
//  firmware ainda sera implementado — por enquanto so as definicoes.)
#define K_TX_PIN   33    // L9637D TX  (UART p/ K-line)
#define K_RX_PIN   39    // L9637D RX  (SENSOR_VN, input-only)
#define L_RX_PIN   34    // L-line RX  (input-only)
#define RTC_INT_PIN 35   // DS3231 INT/SQW (input-only)

// ===== ADC tensao da bateria (independente do CAN) =====
#define PIN_VBAT    36                               // SENSOR_VP / ADC1_CH0
#define VBAT_RATIO  ((39000.0 + 10000.0) / 10000.0)  // divisor 39k/10k -> 4.9

// ============================================================
//  MODO COMERCIAL (#16 da revisao de seguranca)
//  0 = desenvolvimento: TODOS os comandos de engenharia disponiveis (use agora).
//  1 = fabrica/produto: os comandos que TRANSMITEM no CAN ou fazem varredura
//      (SCAN, SWEEP, SWEEP22, M22, GMLIVE, CANDUMP, FUELWATCH, KLINE, DTC...)
//      ficam de FORA da compilacao. Mude para 1 SO ao fechar a versao de venda.
//  Enquanto estiver 0, nada muda no comportamento atual.
// ============================================================
#define MODO_COMERCIAL 0

// ============================================================
//  Versao do firmware (v7) - aparece na tela Sistema e no serial.
//  Usada tambem pelo OTA (comparar versao antes de atualizar no campo).
// ============================================================
#define FIRMWARE_VERSION "7.1.0"   // 7.1: analise de discrepancia de abastecimento
#define FIRMWARE_NOME    "VEICAN"

// ============================================================
//  EEPROM Layout
// ============================================================
#define EEPROM_ADDR      0x57
#define HEADER_SIZE      16
#define RECORD_SIZE      16
#define MAX_RECORDS      176   // era 180; liberou 64 bytes p/ config + hodometro duplo
#define LOGS_BASE        HEADER_SIZE
#define LOGS_END         (LOGS_BASE + MAX_RECORDS*RECORD_SIZE)   // = 2832
#define CONFIG_ADDR      2832  // calibracoes persistentes (voltcal, km_cal)
#define ODO_SLOT_A       2848  // hodometro slot A (gravacao alternada anti-corrupcao)
#define ODO_SLOT_B       2872  // hodometro slot B
#define HODOMETRO_ADDR   2896  // LEGADO: so leitura p/ migrar dados antigos
#define HODOMETRO_SIZE   16
#define MANUTENCAO_ADDR  2912
#define MANUTENCAO_SIZE  320       // 10 itens x 32 (era 160 p/ 5). DEBUG_LOG desceu p/ caber.
#define ITEM_SIZE        32
#define DEBUG_LOG_ADDR   3232      // era 3072; +160 p/ os 5 itens novos de manutencao
#define DEBUG_LOG_SIZE   864       // era 1024; 3232+864 = 4096 (fim da EEPROM 4KB)
#define DEBUG_HEADER_SIZE 16
#define DEBUG_RECORD_SIZE 32
#define MAX_DEBUG_RECORDS ((DEBUG_LOG_SIZE - DEBUG_HEADER_SIZE) / DEBUG_RECORD_SIZE)

// ============================================================
//  Sleep
// ============================================================
#define RPM_LIMIAR_SLEEP   200
#define TEMPO_PRA_SLEEP_MS (2 * 60 * 1000)
#define WAKE_INTERVAL_S    60
// ===== STANDBY =====
#define TENSAO_WAKE          13.0   // V: acima disso = alternador carregando (motor ligado)
#define TEMPO_STANDBY_MS     40000UL // tensao baixa por 40s -> entra em standby
#define CONFIRMA_CAN_MS      3000   // ao acordar, espera atividade CAN por ate 3s

// ============================================================
//  Manutencao
// ============================================================
#define NUM_ITENS_MANUT  10
#define IDX_OLEO_MOTOR   0
#define IDX_FILTRO_AR    1
#define IDX_VELA         2
#define IDX_OLEO_CAMBIO  3
#define IDX_CORREIA      4
#define IDX_PNEU         5
#define IDX_FILTRO_COMB  6
#define IDX_BOMBA_AGUA   7
#define IDX_PASTILHA     8
#define IDX_OLEO_FREIO   9
#define VELA_NORMAL_KM   40000
#define VELA_IRIDIO_KM   60000
#define LONGPRESS_MS     4000

// ============================================================
//  Navegacao (NOVO: modo visualizacao vs edicao)
// ============================================================
#define NAV_MODO_VISUALIZACAO 0
#define NAV_MODO_EDICAO       1

// ============================================================
//  Globais
// ============================================================
RTC_DS3231 rtc;
bool rtc_ok = false;            // RTC presente (definido uma vez no setup)
bool hora_nao_ajustada = false; // RTC perdeu energia: hora precisa ser acertada pelo usuario

float voltcal = 1.0;   // trim fino da leitura ADC (comando VOLTCAL — agora persiste na EEPROM)
// calibracao de hodometro por carro (comando KMCAL <km_real> <km_mostrado> — persiste na EEPROM).
// Padrao de fabrica 1.0 (velocidade OBD crua). Ex: Tiguan calibrado deu 1.0833 (52/48).
float km_cal = 1.0;

struct DadosCarro {
  int rpm, velocidade, temp_motor, tps, ped_abs;
  int combust, carga, carga_abs, temp_adm;
  int warmups, dist_dtc;
  float tensao;
};

DadosCarro dados_publicos;
SemaphoreHandle_t mutex_dados, mutex_hora, mutex_hodometro, mutex_manut, mutex_debug, mutex_i2c;
SemaphoreHandle_t mutex_fs = NULL;   // v7: protege gravacoes na flash (LittleFS) de 2 nucleos

// ============================================================
//  DEBUG TRACE via Serial (para diagnosticar o reboot "so andando")
//  Ligue em 1 para rastrear no Serial; deixe 0 na versao de venda.
// ============================================================
#define DEBUG_TRACE 1

// "migalhas": cada tarefa escreve aqui em que ponto esta. Quando um nucleo
// congela, o Serial para; a ULTIMA migalha impressa antes do buraco = onde travou.
volatile const char* g_stage_tela = "boot";   // nucleo 1 (tela/loop)
volatile const char* g_stage_can  = "boot";   // nucleo 0 (CAN)
volatile const char* g_stage_btn  = "boot";   // nucleo 1 (botoes) <<< o suspeito do reboot
#if DEBUG_TRACE
  #define STAGE_TELA(s) (g_stage_tela = (s))
  #define STAGE_CAN(s)  (g_stage_can  = (s))
  #define STAGE_BTN(s)  (g_stage_btn  = (s))
  // Cronometra um bloco de gravacao (flash/EEPROM). Se travar, o dur sai gigante.
  #define TRACE_DUR(nome, bloco) do { uint32_t _t0 = millis(); bloco; uint32_t _d = millis() - _t0; \
        if (_d >= 8) Serial.printf("[FLASH] %s = %lums\n", nome, _d); } while (0)
#else
  #define STAGE_TELA(s)
  #define STAGE_CAN(s)
  #define STAGE_BTN(s)
  #define TRACE_DUR(nome, bloco) do { bloco; } while (0)
#endif

bool pid_suportado[256] = {false};
volatile uint32_t tx_ok = 0, rx_ok = 0, timeouts = 0;
volatile uint8_t hora_h = 0, hora_m = 0, hora_s = 0;
volatile uint8_t data_dia = 1, data_mes = 1;
volatile uint16_t data_ano = 2026;
volatile uint32_t rtc_unix_cache = 0;   // unixtime em cache (taskRTC) -> tela nao le I2C

volatile uint16_t log_head = 0;
volatile uint16_t log_count = 0;
volatile uint32_t log_total = 0;

volatile uint8_t pagina_atual = 0;
volatile uint8_t pagina_anterior = 255;
volatile bool entrou_pagina = false;  // true no 1o frame apos trocar de pagina (forca redesenho)
const uint8_t TOTAL_PAGINAS = 8;  // 0 cockpit,1 combustivel,2 diag,3 sistema,4 manut,5 ajuste,6 temas,7 historico

// ===== NOVO: Estados da página de ajuste de hora/data =====
#define AJUSTE_ESTADO_MENU    0
#define AJUSTE_ESTADO_DIA     1
#define AJUSTE_ESTADO_MES     2
#define AJUSTE_ESTADO_ANO     3
#define AJUSTE_ESTADO_HORA    4
#define AJUSTE_ESTADO_MIN     5
#define AJUSTE_ESTADO_SEG     6
#define AJUSTE_ESTADO_SALVAR  7

volatile uint8_t ajuste_estado = AJUSTE_ESTADO_MENU;
volatile uint8_t ajuste_dia = 1, ajuste_mes = 1, ajuste_ano = 26;  // ajuste_ano = ano - 2000 (cabe em uint8_t)
volatile uint8_t ajuste_hora = 0, ajuste_min = 0, ajuste_seg = 0;

// NOVO: modo de navegacao (visualizacao vs edicao)
volatile uint8_t nav_modo = NAV_MODO_VISUALIZACAO;

// NOVO: flag para entrar em ajuste de hora/data
volatile bool entrar_ajuste_hora = false;

volatile uint32_t km_total_x100 = 0;
volatile uint32_t segundos_motor_total = 0;
volatile uint32_t km_acumulado_x100 = 0;
volatile bool sistema_confirma_zerar = false;       // janela ZERAR TUDO?
volatile uint8_t sistema_confirma_selecionado = 1;  // 0=SIM, 1=NAO

volatile uint32_t inicio_rpm_baixo = 0;
volatile bool contando_pra_sleep = false;
volatile bool forcar_sleep = false;

// ===== STANDBY =====
enum EstadoEnergia { OPERANDO, STANDBY };
volatile EstadoEnergia estadoAtual = OPERANDO;
volatile bool pedido_acordar = false;   // setado pela taskBotoes quando MENU e apertado em standby
volatile uint32_t hb_tela = 0, hb_botoes = 0;  // "batimentos" p/ watchdog de software
// Marcadores que SOBREVIVEM ao reboot (RTC mem): guardam por que o watchdog
// reiniciou (qual tarefa travou), p/ ver no DEBUG depois — sem notebook no carro.
// RTC_NOINIT_ATTR (NAO zera no reset, ao contrario de RTC_DATA_ATTR com "= 0"
// que vai pra .rtc.bss e e zerado todo boot -> por isso o marcador nao aparecia).
RTC_NOINIT_ATTR uint32_t g_wdt_magic;   // == 0x5744 => marcador valido
RTC_NOINIT_ATTR uint32_t g_wdt_tela;
RTC_NOINIT_ATTR uint32_t g_wdt_btn;
uint32_t reboot_wdt_tela = 0, reboot_wdt_btn = 0;  // copia p/ gravar na EEPROM apos o I2C subir

volatile bool alerta_bateria_ativo = false;
volatile bool alerta_alternador_ativo = false;
// v7 - alertas PREDITIVOS (tendencia, nao so o instante)
volatile bool alerta_bateria_prev = false;   // bateria de repouso caindo ao longo dos dias
volatile int  bateria_semanas_est = 0;       // estimativa de semanas ate nao dar partida (0=sem estimativa)
volatile bool g_primeiro_uso = false;        // v7 - primeiro boot -> mostra onboarding guiado
// H7 - contadores de diagnostico de campo (persistem na NVS namespace "stats")
uint32_t g_boot_count = 0, g_brownout_count = 0, g_wdt_count = 0, g_panic_count = 0;
volatile uint32_t g_busoff_count = 0;        // recuperacoes de bus-off (RAM, zera no boot)

volatile uint8_t item_manut_selecionado = 0;
volatile bool vela_iridio = false;

// ===== Diagnostico DTCs =====
#define DIAG_ESTADO_MENU       0
#define DIAG_ESTADO_LENDO      1
#define DIAG_ESTADO_RESULTADO  2
#define DIAG_ESTADO_CONFIRMAR  3
#define DIAG_ESTADO_APAGANDO   4
#define DIAG_ESTADO_APAGADO_OK 5
#define MAX_DTCS 12

volatile uint8_t diag_estado = DIAG_ESTADO_MENU;
volatile uint8_t diag_menu_selecionado = 0;
volatile uint8_t diag_confirma_selecionado = 1;
volatile uint8_t diag_num_dtcs = 0;
volatile uint32_t diag_ultima_leitura = 0;

// confirmacao de reset de manutencao (janela SIM/NAO)
volatile bool manut_confirma_reset = false;
volatile uint8_t manut_confirma_selecionado = 1;  // 0=SIM, 1=NAO (padrao NAO)
char diag_dtcs[MAX_DTCS][6];
volatile bool diag_solicitar_leitura = false;
volatile bool diag_solicitar_apagar = false;

volatile bool     probe_pedir_fuel = false;
volatile bool     probe_pedir_m22  = false;
volatile int      probe_pid_pedido = -1;   // comando "PID xx": sonda 1 PID e loga cru
volatile bool     probe_temp_scan  = false; // comando "TEMPSCAN": testa PIDs de temperatura
volatile bool     probe_candump    = false; // comando "CANDUMP": lista todos os frames do barramento
volatile bool     probe_fuelwatch  = false; // comando "FUELWATCH": mostra candidatos de combustivel ao vivo
volatile bool     probe_fuelfind   = false; // comando "FUELFIND <pct>": acha o byte do combustivel pelo nivel atual
volatile int      fuelfind_pct     = 50;    // nivel do tanque informado (%) p/ o FUELFIND casar
volatile bool     probe_klraw      = false; // comando "KLRAW": bytes crus da temperatura via K-line
volatile uint16_t probe_did_ini    = 0;
volatile uint16_t probe_did_fim    = 0;
volatile uint32_t probe_reqid      = 0x7E0;
volatile uint8_t  fuel_metodo = 0;
volatile bool     fuel_2f_declarado = false;   // o carro declara o PID 0x2F no bitmask? (p/ desambiguar 0xFF cheio vs indisponivel)
// Hyundai/Kia: combustivel num frame de broadcast proprio (Azera: ID 0x329 byte1, escala /255).
// Ajustavel ao vivo com o comando HYFUEL <id_hex> <byte> <max> p/ outros modelos.
uint32_t hy_fuel_id   = 0x329;
uint8_t  hy_fuel_byte = 1;
uint16_t hy_fuel_max  = 200;   // escala p/ CASAR com o ponteiro do carro (180 -> 90%, = 8/9). Ajuste com HYFUEL.
bool     fuel_custom  = false; // usuario configurou HYFUEL manualmente (tenta esse antes da tabela)

// TABELA UNIVERSAL de combustivel por broadcast (carros ja descobertos). O
// aparelho tenta cada um automaticamente -> plug-and-play, sem comando manual.
// Para adicionar um carro novo: descubra com CANDUMP e inclua aqui (ou use HYFUEL
// uma vez, que fica salvo).
struct FuelBroadcast { uint32_t id; uint8_t byte; uint16_t max; const char* nome; };
static const FuelBroadcast FUEL_TABLE[] = {
  {0x2C4, 3, 100, "Toyota Corolla"}, // Corolla 2013: frame 0x2C4 byte 3 = nivel em % (0-100)
  {0x329, 5, 100, "Hyundai/Azera"},  // Azera 2010: frame 0x329 byte 5 = nivel em % (0-100).
                                     // (byte 1 lia alto demais na metade pra baixo -> corrigido)
  // NAO por o Civic aqui: o combustivel dele esta no B-CAN, nao no OBD (F-CAN). Alem
  // disso o 0x465 existe TAMBEM no Azera (outra finalidade) e sequestrava a deteccao.
};
static const int FUEL_TABLE_N = sizeof(FUEL_TABLE) / sizeof(FUEL_TABLE[0]);


// ===== ANALISE DE ABASTECIMENTO (v8) =====
// Objetivo: detectar apenas discrepancias GRANDES. Nao e instrumento metrologico.
// O volume estimado vem da variacao do nivel do tanque; pequenos erros sao ignorados.
#define FUEL_ALERTA_PCT       5.0f   // alerta a partir de 5% de discrepancia
#define FUEL_ALERTA_L_MIN     1.0f   // e pelo menos 1,0 L de diferenca
#define FUEL_SUBIDA_MIN_PCT   5      // subida minima para considerar abastecimento
#define FUEL_FATOR_MIN        0.6f   // limites fisicos do fator de calibracao (erro de boia)
#define FUEL_FATOR_MAX        1.4f
#define FUEL_LEARN_A          0.25f  // peso do novo abastecimento no fator (media movel)
#define FUEL_MIN_OFF_MS       90000UL // motor tem que ficar DESLIGADO >=90s p/ contar abastecimento
                                      // (parada rapida em ladeira nao gera abastecimento-fantasma)
volatile bool  fuel_abast_pendente = false;
volatile bool  alerta_combustivel_discrep = false;
volatile int   fuel_pct_antes = -1, fuel_pct_depois = -1;
volatile float fuel_l_estimado = 0.0f, fuel_l_informado = 0.0f;
volatile float fuel_dif_l = 0.0f, fuel_dif_pct = 0.0f;
volatile uint8_t fuel_aprendizado = 0;       // 0..5 abastecimentos validos
float fuel_tanque_l = 0.0f;                  // capacidade cadastrada
char  fuel_veiculo[32] = "Veiculo";          // texto simples mostrado ao usuario
float fuel_fator = 1.0f;                     // CALIBRACAO: litros reais / estimativa crua (so via fill confiavel)
float fuel_l_raw = 0.0f;                     // estimativa CRUA (tanque*delta), antes do fator
bool  fuel_calibrado = false;                // ja calibrou com um abastecimento CONFIAVEL?
bool  fuel_gnv = false;                      // carro com GNV: a boia "sobe" sozinha (soft) -> nao auto-detecta
volatile bool fuel_aguardando_mov = false;   // pos-abastecimento: espera o carro andar ~500m p/ a boia assentar
uint32_t fuel_km_ini_x100 = 0;               // km no momento do abastecimento (p/ medir os 500m)
static int fuel_pct_estavel = -1;
static int fuel_pct_pre_parada = -1;
static bool fuel_motor_estava_ligado = false;
static uint32_t fuel_estavel_desde = 0;

static void fuelAnaliseSalvar() {
  Preferences fp; fp.begin("fuelana", false);
  fp.putFloat("tank", fuel_tanque_l);
  fp.putString("car", fuel_veiculo);
  fp.putUChar("learn", fuel_aprendizado);
  fp.putFloat("est", fuel_l_estimado);
  fp.putFloat("inf", fuel_l_informado);
  fp.putFloat("difl", fuel_dif_l);
  fp.putFloat("difp", fuel_dif_pct);
  fp.putBool("pend", fuel_abast_pendente);
  fp.putBool("alert", alerta_combustivel_discrep);
  fp.putFloat("fator", fuel_fator);
  fp.putFloat("raw", fuel_l_raw);
  fp.putBool("calib", fuel_calibrado);
  fp.putBool("gnv", fuel_gnv);
  fp.end();
}
static void fuelAnaliseCarregar() {
  Preferences fp; fp.begin("fuelana", true);
  fuel_tanque_l = fp.getFloat("tank", 0.0f);
  String car = fp.getString("car", "Veiculo");
  strncpy(fuel_veiculo, car.c_str(), sizeof(fuel_veiculo)-1); fuel_veiculo[sizeof(fuel_veiculo)-1]=0;
  fuel_aprendizado = fp.getUChar("learn", 0); if (fuel_aprendizado > 5) fuel_aprendizado = 5;
  fuel_l_estimado = fp.getFloat("est", 0.0f); fuel_l_informado = fp.getFloat("inf", 0.0f);
  fuel_dif_l = fp.getFloat("difl", 0.0f); fuel_dif_pct = fp.getFloat("difp", 0.0f);
  fuel_abast_pendente = fp.getBool("pend", false);
  alerta_combustivel_discrep = fp.getBool("alert", false);
  fuel_fator = fp.getFloat("fator", 1.0f);
  if (fuel_fator < FUEL_FATOR_MIN || fuel_fator > FUEL_FATOR_MAX) fuel_fator = 1.0f;
  fuel_l_raw = fp.getFloat("raw", 0.0f);
  fuel_calibrado = fp.getBool("calib", false);
  fuel_gnv = fp.getBool("gnv", false);
  fp.end();
}
static uint8_t fuelConfiancaPct() {
  if (fuel_tanque_l < 10.0f || fuel_metodo == 3 || fuel_metodo == 0) return 0;
  if (!fuel_calibrado) return 50;                 // ja funciona (5%/1L), mas sem calibracao fina
  int c = 70 + fuel_aprendizado * 6; if (c > 100) c = 100;
  return (uint8_t)c;
}

// Abastecimento CONFIAVEL (posto que voce confia): calibra a boia/tanque.
// O golpe do posto e ~10% SEMPRE — por isso NUNCA calibramos com um fill normal
// (isso ensinaria o aparelho a achar a fraude "normal" e ele pararia de alertar).
// So um fill que VOCE marca como honesto ajusta o fator.
static void fuelCalibrar(float litros_reais) {
  if (fuel_l_raw <= 0.1f || litros_reais <= 0.1f) return;
  float ratio = litros_reais / fuel_l_raw;
  if (ratio < FUEL_FATOR_MIN) ratio = FUEL_FATOR_MIN;
  if (ratio > FUEL_FATOR_MAX) ratio = FUEL_FATOR_MAX;
  // 1a calibracao aplica direto; as seguintes afinam por media movel
  fuel_fator = fuel_calibrado ? (fuel_fator * (1.0f - FUEL_LEARN_A) + ratio * FUEL_LEARN_A) : ratio;
  if (fuel_fator < FUEL_FATOR_MIN) fuel_fator = FUEL_FATOR_MIN;
  if (fuel_fator > FUEL_FATOR_MAX) fuel_fator = FUEL_FATOR_MAX;
  fuel_calibrado = true;
  if (fuel_aprendizado < 5) fuel_aprendizado++;
  fuel_l_informado = litros_reais;
  fuel_l_estimado = fuel_l_raw * fuel_fator;
  fuel_dif_l = 0; fuel_dif_pct = 0; alerta_combustivel_discrep = false;
  fuel_abast_pendente = false;
  fuelAnaliseSalvar();
}

// Abastecimento NORMAL (suspeito): so COMPARA, nunca calibra.
static void fuelInformarBomba(float litros) {
  if (!fuel_abast_pendente || fuel_l_raw <= 0.1f || litros <= 0.1f) return;
  fuel_l_informado = litros;
  float corrigido = fuel_l_raw * fuel_fator;   // fator=1.0 enquanto nao calibrou
  fuel_l_estimado = corrigido;
  fuel_dif_l = litros - corrigido;             // bomba - real. Positivo = bomba marcou a mais
  fuel_dif_pct = (litros > 0.1f) ? (fabsf(fuel_dif_l) * 100.0f / litros) : 0.0f;
  float absL = fabsf(fuel_dif_l);
  // Alerta desde a 1a abastecida:
  //  - sem calibracao fina: 5% E 1L (pega o golpe de ~10% com folga);
  //  - ja calibrado: aperta pra 500 ml (limitado pela resolucao da boia, ~1% do tanque).
  if (fuel_calibrado) alerta_combustivel_discrep = (absL >= 0.5f);
  else                alerta_combustivel_discrep = (fuel_dif_pct >= FUEL_ALERTA_PCT && absL >= FUEL_ALERTA_L_MIN);
  if (alerta_combustivel_discrep) evtRegistrar(6, (int16_t)lroundf(fuel_dif_pct * 10.0f), "FUEL");
  fuel_abast_pendente = false;
  fuelAnaliseSalvar();
}

// Chamada 1x/s. Aprende a estabilidade do sensor e detecta uma subida grande do nivel.
// A comparacao em litros so acontece depois que o app informa quanto a bomba marcou.
static void fuelAprenderEDetectar(const DadosCarro& d) {
  int pct = d.combust;
  if (pct < 0 || pct > 100 || fuel_tanque_l < 10.0f) return;
  if (fuel_gnv) return;   // GNV: a boia cai por software e "sobe" ao religar -> auto-deteccao daria falso
  uint32_t agora = millis();
  static int candidato = -1;
  static uint32_t religou_em = 0;
  static uint32_t desligou_ms = 0;    // quando o motor foi desligado (p/ exigir parada longa)
  if (candidato < 0 || abs(pct - candidato) > 1) { candidato = pct; fuel_estavel_desde = agora; }
  if (agora - fuel_estavel_desde >= 5000) fuel_pct_estavel = candidato;  // 5 s estavel
  bool ligado = d.rpm > 0;

  // Guarda o nivel estabilizado imediatamente antes de desligar para abastecer.
  if (fuel_motor_estava_ligado && !ligado && fuel_pct_estavel >= 0) {
    fuel_pct_pre_parada = fuel_pct_estavel;
    desligou_ms = agora;
    religou_em = 0;
  }
  // Ao religar, NAO compara imediatamente: espera o sensor/boia estabilizar.
  if (!fuel_motor_estava_ligado && ligado && fuel_pct_pre_parada >= 0) religou_em = agora;
  if (ligado && religou_em && agora - religou_em >= 8000 && fuel_pct_estavel >= 0) {
    int delta = fuel_pct_estavel - fuel_pct_pre_parada;
    // exige parada LONGA (>=90s): abastecer leva minutos; parada rapida em ladeira
    // (gasolina escorre e a boia "sobe") nao pode virar abastecimento-fantasma.
    bool parou_de_verdade = (desligou_ms && (religou_em - desligou_ms) >= FUEL_MIN_OFF_MS);
    if (delta >= FUEL_SUBIDA_MIN_PCT && parou_de_verdade) {
      fuel_pct_antes = fuel_pct_pre_parada; fuel_pct_depois = fuel_pct_estavel;
      fuel_l_raw = fuel_tanque_l * ((float)delta / 100.0f);   // estimativa crua
      fuel_l_estimado = fuel_l_raw * fuel_fator;              // ja mostra corrigida pela calibracao
      fuel_l_informado = 0; fuel_dif_l = 0; fuel_dif_pct = 0;
      fuel_abast_pendente = true; alerta_combustivel_discrep = false;
      // v7.1: estimativa acima e PROVISORIA; espera o carro andar ~500m p/ a boia
      // assentar (combustivel balança parado) e ai refina.
      fuel_aguardando_mov = true;
      if (xSemaphoreTake(mutex_hodometro, pdMS_TO_TICKS(20)) == pdTRUE) {
        fuel_km_ini_x100 = km_total_x100 + km_acumulado_x100;
        xSemaphoreGive(mutex_hodometro);
      }
      fuelAnaliseSalvar();
      Serial.printf("[Fuel] abastecimento detectado: %d%% -> %d%%, estimado %.2f L (refina em 500m)\n", fuel_pct_antes, fuel_pct_depois, fuel_l_estimado);
    }
    fuel_pct_pre_parada = -1; religou_em = 0;
  }

  // v7.1: depois de ~500m rodados, re-le o nivel JA ASSENTADO e ajusta a estimativa.
  if (fuel_aguardando_mov && fuel_pct_estavel >= 0) {
    uint32_t kmx = 0;
    if (xSemaphoreTake(mutex_hodometro, pdMS_TO_TICKS(20)) == pdTRUE) {
      kmx = km_total_x100 + km_acumulado_x100;
      xSemaphoreGive(mutex_hodometro);
    }
    if (kmx >= fuel_km_ini_x100 && (kmx - fuel_km_ini_x100) >= 50) {   // ~500m
      int depois = fuel_pct_estavel;
      if (depois > fuel_pct_antes) {
        fuel_pct_depois = depois;
        fuel_l_raw = fuel_tanque_l * ((float)(depois - fuel_pct_antes) / 100.0f);
        fuel_l_estimado = fuel_l_raw * fuel_fator;
        fuelAnaliseSalvar();
        Serial.printf("[Fuel] boia assentada apos 500m: %d%% -> refino %.2f L\n", depois, fuel_l_estimado);
      }
      fuel_aguardando_mov = false;
    }
  }
  fuel_motor_estava_ligado = ligado;
}
volatile uint16_t debug_log_head = 0;
volatile uint16_t debug_log_count = 0;
volatile uint32_t ultimo_heartbeat = 0;

// ============================================================
//  Estruturas
// ============================================================
struct LogRecord {
  uint32_t timestamp;
  uint8_t evento;
  uint16_t rpm;
  uint8_t velocidade;
  int8_t temp_motor;
  uint8_t tps;
  uint8_t ped_abs;
  uint8_t tensao_x10;
  uint8_t carga;
  uint8_t carga_abs;
  uint8_t combust;
  int8_t temp_adm;
  uint8_t crc;
} __attribute__((packed));

struct EepromHeader {
  char magic[4];
  uint8_t versao;
  uint16_t head;
  uint16_t count;
  uint32_t total;
  uint8_t reservado[3];
} __attribute__((packed));

struct EepromHodometro {
  char magic[4];
  uint32_t km_total_x100;
  uint32_t segundos_motor;
  uint32_t reservado;
} __attribute__((packed));

// Hodometro com gravacao alternada (2 slots + sequencia + CRC):
// se a energia cair no meio de uma gravacao, o outro slot continua integro.
struct OdoSlot {
  char magic[4];          // "ODO2"
  uint32_t km_total_x100;
  uint32_t segundos_motor;
  uint32_t seq;           // numero de sequencia: o maior seq valido vence
  uint8_t crc;            // soma dos 16 bytes anteriores
  uint8_t pad[7];
} __attribute__((packed)); // 24 bytes

struct EepromConfig {
  char magic[4];          // "CFG1"
  float voltcal;
  float km_cal;
  uint8_t crc;            // soma dos 12 bytes anteriores
  uint8_t pad[3];
} __attribute__((packed)); // 16 bytes

struct ItemManutencao {
  char magic[2];
  uint8_t tipo;
  uint8_t flags;
  uint32_t km_intervalo;
  uint32_t dias_intervalo;
  uint32_t km_ultima;
  uint32_t timestamp_ultima;
  uint8_t reservado[10];
} __attribute__((packed));

ItemManutencao itens_manut[NUM_ITENS_MANUT];

const char* NOMES_ITENS[] = {
  "Oleo Motor", "Filtro Ar", "Vela", "Oleo Cambio", "Correia",
  "Pneu", "Filtro Comb", "Bomba Agua", "Past. Freio", "Oleo Freio"
};

// ============================================================
//  ICONES 16x16
// ============================================================
const uint8_t ICONE_BATERIA[] PROGMEM = {
  0b00011000, 0b00011000, 0b01111111, 0b11111110,
  0b01000000, 0b00000010, 0b01000011, 0b00000010,
  0b01000011, 0b00011110, 0b01001111, 0b00011110,
  0b01001111, 0b00000010, 0b01000011, 0b00000010,
  0b01000011, 0b00011110, 0b01001111, 0b00011110,
  0b01001111, 0b00000010, 0b01000011, 0b00000010,
  0b01000011, 0b00011110, 0b01000000, 0b00000010,
  0b01111111, 0b11111110, 0b00000000, 0b00000000
};
const uint8_t ICONE_RAIO[] PROGMEM = {
  0b00000000, 0b11100000, 0b00000001, 0b11000000,
  0b00000011, 0b10000000, 0b00000111, 0b00000000,
  0b00001110, 0b00000000, 0b00011100, 0b00000000,
  0b00111111, 0b11110000, 0b01111111, 0b11100000,
  0b00000011, 0b11000000, 0b00000111, 0b10000000,
  0b00001111, 0b00000000, 0b00011110, 0b00000000,
  0b00111100, 0b00000000, 0b01111000, 0b00000000,
  0b11110000, 0b00000000, 0b00000000, 0b00000000
};
const uint8_t ICONE_TERMO[] PROGMEM = {
  0b00000111, 0b00000000, 0b00001111, 0b10000000,
  0b00001001, 0b10000000, 0b00001111, 0b10000000,
  0b00001001, 0b10000000, 0b00001111, 0b10000000,
  0b00001001, 0b10000000, 0b00001111, 0b10000000,
  0b00001001, 0b10000000, 0b00001111, 0b10000000,
  0b00011111, 0b11000000, 0b00111111, 0b11100000,
  0b00111111, 0b11100000, 0b00111111, 0b11100000,
  0b00011111, 0b11000000, 0b00001111, 0b10000000
};
const uint8_t ICONE_VEL[] PROGMEM = {
  0b00000000, 0b00000000, 0b00000111, 0b11100000,
  0b00011111, 0b11111000, 0b00111000, 0b00011100,
  0b01110000, 0b00001110, 0b01100000, 0b00000110,
  0b11000000, 0b00000011, 0b11000111, 0b00000011,
  0b11000111, 0b00000011, 0b11000111, 0b00000011,
  0b11000111, 0b11111011, 0b11000000, 0b00000011,
  0b01100000, 0b00000110, 0b01110000, 0b00001110,
  0b00111111, 0b11111100, 0b00011111, 0b11111000
};
const uint8_t ICONE_OLEO[] PROGMEM = {
  0b00000001, 0b10000000, 0b00000001, 0b10000000,
  0b00000011, 0b11000000, 0b00000011, 0b11000000,
  0b00000111, 0b11100000, 0b00000111, 0b11100000,
  0b00001111, 0b11110000, 0b00001111, 0b11110000,
  0b00011111, 0b11111000, 0b00011111, 0b11111000,
  0b00111111, 0b11111100, 0b00111111, 0b11111100,
  0b00111111, 0b11111100, 0b00011111, 0b11111000,
  0b00001111, 0b11110000, 0b00000111, 0b11100000
};
const uint8_t ICONE_FILTRO[] PROGMEM = {
  0b00111111, 0b11111100, 0b01000000, 0b00000010,
  0b10111111, 0b11111101, 0b10100000, 0b00000101,
  0b10101111, 0b11110101, 0b10101000, 0b00010101,
  0b10101011, 0b11010101, 0b10101010, 0b01010101,
  0b10101010, 0b01010101, 0b10101011, 0b11010101,
  0b10101000, 0b00010101, 0b10101111, 0b11110101,
  0b10100000, 0b00000101, 0b10111111, 0b11111101,
  0b01000000, 0b00000010, 0b00111111, 0b11111100
};
const uint8_t ICONE_VELA[] PROGMEM = {
  0b00000111, 0b11100000, 0b00000111, 0b11100000,
  0b00000110, 0b01100000, 0b00000111, 0b11100000,
  0b00000110, 0b01100000, 0b00000111, 0b11100000,
  0b00000100, 0b00100000, 0b00001111, 0b11110000,
  0b00001111, 0b11110000, 0b00011111, 0b11111000,
  0b00011111, 0b11111000, 0b00001111, 0b11110000,
  0b00000111, 0b11100000, 0b00000011, 0b11000000,
  0b00000001, 0b10000000, 0b00000001, 0b10000000
};
const uint8_t ICONE_CORREIA[] PROGMEM = {
  0b00000000, 0b00000000, 0b00000111, 0b11100000,
  0b00011111, 0b11111000, 0b00111100, 0b00111100,
  0b01110000, 0b00001110, 0b01100000, 0b00000110,
  0b11000111, 0b11100011, 0b11000111, 0b11100011,
  0b11000111, 0b11100011, 0b11000111, 0b11100011,
  0b01100000, 0b00000110, 0b01110000, 0b00001110,
  0b00111100, 0b00111100, 0b00011111, 0b11111000,
  0b00000111, 0b11100000, 0b00000000, 0b00000000
};
const uint8_t ICONE_ALERTA[] PROGMEM = {
  0b00000001, 0b10000000, 0b00000011, 0b11000000,
  0b00000011, 0b11000000, 0b00000111, 0b11100000,
  0b00000111, 0b11100000, 0b00001110, 0b01110000,
  0b00001110, 0b01110000, 0b00011100, 0b00111000,
  0b00011100, 0b00111000, 0b00111000, 0b00011100,
  0b00111000, 0b00011100, 0b01110001, 0b10001110,
  0b01110001, 0b10001110, 0b11111111, 0b11111111,
  0b11111111, 0b11111111, 0b00000000, 0b00000000
};
// ===== icones 32x32 do painel (1bpp) =====
const uint8_t ICONE_OLEO32[] PROGMEM = {
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x06, 0x00, 0x00, 0x00,
  0x0F, 0x00, 0x00, 0x00,
  0x1F, 0x80, 0x00, 0x00,
  0x3F, 0xC0, 0x00, 0x00,
  0x1F, 0xE0, 0x00, 0x00,
  0x17, 0xF0, 0x00, 0x00,
  0x13, 0xF8, 0x00, 0x00,
  0x39, 0xFC, 0x00, 0x00,
  0x7C, 0xFE, 0x00, 0x00,
  0x7C, 0x7F, 0x00, 0x00,
  0x3C, 0x3F, 0xFF, 0x80,
  0x10, 0x1F, 0xFF, 0xC0,
  0x00, 0x3F, 0xFF, 0xE0,
  0x00, 0x3F, 0xFF, 0xE0,
  0x00, 0x3F, 0xFF, 0xE0,
  0x00, 0x3F, 0xFF, 0xE0,
  0x00, 0x3F, 0xFF, 0xE0,
  0x00, 0x1F, 0xFF, 0xC0,
  0x00, 0x0F, 0xFF, 0x80,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00
};

const uint8_t ICONE_FILTRO32[] PROGMEM = {
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x03, 0xFF, 0xFF, 0xC0,
  0x07, 0xFF, 0xFF, 0xE0,
  0x07, 0x4A, 0x5A, 0x60,
  0x07, 0x4A, 0x52, 0x60,
  0x07, 0x4A, 0x52, 0x60,
  0x07, 0x4A, 0x52, 0x60,
  0x07, 0x4A, 0x52, 0x60,
  0x07, 0x4A, 0x52, 0x60,
  0x07, 0x4A, 0x52, 0x60,
  0x07, 0x4A, 0x52, 0x60,
  0x07, 0x4A, 0x52, 0x60,
  0x07, 0x4A, 0x52, 0x60,
  0x07, 0xFF, 0xFF, 0xE0,
  0x03, 0xFF, 0xFF, 0xE0,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00
};

const uint8_t ICONE_VELA32[] PROGMEM = {
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x03, 0xC0, 0x00,
  0x00, 0x07, 0xE0, 0x00,
  0x00, 0x07, 0xE0, 0x00,
  0x00, 0x07, 0xE0, 0x00,
  0x00, 0x03, 0xE0, 0x00,
  0x00, 0x0F, 0xF0, 0x00,
  0x00, 0x0F, 0xF0, 0x00,
  0x00, 0x0F, 0xF0, 0x00,
  0x00, 0x0F, 0xF0, 0x00,
  0x00, 0x0F, 0xF0, 0x00,
  0x00, 0x07, 0xF0, 0x00,
  0x00, 0x07, 0xE0, 0x00,
  0x00, 0x07, 0xE0, 0x00,
  0x00, 0x1F, 0xF8, 0x00,
  0x00, 0x1F, 0xFC, 0x00,
  0x00, 0x3F, 0xFC, 0x00,
  0x00, 0x3F, 0xFC, 0x00,
  0x00, 0x3F, 0xFC, 0x00,
  0x00, 0x3F, 0xFC, 0x00,
  0x00, 0x1F, 0xFC, 0x00,
  0x00, 0x1F, 0xF8, 0x00,
  0x00, 0x0F, 0xF0, 0x00,
  0x00, 0x0F, 0xF0, 0x00,
  0x00, 0x0F, 0xF0, 0x00,
  0x00, 0x0F, 0xF0, 0x00,
  0x00, 0x0F, 0xF0, 0x00,
  0x00, 0x01, 0x80, 0x00,
  0x00, 0x07, 0x80, 0x00,
  0x00, 0x07, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00
};

const uint8_t ICONE_CAMBIO32[] PROGMEM = {
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x20, 0x00,
  0x00, 0x00, 0xE0, 0x00,
  0x00, 0x71, 0xF0, 0x00,
  0x00, 0x7F, 0xF8, 0x00,
  0x00, 0x7F, 0xFF, 0x00,
  0x00, 0xFF, 0xFF, 0xC0,
  0x00, 0xFF, 0xFF, 0xC0,
  0x03, 0xFF, 0xFF, 0xC0,
  0x0F, 0xFF, 0xFF, 0xC0,
  0x0F, 0xF8, 0x1F, 0xC0,
  0x07, 0xF0, 0x0F, 0xE0,
  0x07, 0xF0, 0x0F, 0xF0,
  0x03, 0xF0, 0x07, 0xF8,
  0x03, 0xF0, 0x07, 0xF8,
  0x07, 0xF0, 0x0F, 0xF0,
  0x07, 0xF0, 0x0F, 0xE0,
  0x0F, 0xF8, 0x1F, 0xC0,
  0x0F, 0xFE, 0x7F, 0xC0,
  0x03, 0xFF, 0xFF, 0xC0,
  0x00, 0xFF, 0xFF, 0xC0,
  0x00, 0xFF, 0xFF, 0xC0,
  0x00, 0x7F, 0xFF, 0x00,
  0x00, 0x7F, 0xF8, 0x00,
  0x00, 0x71, 0xF0, 0x00,
  0x00, 0x00, 0xE0, 0x00,
  0x00, 0x00, 0x20, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00
};

const uint8_t ICONE_CORREIA32[] PROGMEM = {
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x3F, 0xFC, 0x00,
  0x00, 0xFF, 0xFF, 0x80,
  0x03, 0xC0, 0x03, 0xC0,
  0x07, 0x00, 0x00, 0xE0,
  0x06, 0xF0, 0x0F, 0x70,
  0x0D, 0xF8, 0x1F, 0xB0,
  0x0D, 0x98, 0x19, 0xB0,
  0x0D, 0x98, 0x19, 0xB0,
  0x0D, 0xF8, 0x1F, 0xB0,
  0x0E, 0xF0, 0x0F, 0x70,
  0x07, 0x00, 0x00, 0xE0,
  0x03, 0xC0, 0x03, 0xC0,
  0x01, 0xFF, 0xFF, 0x80,
  0x00, 0x3F, 0xFC, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00
};

// embrulha como imagens do LVGL (alpha 1-bit, recoloriveis)
#define IMG_ICONE(nome, dados) \
  const lv_img_dsc_t nome = { { LV_IMG_CF_ALPHA_1BIT, 0, 0, 32, 32 }, 128, (dados) }

IMG_ICONE(IMG_OLEO,    ICONE_OLEO32);
IMG_ICONE(IMG_FILTRO,  ICONE_FILTRO32);
IMG_ICONE(IMG_VELA,    ICONE_VELA32);
IMG_ICONE(IMG_CAMBIO,  ICONE_CAMBIO32);
IMG_ICONE(IMG_CORREIA, ICONE_CORREIA32);

const lv_img_dsc_t* ICONES_MANUT[] = {
  &IMG_OLEO, &IMG_FILTRO, &IMG_VELA, &IMG_CAMBIO, &IMG_CORREIA,
  // itens novos reaproveitam icones (o texto do lado diz o que e):
  &IMG_CAMBIO,   // Pneu
  &IMG_FILTRO,   // Filtro Combustivel
  &IMG_OLEO,     // Bomba d'Agua
  &IMG_VELA,     // Pastilha de Freio
  &IMG_OLEO      // Oleo de Freio
};

// ============================================================
//  Banco de DTCs TRADUZIDO (v7) - descricao + causa provavel + gravidade
//  gravidade: 1 = leve (pode rodar, resolve sem pressa)
//             2 = oficina esta semana
//             3 = PARE / risco de quebrar o motor
//  Fica na flash (const) - ~150 codigos ocupam ~25 KB dos 8 MB do WROVER-E.
//  Foco: os codigos mais comuns da frota BR (VW, GM/Chevrolet, Fiat, Ford,
//  Hyundai, Toyota, Honda, Renault) + generico OBD-II.
// ============================================================
struct DtcInfo { const char* codigo; const char* descricao; const char* causa; uint8_t gravidade; };

const DtcInfo DTC_TABLE[] = {
  // ---- Mistura / combustivel (fuel trim) ----
  {"P0171","Mistura pobre (lado 1)","Entrada de ar falsa (mangueira/junta), bico sujo, sensor MAF sujo ou bomba fraca.",2},
  {"P0172","Mistura rica (lado 1)","Bico vazando, sensor de oxigenio (sonda) velho, pressao de combustivel alta.",2},
  {"P0174","Mistura pobre (lado 2)","Entrada de ar falsa, MAF sujo, pressao de combustivel baixa.",2},
  {"P0175","Mistura rica (lado 2)","Bico vazando, sonda velha, pressao de combustivel alta.",2},
  {"P0170","Ajuste de combustivel fora","Vazamento de ar, MAF ou sonda com problema.",2},
  {"P0173","Ajuste de combustivel fora (lado 2)","Vazamento de ar, MAF ou sonda com problema.",2},
  {"P0087","Pressao de combustivel baixa","Bomba fraca, filtro entupido, regulador de pressao.",2},
  {"P0089","Regulador de pressao com defeito","Regulador ou bomba de combustivel.",2},
  {"P018B","Sensor de pressao de combustivel","Sensor de pressao ou chicote.",2},
  // ---- Falha de ignicao (misfire) ----
  {"P0300","Falha de ignicao em varios cilindros","Velas/bobinas gastas, combustivel ruim, bico entupido. Trepida e gasta mais.",2},
  {"P0301","Falha de ignicao - cilindro 1","Vela/bobina/cabo do cil.1, bico do cil.1, compressao baixa.",2},
  {"P0302","Falha de ignicao - cilindro 2","Vela/bobina/cabo do cil.2, bico do cil.2, compressao baixa.",2},
  {"P0303","Falha de ignicao - cilindro 3","Vela/bobina/cabo do cil.3, bico do cil.3, compressao baixa.",2},
  {"P0304","Falha de ignicao - cilindro 4","Vela/bobina/cabo do cil.4, bico do cil.4, compressao baixa.",2},
  {"P0305","Falha de ignicao - cilindro 5","Vela/bobina/cabo do cil.5, bico do cil.5, compressao baixa.",2},
  {"P0306","Falha de ignicao - cilindro 6","Vela/bobina/cabo do cil.6, bico do cil.6, compressao baixa.",2},
  {"P0313","Falha de ignicao com pouco combustivel","Abasteca; se persistir, sistema de combustivel.",1},
  {"P0316","Falha de ignicao logo na partida","Velas/bobinas ou combustivel ruim.",2},
  // ---- Bobinas / injetores (circuito) ----
  {"P0351","Bobina de ignicao 1","Bobina, chicote ou conector do cil.1.",2},
  {"P0352","Bobina de ignicao 2","Bobina, chicote ou conector do cil.2.",2},
  {"P0353","Bobina de ignicao 3","Bobina, chicote ou conector do cil.3.",2},
  {"P0354","Bobina de ignicao 4","Bobina, chicote ou conector do cil.4.",2},
  {"P0201","Injetor - cilindro 1","Injetor, chicote ou conector do cil.1.",2},
  {"P0202","Injetor - cilindro 2","Injetor, chicote ou conector do cil.2.",2},
  {"P0203","Injetor - cilindro 3","Injetor, chicote ou conector do cil.3.",2},
  {"P0204","Injetor - cilindro 4","Injetor, chicote ou conector do cil.4.",2},
  {"P0205","Injetor - cilindro 5","Injetor, chicote ou conector do cil.5.",2},
  {"P0206","Injetor - cilindro 6","Injetor, chicote ou conector do cil.6.",2},
  {"P0261","Injetor 1 sinal baixo","Injetor ou chicote em curto/aberto.",2},
  {"P0264","Injetor 2 sinal baixo","Injetor ou chicote em curto/aberto.",2},
  {"P0267","Injetor 3 sinal baixo","Injetor ou chicote em curto/aberto.",2},
  {"P0270","Injetor 4 sinal baixo","Injetor ou chicote em curto/aberto.",2},
  // ---- Catalisador / sondas (oxigenio) ----
  {"P0420","Catalisador fraco (lado 1)","Catalisador gasto, sonda velha ou motor queimando oleo. Raramente para o carro.",1},
  {"P0430","Catalisador fraco (lado 2)","Catalisador gasto ou sonda velha.",1},
  {"P0130","Sonda lambda 1 (antes do cat)","Sonda de oxigenio velha ou chicote.",1},
  {"P0131","Sonda lambda 1 sinal baixo","Sonda, fio ou entrada de ar falsa.",1},
  {"P0132","Sonda lambda 1 sinal alto","Sonda ou mistura rica.",1},
  {"P0133","Sonda lambda 1 lenta","Sonda de oxigenio velha (troca).",1},
  {"P0134","Sonda lambda 1 sem sinal","Sonda desligada, fio partido ou aquecedor da sonda.",1},
  {"P0135","Aquecedor da sonda 1","Resistencia do aquecedor da sonda ou fusivel.",1},
  {"P0136","Sonda lambda 2 (depois do cat)","Sonda traseira velha ou chicote.",1},
  {"P0137","Sonda 2 sinal baixo","Sonda traseira ou fio.",1},
  {"P0138","Sonda 2 sinal alto","Sonda traseira ou mistura.",1},
  {"P0141","Aquecedor da sonda 2","Resistencia do aquecedor da sonda traseira.",1},
  {"P0150","Sonda lambda 1 (lado 2)","Sonda de oxigenio ou chicote.",1},
  {"P0155","Aquecedor da sonda (lado 2)","Aquecedor da sonda.",1},
  {"P0156","Sonda lambda 2 (lado 2)","Sonda traseira ou chicote.",1},
  // ---- EVAP (vapor de combustivel) ----
  {"P0440","Vazamento no sistema de vapor (EVAP)","Tampa do tanque mal fechada, mangueira ou valvula canister.",1},
  {"P0441","Fluxo de purga do EVAP errado","Valvula de purga (canister) presa.",1},
  {"P0442","Vazamento pequeno no EVAP","Tampa do tanque frouxa - reaperte primeiro. Ou mangueira do canister.",1},
  {"P0446","Ventilacao do canister","Valvula de ventilacao do canister.",1},
  {"P0455","Vazamento grande no EVAP","Tampa do tanque aberta/ruim ou mangueira solta.",1},
  {"P0456","Vazamento minimo no EVAP","Tampa do tanque - reaperte. Ou mangueira fina rachada.",1},
  {"P0457","Tampa do tanque solta","Aperte a tampa do tanque ate clicar.",1},
  // ---- Ar / admissao (MAF, MAP, IAT) ----
  {"P0100","Sensor de fluxo de ar (MAF)","Sensor MAF sujo ou chicote.",2},
  {"P0101","MAF fora da faixa","MAF sujo, entrada de ar falsa ou filtro de ar entupido.",2},
  {"P0102","MAF sinal baixo","MAF sujo/desligado ou fio.",2},
  {"P0103","MAF sinal alto","MAF ou chicote.",2},
  {"P0105","Sensor de pressao do coletor (MAP)","Sensor MAP ou mangueira de vacuo.",2},
  {"P0106","MAP fora da faixa","Mangueira de vacuo solta ou sensor MAP.",2},
  {"P0107","MAP sinal baixo","Sensor MAP ou fio.",2},
  {"P0108","MAP sinal alto","Sensor MAP ou mangueira.",2},
  {"P0110","Sensor de temperatura do ar (IAT)","Sensor IAT ou chicote.",1},
  {"P0111","IAT fora da faixa","Sensor IAT.",1},
  {"P0112","IAT sinal baixo","Sensor IAT em curto.",1},
  {"P0113","IAT sinal alto","Sensor IAT aberto ou fio.",1},
  {"P2015","Sensor de posicao do coletor de admissao","Sensor/haste do coletor (comum em VW/Audi).",2},
  {"P2279","Entrada de ar falsa na admissao","Mangueira/junta solta admitindo ar.",2},
  // ---- Temperatura do motor (ATENCAO) ----
  {"P0115","Sensor de temperatura do motor","Sensor de temperatura (agua) ou chicote.",2},
  {"P0116","Temperatura do motor fora da faixa","Sensor de temperatura ou termostato.",2},
  {"P0117","Temperatura do motor - sinal baixo","Sensor em curto.",2},
  {"P0118","Temperatura do motor - sinal alto","Sensor aberto/desligado ou fio partido.",2},
  {"P0125","Motor demora a esquentar","Termostato aberto/preso ou sensor de temperatura.",1},
  {"P0128","Termostato abrindo cedo","Termostato preso aberto (motor nao esquenta direito).",1},
  {"P0217","Motor superaquecendo","PARE: falta de agua, termostato, bomba d'agua ou ventoinha.",3},
  {"P0218","Temperatura do cambio alta","PARE e deixe esfriar: nivel/qualidade do oleo do cambio.",3},
  // ---- Borboleta / pedal (TPS / acelerador) ----
  {"P0120","Sensor da borboleta (TPS)","Corpo de borboleta ou sensor TPS.",2},
  {"P0121","TPS fora da faixa","Corpo de borboleta sujo ou sensor.",2},
  {"P0122","TPS sinal baixo","Sensor TPS ou fio.",2},
  {"P0123","TPS sinal alto","Sensor TPS ou fio.",2},
  {"P0221","Sensor do pedal do acelerador","Sensor do pedal ou chicote.",2},
  {"P0222","Pedal do acelerador sinal baixo","Sensor do pedal.",2},
  {"P0223","Pedal do acelerador sinal alto","Sensor do pedal.",2},
  {"P2101","Motor da borboleta eletronica","Corpo de borboleta eletronico (limpar ou trocar).",2},
  {"P2111","Borboleta presa aberta","Corpo de borboleta travado.",3},
  {"P2118","Corrente do motor da borboleta","Corpo de borboleta eletronico.",2},
  {"P2135","Sensores da borboleta divergentes","Corpo de borboleta ou sensor TPS.",2},
  // ---- Marcha lenta / velocidade ----
  {"P0505","Controle de marcha lenta","Corpo de borboleta sujo ou atuador de marcha lenta.",1},
  {"P0506","Marcha lenta baixa","Borboleta suja ou entrada de ar.",1},
  {"P0507","Marcha lenta alta","Entrada de ar falsa ou borboleta.",1},
  {"P0500","Sensor de velocidade","Sensor de velocidade (VSS) ou chicote.",1},
  {"P0501","Velocidade fora da faixa","Sensor de velocidade.",1},
  // ---- Ignicao / sincronismo (virabrequim/comando) ----
  {"P0335","Sensor de rotacao (virabrequim)","Sensor de rotacao (comum: carro morre e nao pega). Chicote ou roda fonica.",3},
  {"P0336","Roda fonica do virabrequim","Roda dentada danificada ou sensor.",2},
  {"P0340","Sensor de fase (comando)","Sensor de fase ou chicote.",2},
  {"P0341","Sensor de fase fora de sincronismo","Sensor de fase, corrente/correia solta.",2},
  {"P0016","Sincronismo virabrequim x comando","Corrente/correia dentada esticada ou variador. Pode danificar o motor.",3},
  {"P0011","Variador de comando (admissao) adiantado","Variador (VVT), solenoide ou oleo sujo/baixo.",2},
  {"P0012","Variador de comando (admissao) atrasado","Variador (VVT), solenoide ou oleo.",2},
  {"P0014","Variador de comando (escape) adiantado","Variador (VVT) do escape ou oleo.",2},
  {"P0021","Variador de comando (lado 2)","Variador (VVT) ou oleo.",2},
  // ---- Detonacao / EGR ----
  {"P0325","Sensor de detonacao (knock)","Sensor de detonacao ou chicote.",1},
  {"P0327","Sensor de detonacao sinal baixo","Sensor de detonacao.",1},
  {"P0401","Fluxo do EGR baixo","Valvula EGR entupida de carvao.",1},
  {"P0402","Fluxo do EGR alto","Valvula EGR presa aberta.",1},
  {"P0403","Circuito da valvula EGR","Valvula EGR eletrica ou chicote.",1},
  {"P0404","Valvula EGR fora da faixa","Valvula EGR.",1},
  // ---- Pressao de oleo (ATENCAO) ----
  {"P0520","Sensor de pressao de oleo","Sensor de pressao de oleo ou chicote.",2},
  {"P0521","Pressao de oleo fora da faixa","Sensor ou pressao real baixa - verifique o nivel.",2},
  {"P0522","Pressao de oleo baixa","PARE e cheque o oleo: pode ser bomba/desgaste do motor.",3},
  // ---- Turbo / sobrealimentacao ----
  {"P0299","Turbo com pressao baixa","Vazamento na tubulacao do turbo, valvula ou turbo.",2},
  {"P0234","Turbo com pressao alta (sobrepressao)","Valvula wastegate presa ou atuador.",2},
  {"P02CD","Turbo/atuador","Atuador do turbo ou chicote.",2},
  // ---- Cambio automatico ----
  {"P0700","Falha no cambio automatico","Veja tambem os codigos do modulo do cambio (TCM).",2},
  {"P0715","Sensor de rotacao de entrada do cambio","Sensor do cambio ou chicote.",2},
  {"P0720","Sensor de rotacao de saida do cambio","Sensor do cambio.",2},
  {"P0730","Relacao de marcha errada","Oleo do cambio, solenoides ou embreagens internas.",2},
  {"P0740","Conversor de torque (lock-up)","Solenoide do conversor ou oleo do cambio.",2},
  {"P0741","Conversor de torque preso solto","Solenoide do conversor ou oleo.",2},
  {"P0748","Solenoide de pressao do cambio","Solenoide ou oleo do cambio.",2},
  {"P0755","Solenoide de marcha (B)","Solenoide do cambio.",2},
  // ---- Eletrico / bateria / sistema ----
  {"P0562","Tensao do sistema baixa","Bateria fraca, alternador ou correia. Pode te deixar na mao.",2},
  {"P0563","Tensao do sistema alta","Regulador do alternador (sobrecarga).",2},
  {"P0620","Circuito do alternador","Alternador ou chicote.",2},
  {"P0645","Rele do compressor do ar-condicionado","Rele do A/C.",1},
  {"P0650","Luz de injecao (MIL)","Circuito da luz do painel.",1},
  {"P0685","Rele principal (ECM)","Rele de alimentacao do modulo do motor.",2},
  // ---- Comunicacao entre modulos (rede CAN) ----
  {"U0001","Falha na rede CAN","Chicote da rede, mau contato ou modulo travado.",2},
  {"U0100","Sem comunicacao com o modulo do motor (ECM)","Modulo do motor, alimentacao ou rede CAN.",3},
  {"U0101","Sem comunicacao com o cambio (TCM)","Modulo do cambio ou rede.",2},
  {"U0121","Sem comunicacao com o ABS","Modulo do ABS ou rede.",2},
  {"U0140","Sem comunicacao com a carroceria (BCM)","Modulo da carroceria ou rede.",2},
  {"U0155","Sem comunicacao com o painel","Painel de instrumentos ou rede.",2},
  {"U0073","Rede de comunicacao desligada","Curto na rede CAN ou modulo em curto.",2},
  // ---- Marcas comuns na frota BR (P1xxx especificos) ----
  {"P1612","GM: falha de comunicacao do modulo","Modulo do motor (GM) ou chicote.",2},
  {"P1613","GM: falha de comunicacao","Rede/modulo GM.",2},
  {"P1614","GM: falha de comunicacao","Rede/modulo GM.",2},
  {"P1258","Motor superaquecido (protecao)","PARE: sistema de arrefecimento (Ford/outros).",3},
  {"P1000","Monitores de emissao incompletos","Normal apos apagar codigos; rode alguns dias.",1},
  {"P1101","MAF fora da faixa na partida","MAF sujo ou entrada de ar (Ford/GM).",2},
  {"P1128","Malha de combustivel nao fecha","Sonda velha ou entrada de ar (VW/Audi).",2},
  {"P1136","Mistura pobre (VW/Audi)","Entrada de ar falsa ou sonda.",2},
};
const uint16_t DTC_TABLE_SIZE = sizeof(DTC_TABLE) / sizeof(DtcInfo);

const DtcInfo* infoDTC(const char* codigo) {
  for (uint16_t i = 0; i < DTC_TABLE_SIZE; i++) {
    if (strcmp(codigo, DTC_TABLE[i].codigo) == 0) return &DTC_TABLE[i];
  }
  return NULL;
}
// compat: continua devolvendo so a descricao (usado em varios lugares)
const char* descricaoDTC(const char* codigo) {
  const DtcInfo* d = infoDTC(codigo);
  return d ? d->descricao : NULL;
}
// texto curto da gravidade (pro usuario leigo)
const char* gravidadeTexto(uint8_t g) {
  switch (g) {
    case 3: return "PARE - risco de quebrar";
    case 2: return "Leve na oficina esta semana";
    case 1: return "Pode rodar, resolva sem pressa";
    default: return "";
  }
}

// ============================================================
//  Armazenamento na FLASH interna (LittleFS) - v7
//  A EEPROM externa (24C32, 4KB) esta cheia; historico de eventos e
//  amostras de bateria vao pra flash de 8MB (particao 'spiffs').
//  Estrategia: arrays em RAM carregados no boot, regravados ao mudar
//  (poucos bytes, gravacao rara -> nao desgasta a flash).
// ============================================================
bool fs_ok = false;
bool fs_corrompido = false;   // montou depois de ja ter formatado -> suspeita de corrupcao

// ---- Tendencia de bateria (tensao de REPOUSO, 1 amostra/dia) ----
#define VBAT_HIST_N 30
struct VbatSample { uint32_t ts; uint16_t mv; };   // mv = milivolts
VbatSample vbat_hist[VBAT_HIST_N];
uint8_t    vbat_n = 0;      // quantas amostras validas
static const char* VBAT_FILE = "/vbat.bin";

// ---- Historico de eventos (DTC / alertas / picos) ----
#define EVT_HIST_N 20
// tipo: 0=DTC  1=TEMP ALTA  2=BATERIA FRACA  3=ALTERNADOR  4=SUPERAQUEC.  5=INFO  6=COMBUSTIVEL
struct Evento { uint32_t ts; uint8_t tipo; int16_t v; char cod[6]; };
Evento   evt_hist[EVT_HIST_N];
uint8_t  evt_n = 0;         // quantos validos (ate EVT_HIST_N, ring)
uint16_t evt_head = 0;      // proximo indice de escrita (ring)
static const char* EVT_FILE = "/evt.bin";

static uint32_t agoraTS() { return rtc_ok ? rtcNow().unixtime() : (millis() / 1000); }

// CRC32 (poly refletido 0xEDB88320) - deteta troca de bytes, rajadas, etc.
// (a soma de 8 bits usada na EEPROM e fraca; nos arquivos usamos CRC32.)
static uint32_t crc32_calc(const uint8_t* d, size_t n) {
  uint32_t c = 0xFFFFFFFFUL;
  for (size_t i = 0; i < n; i++) {
    c ^= d[i];
    for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320UL & (uint32_t)(-(int32_t)(c & 1)));
  }
  return c ^ 0xFFFFFFFFUL;
}

struct FsHdr { uint32_t magic; uint16_t versao; uint16_t n; uint16_t extra; uint16_t rsv; uint32_t crc; } __attribute__((packed));
#define FS_MAGIC_VBAT 0x31544256UL  // "VBT1"
#define FS_MAGIC_EVT  0x31545645UL  // "EVT1"

// Gravacao ATOMICA: escreve no .tmp, move o atual p/ .bak, renomeia o .tmp p/
// definitivo. Uma queda de energia nunca destroi o unico arquivo valido.
static bool fsSaveAtomic(const char* path, uint32_t magic, uint16_t ver, uint16_t n, uint16_t extra,
                         const uint8_t* payload, size_t plen) {
  if (!fs_ok) return false;
  char tmp[28], bak[28];
  snprintf(tmp, sizeof(tmp), "%s.tmp", path);
  snprintf(bak, sizeof(bak), "%s.bak", path);
  FsHdr h; h.magic = magic; h.versao = ver; h.n = n; h.extra = extra; h.rsv = 0;
  h.crc = crc32_calc(payload, plen);
  File f = LittleFS.open(tmp, "w");
  if (!f) return false;
  bool ok = ((size_t)f.write((uint8_t*)&h, sizeof(h)) == sizeof(h));
  if (ok && plen) ok = ((size_t)f.write(payload, plen) == plen);
  f.flush(); f.close();
  if (!ok) { LittleFS.remove(tmp); return false; }
  LittleFS.remove(bak);
  if (LittleFS.exists(path)) LittleFS.rename(path, bak);
  if (!LittleFS.rename(tmp, path)) {
    if (LittleFS.exists(bak)) LittleFS.rename(bak, path);   // restaura o anterior
    return false;
  }
  return true;
}
// Le e VALIDA (magic + CRC). Se o arquivo principal estiver ruim, tenta o .bak.
static bool fsLoadValid(const char* path, uint32_t magic, FsHdr& h, uint8_t* payload, size_t plenMax, size_t* plenOut) {
  char bak[28]; snprintf(bak, sizeof(bak), "%s.bak", path);
  const char* tents[2] = { path, bak };
  for (int t = 0; t < 2; t++) {
    const char* p = tents[t];
    if (!LittleFS.exists(p)) continue;
    File f = LittleFS.open(p, "r");
    if (!f) continue;
    size_t sz = f.size();
    if (sz < sizeof(FsHdr) || sz - sizeof(FsHdr) > plenMax) { f.close(); continue; }
    size_t plen = sz - sizeof(FsHdr);
    bool ok = ((size_t)f.read((uint8_t*)&h, sizeof(h)) == sizeof(h)) && h.magic == magic;
    if (ok) ok = ((size_t)f.read(payload, plen) == plen);
    f.close();
    if (!ok) continue;
    if (crc32_calc(payload, plen) != h.crc) continue;   // CRC nao bate -> arquivo corrompido
    *plenOut = plen;
    return true;
  }
  return false;
}

void vbatLoad() {
  vbat_n = 0;
  FsHdr h; size_t plen;
  if (!fsLoadValid(VBAT_FILE, FS_MAGIC_VBAT, h, (uint8_t*)vbat_hist, sizeof(vbat_hist), &plen)) return;
  uint16_t n = (h.n > VBAT_HIST_N) ? VBAT_HIST_N : h.n;
  if (plen >= (size_t)n * sizeof(VbatSample)) vbat_n = (uint8_t)n;
}
void vbatSave() {   // chamada sempre com mutex_fs ja tomado (por vbatRegistrar)
  fsSaveAtomic(VBAT_FILE, FS_MAGIC_VBAT, 1, vbat_n, 0, (uint8_t*)vbat_hist, (size_t)vbat_n * sizeof(VbatSample));
}
// grava 1 amostra de tensao de repouso (chamar no maximo 1x/dia)
void vbatRegistrar(uint16_t mv) {
  if (mutex_fs && xSemaphoreTake(mutex_fs, pdMS_TO_TICKS(300)) != pdTRUE) return;
  if (vbat_n >= VBAT_HIST_N) {   // desliza (descarta a mais antiga)
    for (int i = 1; i < VBAT_HIST_N; i++) vbat_hist[i - 1] = vbat_hist[i];
    vbat_n = VBAT_HIST_N - 1;
  }
  vbat_hist[vbat_n].ts = agoraTS();
  vbat_hist[vbat_n].mv = mv;
  vbat_n++;
  vbatSave();
  if (mutex_fs) xSemaphoreGive(mutex_fs);
}
// tendencia: quantos mV/dia a bateria de repouso esta caindo (0 se poucos dados).
// negativo = enfraquecendo. Le sob mutex (copia e libera) p/ nao pegar dado a meio.
int vbatTendenciaMvPorDia() {
  VbatSample cp[VBAT_HIST_N]; uint8_t n;
  if (mutex_fs && xSemaphoreTake(mutex_fs, pdMS_TO_TICKS(100)) != pdTRUE) return 0;
  n = vbat_n; memcpy(cp, vbat_hist, sizeof(cp));
  if (mutex_fs) xSemaphoreGive(mutex_fs);
  if (n < 6) return 0;
  int meio = n / 2;
  long soma1 = 0, soma2 = 0;
  for (int i = 0; i < meio; i++) soma1 += cp[i].mv;
  for (int i = meio; i < n; i++) soma2 += cp[i].mv;
  int med1 = soma1 / meio;
  int med2 = soma2 / (n - meio);
  uint32_t dt = cp[n - 1].ts - cp[0].ts;
  int dias = dt / 86400; if (dias < 1) dias = 1;
  return (med2 - med1) / dias;   // mV por dia (negativo = caindo)
}

void evtLoad() {
  evt_n = 0; evt_head = 0;
  FsHdr h; size_t plen;
  if (!fsLoadValid(EVT_FILE, FS_MAGIC_EVT, h, (uint8_t*)evt_hist, sizeof(evt_hist), &plen)) return;
  if (plen != sizeof(evt_hist)) return;
  evt_n = (h.n > EVT_HIST_N) ? EVT_HIST_N : (uint8_t)h.n;
  evt_head = (h.extra >= EVT_HIST_N) ? 0 : h.extra;
}
void evtSave() {   // chamada sempre com mutex_fs ja tomado (por evtRegistrar)
  fsSaveAtomic(EVT_FILE, FS_MAGIC_EVT, 1, evt_n, evt_head, (uint8_t*)evt_hist, sizeof(evt_hist));
}
// registra um evento no historico (ring dos ultimos EVT_HIST_N)
void evtRegistrar(uint8_t tipo, int16_t v, const char* cod) {
  // ANTI-DESGASTE DA FLASH: eventos de sensor (temp/bateria/alternador/superaquec)
  // podem repetir muito — ex.: alternador oscilando dispararia gravacoes sem parar,
  // esgotando a vida da flash. Grava no maximo 1x a cada 10 min POR TIPO. DTC (0) e
  // combustivel (6) sao acionados pelo usuario (raros) -> sem cooldown.
  if (tipo >= 1 && tipo <= 4) {
    static uint32_t last_ms[5] = {0};   // indices 1..4
    uint32_t agora = millis(); if (agora == 0) agora = 1;
    if (last_ms[tipo] && (agora - last_ms[tipo]) < 600000UL) return;   // ainda no cooldown
    last_ms[tipo] = agora;
  }
  if (mutex_fs && xSemaphoreTake(mutex_fs, pdMS_TO_TICKS(300)) != pdTRUE) return;
  Evento& e = evt_hist[evt_head];
  e.ts = agoraTS(); e.tipo = tipo; e.v = v;
  memset(e.cod, 0, sizeof(e.cod));
  if (cod) strncpy(e.cod, cod, sizeof(e.cod) - 1);
  evt_head = (evt_head + 1) % EVT_HIST_N;
  if (evt_n < EVT_HIST_N) evt_n++;
  evtSave();
  if (mutex_fs) xSemaphoreGive(mutex_fs);
}
// devolve o evento 'k' (0 = mais recente). Le sob mutex (copia rapida e libera).
bool evtGet(int k, Evento& out) {
  bool ok = false;
  if (mutex_fs && xSemaphoreTake(mutex_fs, pdMS_TO_TICKS(100)) != pdTRUE) return false;
  if (k >= 0 && k < evt_n) {
    int idx = (evt_head - 1 - k + EVT_HIST_N * 2) % EVT_HIST_N;
    out = evt_hist[idx];
    ok = true;
  }
  if (mutex_fs) xSemaphoreGive(mutex_fs);
  return ok;
}

void flashStorageInit() {
  // NAO formata sozinho na 1a falha (era begin(true)): uma corrupcao temporaria por
  // queda de tensao apagaria o historico. Estrategia: monta; se falhar, tenta de novo;
  // so formata na PRIMEIRA vida do aparelho (flag na NVS). Depois disso, falha de
  // montagem = suspeita de corrupcao -> roda sem historico e tenta no proximo boot.
  fs_ok = LittleFS.begin(false);
  if (!fs_ok) { delay(50); fs_ok = LittleFS.begin(false); }   // falha transitoria
  if (!fs_ok) {
    Preferences fsp; fsp.begin("veican", false);
    bool jaFormatou = fsp.getBool("fsinit", false);
    if (!jaFormatou) {   // particao virgem (1o uso) -> formata UMA vez, controlado
      Serial.println("[FS] 1o uso: formatando a particao de dados");
      if (LittleFS.format() && LittleFS.begin(false)) { fs_ok = true; fsp.putBool("fsinit", true); }
    } else {
      fs_corrompido = true;   // ja formatou antes e agora falhou -> preserva p/ diagnostico
      Serial.println("[FS] >>> montagem falhou (ja formatado antes): SUSPEITA DE CORRUPCAO. Sem historico esta sessao.");
    }
    fsp.end();
  }
  Serial.printf("[FS] LittleFS %s\n", fs_ok ? "montado" : "FALHOU");
  if (fs_ok) { vbatLoad(); evtLoad(); Serial.printf("[FS] vbat=%d amostras, evt=%d eventos\n", vbat_n, evt_n); }
}

// ============================================================
//  Debug log
// ============================================================
struct DebugHeader {
  char magic[4]; uint16_t head; uint16_t count; uint32_t total; uint32_t reservado;
} __attribute__((packed));

struct DebugRecord {
  uint32_t timestamp_ms; uint32_t unix_ts; uint8_t tipo; uint8_t boot_reason;
  uint16_t valor1; uint16_t valor2; char msg[16]; uint8_t reservado[2];
} __attribute__((packed));

// ============================================================
//  EEPROM low-level
// ============================================================
bool eepromWriteBytes(uint16_t addr, uint8_t* buf, uint16_t len) {
  // #8: NUNCA espera o mutex I2C pra sempre — timeout p/ nao travar a tarefa
  if (mutex_i2c && xSemaphoreTake(mutex_i2c, pdMS_TO_TICKS(300)) != pdTRUE) return false;
  bool ok = true;
  uint16_t escritos = 0;
  while (escritos < len) {
    uint16_t pagina_end = (addr / 32 + 1) * 32;
    uint16_t pode = pagina_end - addr;
    if (pode > len - escritos) pode = len - escritos;
    Wire.beginTransmission(EEPROM_ADDR);
    Wire.write((addr >> 8) & 0xFF);
    Wire.write(addr & 0xFF);
    for (uint16_t i = 0; i < pode; i++) Wire.write(buf[escritos + i]);
    if (Wire.endTransmission() != 0) { ok = false; break; }
    vTaskDelay(pdMS_TO_TICKS(6));
    addr += pode;
    escritos += pode;
  }
  if (mutex_i2c) xSemaphoreGive(mutex_i2c);
  return ok;
}

bool eepromReadBytes(uint16_t addr, uint8_t* buf, uint16_t len) {
  // #8: mutex com timeout (nao trava a tarefa se o barramento estiver ocupado)
  if (mutex_i2c && xSemaphoreTake(mutex_i2c, pdMS_TO_TICKS(300)) != pdTRUE) return false;
  bool ok = true;
  Wire.beginTransmission(EEPROM_ADDR);
  Wire.write((addr >> 8) & 0xFF);
  Wire.write(addr & 0xFF);
  if (Wire.endTransmission() != 0) {
    ok = false;
  } else {
    uint16_t lidos = 0;
    while (lidos < len) {
      uint8_t pedaco = min((uint16_t)32, (uint16_t)(len - lidos));
      // #7: se o EEPROM nao responder, requestFrom devolve 0 -> SAI (antes travava aqui pra sempre)
      uint8_t got = Wire.requestFrom(EEPROM_ADDR, pedaco);
      if (got == 0) { ok = false; break; }
      uint16_t antes = lidos;
      while (Wire.available() && lidos < len) buf[lidos++] = Wire.read();
      if (lidos == antes) { ok = false; break; }   // sem progresso -> sai (nunca trava)
    }
  }
  if (mutex_i2c) xSemaphoreGive(mutex_i2c);
  return ok;
}

// Wrappers do RTC com mutex I2C (RTC e EEPROM dividem o barramento).
// TIMEOUT em vez de portMAX_DELAY: se o barramento engasgar (ruido do carro
// andando durante uma gravacao da EEPROM), NUNCA trava — devolve o ultimo
// horario bom. Era essa trava que reiniciava o aparelho so com o carro andando.
DateTime rtcNow() {
  static DateTime cache(2000, 1, 1, 0, 0, 0);   // ultimo valor bom (semente no boot)
  if (mutex_i2c && xSemaphoreTake(mutex_i2c, pdMS_TO_TICKS(150)) != pdTRUE) {
    return cache;   // barramento ocupado/travado -> ultimo valor bom, sem travar
  }
  cache = rtc.now();
  if (mutex_i2c) xSemaphoreGive(mutex_i2c);
  return cache;
}
void rtcAdjust(const DateTime &dt) {
  if (mutex_i2c && xSemaphoreTake(mutex_i2c, pdMS_TO_TICKS(300)) != pdTRUE) return;
  rtc.adjust(dt);
  if (mutex_i2c) xSemaphoreGive(mutex_i2c);
}

// ============================================================
//  DEBUG LOG
// ============================================================
void salvarDebugHeader() {
  DebugHeader h;
  memcpy(h.magic, "DBG1", 4);
  h.head = debug_log_head; h.count = debug_log_count; h.total = 0; h.reservado = 0;
  eepromWriteBytes(DEBUG_LOG_ADDR, (uint8_t*)&h, sizeof(h));
}
bool carregarDebugHeader() {
  DebugHeader h;
  eepromReadBytes(DEBUG_LOG_ADDR, (uint8_t*)&h, sizeof(h));
  if (memcmp(h.magic, "DBG1", 4) != 0) return false;
  // indices fora da faixa = header velho/invalido (ex.: apos mudar o tamanho/endereco) -> reformata
  if (h.head >= MAX_DEBUG_RECORDS || h.count > MAX_DEBUG_RECORDS) return false;
  debug_log_head = h.head; debug_log_count = h.count;
  return true;
}
void formatarDebugLog() { debug_log_head = 0; debug_log_count = 0; salvarDebugHeader(); }

void debugLog(uint8_t tipo, const char* msg, uint16_t v1 = 0, uint16_t v2 = 0, uint8_t bootReason = 0) {
  if (xSemaphoreTake(mutex_debug, pdMS_TO_TICKS(100)) != pdTRUE) return;
  DebugRecord r;
  r.timestamp_ms = millis();
  r.unix_ts = 0;
  if (rtc_ok) r.unix_ts = rtcNow().unixtime();
  r.tipo = tipo; r.boot_reason = bootReason; r.valor1 = v1; r.valor2 = v2;
  strncpy(r.msg, msg, 15); r.msg[15] = 0; memset(r.reservado, 0, 2);
  uint16_t addr = DEBUG_LOG_ADDR + DEBUG_HEADER_SIZE + (debug_log_head * DEBUG_RECORD_SIZE);
  eepromWriteBytes(addr, (uint8_t*)&r, DEBUG_RECORD_SIZE);
  debug_log_head = (debug_log_head + 1) % MAX_DEBUG_RECORDS;
  if (debug_log_count < MAX_DEBUG_RECORDS) debug_log_count++;
  static uint8_t dbg_hdr_skip = 0;
  if ((++dbg_hdr_skip & 3) == 0) salvarDebugHeader();  // header a cada 4: menos desgaste
  xSemaphoreGive(mutex_debug);
  const char* tipos[] = {"INFO", "WARN", "ERR ", "BOOT", "BEAT"};
  Serial.printf("[DBG %s] %s v1=%u v2=%u\n", (tipo < 5) ? tipos[tipo] : "?", r.msg, v1, v2);
}

void dumpDebugLog() {
  Serial.println("\n========== DEBUG LOG ==========");
  Serial.printf("Total: %u/%u (head=%u)\n", debug_log_count, MAX_DEBUG_RECORDS, debug_log_head);
  if (debug_log_count == 0) { Serial.println("Vazio."); return; }
  uint16_t start = (debug_log_count < MAX_DEBUG_RECORDS) ? 0 : ((debug_log_head + 1) % MAX_DEBUG_RECORDS);
  const char* tipos[] = {"INFO", "WARN", "ERR ", "BOOT", "BEAT"};
  const char* boots[] = {"POWERON","EXT","SOFT","WATCHDOG","DEEPSL","BROWNOUT","SDIO","RTCWDT","INTWDT","TG0WDT","TG1WDT","RTCWDT_RTC"};
  for (uint16_t i = 0; i < debug_log_count; i++) {
    uint16_t idx = (start + i) % MAX_DEBUG_RECORDS;
    uint16_t addr = DEBUG_LOG_ADDR + DEBUG_HEADER_SIZE + (idx * DEBUG_RECORD_SIZE);
    DebugRecord r;
    eepromReadBytes(addr, (uint8_t*)&r, DEBUG_RECORD_SIZE);
    Serial.printf("#%02u [%-4s] ms=%lu ts=%lu %s", i, (r.tipo < 5) ? tipos[r.tipo] : "?", r.timestamp_ms, r.unix_ts, r.msg);
    if (r.tipo == 3) Serial.printf(" boot=%s", (r.boot_reason < 12) ? boots[r.boot_reason] : "?");
    if (r.valor1 || r.valor2) Serial.printf(" v1=%u v2=%u", r.valor1, r.valor2);
    Serial.println();
  }
  Serial.println("===============================\n");
}

// ============================================================
//  Header Logger
// ============================================================
void salvarHeader() {
  EepromHeader h;
  memcpy(h.magic, "MGRD", 4);
  h.versao = 6; h.head = log_head; h.count = log_count; h.total = log_total;
  memset(h.reservado, 0, 3);
  eepromWriteBytes(0, (uint8_t*)&h, sizeof(h));
}
bool carregarHeader() {
  EepromHeader h;
  eepromReadBytes(0, (uint8_t*)&h, sizeof(h));
  if (memcmp(h.magic, "MGRD", 4) != 0) return false;
  if (h.versao != 6) return false;   // v6: MAX_RECORDS mudou de 180 p/ 176
  log_head = h.head; log_count = h.count; log_total = h.total;
  return true;
}
void formatarEEPROM() {
  Serial.println("[Logger] Formatando...");
  log_head = 0; log_count = 0; log_total = 0; salvarHeader();
}

// ============================================================
//  Config persistente (calibracoes)
// ============================================================
static uint8_t somaCRC(uint8_t* p, uint8_t n) {
  uint8_t s = 0; for (uint8_t i = 0; i < n; i++) s += p[i]; return s;
}

void salvarConfig() {
  EepromConfig c = {};
  memcpy(c.magic, "CFG1", 4);
  c.voltcal = voltcal; c.km_cal = km_cal;
  c.crc = somaCRC((uint8_t*)&c, 12);
  // #9: nao ignora falha de gravacao — registra no log de diagnostico
  if (!eepromWriteBytes(CONFIG_ADDR, (uint8_t*)&c, sizeof(c))) debugLog(2, "EEPROM cfg falhou");
}
bool carregarConfig() {
  EepromConfig c;
  if (!eepromReadBytes(CONFIG_ADDR, (uint8_t*)&c, sizeof(c))) return false;
  if (memcmp(c.magic, "CFG1", 4) != 0) return false;
  if (c.crc != somaCRC((uint8_t*)&c, 12)) return false;
  // sanidade: rejeita valores absurdos (EEPROM corrompida nunca pode aleijar a leitura)
  if (c.voltcal > 0.5f && c.voltcal < 2.0f) voltcal = c.voltcal;
  if (c.km_cal  > 0.5f && c.km_cal  < 2.0f) km_cal  = c.km_cal;
  return true;
}

// ============================================================
//  Hodometro
// ============================================================
static uint32_t odo_seq = 0;   // sequencia da gravacao alternada

void salvarHodometro() {
  OdoSlot s = {};
  memcpy(s.magic, "ODO2", 4);
  if (xSemaphoreTake(mutex_hodometro, pdMS_TO_TICKS(100)) == pdTRUE) {
    s.km_total_x100 = km_total_x100; s.segundos_motor = segundos_motor_total;
    xSemaphoreGive(mutex_hodometro);
  }
  s.seq = ++odo_seq;
  s.crc = somaCRC((uint8_t*)&s, 16);
  // alterna o slot: seq impar -> A, par -> B (o slot antigo fica intacto durante a gravacao)
  uint16_t addr = (odo_seq & 1) ? ODO_SLOT_A : ODO_SLOT_B;
  TRACE_DUR("salvarHodometro", {
    if (!eepromWriteBytes(addr, (uint8_t*)&s, sizeof(s))) debugLog(2, "EEPROM odo falhou");   // #9
  });
}

static bool lerSlotOdo(uint16_t addr, OdoSlot &s) {
  if (!eepromReadBytes(addr, (uint8_t*)&s, sizeof(s))) return false;
  if (memcmp(s.magic, "ODO2", 4) != 0) return false;
  return s.crc == somaCRC((uint8_t*)&s, 16);
}

bool carregarHodometro() {
  OdoSlot a, b;
  bool va = lerSlotOdo(ODO_SLOT_A, a);
  bool vb = lerSlotOdo(ODO_SLOT_B, b);
  if (va || vb) {
    OdoSlot &m = (va && vb) ? ((a.seq >= b.seq) ? a : b) : (va ? a : b);
    if (va && vb && a.seq != b.seq) Serial.printf("[Odo] slots A=%lu B=%lu -> usando %lu\n", a.seq, b.seq, m.seq);
    odo_seq = m.seq;
    if (xSemaphoreTake(mutex_hodometro, pdMS_TO_TICKS(100)) == pdTRUE) {
      km_total_x100 = m.km_total_x100; segundos_motor_total = m.segundos_motor;
      xSemaphoreGive(mutex_hodometro);
    }
    return true;
  }
  // migracao: formato antigo (slot unico em HODOMETRO_ADDR)
  EepromHodometro h;
  eepromReadBytes(HODOMETRO_ADDR, (uint8_t*)&h, sizeof(h));
  if (memcmp(h.magic, "ODOM", 4) != 0) return false;
  Serial.println("[Odo] migrando formato antigo -> slots duplos");
  if (xSemaphoreTake(mutex_hodometro, pdMS_TO_TICKS(100)) == pdTRUE) {
    km_total_x100 = h.km_total_x100; segundos_motor_total = h.segundos_motor;
    xSemaphoreGive(mutex_hodometro);
  }
  salvarHodometro(); salvarHodometro();  // grava nos dois slots
  return true;
}
void formatarHodometro() {
  Serial.println("[Odo] Formatando...");
  if (xSemaphoreTake(mutex_hodometro, pdMS_TO_TICKS(100)) == pdTRUE) {
    km_total_x100 = 0; segundos_motor_total = 0; km_acumulado_x100 = 0;
    xSemaphoreGive(mutex_hodometro);
  }
  salvarHodometro(); salvarHodometro();  // zera os DOIS slots
}

// ============================================================
//  Manutencao
// ============================================================
void salvarItensManutencao() {
  if (xSemaphoreTake(mutex_manut, pdMS_TO_TICKS(200)) != pdTRUE) return;
  for (int i = 0; i < NUM_ITENS_MANUT; i++) {
    uint16_t addr = MANUTENCAO_ADDR + (i * ITEM_SIZE);
    eepromWriteBytes(addr, (uint8_t*)&itens_manut[i], sizeof(ItemManutencao));
  }
  xSemaphoreGive(mutex_manut);
}
bool carregarItensManutencao() {
  if (xSemaphoreTake(mutex_manut, pdMS_TO_TICKS(200)) != pdTRUE) return false;
  bool ok = true;
  for (int i = 0; i < NUM_ITENS_MANUT; i++) {
    uint16_t addr = MANUTENCAO_ADDR + (i * ITEM_SIZE);
    eepromReadBytes(addr, (uint8_t*)&itens_manut[i], sizeof(ItemManutencao));
    if (memcmp(itens_manut[i].magic, "MT", 2) != 0) { ok = false; break; }
  }
  xSemaphoreGive(mutex_manut);
  return ok;
}
void inicializarManutencao() {
  Serial.println("[Manut] Inicializando defaults...");
  if (xSemaphoreTake(mutex_manut, pdMS_TO_TICKS(200)) != pdTRUE) return;
  DateTime agora = rtcNow();
  uint32_t ts = agora.unixtime();
  for (int i = 0; i < NUM_ITENS_MANUT; i++) {
    memcpy(itens_manut[i].magic, "MT", 2);
    itens_manut[i].tipo = i; itens_manut[i].flags = 0;
    itens_manut[i].km_ultima = 0; itens_manut[i].timestamp_ultima = ts;
    memset(itens_manut[i].reservado, 0, 10);
  }
  itens_manut[IDX_OLEO_MOTOR].km_intervalo = 10000;  itens_manut[IDX_OLEO_MOTOR].dias_intervalo = 180;
  itens_manut[IDX_FILTRO_AR].km_intervalo = 10000;   itens_manut[IDX_FILTRO_AR].dias_intervalo = 180;
  itens_manut[IDX_VELA].km_intervalo = VELA_NORMAL_KM; itens_manut[IDX_VELA].dias_intervalo = 0;
  itens_manut[IDX_OLEO_CAMBIO].km_intervalo = 80000; itens_manut[IDX_OLEO_CAMBIO].dias_intervalo = 0;
  itens_manut[IDX_CORREIA].km_intervalo = 60000;     itens_manut[IDX_CORREIA].dias_intervalo = 1095;
  itens_manut[IDX_PNEU].km_intervalo = 50000;        itens_manut[IDX_PNEU].dias_intervalo = 0;
  itens_manut[IDX_FILTRO_COMB].km_intervalo = 15000; itens_manut[IDX_FILTRO_COMB].dias_intervalo = 0;
  itens_manut[IDX_BOMBA_AGUA].km_intervalo = 40000;  itens_manut[IDX_BOMBA_AGUA].dias_intervalo = 0;   // = correia
  itens_manut[IDX_PASTILHA].km_intervalo = 40000;    itens_manut[IDX_PASTILHA].dias_intervalo = 0;
  itens_manut[IDX_OLEO_FREIO].km_intervalo = 60000;  itens_manut[IDX_OLEO_FREIO].dias_intervalo = 730; // 2 anos
  xSemaphoreGive(mutex_manut);
  salvarItensManutencao();
}
void resetarItem(uint8_t idx) {
  if (idx >= NUM_ITENS_MANUT) return;
  if (xSemaphoreTake(mutex_manut, pdMS_TO_TICKS(200)) != pdTRUE) return;
  DateTime agora = rtcNow();
  uint32_t km_atual = 0;
  if (xSemaphoreTake(mutex_hodometro, pdMS_TO_TICKS(50)) == pdTRUE) {
    km_atual = (km_total_x100 + km_acumulado_x100) / 100;
    xSemaphoreGive(mutex_hodometro);
  }
  itens_manut[idx].km_ultima = km_atual;
  itens_manut[idx].timestamp_ultima = agora.unixtime();
  xSemaphoreGive(mutex_manut);
  salvarItensManutencao();
  Serial.printf("[Manut] %s resetado em %lukm\n", NOMES_ITENS[idx], km_atual);
}
bool itemVencido(uint8_t idx, uint32_t km_atual, uint32_t ts_atual) {
  ItemManutencao &item = itens_manut[idx];
  // CORRECAO A: protege underflow. Apos ZERAR TUDO, km_atual=0 < km_ultima (valor antigo)
  // e a subtracao sem sinal viraria um numero gigante -> item aparecia "VENC." falso.
  uint32_t km_rodado = (km_atual >= item.km_ultima) ? (km_atual - item.km_ultima) : 0;
  if (item.km_intervalo > 0 && km_rodado >= item.km_intervalo) return true;
  // H8 (#42): so conta manutencao por TEMPO com o relogio confiavel (ajustado e
  // com data plausivel > 2023). Relogio nao ajustado -> nao dispara vencimento falso.
  if (item.dias_intervalo > 0 && !hora_nao_ajustada &&
      ts_atual > 1672531200UL && ts_atual >= item.timestamp_ultima) {
    uint32_t segs = ts_atual - item.timestamp_ultima;
    if (segs / 86400 >= item.dias_intervalo) return true;
  }
  return false;
}
uint16_t itemPercentual(uint8_t idx, uint32_t km_atual, uint32_t ts_atual) {
  ItemManutencao &item = itens_manut[idx];
  if (item.km_intervalo == 0) return 0;  // guarda contra divisao por zero
  // CORRECAO A: mesmo cuidado com underflow do calculo de percentual.
  uint32_t km_rodado = (km_atual >= item.km_ultima) ? (km_atual - item.km_ultima) : 0;
  uint16_t pct_km = (km_rodado * 100) / item.km_intervalo;
  uint16_t pct_tempo = 0;
  if (item.dias_intervalo > 0 && ts_atual >= item.timestamp_ultima) {
    uint32_t segs = ts_atual - item.timestamp_ultima;
    pct_tempo = ((segs / 86400) * 100) / item.dias_intervalo;
  }
  return (pct_km > pct_tempo) ? pct_km : pct_tempo;
}

// ============================================================
//  Gravar log
// ============================================================
void gravarRegistro(uint8_t tipo_evento) {
  DateTime agora = rtcNow();
  DadosCarro d;
  if (xSemaphoreTake(mutex_dados, pdMS_TO_TICKS(100)) != pdTRUE) return;
  d = dados_publicos;
  xSemaphoreGive(mutex_dados);
  // SATURACAO em cada campo: dado corrompido/fora de faixa nao pode virar lixo no
  // log. Em especial a temperatura em int8_t: 130C sem saturar viraria -126 (um
  // superaquecimento apareceria como negativo). Aqui prende no maximo do tipo.
  // (Aumentar p/ int16_t exige mudar RECORD_SIZE e o layout da EEPROM -> fica p/ v8.)
  LogRecord r;
  r.timestamp = agora.unixtime();
  r.evento = tipo_evento;
  r.rpm         = (uint16_t)constrain(d.rpm, 0, 16000);
  r.velocidade  = (uint8_t)constrain(d.velocidade, 0, 255);
  r.temp_motor  = (int8_t)constrain(d.temp_motor, -40, 127);   // satura em 127 (nao vira negativo)
  r.tps         = (uint8_t)constrain(d.tps, 0, 100);
  r.ped_abs     = (uint8_t)constrain(d.ped_abs, 0, 100);
  float vlog = d.tensao;
  if (!isfinite(vlog)) vlog = 0.0f;
  vlog = constrain(vlog, 0.0f, 25.5f);
  r.tensao_x10  = (uint8_t)lroundf(vlog * 10.0f);
  r.carga       = (uint8_t)constrain(d.carga, 0, 100);
  r.carga_abs   = (uint8_t)constrain(d.carga_abs, 0, 255);
  r.combust     = (uint8_t)constrain(d.combust, 0, 100);
  r.temp_adm    = (int8_t)constrain(d.temp_adm, -40, 127);
  uint8_t* p = (uint8_t*)&r;
  uint8_t soma = 0;
  for (int i = 0; i < 15; i++) soma += p[i];
  r.crc = soma;
  uint16_t addr = LOGS_BASE + (log_head * RECORD_SIZE);
  if (eepromWriteBytes(addr, (uint8_t*)&r, RECORD_SIZE)) {
    log_head = (log_head + 1) % MAX_RECORDS;
    if (log_count < MAX_RECORDS) log_count++;
    log_total++;
    // header so a cada 8 registros: 8x menos desgaste no endereco 0 da EEPROM.
    if ((log_total & 7) == 0) salvarHeader();
  }
}

// ============================================================
//  CAN OBD-II
// ============================================================
// ===== Protocolo OBD autodetectado (ISO 15765-4) =====
volatile uint32_t obd_req_id   = 0x7DF;   // ID do pedido funcional
volatile bool     obd_extd     = false;   // false=11bit, true=29bit
volatile uint32_t obd_resp_min = 0x7E8;   // faixa de resposta (11bit)
volatile uint32_t obd_resp_max = 0x7EF;
volatile uint16_t obd_baud     = 500;     // 500 ou 250 kbps
volatile bool     obd_ok       = false;   // protocolo detectado?

// Confere se um frame recebido e uma resposta OBD valida no protocolo atual
bool ehRespostaOBD(const twai_message_t &rx) {
  if (obd_extd) {
    // 29-bit: respostas em 0x18DAF1xx
    return rx.extd && ((rx.identifier & 0xFFFFFF00) == 0x18DAF100);
  }
  return (!rx.extd) && rx.identifier >= obd_resp_min && rx.identifier <= obd_resp_max;
}

// ID de flow control (fisico) a partir do ID que respondeu
uint32_t fcIdDaResposta(uint32_t resp_id, bool extd) {
  if (extd) {
    // 0x18DAF1<src>  ->  0x18DA<src>F1
    uint8_t src = resp_id & 0xFF;
    return 0x18DA00F1 | ((uint32_t)src << 8);
  }
  return resp_id - 8;   // 0x7E8 -> 0x7E0
}

// (Re)instala o driver TWAI no baud indicado, com checagem de erro
// mode = TWAI_MODE_NORMAL (transmite) ou TWAI_MODE_LISTEN_ONLY (so escuta, nao da ACK).
// Listen-only e usado na DETECCAO p/ nao perturbar o barramento (evita acender luz de airbag
// em carros com gateway ou que nem tem CAN).
bool instalarCAN(uint16_t baud, twai_mode_t mode = TWAI_MODE_NORMAL) {
  twai_general_config_t g = TWAI_GENERAL_CONFIG_DEFAULT(CAN_TX_PIN, CAN_RX_PIN, mode);
  g.rx_queue_len = 32;   // barramento cheio (ex.: Cruze) -> fila maior evita perder respostas
  g.tx_queue_len = 10;
  twai_timing_config_t  t500 = TWAI_TIMING_CONFIG_500KBITS();
  twai_timing_config_t  t250 = TWAI_TIMING_CONFIG_250KBITS();
  twai_timing_config_t  t = (baud == 250) ? t250 : t500;  // ternario sobre variaveis, nao sobre as macros
  twai_filter_config_t  f = TWAI_FILTER_CONFIG_ACCEPT_ALL();
  esp_err_t e = twai_driver_install(&g, &t, &f);
  if (e != ESP_OK) { Serial.printf("[CAN] driver_install %dk falhou: %s\n", baud, esp_err_to_name(e)); return false; }
  e = twai_start();
  if (e != ESP_OK) { Serial.printf("[CAN] start %dk falhou: %s\n", baud, esp_err_to_name(e)); twai_driver_uninstall(); return false; }
  return true;
}

// Reinicia o driver do zero (faz o que religar na tomada faz: limpa erro acumulado)
void reiniciarCAN() {
  Serial.println("[CAN] reiniciando driver (travou/bus-off)");
  twai_stop();
  twai_driver_uninstall();
  vTaskDelay(pdMS_TO_TICKS(50));
  instalarCAN(obd_baud);
}

// Envia mode01/PID00 (obrigatorio) e ve se ha resposta no par (reqid, extd)
bool sondaOBD(uint32_t reqid, bool extd) {
  twai_message_t lixo;
  while (twai_receive(&lixo, 0) == ESP_OK) {}  // limpa fila
  twai_message_t tx = {};
  tx.identifier = reqid; tx.extd = extd ? 1 : 0; tx.data_length_code = 8;
  tx.data[0] = 0x02; tx.data[1] = 0x01; tx.data[2] = 0x00;  // PIDs suportados
  for (int i = 3; i < 8; i++) tx.data[i] = 0x00;
  if (twai_transmit(&tx, pdMS_TO_TICKS(80)) != ESP_OK) return false;
  uint32_t t0 = millis();
  while (millis() - t0 < 300) {
    twai_message_t rx;
    if (twai_receive(&rx, pdMS_TO_TICKS(60)) == ESP_OK) {
      if (!extd && !rx.extd && rx.identifier >= 0x7E8 && rx.identifier <= 0x7EF && rx.data[1] == 0x41) return true;
      if (extd &&  rx.extd && ((rx.identifier & 0xFFFFFF00) == 0x18DAF100) && rx.data[1] == 0x41) return true;
    }
  }
  return false;
}

// Escuta o barramento passivamente (NAO transmite nada) e reporta no Serial.
uint32_t sniffCAN(uint16_t baud, uint16_t ms) {
  uint32_t n = 0, n11 = 0, n29 = 0;
  uint32_t ids[8]; int nids = 0;
  uint32_t t0 = millis();
  while (millis() - t0 < ms) {
    twai_message_t rx;
    if (twai_receive(&rx, pdMS_TO_TICKS(20)) == ESP_OK) {
      n++;
      if (rx.extd) n29++; else n11++;
      bool novo = true;
      for (int i = 0; i < nids; i++) if (ids[i] == rx.identifier) { novo = false; break; }
      if (novo && nids < 8) ids[nids++] = rx.identifier;
    }
  }
  Serial.printf("[SNIFF] %dk: %lu frames (11b:%lu 29b:%lu)", baud, n, n11, n29);
  if (nids > 0) {
    Serial.print(" ex:");
    for (int i = 0; i < nids; i++) Serial.printf(" %03X", (unsigned)ids[i]);
  }
  Serial.println();
  return n;
}

// Detecta o protocolo SEM perturbar o barramento:
// 1) escuta em LISTEN-ONLY (nao transmite, nao da ACK) p/ ver se ha CAN naquele baud;
// 2) SO se houver frames, reinstala em NORMAL e sonda (transmite) o OBD;
// 3) se nao houver CAN em nenhum baud, NAO transmite nada (fica passivo) -> nao acende airbag.
// Detecta o protocolo com o MINIMO de perturbacao (importante: NAO acender airbag).
// Regra de ouro: nunca transmitir na velocidade errada. Primeiro DESCOBRE a velocidade
// so ESCUTANDO (listen-only, nao transmite), e so entao transmite UMA vez, na velocidade certa.
static void obdListenOnly(uint16_t baud) {
  instalarCAN(baud, TWAI_MODE_LISTEN_ONLY);
  obd_req_id = 0x7DF; obd_extd = false; obd_resp_min = 0x7E8; obd_resp_max = 0x7EF;
  obd_baud = baud; obd_ok = false;
}
bool detectarProtocoloOBD() {
  const uint16_t bauds[] = {500, 250};
  // ---- passo 1: acha a velocidade SO ESCUTANDO (nao transmite -> nao mexe no airbag) ----
  int baud_ativo = 0;
  for (int b = 0; b < 2; b++) {
    if (!instalarCAN(bauds[b], TWAI_MODE_LISTEN_ONLY)) continue;
    delay(120);
    uint32_t vistos = sniffCAN(bauds[b], 500);
    twai_stop(); twai_driver_uninstall();
    if (vistos > 0) { baud_ativo = bauds[b]; break; }   // ESSA e a velocidade real do barramento
  }

  // ---- passo 2: barramento com trafego -> sonda OBD SO nessa velocidade (single-shot) ----
  if (baud_ativo) {
    Serial.printf("[CAN] barramento ativo em %dk -> sondando OBD (velocidade certa)\n", baud_ativo);
    if (instalarCAN(baud_ativo, TWAI_MODE_NORMAL)) {
      delay(80);
      if (sondaOBD(0x7DF, false)) {
        obd_req_id = 0x7DF; obd_extd = false; obd_resp_min = 0x7E8; obd_resp_max = 0x7EF;
        obd_baud = baud_ativo; obd_ok = true;
        Serial.printf("[CAN] >>> Protocolo: 11-bit / %dk <<<\n", obd_baud); return true;
      }
      if (sondaOBD(0x18DB33F1, true)) {
        obd_req_id = 0x18DB33F1; obd_extd = true; obd_baud = baud_ativo; obd_ok = true;
        Serial.printf("[CAN] >>> Protocolo: 29-bit / %dk <<<\n", obd_baud); return true;
      }
      twai_stop(); twai_driver_uninstall();
    }
    // tem barramento mas nao respondeu OBD -> fica PASSIVO na velocidade certa (nao transmite mais)
    Serial.printf("[CAN] %dk tem barramento mas sem OBD -> LISTEN-ONLY (passivo)\n", baud_ativo);
    obdListenOnly(baud_ativo);
    return false;
  }

  // ---- passo 3: silencio total. Pode ser gateway silencioso (VW): sonda 500k e 250k ----
  Serial.println("[CAN] sem trafego -> sondando gateway em 500k e 250k");
  const uint16_t tb[] = {500, 250};
  for (int b = 0; b < 2; b++) {
    if (!instalarCAN(tb[b], TWAI_MODE_NORMAL)) continue;
    delay(80);
    if (sondaOBD(0x7DF, false)) {
      obd_req_id = 0x7DF; obd_extd = false; obd_resp_min = 0x7E8; obd_resp_max = 0x7EF;
      obd_baud = tb[b]; obd_ok = true;
      Serial.printf("[CAN] >>> Protocolo: 11-bit / %dk (gateway) <<<\n", tb[b]); return true;
    }
    if (sondaOBD(0x18DB33F1, true)) {
      obd_req_id = 0x18DB33F1; obd_extd = true; obd_baud = tb[b]; obd_ok = true;
      Serial.printf("[CAN] >>> Protocolo: 29-bit / %dk (gateway) <<<\n", tb[b]); return true;
    }
    twai_stop(); twai_driver_uninstall();
  }
  // Nada: LISTEN-ONLY passivo (nunca mais transmite) -> zero perturbacao.
  obdListenOnly(500);
  Serial.println("[CAN] Nenhum CAN detectado -> LISTEN-ONLY (passivo)");
  return false;
}

// ---- SCAN pesado do CAN (carros com gateway, ex.: Fiat Stilo) ----
// Dispara um pedido OBD num (reqid,extd) e loga TODAS as respostas cruas.
static void scanProbe(uint32_t reqid, bool extd, uint16_t baud) {
  twai_message_t lixo; while (twai_receive(&lixo, 0) == ESP_OK) {}
  twai_message_t tx = {};
  tx.identifier = reqid; tx.extd = extd ? 1 : 0; tx.data_length_code = 8;
  tx.data[0] = 0x02; tx.data[1] = 0x01; tx.data[2] = 0x00;
  for (int i = 3; i < 8; i++) tx.data[i] = 0x00;
  bool txok = (twai_transmit(&tx, pdMS_TO_TICKS(80)) == ESP_OK);
  Serial.printf("[SCAN] tx %s %lX (%dk): %s\n", extd ? "29b" : "11b", (unsigned long)reqid, baud, txok ? "enviado" : "TX FALHOU (sem ACK)");
  uint32_t t0 = millis(); int got = 0;
  while (millis() - t0 < 600) {
    twai_message_t rx;
    if (twai_receive(&rx, pdMS_TO_TICKS(50)) == ESP_OK) {
      Serial.printf("[SCAN]  <- %s %lX:", rx.extd ? "29b" : "11b", (unsigned long)rx.identifier);
      for (int i = 0; i < rx.data_length_code; i++) Serial.printf(" %02X", rx.data[i]);
      Serial.println();
      if (++got >= 16) break;
    }
  }
  if (!got) Serial.println("[SCAN]  <- (nada)");
}

static void scanCANBody() {
  Serial.println("\n===== SCAN CAN (gateway/Fiat Stilo) =====");
  const uint16_t bauds[] = {500, 250};
  for (int b = 0; b < 2; b++) {
    Serial.printf("[SCAN] --- %dk ---\n", bauds[b]);
    if (instalarCAN(bauds[b], TWAI_MODE_LISTEN_ONLY)) {   // escuta passiva longa
      delay(120); sniffCAN(bauds[b], 1500);
      twai_stop(); twai_driver_uninstall();
    }
    if (instalarCAN(bauds[b], TWAI_MODE_NORMAL)) {         // sonda ativa varios enderecos
      delay(80);
      scanProbe(0x7DF, false, bauds[b]);       // funcional 11-bit
      scanProbe(0x7E0, false, bauds[b]);       // fisico ECU motor 11-bit
      scanProbe(0x18DB33F1, true, bauds[b]);   // funcional 29-bit
      twai_stop(); twai_driver_uninstall();
    }
  }
  Serial.println("[SCAN] fim. Se so 'TX FALHOU' -> nao ha CAN (fio/velocidade). Se 'enviado' mas '(nada)'");
  Serial.println("[SCAN] -> tem barramento mas o motor esta atras do gateway (Body Computer Fiat).");
  Serial.println("====\n");
}

void scanCAN() {
  TaskHandle_t hcan = xTaskGetHandle("CAN");
  if (hcan) { vTaskSuspend(hcan); twai_stop(); twai_driver_uninstall(); }
  vTaskDelay(pdMS_TO_TICKS(100));
  scanCANBody();
  if (hcan) { twai_stop(); twai_driver_uninstall(); instalarCAN(500, TWAI_MODE_LISTEN_ONLY); vTaskResume(hcan); }
}

// Varre os 8 enderecos fisicos padrao de ECU (0x7E0..0x7E7) a 500k e loga qualquer
// resposta. Ultimo tiro seguro p/ o Stilo (so IDs de diagnostico, nao mexe em modulos).
static void scanSweepBody() {
  Serial.println("\n===== SWEEP 0x7E0..0x7E7 (500k) =====");
  if (!instalarCAN(500, TWAI_MODE_NORMAL)) { Serial.println("[SWP] falha instalar 500k"); Serial.println("====\n"); return; }
  delay(80);
  int achou = 0;
  for (uint32_t id = 0x7E0; id <= 0x7E7; id++) {
    twai_message_t lixo; while (twai_receive(&lixo, 0) == ESP_OK) {}
    twai_message_t tx = {};
    tx.identifier = id; tx.extd = 0; tx.data_length_code = 8;
    tx.data[0] = 0x02; tx.data[1] = 0x01; tx.data[2] = 0x00;
    for (int i = 3; i < 8; i++) tx.data[i] = 0x00;
    bool txok = (twai_transmit(&tx, pdMS_TO_TICKS(60)) == ESP_OK);
    Serial.printf("[SWP] REQ %lX: %s\n", (unsigned long)id, txok ? "tx ok" : "TX FALHOU");
    uint32_t t0 = millis();
    while (millis() - t0 < 200) {
      twai_message_t rx;
      if (twai_receive(&rx, pdMS_TO_TICKS(40)) == ESP_OK) {
        if (rx.identifier == id) continue;
        Serial.printf("[SWP]   <- %lX:", (unsigned long)rx.identifier);
        for (int i = 0; i < rx.data_length_code; i++) Serial.printf(" %02X", rx.data[i]);
        Serial.println();
        achou++;
      }
    }
  }
  twai_stop(); twai_driver_uninstall();
  if (!achou) Serial.println("[SWP] NENHUM respondeu -> motor fora do barramento OBD (gateway/CAN-C). Confirmado.");
  Serial.println("====\n");
}

void scanSweep() {
  TaskHandle_t hcan = xTaskGetHandle("CAN");
  if (hcan) { vTaskSuspend(hcan); twai_stop(); twai_driver_uninstall(); }
  vTaskDelay(pdMS_TO_TICKS(100));
  scanSweepBody();
  if (hcan) { twai_stop(); twai_driver_uninstall(); instalarCAN(500, TWAI_MODE_LISTEN_ONLY); vTaskResume(hcan); }
}

bool obdRequest(uint8_t pid, uint8_t* resp, uint8_t* len) {
  // limpa frames antigos da fila ANTES de perguntar: em barramento cheio (Cruze) a fila
  // enchia de mensagens de outros modulos e a resposta era descartada por overflow.
  twai_message_t lixo;
  while (twai_receive(&lixo, 0) == ESP_OK) { /* descarta */ }
  twai_message_t tx = {};
  tx.identifier = obd_req_id; tx.extd = obd_extd ? 1 : 0; tx.data_length_code = 8;
  tx.data[0] = 0x02; tx.data[1] = 0x01; tx.data[2] = pid;
  for (int i = 3; i < 8; i++) tx.data[i] = 0x00;
  if (twai_transmit(&tx, pdMS_TO_TICKS(80)) != ESP_OK) return false;
  tx_ok++;
  uint32_t t0 = millis();
  while (millis() - t0 < 150) {
    twai_message_t rx;
    if (twai_receive(&rx, pdMS_TO_TICKS(50)) == ESP_OK) {
      if (ehRespostaOBD(rx) && rx.data[1] == 0x41 && rx.data[2] == pid) {
        // SEGURANCA: rx.data[0] vem do barramento (nao confiavel). Sem limite, um
        // frame com data[0]=0xFF faria memcpy de 253 bytes num buffer de 8 -> estouro.
        int n = (int)rx.data[0] - 2;            // bytes de payload declarados
        if (n < 0) n = 0;
        if (n > 5) n = 5;                        // resp[] = 8 bytes; data[3..7] = 5 uteis
        *len = n;
        memcpy(resp, &rx.data[3], n);
        rx_ok++;
        return true;
      }
    }
  }
  timeouts++;
  return false;
}

void descobrirPIDs() {
  Serial.println("\n=== AUTO-DESCOBERTA ===");
  uint8_t ranges[] = {0x00, 0x20, 0x40, 0x60, 0x80, 0xA0, 0xC0};
  for (int r = 0; r < 7; r++) {
    uint8_t pid_inicial = ranges[r];
    uint8_t resp[8], len;
    bool ok = false;
    for (int t = 0; t < 3 && !ok; t++) {
      ok = obdRequest(pid_inicial, resp, &len);
      if (!ok) vTaskDelay(pdMS_TO_TICKS(100));
    }
    if (!ok || len < 4) break;
    for (int byte = 0; byte < 4; byte++) {
      for (int bit = 0; bit < 8; bit++) {
        if (resp[byte] & (0x80 >> bit)) {
          uint8_t pid = pid_inicial + (byte * 8) + bit + 1;
          pid_suportado[pid] = true;
        }
      }
    }
    if (!(resp[3] & 0x01)) break;
  }
  // registra se o carro DECLAROU o 0x2F ANTES de forcar (p/ desambiguar 0xFF = cheio vs indisponivel)
  fuel_2f_declarado = pid_suportado[0x2F];
  // garante os essenciais: a descoberta pode vir incompleta em barramento cheio
  pid_suportado[0x05] = true;  // temperatura do motor
  pid_suportado[0x0C] = true;  // rpm
  pid_suportado[0x0D] = true;  // velocidade
  pid_suportado[0x2F] = true;  // nivel de combustivel
  int total = 0;
  for (int i = 1; i < 256; i++) if (pid_suportado[i]) total++;
  Serial.printf("Total PIDs suportados: %d\n", total);
  debugLog(0, "PIDs descobertos", total);
}

int f_rpm(uint8_t* d) { return ((d[0]*256)+d[1])/4; }
int f_vel(uint8_t* d) { return d[0]; }
int f_temp(uint8_t* d) { return d[0]-40; }
int f_pct(uint8_t* d) { return (d[0]*100)/255; }
int f_raw(uint8_t* d) { return d[0]; }
int f_16bit(uint8_t* d) { return (d[0]*256)+d[1]; }
int f_carga_abs(uint8_t* d) { return ((d[0]*256)+d[1])*100/255; }
float f_tensao(uint8_t* d) { return ((d[0]*256)+d[1])/1000.0; }

// CORRECAO B: sentinela de erro = -1000 (fora da faixa valida de qualquer PID).
// Antes era -1, que colidia com a faixa de temperatura (-40..215): leitura falha
// virava "TEMP -1C" na tela. Com -1000 o teste 'valor >= -40' rejeita a falha.
#define PID_ERRO (-1000)
int lerPID_int(uint8_t pid, int (*formula)(uint8_t*)) {
  if (!pid_suportado[pid]) return PID_ERRO;
  uint8_t d[8] = {0}; uint8_t len;   // zera: resposta curta nao deixa d[1] com lixo
  if (obdRequest(pid, d, &len)) return formula(d);
  return PID_ERRO;
}
float lerPID_float(uint8_t pid, float (*formula)(uint8_t*)) {
  if (!pid_suportado[pid]) return -1.0;
  uint8_t d[8] = {0}; uint8_t len;
  if (obdRequest(pid, d, &len)) return formula(d);
  return -1.0;
}

// ===== Tensao da bateria pelo ADC (independente do CAN) =====
float lerTensaoADC() {
  uint32_t soma = 0;
  for (int i = 0; i < 16; i++) soma += analogReadMilliVolts(PIN_VBAT);
  float vpin = (soma / 16.0) / 1000.0;     // V no pino do ESP
  return vpin * VBAT_RATIO * voltcal;      // V real da bateria
}

// ============================================================
//  DTCs
// ============================================================
void decodificaDTC(uint8_t b1, uint8_t b2, char* out) {
  char tipo = 'P';
  switch ((b1 >> 6) & 0x03) {
    case 0: tipo = 'P'; break; case 1: tipo = 'C'; break;
    case 2: tipo = 'B'; break; case 3: tipo = 'U'; break;
  }
  uint8_t d1 = (b1 >> 4) & 0x03; uint8_t d2 = b1 & 0x0F;
  uint8_t d3 = (b2 >> 4) & 0x0F; uint8_t d4 = b2 & 0x0F;
  snprintf(out, 6, "%c%X%X%X%X", tipo, d1, d2, d3, d4);
}

int lerDTCs(char dtcs[][6]) {
  twai_message_t tx = {};
  tx.identifier = obd_req_id; tx.extd = obd_extd ? 1 : 0; tx.data_length_code = 8;
  tx.data[0] = 0x01; tx.data[1] = 0x03;
  for (int i = 2; i < 8; i++) tx.data[i] = 0x00;
  if (twai_transmit(&tx, pdMS_TO_TICKS(100)) != ESP_OK) return -1;
  tx_ok++;
  int num_dtcs = 0;
  uint32_t t0 = millis();
  while (millis() - t0 < 800 && num_dtcs < MAX_DTCS) {
    twai_message_t rx;
    if (twai_receive(&rx, pdMS_TO_TICKS(100)) != ESP_OK) continue;
    if (!ehRespostaOBD(rx)) continue;
    rx_ok++;
    Serial.printf("[DTC] rx %03lX:", (unsigned long)rx.identifier);
    for (int j = 0; j < 8; j++) Serial.printf(" %02X", rx.data[j]);
    Serial.println();
    uint8_t pci = rx.data[0] & 0xF0;
    if (pci == 0x00) {
      if (rx.data[1] != 0x43) continue;
      // A resposta pode vir COM ou SEM byte de contagem apos o 0x43:
      //   com:  43 <n> <hi lo> <hi lo> ...   (after = 1 + 2n -> impar)
      //   sem:  43 <hi lo> <hi lo> ...       (after = 2n     -> par)
      // Decide pelo tamanho declarado no PCI (nibble baixo do byte 0).
      int after = (int)(rx.data[0] & 0x0F) - 1;   // bytes de dados apos o 0x43
      if (after < 2) after = 6;                    // PCI nao confiavel: assume quadro cheio
      int start, count;
      if ((after % 2) == 1 && rx.data[2] == (after - 1) / 2) { count = rx.data[2]; start = 3; }
      else                                                   { count = after / 2;  start = 2; }
      for (int i = 0; i < count && num_dtcs < MAX_DTCS && (start + i*2 + 1) < 8; i++) {
        uint8_t b1 = rx.data[start + i*2]; uint8_t b2 = rx.data[start + 1 + i*2];
        if (b1 == 0 && b2 == 0) continue;
        decodificaDTC(b1, b2, dtcs[num_dtcs]); num_dtcs++;
      }
      return num_dtcs;
    } else if (pci == 0x10) {
      if (rx.data[2] != 0x43) continue;
      uint8_t qtd = rx.data[3];
      for (int i = 0; i < 2 && i < qtd && num_dtcs < MAX_DTCS; i++) {
        uint8_t b1 = rx.data[4 + i*2]; uint8_t b2 = rx.data[5 + i*2];
        if (b1 == 0 && b2 == 0) continue;
        decodificaDTC(b1, b2, dtcs[num_dtcs]); num_dtcs++;
      }
      twai_message_t fc = {};
      fc.identifier = fcIdDaResposta(rx.identifier, obd_extd); fc.extd = obd_extd ? 1 : 0; fc.data_length_code = 8;
      fc.data[0] = 0x30; fc.data[1] = 0x00; fc.data[2] = 0x00;
      for (int i = 3; i < 8; i++) fc.data[i] = 0x00;
      twai_transmit(&fc, pdMS_TO_TICKS(50));
      uint32_t t1 = millis();
      while (millis() - t1 < 500 && num_dtcs < MAX_DTCS) {
        twai_message_t cf;
        if (twai_receive(&cf, pdMS_TO_TICKS(100)) != ESP_OK) continue;
        if (!ehRespostaOBD(cf)) continue;
        if ((cf.data[0] & 0xF0) != 0x20) continue;
        for (int i = 1; i < 8 && num_dtcs < MAX_DTCS; i++) {
          uint8_t b1 = cf.data[i]; uint8_t b2 = 0;
          if (b1 != 0) { decodificaDTC(b1, b2, dtcs[num_dtcs]); num_dtcs++; }
        }
      }
      return num_dtcs;
    }
  }
  Serial.println("[DTC] (CAN) sem resposta ao mode03 (ou ECU nao expoe DTC generico)");
  return -1;
}

bool apagarDTCs() {
  twai_message_t tx = {};
  tx.identifier = obd_req_id; tx.extd = obd_extd ? 1 : 0; tx.data_length_code = 8;
  tx.data[0] = 0x01; tx.data[1] = 0x04;
  for (int i = 2; i < 8; i++) tx.data[i] = 0x00;
  if (twai_transmit(&tx, pdMS_TO_TICKS(100)) != ESP_OK) return false;
  tx_ok++;
  uint32_t t0 = millis();
  while (millis() - t0 < 800) {
    twai_message_t rx;
    if (twai_receive(&rx, pdMS_TO_TICKS(100)) != ESP_OK) continue;
    if (ehRespostaOBD(rx)) {
      rx_ok++;
      if (rx.data[1] == 0x44) return true;
      if (rx.data[1] == 0x7F && rx.data[2] == 0x04) return false;
    }
  }
  timeouts++;
  return false;
}

// ============================================================
//  Sondagem combustivel (Mode 22 / UDS)
// ============================================================
void flushCAN() {
  twai_message_t rx;
  int n = 0;
  while (twai_receive(&rx, 0) == ESP_OK && n < 64) n++;
}

int lerDID22(uint32_t reqId, uint16_t did, uint8_t* out, int maxOut) {
  flushCAN();
  uint8_t dh = (did >> 8) & 0xFF, dl = did & 0xFF;
  twai_message_t tx = {};
  tx.identifier = reqId; tx.data_length_code = 8;
  tx.data[0] = 0x03; tx.data[1] = 0x22; tx.data[2] = dh; tx.data[3] = dl;
  for (int i = 4; i < 8; i++) tx.data[i] = 0x00;
  if (twai_transmit(&tx, pdMS_TO_TICKS(80)) != ESP_OK) return -1;
  tx_ok++;
  uint32_t t0 = millis();
  while (millis() - t0 < 350) {
    twai_message_t rx;
    if (twai_receive(&rx, pdMS_TO_TICKS(60)) != ESP_OK) continue;
    if (rx.identifier < 0x700 || rx.identifier > 0x7FF) continue;
    uint8_t pci = rx.data[0] & 0xF0;
    if (pci == 0x00 && rx.data[1] == 0x62 && rx.data[2] == dh && rx.data[3] == dl) {
      int n = (rx.data[0] & 0x0F) - 3;
      if (n < 0) n = 0;
      if (n > maxOut) n = maxOut;
      if (n > 4) n = 4;   // SEGURANCA: frame unico so tem data[4..7] = 4 bytes de payload
      for (int i = 0; i < n; i++) out[i] = rx.data[4 + i];
      rx_ok++; return n;
    }
    if (pci == 0x10 && rx.data[2] == 0x62 && rx.data[3] == dh && rx.data[4] == dl) {
      int total = ((rx.data[0] & 0x0F) << 8) | rx.data[1];
      int dataTotal = total - 3;
      int idx = 0;
      for (int i = 5; i < 8 && idx < dataTotal && idx < maxOut; i++) out[idx++] = rx.data[i];
      twai_message_t fc = {};
      fc.identifier = reqId; fc.data_length_code = 8;
      fc.data[0] = 0x30; fc.data[1] = 0x00; fc.data[2] = 0x00;
      for (int i = 3; i < 8; i++) fc.data[i] = 0x00;
      twai_transmit(&fc, pdMS_TO_TICKS(50));
      uint32_t t1 = millis();
      while (idx < dataTotal && idx < maxOut && millis() - t1 < 350) {
        twai_message_t cf;
        if (twai_receive(&cf, pdMS_TO_TICKS(60)) != ESP_OK) continue;
        if (cf.identifier < 0x700 || cf.identifier > 0x7FF) continue;
        if ((cf.data[0] & 0xF0) != 0x20) continue;
        for (int i = 1; i < 8 && idx < dataTotal && idx < maxOut; i++) out[idx++] = cf.data[i];
      }
      rx_ok++; return idx;
    }
  }
  return -1;
}

int lerFrameByte(uint32_t id, uint8_t bi, uint32_t to_ms);   // definida adiante
void detectarMetodoCombustivel() {
  uint8_t d[8], len;
  bool val2F_ok = false;    // respondeu com valor valido (<0xFF)
  for (int t = 0; t < 3 && !val2F_ok; t++) {   // barramento cheio: tenta algumas vezes
    if (obdRequest(0x2F, d, &len) && d[0] != 0xFF) val2F_ok = true;
    else vTaskDelay(pdMS_TO_TICKS(80));
  }
  // Usa 0x2F SO se veio um valor valido (<0xFF). Declarar no bitmask nao basta:
  // o Azera declara o 0x2F mas responde 0xFF sem entregar o nivel real.
  if (val2F_ok) {
    fuel_metodo = 1;
    Serial.printf("[Fuel] metodo = PID 0x2F (declarado=%d)\n", fuel_2f_declarado);
    return;
  }
  uint8_t vin[20];
  int n = lerDID22(VW_CLUSTER_REQ, 0xF190, vin, sizeof(vin));
  if (n >= 3) {
    char wmi[4] = { (char)vin[0], (char)vin[1], (char)vin[2], 0 };
    Serial.printf("[Fuel] VIN WMI = %s\n", wmi);
    bool ehVW = (vin[0] == 'W' && vin[1] == 'V') ||
                (vin[0] == '9' && vin[1] == 'B' && vin[2] == 'W');
    if (ehVW) {
      fuel_metodo = 2;
      Serial.println("[Fuel] metodo = VW Mode22 (painel, DID 2206)");
      return;
    }
  }
  // Combustivel por BROADCAST (frame proprio do carro). AUTO-DETECTA:
  // 1) se o usuario salvou um custom (HYFUEL), tenta esse primeiro (calibrado);
  // 2) senao, varre a TABELA de carros conhecidos (Honda, Azera, ...) e usa o
  //    primeiro frame que existir -> plug-and-play, sem comando manual.
  if (fuel_custom) {
    int hb = lerFrameByte(hy_fuel_id, hy_fuel_byte, 500);
    if (hb >= 0) {
      fuel_metodo = 4;
      Serial.printf("[Fuel] metodo = broadcast SALVO (ID %lX byte %d /%d) = %d%%\n",
                    (unsigned long)hy_fuel_id, hy_fuel_byte, hy_fuel_max, (hb * 100) / hy_fuel_max);
      return;
    }
  }
  for (int i = 0; i < FUEL_TABLE_N; i++) {
    int hb = lerFrameByte(FUEL_TABLE[i].id, FUEL_TABLE[i].byte, 400);
    if (hb < 0) continue;                                  // frame nao existe nesse carro
    int pct = (hb * 100) / FUEL_TABLE[i].max;
    // PROTECAO anti-sequestro: rejeita so quando ESTOURA (escala errada / frame de
    // outro carro). NAO rejeita nivel baixo — tanque vazio le ~0% e e valido.
    if (pct > 110) continue;
    hy_fuel_id = FUEL_TABLE[i].id; hy_fuel_byte = FUEL_TABLE[i].byte; hy_fuel_max = FUEL_TABLE[i].max;
    fuel_metodo = 4;
    Serial.printf("[Fuel] metodo = broadcast %s (ID %lX byte %d /%d) = %d%%\n",
                  FUEL_TABLE[i].nome, (unsigned long)hy_fuel_id, hy_fuel_byte, hy_fuel_max, pct);
    return;
  }
  fuel_metodo = 3;
  Serial.println("[Fuel] metodo = indisponivel");
}

// Escuta ate to_ms por um frame CAN com 'id' e retorna o byte 'bi' (-1 se nao veio).
int lerFrameByte(uint32_t id, uint8_t bi, uint32_t to_ms) {
  uint32_t t0 = millis();
  while (millis() - t0 < to_ms) {
    twai_message_t rx;
    if (twai_receive(&rx, pdMS_TO_TICKS(20)) == ESP_OK) {
      if (rx.identifier == id && bi < rx.data_length_code) return rx.data[bi];
    }
  }
  return -1;
}

int lerCombustivelPct() {
  if (fuel_metodo == 4) {   // Hyundai/Kia: broadcast (Azera ID 0x329 byte1 /255)
    int b = lerFrameByte(hy_fuel_id, hy_fuel_byte, 250);
    if (b < 0) return -1;
    int pct = (b * 100) / hy_fuel_max;
    if (pct > 100) pct = 100;
    return pct;
  }
  if (fuel_metodo == 1) {
    uint8_t d[8], len;
    if (obdRequest(0x2F, d, &len)) {
      // 0xFF e ambiguo (cheio OU indisponivel). Como muitos carros (Azera, Honda) respondem
      // 0xFF sem entregar o nivel real, e mais seguro ESCONDER (mostra --) do que mostrar 100% falso.
      if (d[0] == 0xFF) return -1;
      return (d[0] * 100) / 255;
    }
    return -1;
  }
  if (fuel_metodo == 2) {
    uint8_t d[8];
    int n = lerDID22(VW_CLUSTER_REQ, VW_DID_FUEL, d, sizeof(d));
    if (n >= 1) {
      int litros = d[0];
      int pct = (litros * 100) / TANQUE_VW_L;
      if (pct > 100) pct = 100;
      return pct;
    }
    return -1;
  }
  return -1;
}

void probeFuel2F() {
  uint8_t d[8], len;
  flushCAN();
  Serial.print("\n[FUEL] PID 0x2F bruto: ");
  if (obdRequest(0x2F, d, &len)) {
    Serial.printf("len=%u A=%u (0x%02X) -> %d%%", len, d[0], d[0], (d[0]*100)/255);
    if (d[0] == 0xFF) Serial.print("   >>> 0xFF = carro NAO entrega combustivel nesse PID");
    Serial.println();
  } else Serial.println("sem resposta");
}

void probeM22(uint16_t did, bool soPositivo) {
  flushCAN();
  twai_message_t tx = {};
  tx.identifier = probe_reqid; tx.data_length_code = 8;
  tx.data[0] = 0x03; tx.data[1] = 0x22;
  tx.data[2] = (did >> 8) & 0xFF; tx.data[3] = did & 0xFF;
  for (int i = 4; i < 8; i++) tx.data[i] = 0x00;
  if (twai_transmit(&tx, pdMS_TO_TICKS(100)) != ESP_OK) {
    if (!soPositivo) Serial.printf("DID %04X: TX falhou\n", did);
    return;
  }
  tx_ok++;
  uint32_t janela = soPositivo ? 120 : 700;
  uint32_t t0 = millis();
  bool achou = false;
  while (millis() - t0 < janela) {
    twai_message_t rx;
    if (twai_receive(&rx, pdMS_TO_TICKS(60)) != ESP_OK) continue;
    if (rx.identifier < 0x700 || rx.identifier > 0x7FF) continue;
    rx_ok++;
    uint8_t pci = rx.data[0] & 0xF0;
    bool positivo = (rx.data[1] == 0x62) || (pci == 0x10 && rx.data[2] == 0x62);
    bool negativo = (rx.data[1] == 0x7F && rx.data[2] == 0x22);
    if (!positivo && !negativo) continue;
    if (soPositivo && negativo) break;
    achou = true;
    Serial.printf("DID %04X <- ID %03X: %02X %02X %02X %02X %02X %02X %02X %02X",
                  did, rx.identifier, rx.data[0], rx.data[1], rx.data[2], rx.data[3],
                  rx.data[4], rx.data[5], rx.data[6], rx.data[7]);
    if (negativo) Serial.print("   (resposta negativa)");
    Serial.println();
    if (pci == 0x10) {
      twai_message_t fc = {};
      fc.identifier = probe_reqid; fc.data_length_code = 8;
      fc.data[0] = 0x30; fc.data[1] = 0x00; fc.data[2] = 0x00;
      for (int i = 3; i < 8; i++) fc.data[i] = 0x00;
      twai_transmit(&fc, pdMS_TO_TICKS(50));
    }
    if (soPositivo) break;
  }
  if (!achou && !soPositivo)
    Serial.printf("DID %04X: sem resposta no ID %03X\n", did, probe_reqid);
}

void runProbeM22() {
  if (probe_did_ini == probe_did_fim) {
    Serial.printf("\n[M22] DID %04X em ID %03X:\n", probe_did_ini, probe_reqid);
    probeM22(probe_did_ini, false);
    Serial.println("[M22] fim\n");
  } else {
    Serial.printf("\n[SWEEP22] %04X..%04X em ID %03X (so respostas):\n", probe_did_ini, probe_did_fim, probe_reqid);
    for (uint32_t d = probe_did_ini; d <= probe_did_fim; d++) {
      probeM22((uint16_t)d, true);
      vTaskDelay(pdMS_TO_TICKS(15));
    }
    Serial.println("[SWEEP22] fim\n");
  }
}

// ============================================================
//  K-LINE (ISO 9141-2 / ISO 14230-4 KWP2000) - carros antigos (ex.: Peugeot 206)
//  Modulo de TESTE: use o comando de Serial "KLINE" para diagnosticar.
//  Hardware: L9637D. K_TX=GPIO33, K_RX=GPIO39 (via UART1), a 10400 baud 8N1.
// ============================================================
HardwareSerial KLine(1);
volatile bool kline_ok = false;
volatile bool kline_ativo = false;   // K-line e a fonte de dados do painel (sem CAN)
uint8_t kline_kb1 = 0, kline_kb2 = 0;
uint8_t kline_ecu = 0x11;   // endereco do ECU (capturado no init)
uint8_t kline_tgt = 0x33;   // alvo do pedido (descoberto no diagnostico)
uint8_t kline_fmt = 0;      // 0 = "Cx tgt src.." ; 1 = "80 tgt src len.." ; 2 = ISO9141
int kline_temp_off = 40;    // offset da temperatura K-line: tempC = A - off. Padrao SAE = 40.
                            // Alguns ECUs (ex.: certos VW/Gol) mandam A puro -> use 0 (comando KTEMPOFF).
// ---- Montana / GM: le TODO o dado do motor num bloco unico (servico 0x21 LID 0x01) ----
// Descoberto por engenharia reversa (comando GMLIVE) na Montana 2010. mode01 nao tem RPM/temp.
volatile bool kline_gm = false;   // fonte = bloco GM 0x21 LID 01 (offsets abaixo)
int gm_off_rpm  = 32;   // RPM  = (bloco[32]*256 + bloco[33]) / 4   (lenta ~780rpm confirmada)
int gm_off_temp = 41;   // TEMP = bloco[41] em °C DIRETO (leu 74 = termometro 74; faixa 71..74 estavel)
int gm_off_vel  = 36;   // VEL  = bloco[36] em km/h direto (0..64 no teste; min=0 parado). Verificar na estrada.
// Gravador de min/max do bloco em RAM: caca a velocidade DIRIGINDO sem laptop.
// O aparelho acumula sozinho enquanto le a Montana; depois use GMDUMP no serial.
uint8_t gm_mn[128], gm_mx[128];
int gm_rec_n = 0;
uint32_t gm_rec_amostras = 0;
// Temperatura por calibracao linear de 2 pontos: TEMP = a*byte + b.
// O sensor da GM manda valor CRU (inverso: sobe temp -> desce byte), entao 'a' pode ser negativo.
// Default = byte-40 (OBD); ajuste com GMTC1/GMTC2 com o motor frio e quente.
float gm_temp_a = 1.0f, gm_temp_b = 0.0f;   // [41] ja vem em °C direto (byte = graus)
uint8_t gm_last_temp_byte = 0;          // ultimo byte cru de temperatura (p/ calibrar)
uint8_t gm_tc_b1 = 0; float gm_tc_t1 = 0; bool gm_tc_have1 = false;

static uint8_t klineCS(const uint8_t* d, int n) { uint8_t s = 0; for (int i = 0; i < n; i++) s += d[i]; return s; }

// le 1 byte com timeout (ms); -1 se nao veio
static int klineRead(uint32_t to_ms) {
  uint32_t t0 = millis();
  while (millis() - t0 < to_ms) { if (KLine.available()) return (uint8_t)KLine.read(); vTaskDelay(1); }
  return -1;
}

// envia bytes descartando o ECHO (K-line e half-duplex: o que sai volta no RX)
static void klineSend(const uint8_t* d, int n) {
  for (int i = 0; i < n; i++) {
    while (KLine.available()) KLine.read();   // limpa RX
    KLine.write(d[i]); KLine.flush();
    klineRead(80);                            // descarta o echo do proprio byte
    delay(6);                                 // P4: intervalo entre bytes
  }
}

// Slow init 5-baud (endereco 0x33) - ISO 9141-2 / ISO 14230 slow
bool klineInit5baud() {
  Serial.println("[KL] tentando 5-baud init (0x33)...");
  KLine.end();
  pinMode(K_TX_PIN, OUTPUT);
  digitalWrite(K_TX_PIN, HIGH); delay(350);        // idle (W5)
  uint8_t addr = 0x33;
  digitalWrite(K_TX_PIN, LOW);  delay(200);        // start bit
  for (int i = 0; i < 8; i++) { digitalWrite(K_TX_PIN, (addr >> i) & 1); delay(200); }  // LSB first
  digitalWrite(K_TX_PIN, HIGH); delay(200);        // stop bit
  KLine.begin(10400, SERIAL_8N1, K_RX_PIN, K_TX_PIN);
  int sync = klineRead(300);
  Serial.printf("[KL] sync=0x%02X (esperado 0x55)\n", sync & 0xFF);
  if (sync != 0x55) { Serial.println("[KL] 5-baud FALHOU (sem 0x55)"); return false; }
  int kb1 = klineRead(60), kb2 = klineRead(60);
  if (kb1 < 0 || kb2 < 0) { Serial.println("[KL] sem key bytes"); return false; }
  kline_kb1 = kb1; kline_kb2 = kb2;
  delay(30);
  uint8_t inv = ~(uint8_t)kb2;
  while (KLine.available()) KLine.read();
  KLine.write(inv); KLine.flush(); klineRead(80);   // manda KB2 invertido, descarta echo
  int ack = klineRead(120);                          // ECU responde 0xCC (0x33 invertido)
  Serial.printf("[KL] 5-baud OK: KB1=0x%02X KB2=0x%02X ack=0x%02X\n", kb1, kb2, ack & 0xFF);
  if (kb2 == 0x8F) { kline_fmt = 0; kline_tgt = 0x33; Serial.println("[KL] protocolo KWP2000"); }
  else             { kline_fmt = 2; kline_tgt = 0x6A; Serial.println("[KL] protocolo ISO9141"); }  // fmt 2 = ISO9141 (68 6A F1)
  kline_ok = true; return true;
}

// Fast init (ISO 14230-4 KWP2000)
bool klineInitFast() {
  Serial.println("[KL] tentando fast init (KWP2000)...");
  KLine.end();
  pinMode(K_TX_PIN, OUTPUT);
  digitalWrite(K_TX_PIN, HIGH); delay(350);
  digitalWrite(K_TX_PIN, LOW);  delay(25);          // WUP: 25ms low
  digitalWrite(K_TX_PIN, HIGH); delay(25);          // 25ms high
  KLine.begin(10400, SERIAL_8N1, K_RX_PIN, K_TX_PIN);
  uint8_t req[5] = {0xC1, 0x33, 0xF1, 0x81, 0}; req[4] = klineCS(req, 4);  // StartCommunication
  klineSend(req, 5);
  uint8_t resp[16]; int n = 0; uint32_t t0 = millis();
  while (n < 7 && millis() - t0 < 300) { int b = klineRead(60); if (b < 0) break; resp[n++] = b; }
  Serial.print("[KL] resp fast:"); for (int i = 0; i < n; i++) Serial.printf(" %02X", resp[i]); Serial.println();
  if (n >= 6 && resp[3] == 0xC1) {
    kline_kb1 = resp[4]; kline_kb2 = resp[5];
    kline_ecu = resp[2];              // endereco fisico do ECU (ex.: 0x11)
    Serial.printf("[KL] fast init OK: KB1=0x%02X KB2=0x%02X ECU=0x%02X\n", kline_kb1, kline_kb2, kline_ecu);
    kline_ok = true; return true;
  }
  Serial.println("[KL] fast init FALHOU"); return false;
}

// Monta e envia um pedido mode01 PID com um formato/alvo dados, logando tudo.
// fmt 0: "Cx tgt F1 01 pid cs"     (KWP2000, comprimento no fmt)
// fmt 1: "80 tgt F1 02 01 pid cs"  (KWP2000, comprimento em byte separado)
// fmt 2: "68 6A F1 01 pid cs"      (ISO 9141-2)
// retorna nº de bytes de dados em out (ou -1)
int klinePID(uint8_t pid, uint8_t fmt, uint8_t tgt, uint8_t* out, int maxout, bool log) {
  if (!kline_ok) return -1;
  uint8_t req[8]; int rn = 0;
  if (fmt == 2) { req[rn++] = 0x68; req[rn++] = 0x6A; req[rn++] = 0xF1; req[rn++] = 0x01; req[rn++] = pid; }
  else if (fmt == 1) { req[rn++] = 0x80; req[rn++] = tgt; req[rn++] = 0xF1; req[rn++] = 0x02; req[rn++] = 0x01; req[rn++] = pid; }
  else { req[rn++] = 0xC0 | 2; req[rn++] = tgt; req[rn++] = 0xF1; req[rn++] = 0x01; req[rn++] = pid; }
  req[rn] = klineCS(req, rn); rn++;
  if (log) { Serial.printf("[KL] req(f%d t%02X):", fmt, tgt); for (int i = 0; i < rn; i++) Serial.printf(" %02X", req[i]); Serial.println(); }
  klineSend(req, rn);
  uint8_t resp[24]; int n = 0; uint32_t t0 = millis();
  while (n < (int)sizeof(resp) && millis() - t0 < 400) { int b = klineRead(90); if (b < 0) break; resp[n++] = b; }
  if (log) { Serial.print("[KL]  resp:"); if (n == 0) Serial.print(" (nada)"); for (int i = 0; i < n; i++) Serial.printf(" %02X", resp[i]); Serial.println(); }
  for (int i = 0; i + 1 < n; i++) {
    if (resp[i] == 0x41 && resp[i + 1] == pid) {
      int nd = n - (i + 2) - 1; if (nd < 0) nd = 0; if (nd > maxout) nd = maxout;
      for (int j = 0; j < nd; j++) out[j] = resp[i + 2 + j];
      return nd;
    }
  }
  return -1;
}

// usa o formato/alvo ja descobertos
int klineReadPID(uint8_t pid, uint8_t* out, int maxout) {
  return klinePID(pid, kline_fmt, kline_tgt, out, maxout, false);
}

// envia um bloco cru e loga a resposta (p/ diagnostico: sessao, etc.)
static void klineRaw(const char* nome, const uint8_t* payload, int np, uint8_t tgt) {
  uint8_t req[10]; int rn = 0;
  req[rn++] = 0xC0 | np; req[rn++] = tgt; req[rn++] = 0xF1;
  for (int i = 0; i < np; i++) req[rn++] = payload[i];
  req[rn] = klineCS(req, rn); rn++;
  Serial.printf("[KL] %s ->", nome); for (int i = 0; i < rn; i++) Serial.printf(" %02X", req[i]); Serial.println();
  klineSend(req, rn);
  uint8_t r[24]; int n = 0; uint32_t t0 = millis();
  while (n < 24 && millis() - t0 < 400) { int b = klineRead(90); if (b < 0) break; r[n++] = b; }
  Serial.printf("[KL]  %s resp:", nome); if (n == 0) Serial.print(" (nada)"); for (int i = 0; i < n; i++) Serial.printf(" %02X", r[i]); Serial.println();
}

// Nome do codigo de resposta negativa (NRC) do KWP2000 - ajuda a entender a recusa
static const char* nrcNome(uint8_t c) {
  switch (c) {
    case 0x10: return "generalReject";
    case 0x11: return "serviceNotSupported";
    case 0x12: return "subFunctionNotSupported";
    case 0x21: return "busyRepeatRequest";
    case 0x22: return "conditionsNotCorrect";
    case 0x31: return "requestOutOfRange";
    case 0x33: return "securityAccessDenied";
    case 0x35: return "invalidKey";
    case 0x78: return "responsePending";
    case 0x7E: return "serviceNotSupportedInActiveSession";
    case 0x7F: return "serviceNotSupportedInActiveSession";
    default:   return "?";
  }
}

// Envia um servico KWP com formato/alvo dados e loga a resposta JA DECODIFICADA.
// fmt 0: "Cx tgt F1 <payload> cs"   1: "80 tgt F1 len <payload> cs"   2: ISO9141 "68 6A F1 <payload> cs"
// Retorna: 1 = resposta positiva (servico+0x40), 0 = negativa (7F ..), -1 = nada.
// Se out != nullptr, copia os bytes de dados apos o byte de servico positivo.
static int klineServico(const char* nome, const uint8_t* payload, int np,
                        uint8_t fmt, uint8_t tgt, uint8_t* out, int maxout, int* outN) {
  if (outN) *outN = 0;
  if (!kline_ok) return -1;
  uint8_t req[20]; int rn = 0;
  if (fmt == 2)      { req[rn++] = 0x68; req[rn++] = 0x6A; req[rn++] = 0xF1; }
  else if (fmt == 1) { req[rn++] = 0x80; req[rn++] = tgt; req[rn++] = 0xF1; req[rn++] = np; }
  else               { req[rn++] = 0xC0 | np; req[rn++] = tgt; req[rn++] = 0xF1; }
  for (int i = 0; i < np; i++) req[rn++] = payload[i];
  req[rn] = klineCS(req, rn); rn++;
  Serial.printf("[KL] %s (f%d t%02X) ->", nome, fmt, tgt); for (int i = 0; i < rn; i++) Serial.printf(" %02X", req[i]); Serial.println();
  klineSend(req, rn);
  uint8_t r[40]; int n = 0; uint32_t t0 = millis();
  while (n < (int)sizeof(r) && millis() - t0 < 500) { int b = klineRead(100); if (b < 0) break; r[n++] = b; }
  Serial.printf("[KL]  resp:"); if (n == 0) Serial.print(" (nada)"); for (int i = 0; i < n; i++) Serial.printf(" %02X", r[i]);
  uint8_t pos = payload[0] + 0x40;
  int res = -1;
  for (int i = 0; i < n; i++) {
    if (r[i] == 0x7F && i + 2 < n) { Serial.printf("   <<< NEG servico %02X NRC %02X (%s)", r[i + 1], r[i + 2], nrcNome(r[i + 2])); res = 0; break; }
    if (r[i] == pos) {
      Serial.print("   <<< POSITIVO");
      if (out) { int nd = n - (i + 1); if (nd < 0) nd = 0; if (nd > maxout) nd = maxout; for (int j = 0; j < nd; j++) out[j] = r[i + 1 + j]; if (outN) *outN = nd; }
      res = 1; break;
    }
  }
  Serial.println();
  return res;
}

static void klineLerRestante() {
  uint8_t d[8]; int r;
  delay(55);
  r = klineReadPID(0x0D, d, 8); if (r >= 1) Serial.printf("[KL] VEL = %d km/h\n", d[0]); else Serial.println("[KL] VEL sem resposta");
  delay(55);
  r = klineReadPID(0x05, d, 8); if (r >= 1) Serial.printf("[KL] TEMP = %d C\n", d[0] - 40); else Serial.println("[KL] TEMP sem resposta");
  delay(55);
  r = klineReadPID(0x2F, d, 8); if (r >= 1 && d[0] != 0xFF) Serial.printf("[KL] COMB = %d%%\n", (d[0] * 100) / 255); else Serial.println("[KL] COMB nao suportado (0x2F)");
}

// Diagnostico completo pelo Serial (comando "KLINE") - KWP primeiro (Montana conecta por fast init)
static void klineDiagBody() {
  Serial.println("\n===== TESTE K-LINE (foco Montana/GM KWP2000) =====");
  uint8_t d[16]; int nd;
  struct { uint8_t fmt, tgt; } combos[] = { {0,0x33}, {1,0x33}, {0,kline_ecu}, {1,kline_ecu} };
  uint8_t tp[1] = {0x3E};   // TesterPresent, mantem a sessao viva entre os testes

  // ----- 1) Conexao: fast init KWP2000 (o que a Montana aceita) -----
  kline_ok = false;
  bool conectou = klineInitFast();
  if (!conectou) {
    Serial.println("[KL] fast init falhou; tentando 5-baud (ISO9141)...");
    delay(1000);
    conectou = klineInit5baud();
  }
  if (!conectou) { Serial.println("[KL] nenhum init conectou. Verifique pull-up 510R / ignicao."); Serial.println("====\n"); return; }
  delay(60);

  // atualiza o alvo com o endereco fisico do ECU capturado (0x11 na Montana)
  combos[2].tgt = kline_ecu; combos[3].tgt = kline_ecu;

  // ----- 2) Abrir sessao diagnostica (varios tipos) -----
  Serial.println("[KL] -- StartDiagnosticSession (0x10) --");
  uint8_t sess[][2] = { {0x10,0x81}, {0x10,0x85}, {0x10,0x89}, {0x10,0x92} };
  for (int s = 0; s < 4; s++) {
    klineServico("StartDiagSession", sess[s], 2, 0, 0x33, nullptr, 0, nullptr);
    delay(80);
  }
  klineServico("TesterPresent", tp, 1, 0, 0x33, nullptr, 0, nullptr); delay(60);

  // ----- 3) Mode 01 (EOBD) - PID 00 (suportados) e 0C (RPM) -----
  Serial.println("[KL] -- mode 01 (EOBD) --");
  uint8_t pids[2] = {0x00, 0x0C};
  for (int p = 0; p < 2; p++) {
    for (int i = 0; i < 4; i++) {
      uint8_t req[2] = {0x01, pids[p]};
      int r = klineServico("mode01", req, 2, combos[i].fmt, combos[i].tgt, d, 16, &nd);
      if (r == 1 && pids[p] == 0x0C && nd >= 3) {
        kline_fmt = combos[i].fmt; kline_tgt = combos[i].tgt;
        Serial.printf("[KL] >>> mode01 FUNCIONOU! RPM=%d (f%d t%02X)\n", ((d[1]*256)+d[2])/4, kline_fmt, kline_tgt);
        klineLerRestante(); Serial.println("====\n"); return;
      }
      delay(50);
    }
  }
  klineServico("TesterPresent", tp, 1, 0, 0x33, nullptr, 0, nullptr); delay(60);

  // ----- 4) GM: ReadDataByLocalIdentifier (servico 0x21) - live data proprietario -----
  //  Scanner de GM le RPM/temp/etc por 0x21 <LID>. Varre LIDs comuns e loga o que responde.
  Serial.println("[KL] -- GM servico 0x21 (ReadDataByLocalIdentifier) --");
  for (uint8_t lid = 0x01; lid <= 0x14; lid++) {
    uint8_t req[2] = {0x21, lid};
    bool achou = false;
    for (int i = 0; i < 4 && !achou; i++) {
      char nm[24]; snprintf(nm, sizeof(nm), "rdBLI 21 %02X", lid);
      int r = klineServico(nm, req, 2, combos[i].fmt, combos[i].tgt, d, 16, &nd);
      if (r == 1 && nd >= 1) { achou = true; Serial.printf("[KL] >>> 0x21 LID %02X respondeu %d bytes (f%d t%02X)\n", lid, nd, combos[i].fmt, combos[i].tgt); }
      delay(40);
    }
    klineServico("TesterPresent", tp, 1, 0, 0x33, nullptr, 0, nullptr); delay(30);
  }

  // ----- 5) GM: ReadDataByCommonIdentifier (servico 0x22) - alguns DIDs comuns -----
  Serial.println("[KL] -- GM servico 0x22 (ReadDataByCommonIdentifier) --");
  uint16_t dids[] = {0x0005, 0x000C, 0x1000, 0x1101, 0x1102};
  for (int k = 0; k < 5; k++) {
    uint8_t req[3] = {0x22, (uint8_t)(dids[k] >> 8), (uint8_t)(dids[k] & 0xFF)};
    char nm[24]; snprintf(nm, sizeof(nm), "rdBCI 22 %04X", dids[k]);
    klineServico(nm, req, 3, 0, combos[0].tgt, d, 16, &nd); delay(40);
  }

  Serial.println("[KL] Fim do sweep. Veja qual servico deu POSITIVO (esse eh o caminho GM).");
  Serial.println("[KL] Se tudo deu NRC 11/12 = ECU nao expoe live data por K-line (so codigos/emissao).");
  Serial.println("====\n");
}

// Pausa a tarefa do CAN durante o teste K-line (o driver CAN reinstalando
// atrapalhava o timing do init). Retoma no fim.
void klineDiagnostico() {
  TaskHandle_t hcan = xTaskGetHandle("CAN");
  if (hcan) { vTaskSuspend(hcan); twai_stop(); }   // silencia o CAN
  vTaskDelay(pdMS_TO_TICKS(100));
  klineDiagBody();
  if (hcan) { twai_start(); vTaskResume(hcan); }    // religa o CAN
}

// ============================================================
//  GM LIVE (KWP2000 servico 0x21 LID 0x01) - engenharia reversa do bloco
//  A Montana entrega TODA a telemetria do motor num bloco unico (0x21 0x01).
//  Este loop le o bloco e imprime cada byte com indice, marcando (> <) o que
//  mudou desde o ciclo anterior. Acelere -> descobre o RPM; deixe esquentar
//  -> descobre a temperatura; ande -> descobre a velocidade.
// ============================================================
// Le a resposta crua do 0x21 <lid> (fmt 0 "Cx", tgt 0x33). Copia os bytes de
// dados (apos "61 <lid>", sem o checksum final) em out. Retorna nº de bytes, -1 se nada.
static int klineGMRead(uint8_t lid, uint8_t* out, int maxout) {
  uint8_t req[6]; int rn = 0;
  req[rn++] = 0xC0 | 2; req[rn++] = 0x33; req[rn++] = 0xF1; req[rn++] = 0x21; req[rn++] = lid;
  req[rn] = klineCS(req, rn); rn++;
  klineSend(req, rn);
  uint8_t r[160]; int n = 0; uint32_t t0 = millis();
  while (n < (int)sizeof(r) && millis() - t0 < 400) { int b = klineRead(80); if (b < 0) break; r[n++] = b; }
  for (int i = 0; i + 1 < n; i++) {
    if (r[i] == 0x61 && r[i + 1] == lid) {
      int nd = n - (i + 2) - 1;            // -1 tira o checksum final
      if (nd < 0) nd = 0; if (nd > maxout) nd = maxout;
      for (int j = 0; j < nd; j++) out[j] = r[i + 2 + j];
      return nd;
    }
  }
  return -1;
}

static void klineGMLiveBody() {
  Serial.println("\n===== GM LIVE (0x21 LID 01) - mapa de variacao =====");
  Serial.println("PASSO A PASSO:");
  Serial.println(" 1) deixe em marcha lenta ~5s");
  Serial.println(" 2) ACELERE forte 2-3 vezes (ate ~3000+) e solte");
  Serial.println(" 3) digite qualquer coisa no Serial + Enter para PARAR");
  Serial.println("No fim ele mostra QUAIS bytes variaram (o que dispara ao acelerar = RPM).\n");
  kline_ok = false;
  if (!klineInitFast()) { Serial.println("[GM] fast init falhou (ligue o motor / cheque pull-up)"); Serial.println("====\n"); return; }
  delay(60);
  uint8_t prev[160]; int prevN = 0;
  uint8_t mn[160], mx[160]; int blkN = 0; bool temMinMax = false;
  uint8_t tp[1] = {0x3E};
  uint32_t t0 = millis();
  int ciclo = 0, semResp = 0;
  while (millis() - t0 < 180000) {                 // roda por ate 3 min
    if (Serial.available()) { while (Serial.available()) Serial.read(); break; }
    uint8_t d[160];
    int nd = klineGMRead(0x01, d, sizeof(d));
    if (nd < 0) {
      Serial.println("[GM] sem resposta (mantendo sessao viva...)");
      klineServico("TP", tp, 1, 0, 0x33, nullptr, 0, nullptr);
      if (++semResp >= 5) { Serial.println("[GM] sessao caiu, reinit..."); kline_ok = false; if (!klineInitFast()) break; semResp = 0; }
      delay(200); continue;
    }
    semResp = 0;
    // rastreia min/max de cada byte ao longo de toda a captura
    if (!temMinMax) { blkN = nd; for (int i = 0; i < nd && i < 160; i++) { mn[i] = mx[i] = d[i]; } temMinMax = true; }
    else { int lim = nd < blkN ? nd : blkN; for (int i = 0; i < lim; i++) { if (d[i] < mn[i]) mn[i] = d[i]; if (d[i] > mx[i]) mx[i] = d[i]; } }
    // print compacto do bloco (bytes que mudaram desde o ciclo anterior com > <)
    Serial.printf("[GM #%d]", ciclo);
    for (int i = 0; i < nd; i++) {
      bool mudou = (i < prevN && d[i] != prev[i]);
      Serial.printf(" %s%02X%s", mudou ? ">" : "", d[i], mudou ? "<" : "");
    }
    Serial.println();
    memcpy(prev, d, nd); prevN = nd;
    ciclo++;
    delay(300);
  }
  // ---- resumo: quais bytes variaram (amplitude) ----
  Serial.println("\n===== RESUMO: variacao por posicao =====");
  Serial.println("(posicao = indice no bloco depois do 61 01; amp grande + segue a aceleracao = RPM)");
  for (int i = 0; i < blkN; i++) {
    int amp = mx[i] - mn[i];
    if (amp > 0) Serial.printf(" [%02d]  %02X..%02X   amp=%d\n", i, mn[i], mx[i], amp);
  }
  // candidatos de RPM: pares 16-bit onde o par teve variacao
  Serial.println("[GM] pares 16-bit com variacao (val no ultimo ciclo):");
  for (int i = 0; i + 1 < blkN; i++) {
    int amp = (mx[i] - mn[i]) + (mx[i + 1] - mn[i + 1]);
    if (amp >= 4) {
      int v = (prev[i] << 8) | prev[i + 1];
      Serial.printf("  [%02d-%02d] = %d  (/4=%d)\n", i, i + 1, v, v / 4);
    }
  }
  Serial.println("===== fim GM LIVE =====\n");
}

void klineGMLive() {
  TaskHandle_t hcan = xTaskGetHandle("CAN");
  if (hcan) { vTaskSuspend(hcan); twai_stop(); }
  vTaskDelay(pdMS_TO_TICKS(100));
  klineGMLiveBody();
  if (hcan) { twai_start(); vTaskResume(hcan); }
}

// ============================================================
//  LEITURA DE CODIGOS DE FALHA (DTC) - KWP2000 (Montana/GM) e OBD mode 03
//  A Montana e GM-proprietaria (mode01 nao tem RPM), entao o mode03 padrao
//  provavelmente nao responde. Tentamos varios servicos e logamos o que vier.
// ============================================================
// Decodifica um DTC de 2 bytes no formato SAE (P0xxx/C/B/U) e imprime.
static void printDTC2(uint8_t hi, uint8_t lo) {
  const char letra[4] = {'P', 'C', 'B', 'U'};
  // formato SAE: letra + 1 digito(0-3) + 1 hex + 2 hex = ex. P1612 (nao P10612)
  Serial.printf("%c%d%X%02X", letra[(hi >> 6) & 3], (hi >> 4) & 3, hi & 0x0F, lo);
}

static void klineDTCBody() {
  Serial.println("\n===== LEITURA DE CODIGOS (DTC) =====");
  uint8_t d[40]; int nd;
  kline_ok = false;
  if (!klineInitFast()) { Serial.println("[DTC] fast init falhou (ligue a ignicao)"); Serial.println("====\n"); return; }
  delay(60);
  uint8_t tp[1] = {0x3E};
  uint8_t sess[2] = {0x10, 0x81};
  klineServico("StartDiagSession", sess, 2, 0, 0x33, nullptr, 0, nullptr); delay(60);

  // 1) KWP2000 servico 0x18 (readDTCByStatus): 18 <status> <grupoHi> <grupoLo>
  //    status 0x00 = todos; grupo FF00 = todos os grupos
  Serial.println("[DTC] -- KWP 0x18 (readDTCByStatus) --");
  uint8_t r18a[4] = {0x18, 0x00, 0xFF, 0x00};
  int res = klineServico("18 00 FF00", r18a, 4, 0, 0x33, d, sizeof(d), &nd);
  if (res == 1 && nd >= 1) {
    int qtd = d[0];
    Serial.printf("[DTC] >>> %d codigo(s):", qtd);
    for (int i = 0; i + 2 < nd && i / 3 < qtd; i += 3) { Serial.print(" "); printDTC2(d[1 + i], d[2 + i]); Serial.printf("(st=%02X)", d[3 + i]); }
    Serial.println();
  }
  delay(60);
  uint8_t r18b[4] = {0x18, 0x02, 0xFF, 0x00};   // status 0x02 = confirmados
  klineServico("18 02 FF00", r18b, 4, 0, 0x33, d, sizeof(d), &nd); delay(60);
  klineServico("TP", tp, 1, 0, 0x33, nullptr, 0, nullptr); delay(60);

  // 2) OBD mode 03 (request emissions DTCs) - resposta 0x43
  Serial.println("[DTC] -- OBD mode 03 --");
  uint8_t r03[1] = {0x03};
  res = klineServico("mode03", r03, 1, 0, 0x33, d, sizeof(d), &nd);
  if (res == 1) {
    Serial.print("[DTC] >>> mode03:");
    for (int i = 0; i + 1 < nd; i += 2) { if (d[i] == 0 && d[i + 1] == 0) continue; Serial.print(" "); printDTC2(d[i], d[i + 1]); }
    Serial.println();
  }
  delay(60);

  // 3) KWP servico 0x13 (readDTC legado) - alguns ECUs GM antigos
  Serial.println("[DTC] -- KWP 0x13 (readDTC legado) --");
  uint8_t r13[3] = {0x13, 0xFF, 0x00};
  klineServico("13 FF00", r13, 3, 0, 0x33, d, sizeof(d), &nd); delay(60);

  Serial.println("[DTC] Fim. O servico que deu POSITIVO com contagem/pares e o caminho de falhas.");
  Serial.println("[DTC] Para APAGAR (quando implementarmos): KWP 0x14 FF00 ou mode 04.");
  Serial.println("====\n");
}

void klineDTC() {
  TaskHandle_t hcan = xTaskGetHandle("CAN");
  if (hcan) { vTaskSuspend(hcan); twai_stop(); }
  vTaskDelay(pdMS_TO_TICKS(100));
  klineDTCBody();
  if (hcan) { twai_start(); vTaskResume(hcan); }
}

// Apaga os codigos de falha: KWP 0x14 (clearDiagnosticInformation) FF00 = todos.
static void klineDTCClearBody() {
  Serial.println("\n===== APAGAR CODIGOS (DTC) =====");
  uint8_t d[16]; int nd;
  kline_ok = false;
  if (!klineInitFast()) { Serial.println("[DTC] fast init falhou (ligue a ignicao)"); Serial.println("====\n"); return; }
  delay(60);
  uint8_t sess[2] = {0x10, 0x81};
  klineServico("StartDiagSession", sess, 2, 0, 0x33, nullptr, 0, nullptr); delay(60);
  // KWP 0x14 FF 00 (apaga todos os grupos) -> resposta 0x54
  uint8_t clr[3] = {0x14, 0xFF, 0x00};
  int r = klineServico("clear 14 FF00", clr, 3, 0, 0x33, d, sizeof(d), &nd);
  if (r == 1) Serial.println("[DTC] >>> APAGADO (0x54). Rode DTC de novo p/ confirmar 0 codigos.");
  else {
    delay(60);
    uint8_t m4[1] = {0x04};   // fallback: mode 04 (limpa DTC de emissao)
    if (klineServico("mode04", m4, 1, 0, 0x33, d, sizeof(d), &nd) == 1)
      Serial.println("[DTC] >>> APAGADO via mode04. Rode DTC p/ confirmar.");
    else Serial.println("[DTC] nao apagou (a ECU pode exigir motor desligado/condicoes).");
  }
  Serial.println("====\n");
}

void klineDTCClear() {
  TaskHandle_t hcan = xTaskGetHandle("CAN");
  if (hcan) { vTaskSuspend(hcan); twai_stop(); }
  vTaskDelay(pdMS_TO_TICKS(100));
  klineDTCClearBody();
  if (hcan) { twai_start(); vTaskResume(hcan); }
}

// Le DTCs via K-line KWP 0x18 (Montana/GM), preenche dtcs[][6], retorna qtd (-1 = erro).
// Roda INLINE na taskCAN (twai ja off no modo K-line); NAO suspende tarefas.
int klineLerDTCs(char dtcs[][6]) {
  if (!kline_ok) return -1;
  uint8_t d[48]; int nd = 0, num = 0;

  // 1) OBD mode 03 (padrao) — usa o FORMATO/ALVO detectado (ISO9141 ou KWP).
  //    Serve p/ VW/Gol, Honda-via-Kline e a maioria. Resposta positiva = 0x43.
  uint8_t m03[1] = {0x03};
  int res = klineServico("mode03", m03, 1, kline_fmt, kline_tgt, d, sizeof(d), &nd);
  if (res == 1) {
    for (int i = 0; i + 1 < nd && num < MAX_DTCS; i += 2) {
      if (d[i] == 0 && d[i + 1] == 0) continue;
      decodificaDTC(d[i], d[i + 1], dtcs[num]); num++;
    }
    if (num > 0) return num;
  }

  // 2) KWP 0x18 00 FF00 (readDTCByStatus) — GM/Montana e alguns KWP2000.
  //    Resposta positiva = 0x58, formato: <contagem> <hi lo status>...
  uint8_t r18[4] = {0x18, 0x00, 0xFF, 0x00};
  res = klineServico("18 00 FF00", r18, 4, kline_fmt, kline_tgt, d, sizeof(d), &nd);
  if (res == 1 && nd >= 1) {
    int qtd = d[0];
    for (int i = 1; i + 1 < nd && (i - 1) / 3 < qtd && num < MAX_DTCS; i += 3) {
      if (d[i] == 0 && d[i + 1] == 0) continue;
      decodificaDTC(d[i], d[i + 1], dtcs[num]); num++;
    }
    return num;
  }

  if (res == 0) return 0;   // ECU respondeu negativo = sem codigos
  return -1;                // sem resposta
}

// Apaga DTCs via K-line KWP 0x14 FF00 (Montana/GM). Roda inline. true = apagou.
bool klineApagarDTCs() {
  if (!kline_ok) return false;
  uint8_t req[8]; int rn = 0;
  req[rn++] = 0xC0 | 3; req[rn++] = 0x33; req[rn++] = 0xF1; req[rn++] = 0x14; req[rn++] = 0xFF; req[rn++] = 0x00;
  req[rn] = klineCS(req, rn); rn++;
  klineSend(req, rn);
  uint8_t r[24]; int n = 0; uint32_t t0 = millis();
  while (n < (int)sizeof(r) && millis() - t0 < 500) { int b = klineRead(100); if (b < 0) break; r[n++] = b; }
  for (int i = 0; i < n; i++) if (r[i] == 0x54) return true;   // 0x14+0x40 = positivo
  return false;
}

// Inicializa o K-line e descobre o formato de leitura (silencioso).
// true = pronto p/ ler PIDs (kline_fmt/kline_tgt setados). Chamado pela taskCAN.
bool klineIniciar() {
  uint8_t d[8];
  kline_gm = false;
  // 1) KWP2000 fast init
  kline_ok = false;
  if (klineInitFast()) {
    delay(60);
    struct { uint8_t fmt, tgt; } t[] = { {0,0x33}, {1,0x33}, {0,kline_ecu}, {1,kline_ecu} };
    for (int i = 0; i < 4; i++) { if (klinePID(0x0C, t[i].fmt, t[i].tgt, d, 8, false) >= 2) { kline_fmt = t[i].fmt; kline_tgt = t[i].tgt; return true; } delay(40); }
    // 1b) GM (Montana): mode01 nao tem RPM -> le o bloco 0x21 LID 01 por offset
    uint8_t blk[160];
    int nb = klineGMRead(0x01, blk, sizeof(blk));
    if (nb > gm_off_rpm + 1) { kline_gm = true; Serial.printf("[KL] >>> modo GM (0x21 LID01, %d bytes): RPM no offset %d\n", nb, gm_off_rpm); return true; }
  }
  // 2) ISO 9141-2 (5-baud) - Gol/VW antigo, etc.
  delay(1000);
  kline_ok = false;
  if (klineInit5baud()) {
    delay(60);
    struct { uint8_t fmt, tgt; } t[] = { {2,0x6A}, {0,0x33} };
    for (int i = 0; i < 2; i++) { if (klinePID(0x0C, t[i].fmt, t[i].tgt, d, 8, false) >= 2) { kline_fmt = t[i].fmt; kline_tgt = t[i].tgt; return true; } delay(40); }
  }
  kline_ok = false;
  return false;
}

// ============================================================
//  STANDBY (substitui o deep sleep)
// ============================================================
bool canAtivo(uint16_t ms) {
  uint32_t t0 = millis();
  while (millis() - t0 < ms) {
    twai_message_t rx;
    if (twai_receive(&rx, pdMS_TO_TICKS(50)) == ESP_OK) return true;
  }
  return false;
}

void entrarEmStandby() {
  Serial.println("[STANDBY] entrando (carro desligado)");
  salvarHodometro();   // garante km + tempo de motor gravados antes de dormir
  twai_stop();
  twai_driver_uninstall();
  contando_pra_sleep = false;
  estadoAtual = STANDBY;
}

void acordarDoStandby() {
  Serial.println("[STANDBY] tensao alta sustentada -> acordando");
  instalarCAN(obd_baud);
  pagina_atual = 0; pagina_anterior = 255;   // forca redesenho do dashboard
  inicio_rpm_baixo = millis(); contando_pra_sleep = false;
  estadoAtual = OPERANDO;
}

void acordarManual() {
  Serial.println("[STANDBY] acordado pelo botao MENU");
  instalarCAN(obd_baud);
  pagina_atual = 0; pagina_anterior = 255;
  inicio_rpm_baixo = millis(); contando_pra_sleep = false;
  estadoAtual = OPERANDO;
}

// Sondagem rapida: instala o CAN, pergunta RPM e desinstala. true = motor rodando.
bool motorRodandoProbe() {
  if (!instalarCAN(obd_baud)) return false;
  vTaskDelay(pdMS_TO_TICKS(50));
  int rpm = PID_ERRO;
  for (int i = 0; i < 2 && rpm <= 0; i++) rpm = lerPID_int(0x0C, f_rpm);
  twai_stop(); twai_driver_uninstall();
  return rpm > 0;
}

void loopStandby() {
  if (pedido_acordar) { pedido_acordar = false; acordarManual(); return; }
  float tensao = lerTensaoADC();   // GPIO36, sempre ativo
  static uint8_t alta = 0;
  static float v_min = 99;
  static uint32_t ult_probe = 0;
  if (tensao > 0 && tensao < v_min) v_min = tensao;
  if (tensao > TENSAO_WAKE) {
    if (++alta >= 3) { alta = 0; v_min = 99; acordarDoStandby(); return; }  // ~1,5s acima de 13V = alternador
  } else {
    alta = 0;
    bool degrau    = (v_min < 90) && (tensao - v_min >= 0.4f);
    bool periodica = (millis() - ult_probe > 60000UL) && tensao >= 12.0f;
    if (degrau || periodica) {
      ult_probe = millis();
      if (motorRodandoProbe()) { v_min = 99; acordarDoStandby(); return; }
    }
  }
  vTaskDelay(pdMS_TO_TICKS(500));  // checa a cada 0,5s
}

// ============================================================
//  Task CAN
// ============================================================
void taskCAN(void* param) {
  Serial.println("[Task CAN] v2 iniciada");
  debugLog(0, "Task CAN start");
  auto contaPIDs = []() { int n = 0; for (int i = 1; i < 256; i++) if (pid_suportado[i]) n++; return n; };
  if (obd_ok) descobrirPIDs();   // so descobre PIDs (transmite) se houver CAN de verdade
  uint32_t ultimo_calculo_odo = millis();
  uint32_t ciclo = 0;
  uint32_t ultima_redescoberta = millis();
  static DadosCarro ultimo = {PID_ERRO, PID_ERRO, PID_ERRO, PID_ERRO, PID_ERRO, PID_ERRO, PID_ERRO, PID_ERRO, PID_ERRO, PID_ERRO, PID_ERRO, -1.0};
  for (;;) {
    STAGE_CAN("topo");
    // ===== STANDBY: so monitora tensao/botao, CAN desligado =====
    if (estadoAtual == STANDBY) { loopStandby(); continue; }

    // ===== SEM CAN: usa K-LINE se disponivel; senao fica PASSIVO (nao transmite no CAN) =====
    if (!obd_ok) {
      static uint32_t ult_redetect = 0;
      static int kfalhas = 0;
      uint8_t d8[8];

      // ---- K-LINE como fonte de dados do painel ----
      // GENTIL: 1 PID por ciclo, com folga, e SEM re-init agressivo. Ler colado/reiniciar
      // toda hora perturbava o ECU (motor caia no limp / pedal sem resposta). Aqui a
      // atividade no barramento e minima: um pedido a cada ~350ms.
      if (kline_ativo) {
        int r; bool ok1 = false;
        uint8_t pid = 0;
        if (kline_gm) {
          // ---- Montana / GM: um pedido 0x21 LID01 traz RPM + temp de uma vez ----
          uint8_t blk[160];
          int nb = klineGMRead(0x01, blk, sizeof(blk));
          if (nb > gm_off_rpm + 1) {
            ok1 = true; r = nb;
            ultimo.rpm = ((blk[gm_off_rpm] * 256) + blk[gm_off_rpm + 1]) / 4;
            if (gm_off_temp >= 0 && gm_off_temp < nb) { gm_last_temp_byte = blk[gm_off_temp]; ultimo.temp_motor = (int)(gm_temp_a * gm_last_temp_byte + gm_temp_b); }
            if (gm_off_vel  >= 0 && gm_off_vel  < nb) ultimo.velocidade = blk[gm_off_vel];
            // grava min/max de cada byte (caca a velocidade dirigindo, sem laptop -> GMDUMP depois)
            int lim = (nb < 128) ? nb : 128;
            if (gm_rec_n == 0) { gm_rec_n = lim; for (int i = 0; i < lim; i++) { gm_mn[i] = gm_mx[i] = blk[i]; } }
            else { if (lim > gm_rec_n) lim = gm_rec_n; for (int i = 0; i < lim; i++) { if (blk[i] < gm_mn[i]) gm_mn[i] = blk[i]; if (blk[i] > gm_mx[i]) gm_mx[i] = blk[i]; } }
            gm_rec_amostras++;
          } else r = -1;
        } else {
          // ---- ISO 9141 / KWP com mode01 (Gol etc.): 1 PID por ciclo ----
          static uint8_t kpid = 0;

          // KLRAW: dump cru dos bytes de temperatura (diagnostico). Roda aqui pois
          // e o unico lugar com acesso seguro a UART K-line.
          if (probe_klraw) {
            probe_klraw = false;
            uint8_t dbg[8];
            const uint8_t plist[] = {0x05, 0x5C, 0x0F, 0x0C};
            const char* pnome[]  = {"05 agua", "5C oleo", "0F ar-adm", "0C rpm(ref)"};
            Serial.println("\n===== KLRAW (bytes crus - K-line) =====");
            for (int i = 0; i < 4; i++) {
              Serial.printf("[KLRAW] PID %s:\n", pnome[i]);
              klinePID(plist[i], kline_fmt, kline_tgt, dbg, 8, true);  // log=true -> imprime req + resp cru
              vTaskDelay(pdMS_TO_TICKS(80));
            }
            Serial.println("Byte da agua = 1o valor logo DEPOIS de '41 05'. Me manda essas linhas.");
            Serial.println("====\n");
          }
          // SO PIDs essenciais e suportados. 0x2F (combustivel) FORA da leitura continua:
          // pedir PID nao suportado estava envenenando a sessao ISO 9141 (leituras seguintes falhavam).
          pid = (kpid == 0) ? 0x0C : (kpid == 1) ? 0x05 : 0x0D;
          r = klineReadPID(pid, d8, 8);
          if (r >= 1) {
            ok1 = true;
            if      (pid == 0x0C && r >= 2) ultimo.rpm = ((d8[0]*256)+d8[1])/4;
            else if (pid == 0x05) {
              // O loop rapido K-line as vezes devolve byte-lixo (ex.: -4C, -16C).
              // A leitura ISOLADA (KLRAW) le certo, entao filtramos o lixo:
              //  - faixa sã (-30..135C)
              //  - sem salto brusco (>30C entre leituras: agua nao muda tao rapido)
              //  - com motor LIGADO (rpm>400) a agua nunca fica < 10C
              // SEM AUTO-ESCALA. O PID 05 padrao (mode 01) e SEMPRE T = A - 40 (SAE).
              // A auto-troca 40<->0 que existia aqui trocava o offset pra 0 durante o
              // AQUECIMENTO normal (agua 30-45C) e passava a mostrar o byte cru (ex.:
              // 105 em vez de 105-40=65). Removida. O offset fica fixo em kline_temp_off
              // (padrao 40, carregado da NVS). Carro raro que manda o valor JA em C
              // (alguns Gol/VW) se ajusta UMA vez com o comando KTEMPOFF 0 (persiste).
              int tc = d8[0] - kline_temp_off;   // offset calibravel via KTEMPOFF; padrao 40 (SAE)
              static int temp_bom = -1000, pend = 0, pendN = 0;
              if (tc >= -40 && tc <= 140) {                 // faixa fisicamente possivel
                if (temp_bom <= -1000 || abs(tc - temp_bom) <= 25) {
                  ultimo.temp_motor = tc; temp_bom = tc; pendN = 0;   // variacao normal: aceita ja
                } else {
                  // salto grande: so aceita se PERSISTIR (3 leituras parecidas). Isso mata o
                  // pico-lixo isolado, mas segue mudanca real (recalibracao, sensor reconectado).
                  if (pendN > 0 && abs(tc - pend) <= 8) pendN++; else { pend = tc; pendN = 1; }
                  if (pendN >= 3) { ultimo.temp_motor = tc; temp_bom = tc; pendN = 0; }
                }
              }
            }
            else if (pid == 0x0D)           ultimo.velocidade = d8[0];
          }
          kpid = (kpid + 1) % 3;
        }
        ultimo.tensao = lerTensaoADC();
        // LOG detalhado p/ diagnostico (correlacionar com o corte do motor)
        Serial.printf("[KL] t=%lums %s pid=%02X r=%d %s rpm=%d temp=%d fails=%d\n",
                      millis(), kline_gm ? "GM" : "  ", pid, r, (ok1 ? "OK" : "--"), ultimo.rpm, ultimo.temp_motor, kfalhas);
        if (ok1) kfalhas = 0;
        else if (++kfalhas >= 12) {
          kline_ativo = false; kline_ok = false;
          ult_redetect = millis();   // segura o proximo re-init por 20s (menos re-init = menos corte do motor)
          Serial.println("[KL] >>> SESSAO PERDIDA (proximo re-init em 20s; mantendo ultimo valor na tela)");
        }
        // ---- menu de falhas do VEICAN via K-line (Montana): ler / apagar na tela ----
        if (diag_solicitar_leitura) {
          diag_solicitar_leitura = false;
          char dtcs_buf[MAX_DTCS][6];
          int n = klineLerDTCs(dtcs_buf);
          if (n < 0) { diag_num_dtcs = 0; }
          else { for (int i = 0; i < n; i++) memcpy(diag_dtcs[i], dtcs_buf[i], 6); diag_num_dtcs = n; if (rtc_ok) diag_ultima_leitura = rtcNow().unixtime();
                 for (int i = 0; i < n && i < MAX_DTCS; i++) evtRegistrar(0, 0, diag_dtcs[i]); }   // v7: historico
          diag_estado = DIAG_ESTADO_RESULTADO;
        }
        if (diag_solicitar_apagar) {
          diag_solicitar_apagar = false;
          if (klineApagarDTCs()) { diag_num_dtcs = 0; if (rtc_ok) diag_ultima_leitura = rtcNow().unixtime(); diag_estado = DIAG_ESTADO_APAGADO_OK; }
          else { diag_estado = DIAG_ESTADO_MENU; }
        }
        if (xSemaphoreTake(mutex_dados, pdMS_TO_TICKS(50)) == pdTRUE) { dados_publicos = ultimo; xSemaphoreGive(mutex_dados); }
        ultimo_heartbeat = millis();
        vTaskDelay(pdMS_TO_TICKS(80));    // P3 ~80ms (funcionava no teste standalone; CAN agora off)
        continue;
      }

      // ---- sem CAN e sem K-line: tenta detectar (CAN 1x, depois K-line) a cada 20s ----
      if (ult_redetect == 0 || millis() - ult_redetect > 20000) {
        ult_redetect = millis();
        if (detectarProtocoloOBD()) { descobrirPIDs(); ultima_redescoberta = millis(); }
        else {
          // sem CAN: DESLIGA o twai por completo (ele interfere na UART do K-line) e tenta K-line
          twai_stop(); twai_driver_uninstall();
          if (klineIniciar()) { kline_ativo = true; kfalhas = 0; Serial.println("[KL] >>> K-LINE ATIVO como fonte do painel (CAN desligado)"); }
        }
      }
      // sem fonte conectada: nao deixa o menu de falhas travar em "lendo"
      if (diag_solicitar_leitura) { diag_solicitar_leitura = false; diag_num_dtcs = 0; diag_estado = DIAG_ESTADO_RESULTADO; }
      if (diag_solicitar_apagar)  { diag_solicitar_apagar = false; diag_estado = DIAG_ESTADO_MENU; }
      ultimo.rpm = 0; ultimo.velocidade = 0;
      ultimo.tensao = lerTensaoADC();
      if (xSemaphoreTake(mutex_dados, pdMS_TO_TICKS(50)) == pdTRUE) { dados_publicos = ultimo; xSemaphoreGive(mutex_dados); }
      ultimo_heartbeat = millis();
      vTaskDelay(pdMS_TO_TICKS(500));
      continue;
    }

    if (contaPIDs() == 0 && (millis() - ultima_redescoberta > 3000)) {
      ultima_redescoberta = millis();
      Serial.println("[CAN] Nenhum PID ainda, re-descobrindo...");
      descobrirPIDs();
    }
    if (fuel_metodo == 0 && contaPIDs() > 0) {
      STAGE_CAN("detectFuel");
      detectarMetodoCombustivel();
    }
    twai_status_info_t status;
    if (twai_get_status_info(&status) == ESP_OK) {
      if (status.state == TWAI_STATE_BUS_OFF) {
        Serial.println("[CAN] BUS-OFF! recuperando...");
        g_busoff_count++;   // H7: contabiliza p/ diagnostico (STATS)
        debugLog(2, "CAN BUS-OFF", status.tx_error_counter, status.rx_error_counter);
        twai_initiate_recovery();
        vTaskDelay(pdMS_TO_TICKS(200));
      }
      if (status.state == TWAI_STATE_STOPPED) {
        Serial.println("[CAN] STOPPED, reiniciando...");
        debugLog(1, "CAN STOPPED");
        twai_start();
        vTaskDelay(pdMS_TO_TICKS(100));
      }
    }
    int valor;
    static int falhas_rpm = 0;  // leituras seguidas sem resposta
    static uint32_t ult_resp_ok = millis();  // ultima resposta valida do CAN

    // ===== RPM: le e PUBLICA JA (responsivo — nao espera os PIDs lentos p/ mostrar aceleracao) =====
    STAGE_CAN("rpm");
    valor = lerPID_int(0x0C, f_rpm);
    if (valor < 0) { vTaskDelay(pdMS_TO_TICKS(12)); valor = lerPID_int(0x0C, f_rpm); }  // 1 retry
    if (valor >= 0) { ultimo.rpm = valor; falhas_rpm = 0; ult_resp_ok = millis(); }
    else if (++falhas_rpm >= 5) {
      // so zera (motor desligado) se a TENSAO confirmar; senao segura a ultima leitura (barramento cheio)
      if (ultimo.tensao > 0 && ultimo.tensao < TENSAO_WAKE) { ultimo.rpm = 0; ultimo.velocidade = 0; }
      else falhas_rpm = 5;
    }
    if (xSemaphoreTake(mutex_dados, pdMS_TO_TICKS(20)) == pdTRUE) { dados_publicos = ultimo; xSemaphoreGive(mutex_dados); }  // <<< RPM na tela ja
    vTaskDelay(pdMS_TO_TICKS(12));

    // ===== velocidade: toda volta (odometro + tela) =====
    valor = lerPID_int(0x0D, f_vel); if (valor >= 0) { ultimo.velocidade = valor; ult_resp_ok = millis(); }
    vTaskDelay(pdMS_TO_TICKS(12));

    // ===== 1 PID LENTO por ciclo, revezando (temp / tensao / combustivel) — mantem o RPM rapido =====
    STAGE_CAN("pidLento");
    switch (ciclo % 3) {
      case 0: {  // ===== TEMPERATURA (robusta contra alarme falso) =====
        // Sempre tenta o 0x05 (padrao). SO cai pro 0x67 se o 0x05 sumir por MUITAS
        // leituras seguidas (=nao suportado), NUNCA num engasgo isolado (ar-cond.,
        // barramento cheio) — era isso que travava no 0x67 e marcava temp errada.
        static int falha05 = 0;
        int t = lerPID_int(0x05, f_temp);
        if (t >= -40) {
          falha05 = 0;
        } else if (++falha05 >= 12) {
          uint8_t d67[8], l67 = 0;
          if (obdRequest(0x67, d67, &l67) && l67 >= 2) {
            int t67 = d67[1] - 40;
            if (t67 >= -30 && t67 <= 130) t = t67;   // aceita 0x67 so na faixa fisica
          }
        }
        // FILTRO anti-glitch: coolant fica entre -30 e 130 e MUDA DEVAGAR. Um pulo
        // isolado (>12C de uma leitura pra outra) e descartado, a menos que se
        // repita 3x — evita o "TEMP ALTA" falso de um frame corrompido.
        if (t >= -30 && t <= 130) {
          static int temp_ok = -1000;
          static uint8_t susp = 0;
          int d = t - temp_ok; if (d < 0) d = -d;
          if (temp_ok <= -1000 || d <= 12) {
            temp_ok = t; susp = 0;
            ultimo.temp_motor = t; ult_resp_ok = millis();
          } else if (++susp >= 3) {           // pulo sustentado 3x -> aceita
            temp_ok = t; susp = 0;
            ultimo.temp_motor = t; ult_resp_ok = millis();
          }
          // senao: ignora este frame, mantem a ultima temperatura boa
        }
        break;
      }
      case 1: { // tensao (0x42, senao ADC)
        float v = lerPID_float(0x42, f_tensao);
        if (v < 0) v = lerTensaoADC();
        if (v >= 0) ultimo.tensao = v;
        break;
      }
      case 2:   // combustivel
        valor = lerCombustivelPct(); if (valor >= 0) ultimo.combust = valor;
        break;
    }
    vTaskDelay(pdMS_TO_TICKS(12));

    // desconectou / perdeu CAN: apos ~3s sem resposta limpa a tela (nao congela)
    if ((millis() - ult_resp_ok) > 3000) {
      ultimo.rpm = 0; ultimo.velocidade = 0; ultimo.temp_motor = PID_ERRO; ultimo.combust = -1;
    }
    if (xSemaphoreTake(mutex_dados, pdMS_TO_TICKS(20)) == pdTRUE) { dados_publicos = ultimo; xSemaphoreGive(mutex_dados); }
    // auto-recuperacao: so reinstala apos travamento LONGO real (15s sem resposta com motor ligado)
    if (ultimo.tensao > TENSAO_WAKE && (millis() - ult_resp_ok) > 15000) {
      Serial.println("[CAN] travado 15s -> reiniciando driver");
      reiniciarCAN();
      ult_resp_ok = millis();
    }
    if (diag_solicitar_leitura) {
      diag_solicitar_leitura = false;
      char dtcs_buf[MAX_DTCS][6];
      int n = lerDTCs(dtcs_buf);
      if (n < 0) { diag_num_dtcs = 0; }
      else {
        for (int i = 0; i < n; i++) memcpy(diag_dtcs[i], dtcs_buf[i], 6);
        diag_num_dtcs = n;
        diag_ultima_leitura = rtcNow().unixtime();
        for (int i = 0; i < n && i < MAX_DTCS; i++) evtRegistrar(0, 0, diag_dtcs[i]);   // v7: historico
      }
      diag_estado = DIAG_ESTADO_RESULTADO;
    }
    if (diag_solicitar_apagar) {
      diag_solicitar_apagar = false;
      bool ok = apagarDTCs();
      if (ok) { diag_num_dtcs = 0; diag_ultima_leitura = rtcNow().unixtime(); diag_estado = DIAG_ESTADO_APAGADO_OK; }
      else { diag_estado = DIAG_ESTADO_MENU; }
    }
    if (probe_pedir_fuel) { probe_pedir_fuel = false; probeFuel2F(); }
    if (probe_pedir_m22)  { probe_pedir_m22 = false;  runProbeM22(); }
    if (probe_candump) {
      probe_candump = false;
      Serial.println("\n===== CANDUMP (frames do barramento, ~2.5s) =====");
      static struct { uint32_t id; uint8_t d[8]; uint8_t len; } fr[64];
      int nf = 0;
      uint32_t t0 = millis();
      while (millis() - t0 < 2500) {
        twai_message_t rx;
        if (twai_receive(&rx, pdMS_TO_TICKS(20)) == ESP_OK) {
          int idx = -1;
          for (int i = 0; i < nf; i++) if (fr[i].id == rx.identifier) { idx = i; break; }
          if (idx < 0 && nf < 64) { idx = nf++; fr[idx].id = rx.identifier; }
          if (idx >= 0) { fr[idx].len = rx.data_length_code; for (int j = 0; j < 8; j++) fr[idx].d[j] = rx.data[j]; }
        }
      }
      for (int i = 0; i < nf; i++) {
        Serial.printf("[DUMP] %03lX:", (unsigned long)fr[i].id);
        for (int j = 0; j < fr[i].len; j++) Serial.printf(" %02X", fr[i].d[j]);
        Serial.println();
      }
      Serial.printf("[DUMP] %d IDs. Ache o byte do combustivel (tanque ~70%%: procure ~B3 se 0-255, ~46 se 0-100, ~23-2D se litros).\n", nf);
      Serial.println("====\n");
    }
    if (probe_fuelfind) {
      probe_fuelfind = false;
      int pct = fuelfind_pct; if (pct < 1) pct = 1; if (pct > 100) pct = 100;
      Serial.printf("\n===== FUELFIND (tanque ~%d%%) — bytes ESTAVEIS que casam com esse nivel =====\n", pct);
      // Guarda min/max de cada byte de cada ID por ~3s. Combustivel = byte ESTAVEL
      // (quase nao muda) e no valor do nivel. Isso descarta RPM/velocidade/pedal.
      static struct { uint32_t id; uint8_t mn[8], mx[8], len; } ff[48];
      int nf = 0;
      uint32_t t0 = millis();
      while (millis() - t0 < 3000) {
        twai_message_t rx;
        if (twai_receive(&rx, pdMS_TO_TICKS(20)) == ESP_OK) {
          int idx = -1;
          for (int i = 0; i < nf; i++) if (ff[i].id == rx.identifier) { idx = i; break; }
          if (idx < 0 && nf < 48) { idx = nf++; ff[idx].id = rx.identifier; ff[idx].len = rx.data_length_code;
            for (int j = 0; j < 8; j++) { ff[idx].mn[j] = 255; ff[idx].mx[j] = 0; } }
          if (idx >= 0) for (int j = 0; j < rx.data_length_code && j < 8; j++) {
            uint8_t v = rx.data[j];
            if (v < ff[idx].mn[j]) ff[idx].mn[j] = v;
            if (v > ff[idx].mx[j]) ff[idx].mx[j] = v;
          }
        }
      }
      int t255 = pct * 255 / 100, cand = 0;
      for (int i = 0; i < nf; i++) for (int j = 0; j < ff[i].len; j++) {
        int v = ff[i].mn[j], jit = ff[i].mx[j] - ff[i].mn[j];
        if (jit > 4) continue;                              // so o que ficou ESTAVEL
        bool m255 = (v > t255 - 14) && (v < t255 + 14);     // escala 0-255
        bool m100 = (v > pct - 6) && (v < pct + 6);         // escala 0-100
        bool mlit = (v >= pct * 40 / 100) && (v <= pct * 60 / 100) && v >= 8;  // ~litros (tanque 40-60L)
        if (m255 || m100 || mlit) {
          Serial.printf("[FF] %03lX.%d = %d", (unsigned long)ff[i].id, j, v);
          if (m255) Serial.printf("  (/255=%d%%)", v * 100 / 255);
          if (m100) Serial.printf("  (/100=%d%%)", v);
          if (mlit) Serial.printf("  (~%dL)", v);
          Serial.printf("  -> HYFUEL %lX %d %s\n", (unsigned long)ff[i].id, j, m100 ? "100" : "255");
          cand++;
        }
      }
      Serial.printf("[FF] %d IDs, %d candidatos. Confirme: rode FUELFIND de novo com o tanque em OUTRO nivel; o do combustivel muda junto.\n", nf, cand);
      Serial.println("====\n");
    }
    if (probe_fuelwatch) {
      probe_fuelwatch = false;
      Serial.println("\n===== FUELWATCH (candidatos de combustivel ao vivo) =====");
      Serial.println("ANDE p/ variar o tanque e veja qual acompanha o PONTEIRO. Tecla p/ parar.");
      struct { uint32_t id; uint8_t b; } cand[] = { {0x329,1}, {0x280,3}, {0x130,1}, {0x260,4}, {0x545,4}, {0x2A0,4}, {0x131,4}, {0x43F,1} };
      const int NCAND = 8;
      uint32_t t0 = millis();
      while (millis() - t0 < 120000) {
        if (Serial.available()) { while (Serial.available()) Serial.read(); break; }
        Serial.print("[FW]");
        for (int i = 0; i < NCAND; i++) {
          int v = lerFrameByte(cand[i].id, cand[i].b, 150);
          if (v >= 0) Serial.printf("  %lX.%d=%d(%d%%)", (unsigned long)cand[i].id, cand[i].b, v, v * 100 / 255);
          else        Serial.printf("  %lX.%d=--", (unsigned long)cand[i].id, cand[i].b);
        }
        Serial.println();
        vTaskDelay(pdMS_TO_TICKS(500));
      }
      Serial.println("===== fim FUELWATCH =====\n");
    }
    if (probe_pid_pedido >= 0) {
      uint8_t p = (uint8_t)probe_pid_pedido; probe_pid_pedido = -1;
      uint8_t d[8], len = 0;
      bool sup = pid_suportado[p];
      Serial.printf("[PID] %02X (suportado=%d): ", p, sup);
      if (obdRequest(p, d, &len)) {
        for (int i = 0; i < len; i++) Serial.printf("%02X ", d[i]);
        Serial.printf(" | A=%d (A-40=%d)  AB/4=%d\n", d[0], d[0] - 40, ((d[0] * 256) + d[1]) / 4);
      } else Serial.println("SEM RESPOSTA");
    }
    if (probe_temp_scan) {
      probe_temp_scan = false;
      // PIDs de temperatura (mode 01). Formula padrao = A-40, exceto onde indicado.
      struct { uint8_t pid; const char* nome; } tp[] = {
        {0x05, "Agua (padrao)"}, {0x67, "Agua sensor"}, {0x5C, "Oleo"},
        {0x46, "Ar ambiente"}, {0x0F, "Ar admissao"}, {0x68, "Ar admissao multi"}
      };
      Serial.println("\n===== TEMPSCAN (procurando a temperatura) =====");
      for (int i = 0; i < 6; i++) {
        uint8_t d[8], len = 0;
        Serial.printf("[T] PID %02X %-16s: ", tp[i].pid, tp[i].nome);
        if (obdRequest(tp[i].pid, d, &len)) { Serial.printf("A=%d -> %dC (A-40)\n", d[0], d[0] - 40); }
        else Serial.println("sem resposta");
        vTaskDelay(pdMS_TO_TICKS(60));
      }
      Serial.println("O PID que der um valor plausivel (~70-95C com motor quente) e o da agua.");
      Serial.println("====\n");
    }

    // ===== Hodometro conta APENAS quando velocidade > 0 (nao RPM) =====
    uint32_t agora = millis();
    uint32_t delta_ms = agora - ultimo_calculo_odo;
    if (delta_ms >= 1000) {
      ultimo_calculo_odo = agora;
      if (ultimo.rpm > 0) {  // tempo de motor ligado
        static uint16_t seg_save = 0;
        if (xSemaphoreTake(mutex_hodometro, pdMS_TO_TICKS(50)) == pdTRUE) {
          segundos_motor_total++;
          xSemaphoreGive(mutex_hodometro);
        }
        if (++seg_save >= 60) { seg_save = 0; salvarHodometro(); }  // persiste a cada 60s
      }
      // H8 (#43): filtro anti-salto. So integra distancia com velocidade PLAUSIVEL
      // (1..250 km/h) e amostra RECENTE (delta<=3s). Um frame corrompido (ex.: 255)
      // ou um travamento longo nao pode inflar o hodometro.
      if (ultimo.velocidade > 0 && ultimo.velocidade <= 250 && delta_ms <= 3000) {
        float seg = delta_ms / 1000.0;
        float km100_inc = (ultimo.velocidade * seg * 100.0) / 3600.0 * km_cal;
        static float km100_residual = 0;
        km100_residual += km100_inc;
        if (xSemaphoreTake(mutex_hodometro, pdMS_TO_TICKS(50)) == pdTRUE) {
          if (km100_residual >= 1.0) {
            uint32_t inteiro = (uint32_t)km100_residual;
            km_acumulado_x100 += inteiro;
            km100_residual -= inteiro;
          }
          if (km_acumulado_x100 >= 100) {
            km_total_x100 += km_acumulado_x100; km_acumulado_x100 = 0;
            xSemaphoreGive(mutex_hodometro);
            salvarHodometro();
          } else { xSemaphoreGive(mutex_hodometro); }
        }
      }
    }
    // ===== Entrada em standby: tensao baixa E motor parado (rpm 0), sustentado por 40s =====
    // DESLIGADO TEMPORARIAMENTE p/ testes (a leitura VBAT da Rev3 esta lendo ~4V e mandava
    // o aparelho dormir achando "carro desligado"). Reativar quando o VBAT estiver calibrado.
#if 0
    if (ultimo.tensao > 0 && ultimo.tensao < TENSAO_WAKE && ultimo.rpm <= 0) {
      if (!contando_pra_sleep) { contando_pra_sleep = true; inicio_rpm_baixo = millis(); }
      else if (millis() - inicio_rpm_baixo >= TEMPO_STANDBY_MS) { entrarEmStandby(); continue; }
    } else {
      contando_pra_sleep = false;
    }
#else
    contando_pra_sleep = false;
#endif
    ciclo++;
    ultimo_heartbeat = millis();
    vTaskDelay(pdMS_TO_TICKS(400));
  }
}

// ============================================================
//  Task Logger
// ============================================================
void taskLogger(void* param) {
  Serial.println("[Task Logger] iniciada");
  uint32_t ultimo_periodico = 0;
  int rpm_anterior = -1, tps_anterior = -1;
  uint32_t inicio_alto_rpm = 0;
  bool alto_rpm_ativo = false;
  vTaskDelay(pdMS_TO_TICKS(5000));
  for (;;) {
    DadosCarro d;
    if (xSemaphoreTake(mutex_dados, pdMS_TO_TICKS(50)) == pdTRUE) { d = dados_publicos; xSemaphoreGive(mutex_dados); }
    else { vTaskDelay(pdMS_TO_TICKS(500)); continue; }
    uint32_t agora = millis();
    bool gravou = false;
    if (rpm_anterior >= 0 && rpm_anterior < 200 && d.rpm > 300) { gravarRegistro(1); gravou = true; }
    if (!gravou && rpm_anterior > 300 && d.rpm >= 0 && d.rpm < 100) { gravarRegistro(2); gravou = true; }
    if (d.rpm > 4000) {
      if (!alto_rpm_ativo) { inicio_alto_rpm = agora; alto_rpm_ativo = true; }
      else if (!gravou && agora - inicio_alto_rpm > 2000) { gravarRegistro(3); alto_rpm_ativo = false; gravou = true; }
    } else { alto_rpm_ativo = false; }
    if (!gravou && tps_anterior >= 0 && d.tps - tps_anterior > 50) {
      // intervalo minimo: dirigindo na cidade o TPS pula direto -> gravava na
      // EEPROM sem parar (I2C martelado + desgaste). Agora no maximo 1x/5s.
      static uint32_t ult_tps = 0;
      if (agora - ult_tps > 5000) { gravarRegistro(4); ult_tps = agora; gravou = true; }
    }
    if (!gravou && d.tensao > 0 && d.tensao < 12.0) {
      static uint32_t ult_alerta = 0;
      if (agora - ult_alerta > 60000) { gravarRegistro(5); ult_alerta = agora; gravou = true; }
    }
    if (!gravou && d.temp_motor > 105) {
      static uint32_t ult_temp = 0;
      if (agora - ult_temp > 60000) { gravarRegistro(6); ult_temp = agora; gravou = true; }
    }
    if (!gravou && agora - ultimo_periodico > 30000) { gravarRegistro(0); ultimo_periodico = agora; }
    rpm_anterior = d.rpm; tps_anterior = d.tps;
    vTaskDelay(pdMS_TO_TICKS(500));
  }
}

// ============================================================
//  Task Alertas
// ============================================================
void taskAlertas(void* param) {
  Serial.println("[Task Alertas] iniciada");
  vTaskDelay(pdMS_TO_TICKS(5000));
  uint32_t bat_baixa_desde = 0, alt_ruim_desde = 0;
  // v7: memoria de borda p/ gravar cada EPISODIO uma vez no historico
  bool bat_logado = false, alt_logado = false;
  uint32_t temp_alta_desde = 0; bool temp_logada = false;
  uint32_t off_desde = 0; int ultimo_dia_amostra = -1;   // amostra de bateria em repouso (1/dia)
  for (;;) {
    DadosCarro d;
    if (xSemaphoreTake(mutex_dados, pdMS_TO_TICKS(50)) == pdTRUE) { d = dados_publicos; xSemaphoreGive(mutex_dados); }
    else { vTaskDelay(pdMS_TO_TICKS(1000)); continue; }
    uint32_t agora = millis();
    bool ligado = (d.rpm > 0);
    if (!ligado && d.tensao > 0 && d.tensao <= 12.0f) {
      if (bat_baixa_desde == 0) bat_baixa_desde = agora;
      else if (agora - bat_baixa_desde > 10000) {
        if (!alerta_bateria_ativo) { alerta_bateria_ativo = true; debugLog(1, "BAT FRACA", (uint16_t)(d.tensao*10)); }
        if (!bat_logado) { evtRegistrar(2, (int16_t)(d.tensao*100), ""); bat_logado = true; }
      }
    } else { bat_baixa_desde = 0; if (alerta_bateria_ativo) alerta_bateria_ativo = false; bat_logado = false; }
    // CORRECAO C: sobrecarga do alternador a partir de 14.5V (era 15.0V)
    if (ligado && d.tensao > 0 && (d.tensao < 12.2f || d.tensao > 14.5f)) {   // alerta so ABAIXO de 12.2V
      if (alt_ruim_desde == 0) alt_ruim_desde = agora;
      else if (agora - alt_ruim_desde > 10000) {
        if (!alerta_alternador_ativo) { alerta_alternador_ativo = true; debugLog(1, "ALT RUIM", (uint16_t)(d.tensao*10)); }
        if (!alt_logado) { evtRegistrar(3, (int16_t)(d.tensao*100), ""); alt_logado = true; }
      }
    } else { alt_ruim_desde = 0; if (alerta_alternador_ativo) alerta_alternador_ativo = false; alt_logado = false; }

    // ===== v7: TEMPERATURA (grava o episodio no historico p/ o relatorio) =====
    // A temp ja vem filtrada da taskCAN/K-line. Aqui so registramos o evento
    // (o alarme visual continua na tela). Alto = >110C; superaquec = >118C.
    if (d.temp_motor > 110 && d.temp_motor <= 135) {
      if (temp_alta_desde == 0) temp_alta_desde = agora;
      else if (agora - temp_alta_desde > 5000 && !temp_logada) {
        evtRegistrar(d.temp_motor > 118 ? 4 : 1, (int16_t)d.temp_motor, "");
        temp_logada = true;
      }
    } else { temp_alta_desde = 0; temp_logada = false; }

    // ===== v7: TENDENCIA DE BATERIA (1 amostra de tensao de REPOUSO por dia) =====
    // Carro desligado, tensao na faixa de repouso e assentado ha 3 min -> amostra.
    if (!ligado && d.tensao > 10.5f && d.tensao < 13.4f) {
      if (off_desde == 0) off_desde = agora;
      else if (agora - off_desde > 180000UL) {
        int diaHoje = rtc_ok ? rtcNow().day() : -2;
        if (diaHoje != ultimo_dia_amostra) {
          ultimo_dia_amostra = diaHoje;
          vbatRegistrar((uint16_t)(d.tensao * 1000));
          int trend = vbatTendenciaMvPorDia();   // mV/dia (negativo = caindo)
          if (trend <= -30 && vbat_n >= 8) {
            int atual_mv = vbat_hist[vbat_n - 1].mv;
            int margem = atual_mv - 11800;        // ~11.8V: abaixo disso costuma nao dar partida
            if (margem < 0) margem = 0;
            int dias = margem / (-trend);
            bateria_semanas_est = dias / 7;
            alerta_bateria_prev = true;
            evtRegistrar(2, (int16_t)(atual_mv / 10), "PREV");   // evento preditivo
          } else {
            alerta_bateria_prev = false; bateria_semanas_est = 0;
          }
        }
      }
    } else { off_desde = 0; }

    fuelAprenderEDetectar(d);
    vTaskDelay(pdMS_TO_TICKS(1000));
  }
}

// ============================================================
//  Task RTC
// ============================================================
void taskRTC(void* param) {
  Serial.println("[Task RTC] iniciada");
  for (;;) {
    DateTime agora = rtcNow();
    if (xSemaphoreTake(mutex_hora, pdMS_TO_TICKS(50)) == pdTRUE) {
      hora_h = agora.hour(); hora_m = agora.minute(); hora_s = agora.second();
      data_dia = agora.day(); data_mes = agora.month(); data_ano = agora.year();
      xSemaphoreGive(mutex_hora);
    }
    rtc_unix_cache = agora.unixtime();   // cache p/ a tela nao precisar ler o I2C
    vTaskDelay(pdMS_TO_TICKS(500));
  }
}

// ============================================================
//  WATCHDOG DE SOFTWARE (compartilhado)
// ============================================================
// Chamado pelo loop() (nucleo 1) E pela taskHeartbeat (nucleo 0). Antes o watchdog
// so vivia no loop(), que roda no NUCLEO 1 — o mesmo nucleo que congelava. Se o
// nucleo 1 travava, o proprio watchdog travava junto e so reiniciava quando o
// nucleo 1 voltava (por isso o marcador mostrava ~65s em vez de 12s). Agora a
// taskHeartbeat, no NUCLEO 0, tambem vigia: mesmo com o nucleo 1 congelado, ela
// reinicia rapido (~12s). Reiniciar por qualquer um dos dois nucleos = ok.
static void checarTravamento() {
  uint32_t agora = millis();
  if (agora <= 20000) return;                 // ignora a janela de boot
  uint32_t dt = agora - hb_tela;
  uint32_t db = agora - hb_botoes;
  if (dt <= 12000 && db <= 12000) return;     // tudo vivo
  // Quem travou = quem esta mais velho. Guarda a MIGALHA dele NA EEPROM (msg do
  // log), pra ler DEPOIS no PC com "DEBUG" — sem precisar de Serial ao vivo no carro.
  bool btnTravou = (db >= dt);
  const char* culpado = btnTravou ? (const char*)g_stage_btn : (const char*)g_stage_tela;
  char m[16];
  snprintf(m, sizeof(m), "trv%c %s", btnTravou ? 'B' : 'T', culpado);   // ex "trvB okMenu"
  Serial.printf("[WDT] travou (tela=%lums btn=%lums pag=%d stTela=%s stBtn=%s stCan=%s) -> reiniciando\n",
                dt, db, pagina_atual, (const char*)g_stage_tela, (const char*)g_stage_btn, (const char*)g_stage_can);
  // marcador no RTC (sobrevive ao reset) — a EEPROM pode estar ocupada, mas o
  // marcador garante o log "WDT reboot" no proximo boot de qualquer jeito.
  g_wdt_magic = 0x5744;
  g_wdt_tela = dt;
  g_wdt_btn  = db;
  debugLog(2, m, (uint16_t)dt, (uint16_t)db, (uint8_t)pagina_atual);   // msg = onde travou
  delay(80);
  ESP.restart();
}

// ============================================================
//  Task Heartbeat
// ============================================================
void taskHeartbeat(void* param) {
  Serial.println("[Task Heartbeat] iniciada");
  vTaskDelay(pdMS_TO_TICKS(5000));
  uint32_t ult_log = 0;
#if DEBUG_TRACE
  uint32_t ult_trace = 0;
#endif
  for (;;) {
    checarTravamento();   // watchdog AUTORITATIVO no nucleo 0 (sobrevive a um congelamento do nucleo 1)
    uint32_t agora = millis();
#if DEBUG_TRACE
    // ===== RASTREAMENTO ao vivo (1x/s) — vem do NUCLEO 0, que fica vivo mesmo se o
    // nucleo 1 congelar. Se o [TRACE] parar de sair e o millis PULAR na proxima
    // linha, o nucleo 1 travou -> a coluna stTela mostra ONDE. =====
    if (agora - ult_trace >= 1000) {
      ult_trace = agora;
      float v; int rpm, vel;
      if (xSemaphoreTake(mutex_dados, pdMS_TO_TICKS(20)) == pdTRUE) {
        v = dados_publicos.tensao; rpm = dados_publicos.rpm; vel = dados_publicos.velocidade;
        xSemaphoreGive(mutex_dados);
      } else { v = -1; rpm = -1; vel = -1; }
      NimBLEServer* s = NimBLEDevice::getServer();
      int ble = s ? s->getConnectedCount() : 0;
      UBaseType_t btn_stack = 0;
      TaskHandle_t hb = xTaskGetHandle("Botoes"); if (hb) btn_stack = uxTaskGetStackHighWaterMark(hb);
      Serial.printf("[TRACE] t=%lu telaAge=%lu btnAge=%lu stTela=%s stBtn=%s stCan=%s btnStk=%u rpm=%d vel=%d V=%.1f heap=%u ble=%d\n",
                    agora, agora - hb_tela, agora - hb_botoes,
                    (const char*)g_stage_tela, (const char*)g_stage_btn, (const char*)g_stage_can,
                    btn_stack, rpm, vel, v, ESP.getFreeHeap(), ble);
    }
#endif
    // ===== detector de PILHA BAIXA da taskBotoes -> grava NA EEPROM (le offline no PC).
    // Se a pilha dos botoes chegar perto de estourar (a suspeita do travamento no
    // Civic), fica registrado no DEBUG mesmo sem Serial ao vivo. Loga 1x por boot.
    {
      static bool btn_low_logado = false;
      UBaseType_t bs = 0;
      TaskHandle_t hbt = xTaskGetHandle("Botoes"); if (hbt) bs = uxTaskGetStackHighWaterMark(hbt);
      if (bs > 0 && bs < 500 && !btn_low_logado) {
        btn_low_logado = true;
        debugLog(2, "PILHA BTN BAIXA", (uint16_t)bs, 0);
        Serial.printf("[ALERTA] pilha da taskBotoes baixa: %u bytes livres!\n", bs);
      }
    }
    if (agora - ult_log >= 60000) {
      ult_log = agora;
      UBaseType_t can_stack = 0, tela_stack = 0, btn_stack = 0;
      TaskHandle_t h = xTaskGetHandle("CAN");  if (h) can_stack = uxTaskGetStackHighWaterMark(h);
      h = xTaskGetHandle("Tela"); if (h) tela_stack = uxTaskGetStackHighWaterMark(h);
      h = xTaskGetHandle("Botoes"); if (h) btn_stack = uxTaskGetStackHighWaterMark(h);
      Serial.printf("[Beat] CAN=%u Tela=%u Btn=%u TX=%lu RX=%lu TO=%lu\n", can_stack, tela_stack, btn_stack, tx_ok, rx_ok, timeouts);
      debugLog(4, "HEARTBEAT", can_stack, btn_stack);   // v2 agora = pilha dos BOTOES (o suspeito)
    }
#if DEBUG_TRACE
    vTaskDelay(pdMS_TO_TICKS(1000));   // trace 1x/s + vigia travamento
#else
    vTaskDelay(pdMS_TO_TICKS(3000));   // vigia o travamento a cada 3s
#endif
  }
}

// ============================================================
//  CAMADA DE TELA - LVGL + LovyanGFX (cockpit ligado nos dados reais)
// ============================================================
static const uint16_t LV_W = 320, LV_H = 240;
static lv_disp_draw_buf_t draw_buf;
static lv_color_t buf1[LV_W * 20];

class LGFX : public lgfx::LGFX_Device {
  lgfx::Panel_ST7789 _panel; lgfx::Bus_SPI _bus;   // REV3: volta pro ST7789 (driver que funcionava). O ILI9341 gerava corrupcao (chuvisco).
public:
  LGFX() {
    { auto c = _bus.config();
      c.spi_host = VSPI_HOST; c.spi_mode = 0;
      c.freq_write = 20000000; c.freq_read = 16000000;
      c.pin_sclk = 18; c.pin_mosi = 23; c.pin_miso = -1; c.pin_dc = 2;
      c.dma_channel = 1; _bus.config(c); _panel.setBus(&_bus); }
    { auto c = _panel.config();
      c.pin_cs = 5; c.pin_rst = 4; c.pin_busy = -1;
      c.panel_width = 240; c.panel_height = 320;
      // Neste painel ST7789 o fundo escuro sai com invert = false.
      c.invert = false; c.rgb_order = false; _panel.config(c); }
    setPanel(&_panel);
  }
};
LGFX lcd;

void my_disp_flush(lv_disp_drv_t* disp, const lv_area_t* area, lv_color_t* color_p) {
  uint32_t w = area->x2 - area->x1 + 1, h = area->y2 - area->y1 + 1;
  lcd.startWrite(); lcd.setAddrWindow(area->x1, area->y1, w, h);
  lcd.pushPixels((uint16_t*)color_p, w * h, true);
  lcd.endWrite(); lv_disp_flush_ready(disp);
}

// handles dos objetos do cockpit
static lv_obj_t *gCockpit;
static lv_obj_t *meter; static lv_meter_indicator_t *indArco;
static lv_obj_t *meter2 = NULL; static lv_meter_indicator_t *indArco2 = NULL;  // 2o mostrador (cluster)
static lv_obj_t *barFuel = NULL, *barTemp = NULL;   // niveis combustivel/temp (cluster)
static lv_obj_t *lblVel, *lblRpm, *lblTemp, *lblData, *lblVoltTit, *lblVolt, *lblComb, *lblHora;
static lv_obj_t *gFuelPage=NULL, *fuelLblCar=NULL, *fuelLblNivel=NULL, *fuelLblUlt=NULL, *fuelLblDif=NULL, *fuelLblStatus=NULL;
static lv_obj_t *popup, *popupMsg, *popupIcon;
static lv_obj_t *barRpm = NULL, *barVel = NULL;   // para estilos com barra
static lv_obj_t *batBody = NULL, *batFill = NULL, *batTxt = NULL, *batNub = NULL;   // bateria estilo iPhone
static int batInnerW = 0;      // largura util interna do preenchimento da bateria
static lv_obj_t *rpmMarker = NULL;   // "luz" que sobe na arco do conta-giro (estilo Performance)
static int meterMax = 10;      // teto do arco do conta-giro (em milhares) por estilo
uint8_t cockpit_estilo = 0;   // 0=Classico 1=Ferrari 2=Lamborghini 3=Tesla
uint8_t tema_sel = 0;         // selecao na pagina de Temas
static bool popup_shown = false;
static bool pagina_montada_nova = false;
static lv_obj_t *gManut, *manutLista, *manutSel, *manutNome[NUM_ITENS_MANUT], *manutPct[NUM_ITENS_MANUT];
static lv_obj_t *manutBar[NUM_ITENS_MANUT], *manutIcon[NUM_ITENS_MANUT];
static lv_obj_t *manutConfirm, *manutConfirmNome, *manutConfirmSim, *manutConfirmNao;
static lv_obj_t *gDiag, *diagTit, *diagSel, *diagM[3], *diagMsg, *diagLista, *diagSim, *diagNao;
static lv_obj_t *diagBadge = NULL, *diagBadgeTxt = NULL;   // U1: selo de gravidade colorido
static lv_obj_t *gAjuste, *ajTit, *ajCampo[6], *ajSalvar;
static lv_obj_t *gSistema, *sisTit, *sisDist, *sisTempo;
static lv_obj_t *sisConfirm, *sisConfirmSim, *sisConfirmNao;
static lv_obj_t *gTemas, *temasOpt[7], *temasSel;
static lv_obj_t *gHist, *histTit, *histLista;   // v7: tela de historico de eventos
// v7 tema 6 "Saude": barra de status + 3 numeros grandes (temp/bateria/combustivel)
static lv_obj_t *sdBand, *sdBandTxt, *sdBandIco, *sdTemp, *sdBat, *sdComb, *sdFuel, *sdBottom;

// resetCache: no-op no LVGL (a tela se redesenha sozinha); mantido p/ taskBotoes
void resetCache() {}

// ---------- Autoteste de boot (Serial apenas) ----------
void autoteste() {
  uint8_t probe[4] = {0};
  bool eeprom_ok = eepromReadBytes(0, probe, 4);
  float v = lerTensaoADC();
  Serial.println("=== AUTOTESTE ===");
  Serial.printf("  CAN....: %s\n", obd_ok ? "OK" : "FALHA");
  Serial.printf("  RTC....: %s\n", rtc_ok ? "OK" : "FALHA");
  Serial.printf("  EEPROM.: %s\n", eeprom_ok ? "OK" : "FALHA");
  Serial.printf("  BATERIA: %.1fV\n", v);
}

// ---------- Monta o cockpit (estilo HUD) ----------
// Popup de alerta (compartilhado por todos os estilos de painel)
// U3: callback de deslize (anima o Y do banner)
static void popupSlideCb(void* obj, int32_t y) { lv_obj_set_y((lv_obj_t*)obj, y); }
#define POPUP_Y_ABERTO   8
#define POPUP_Y_FECHADO  (-80)

static void criarPopup(lv_obj_t* scr) {
  // U3: BANNER no TOPO (nao tapa a velocidade no centro), semitransparente, desliza.
  popup = lv_obj_create(scr);
  lv_obj_set_size(popup, 300, 60);
  lv_obj_set_pos(popup, 10, POPUP_Y_ABERTO);
  lv_obj_set_style_bg_color(popup, lv_color_hex(0x1A0707), 0);
  lv_obj_set_style_bg_opa(popup, LV_OPA_90, 0);   // semitransparente (estilo notificacao)
  lv_obj_set_style_border_color(popup, lv_color_hex(0xFF1744), 0);
  lv_obj_set_style_border_width(popup, 2, 0);
  lv_obj_set_style_radius(popup, 14, 0);
  lv_obj_set_style_pad_all(popup, 0, 0);
  lv_obj_clear_flag(popup, LV_OBJ_FLAG_SCROLLABLE);
  popupIcon = lv_label_create(popup);
  lv_label_set_text(popupIcon, LV_SYMBOL_WARNING);
  lv_obj_set_style_text_font(popupIcon, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(popupIcon, lv_color_hex(0xFF1744), 0);
  lv_obj_align(popupIcon, LV_ALIGN_LEFT_MID, 16, 0);
  popupMsg = lv_label_create(popup);
  lv_label_set_text(popupMsg, "ALERTA");
  lv_obj_set_style_text_font(popupMsg, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(popupMsg, lv_color_hex(0xFF5252), 0);
  lv_obj_align(popupMsg, LV_ALIGN_CENTER, 18, 0);
  lv_obj_add_flag(popup, LV_OBJ_FLAG_HIDDEN);
}

// Bateria estilo iPhone: corpo arredondado + terminal + preenchimento colorido.
// 11.0V = vazio, 12.6V = cheio. Guarda os handles em globais p/ atualizarBateria().
static void criarBateriaIphone(lv_obj_t* par, lv_align_t al, int x, int y, int w, int h, bool comTexto) {
  batBody = lv_obj_create(par);
  lv_obj_set_size(batBody, w, h);
  lv_obj_align(batBody, al, x, y);
  lv_obj_set_style_bg_opa(batBody, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_color(batBody, lv_color_hex(0xCFD8DC), 0);
  lv_obj_set_style_border_width(batBody, 2, 0);
  lv_obj_set_style_radius(batBody, 4, 0);
  lv_obj_set_style_pad_all(batBody, 2, 0);
  lv_obj_clear_flag(batBody, LV_OBJ_FLAG_SCROLLABLE);
  // terminal (o "biquinho" da bateria) na direita
  batNub = lv_obj_create(par);
  lv_obj_set_size(batNub, 3, h / 2);
  lv_obj_align_to(batNub, batBody, LV_ALIGN_OUT_RIGHT_MID, 1, 0);
  lv_obj_set_style_bg_color(batNub, lv_color_hex(0xCFD8DC), 0);
  lv_obj_set_style_border_width(batNub, 0, 0);
  lv_obj_set_style_radius(batNub, 1, 0);
  // preenchimento interno (largura muda com a tensao)
  batInnerW = w - 8;
  batFill = lv_obj_create(batBody);
  lv_obj_set_size(batFill, 1, h - 8);
  lv_obj_align(batFill, LV_ALIGN_LEFT_MID, 0, 0);
  lv_obj_set_style_bg_color(batFill, lv_color_hex(0x34C759), 0);
  lv_obj_set_style_border_width(batFill, 0, 0);
  lv_obj_set_style_radius(batFill, 2, 0);
  lv_obj_clear_flag(batFill, LV_OBJ_FLAG_SCROLLABLE);
  batTxt = NULL;
  if (comTexto) {
    batTxt = lv_label_create(par);
    lv_label_set_text(batTxt, "--V");
    lv_obj_set_style_text_font(batTxt, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(batTxt, lv_color_hex(0xB0BEC5), 0);
    lv_obj_align_to(batTxt, batBody, LV_ALIGN_OUT_BOTTOM_MID, 0, 3);
  }
}

// ============ Estilo 0: CLASSICO (medidor circular + dados) ============
void montarCockpit0() {
  lv_obj_t* scr = lv_scr_act();
  lv_obj_set_style_bg_color(scr, lv_color_hex(0x05070D), 0);

  gCockpit = lv_obj_create(scr);
  lv_obj_set_size(gCockpit, LV_W, LV_H);
  lv_obj_center(gCockpit);
  lv_obj_set_style_bg_opa(gCockpit, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width(gCockpit, 0, 0);
  lv_obj_set_style_pad_all(gCockpit, 0, 0);
  lv_obj_clear_flag(gCockpit, LV_OBJ_FLAG_SCROLLABLE);

  meter = lv_meter_create(gCockpit);
  lv_obj_set_size(meter, 184, 184);
  lv_obj_align(meter, LV_ALIGN_LEFT_MID, 2, -14);
  lv_obj_set_style_bg_opa(meter, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width(meter, 0, 0);
  lv_obj_set_style_pad_all(meter, 2, 0);
  lv_meter_scale_t* escala = lv_meter_add_scale(meter);
  lv_meter_set_scale_range(meter, escala, 0, 10, 270, 135);
  lv_meter_set_scale_ticks(meter, escala, 51, 3, 15, lv_color_hex(0x33424F));
  lv_meter_set_scale_major_ticks(meter, escala, 5, 4, 19, lv_color_hex(0xECEFF1), 12);
  // ACENDE os numeros da escala do conta-giros (0-10): sem isso o rotulo usa a cor
  // padrao do tema (cinza escuro) e fica quase invisivel. Forca branco + fonte legivel.
  lv_obj_set_style_text_color(meter, lv_color_hex(0xFFFFFF), LV_PART_TICKS);
  lv_obj_set_style_text_font(meter, &lv_font_montserrat_14, LV_PART_TICKS);
  lv_meter_indicator_t* faixa =
      lv_meter_add_scale_lines(meter, escala, lv_color_hex(0x00B0FF), lv_color_hex(0xFF1744), false, 0);
  lv_meter_set_indicator_start_value(meter, faixa, 0);
  lv_meter_set_indicator_end_value(meter, faixa, 10);
  indArco = lv_meter_add_arc(meter, escala, 8, lv_color_hex(0xFFFFFF), -2);
  lv_meter_set_indicator_start_value(meter, indArco, 0);
  lv_meter_set_indicator_end_value(meter, indArco, 0);

  lblVel = lv_label_create(gCockpit);
  lv_label_set_text(lblVel, "0");
  lv_obj_set_style_text_font(lblVel, &lv_font_montserrat_40, 0);
  lv_obj_set_style_text_color(lblVel, lv_color_white(), 0);
  lv_obj_set_width(lblVel, 176);
  lv_obj_set_style_text_align(lblVel, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_align_to(lblVel, meter, LV_ALIGN_CENTER, 0, -8);
  lv_obj_t* un = lv_label_create(gCockpit);
  lv_label_set_text(un, "KM/H");
  lv_obj_set_style_text_font(un, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(un, lv_color_hex(0x90A4AE), 0);
  lv_obj_align_to(un, meter, LV_ALIGN_CENTER, 0, 20);
  lv_obj_t* xr = lv_label_create(gCockpit);
  lv_label_set_text(xr, "x1000 RPM");
  lv_obj_set_style_text_font(xr, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(xr, lv_color_hex(0x455A64), 0);
  lv_obj_align_to(xr, meter, LV_ALIGN_CENTER, 0, 54);   // mais p/ baixo: nao tapa os numeros do conta-giro

  lblTemp = lv_label_create(gCockpit);
  lv_label_set_text(lblTemp, "TEMP --C");
  lv_obj_set_style_text_font(lblTemp, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(lblTemp, lv_color_hex(0x4CAF50), 0);
  lv_obj_align(lblTemp, LV_ALIGN_BOTTOM_LEFT, 8, -22);
  lblData = lv_label_create(gCockpit);
  lv_label_set_text(lblData, "--/--/----");
  lv_obj_set_style_text_font(lblData, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(lblData, lv_color_hex(0x90A4AE), 0);
  lv_obj_align(lblData, LV_ALIGN_BOTTOM_LEFT, 8, -4);

  lv_obj_t* divi = lv_obj_create(gCockpit);
  lv_obj_set_size(divi, 2, 210);
  lv_obj_align(divi, LV_ALIGN_LEFT_MID, 206, 0);
  lv_obj_set_style_bg_color(divi, lv_color_hex(0x16202F), 0);
  lv_obj_set_style_border_width(divi, 0, 0);

  lblVoltTit = lv_label_create(gCockpit);
  lv_label_set_text(lblVoltTit, LV_SYMBOL_BATTERY_FULL " BAT.");
  lv_obj_set_style_text_font(lblVoltTit, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(lblVoltTit, lv_color_hex(0x78909C), 0);
  lv_obj_align(lblVoltTit, LV_ALIGN_TOP_RIGHT, -8, 4);
  lblVolt = lv_label_create(gCockpit);
  lv_label_set_text(lblVolt, "--");
  lv_obj_set_style_text_font(lblVolt, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(lblVolt, lv_color_white(), 0);
  lv_obj_align(lblVolt, LV_ALIGN_TOP_RIGHT, -8, 20);

  lv_obj_t* rt = lv_label_create(gCockpit);
  lv_label_set_text(rt, "RPM");
  lv_obj_set_style_text_font(rt, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(rt, lv_color_hex(0x78909C), 0);
  lv_obj_align(rt, LV_ALIGN_TOP_RIGHT, -8, 54);
  lblRpm = lv_label_create(gCockpit);
  lv_label_set_text(lblRpm, "0");
  lv_obj_set_style_text_font(lblRpm, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(lblRpm, lv_color_hex(0x00E5FF), 0);
  lv_obj_align(lblRpm, LV_ALIGN_TOP_RIGHT, -8, 70);

  lv_obj_t* ct = lv_label_create(gCockpit);
  lv_label_set_text(ct, "COMBUSTIVEL");
  lv_obj_set_style_text_font(ct, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(ct, lv_color_hex(0x78909C), 0);
  lv_obj_align(ct, LV_ALIGN_TOP_RIGHT, -8, 104);
  lblComb = lv_label_create(gCockpit);
  lv_label_set_text(lblComb, "--");
  lv_obj_set_style_text_font(lblComb, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(lblComb, lv_color_hex(0xFFC107), 0);
  lv_obj_align(lblComb, LV_ALIGN_TOP_RIGHT, -8, 120);

  lblHora = lv_label_create(gCockpit);
  lv_label_set_text(lblHora, "--:--");
  lv_obj_set_style_text_font(lblHora, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(lblHora, lv_color_hex(0xB0BEC5), 0);
  lv_obj_align(lblHora, LV_ALIGN_BOTTOM_RIGHT, -8, -6);

  // bateria estilo iPhone (so aparece com o carro desligado; a tensao ja tem texto).
  // Fica no rodape direito, longe do COMBUSTIVEL, e some com o motor ligado.
  criarBateriaIphone(gCockpit, LV_ALIGN_BOTTOM_RIGHT, -8, -40, 50, 20, false);

  criarPopup(scr);
}

// helper: rotulo pequeno em (x,y) ancorado, devolve o label
static lv_obj_t* rotulo(lv_obj_t* par, const char* txt, const lv_font_t* f, uint32_t cor,
                        lv_align_t al, int x, int y) {
  lv_obj_t* l = lv_label_create(par);
  lv_label_set_text(l, txt);
  lv_obj_set_style_text_font(l, f, 0);
  lv_obj_set_style_text_color(l, lv_color_hex(cor), 0);
  lv_obj_align(l, al, x, y);
  return l;
}

// Base transparente do cockpit (fundo + container full-screen). Devolve o scr.
static lv_obj_t* baseCockpit(uint32_t bgScr) {
  lv_obj_t* scr = lv_scr_act();
  lv_obj_set_style_bg_color(scr, lv_color_hex(bgScr), 0);
  gCockpit = lv_obj_create(scr);
  lv_obj_set_size(gCockpit, LV_W, LV_H);
  lv_obj_center(gCockpit);
  lv_obj_set_style_bg_opa(gCockpit, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width(gCockpit, 0, 0);
  lv_obj_set_style_pad_all(gCockpit, 0, 0);
  lv_obj_clear_flag(gCockpit, LV_OBJ_FLAG_SCROLLABLE);
  return scr;
}

// Conta-giro circular reutilizado pelos estilos esportivos. Preenche meter/indArco
// e ajusta meterMax=8. corLo->corHi = gradiente da escala; redline = inicio da zona vermelha.
static void criarTacometro(lv_obj_t* par, int size, lv_align_t al, int x, int y,
                           uint32_t corLo, uint32_t corHi, uint32_t corArco, uint32_t corTicks,
                           int redline) {
  lv_obj_t* m = lv_meter_create(par);
  lv_obj_set_size(m, size, size);
  lv_obj_align(m, al, x, y);
  lv_obj_set_style_bg_opa(m, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width(m, 0, 0);
  lv_obj_set_style_pad_all(m, 2, 0);
  lv_meter_scale_t* sc = lv_meter_add_scale(m);
  lv_meter_set_scale_range(m, sc, 0, 8, 270, 135);
  lv_meter_set_scale_ticks(m, sc, 41, 2, 9, lv_color_hex(0x33424F));
  lv_meter_set_scale_major_ticks(m, sc, 5, 4, 16, lv_color_hex(corTicks), 12);
  lv_obj_set_style_text_color(m, lv_color_hex(0xFFFFFF), LV_PART_TICKS);
  lv_obj_set_style_text_font(m, &lv_font_montserrat_14, LV_PART_TICKS);
  lv_meter_indicator_t* faixa = lv_meter_add_scale_lines(m, sc, lv_color_hex(corLo), lv_color_hex(corHi), false, 0);
  lv_meter_set_indicator_start_value(m, faixa, 0);
  lv_meter_set_indicator_end_value(m, faixa, redline);
  lv_meter_indicator_t* red = lv_meter_add_scale_lines(m, sc, lv_color_hex(0xFF1744), lv_color_hex(0xFF1744), false, 0);
  lv_meter_set_indicator_start_value(m, red, redline);
  lv_meter_set_indicator_end_value(m, red, 8);
  indArco = lv_meter_add_arc(m, sc, 9, lv_color_hex(corArco), -3);
  lv_meter_set_indicator_start_value(m, indArco, 0);
  lv_meter_set_indicator_end_value(m, indArco, 0);
  meter = m; meterMax = 8;
}

// ============ Estilo 1: FERRARI (conta-giro amarelo central, velocidade dentro) ============
void montarCockpit1() {
  lv_obj_t* scr = baseCockpit(0x0A0A0A);

  // faixa vermelha no topo (assinatura rosso corsa)
  lv_obj_t* topo = lv_obj_create(gCockpit);
  lv_obj_set_size(topo, LV_W, 5);
  lv_obj_align(topo, LV_ALIGN_TOP_MID, 0, 0);
  lv_obj_set_style_bg_color(topo, lv_color_hex(0xD40000), 0);
  lv_obj_set_style_border_width(topo, 0, 0);
  lv_obj_set_style_radius(topo, 0, 0);

  // conta-giro amarelo Ferrari (redline em 6k), grande a esquerda
  criarTacometro(gCockpit, 210, LV_ALIGN_LEFT_MID, 4, 6, 0xFFD54F, 0xFFA000, 0xFFD600, 0xFFECB3, 6);

  // velocidade DENTRO do medidor
  lblVel = lv_label_create(gCockpit);
  lv_label_set_text(lblVel, "0");
  lv_obj_set_style_text_font(lblVel, &lv_font_montserrat_40, 0);
  lv_obj_set_style_text_color(lblVel, lv_color_white(), 0);
  lv_obj_set_width(lblVel, 200);
  lv_obj_set_style_text_align(lblVel, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_align_to(lblVel, meter, LV_ALIGN_CENTER, 0, -6);
  rotulo(gCockpit, "KM/H", &lv_font_montserrat_14, 0x90A4AE, LV_ALIGN_LEFT_MID, 92, 24);

  // coluna direita: TEMP, COMB, bateria iPhone, relogio
  rotulo(gCockpit, "TEMP", &lv_font_montserrat_14, 0x78909C, LV_ALIGN_TOP_RIGHT, -8, 14);
  lblTemp = rotulo(gCockpit, "--C", &lv_font_montserrat_28, 0x4CAF50, LV_ALIGN_TOP_RIGHT, -8, 30);
  rotulo(gCockpit, "COMB", &lv_font_montserrat_14, 0x78909C, LV_ALIGN_TOP_RIGHT, -8, 70);
  lblComb = rotulo(gCockpit, "--%", &lv_font_montserrat_28, 0xFFC107, LV_ALIGN_TOP_RIGHT, -8, 86);
  criarBateriaIphone(gCockpit, LV_ALIGN_TOP_RIGHT, -26, 132, 52, 22, true);
  lblHora = rotulo(gCockpit, "--:--", &lv_font_montserrat_28, 0xB0BEC5, LV_ALIGN_BOTTOM_RIGHT, -8, -6);
  criarPopup(scr);
}

// ============ Estilo 2: LAMBORGHINI (hexagono angular verde, velocidade gigante) ============
void montarCockpit2() {
  lv_obj_t* scr = baseCockpit(0x080A06);

  // moldura hexagonal (assinatura Lamborghini) ao redor do conta-giro, a esquerda
  static lv_point_t hex[7] = {{100,22},{178,68},{178,160},{100,206},{22,160},{22,68},{100,22}};
  lv_obj_t* linha = lv_line_create(gCockpit);
  lv_line_set_points(linha, hex, 7);
  lv_obj_set_style_line_color(linha, lv_color_hex(0xAEEA00), 0);
  lv_obj_set_style_line_width(linha, 3, 0);
  lv_obj_set_style_line_rounded(linha, false, 0);

  // conta-giro verde acido dentro do hexagono
  criarTacometro(gCockpit, 150, LV_ALIGN_LEFT_MID, 25, -6, 0xAEEA00, 0xFF3D00, 0x76FF03, 0xCCFF90, 6);
  rotulo(gCockpit, "x1000 RPM", &lv_font_montserrat_14, 0x557000, LV_ALIGN_LEFT_MID, 60, 66);

  // velocidade grande na direita (fonte 40 real, sem zoom p/ nao cortar na borda)
  lblVel = lv_label_create(gCockpit);
  lv_label_set_text(lblVel, "0");
  lv_obj_set_style_text_font(lblVel, &lv_font_montserrat_40, 0);
  lv_obj_set_style_text_color(lblVel, lv_color_white(), 0);
  lv_obj_set_width(lblVel, 140);
  lv_obj_set_style_text_align(lblVel, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_align(lblVel, LV_ALIGN_TOP_RIGHT, -4, 40);
  rotulo(gCockpit, "KM/H", &lv_font_montserrat_14, 0x9E9E9E, LV_ALIGN_TOP_RIGHT, -60, 90);

  lblTemp = rotulo(gCockpit, "--C", &lv_font_montserrat_28, 0x4CAF50, LV_ALIGN_TOP_RIGHT, -80, 118);
  lblComb = rotulo(gCockpit, "--%", &lv_font_montserrat_28, 0xFFC107, LV_ALIGN_TOP_RIGHT, -14, 118);
  criarBateriaIphone(gCockpit, LV_ALIGN_BOTTOM_RIGHT, -40, -22, 52, 22, true);
  criarPopup(scr);
}

// ============ Estilo 3: TESLA (minimalista, velocidade enorme + barra de RPM) ============
void montarCockpit3() {
  lv_obj_t* scr = baseCockpit(0x000000);

  // velocidade grande e limpa em cima a esquerda (estilo Tesla), fonte real (nitida)
  lblVel = lv_label_create(gCockpit);
  lv_label_set_text(lblVel, "0");
  lv_obj_set_style_text_font(lblVel, &lv_font_montserrat_40, 0);
  lv_obj_set_style_text_color(lblVel, lv_color_white(), 0);
  lv_obj_align(lblVel, LV_ALIGN_TOP_LEFT, 24, 22);
  rotulo(gCockpit, "km/h", &lv_font_montserrat_28, 0x8E9AA6, LV_ALIGN_TOP_LEFT, 30, 66);

  // relogio no canto
  lblHora = rotulo(gCockpit, "--:--", &lv_font_montserrat_28, 0xE0E0E0, LV_ALIGN_TOP_RIGHT, -14, 22);

  // conta-giro como barra fina arredondada (Tesla nao tem ponteiro; usa barra limpa)
  rotulo(gCockpit, "RPM", &lv_font_montserrat_14, 0x5A6B7A, LV_ALIGN_LEFT_MID, 16, 18);
  lblRpm = rotulo(gCockpit, "0", &lv_font_montserrat_14, 0x0A84FF, LV_ALIGN_RIGHT_MID, -16, 18);
  barRpm = lv_bar_create(gCockpit);
  lv_obj_set_size(barRpm, 288, 12);
  lv_obj_align(barRpm, LV_ALIGN_CENTER, 0, 40);
  lv_bar_set_range(barRpm, 0, 8000);
  lv_obj_set_style_bg_color(barRpm, lv_color_hex(0x1C1C1E), LV_PART_MAIN);
  lv_obj_set_style_radius(barRpm, 6, LV_PART_MAIN);
  lv_obj_set_style_bg_color(barRpm, lv_color_hex(0x0A84FF), LV_PART_INDICATOR);
  lv_obj_set_style_radius(barRpm, 6, LV_PART_INDICATOR);

  // rodape: TEMP | COMB | bateria iPhone
  rotulo(gCockpit, "TEMP", &lv_font_montserrat_14, 0x5A6B7A, LV_ALIGN_BOTTOM_LEFT, 16, -34);
  lblTemp = rotulo(gCockpit, "--C", &lv_font_montserrat_28, 0xE0E0E0, LV_ALIGN_BOTTOM_LEFT, 16, -6);
  rotulo(gCockpit, "COMB", &lv_font_montserrat_14, 0x5A6B7A, LV_ALIGN_BOTTOM_MID, -10, -34);
  lblComb = rotulo(gCockpit, "--%", &lv_font_montserrat_28, 0xE0E0E0, LV_ALIGN_BOTTOM_MID, -10, -6);
  criarBateriaIphone(gCockpit, LV_ALIGN_BOTTOM_RIGHT, -34, -30, 54, 22, true);
  criarPopup(scr);
}

// ============ Estilo 4: PAINEL DUPLO (cluster: velocidade+comb / rpm+temp) ============
void montarCockpit4() {
  lv_obj_t* scr = baseCockpit(0x05070D);

  // ----- mostrador ESQUERDO: velocidade (0-220) + combustivel -----
  meter = lv_meter_create(gCockpit);
  lv_obj_set_size(meter, 150, 150);
  lv_obj_align(meter, LV_ALIGN_LEFT_MID, 4, -8);
  lv_obj_set_style_bg_opa(meter, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width(meter, 0, 0);
  lv_obj_set_style_pad_all(meter, 2, 0);
  lv_meter_scale_t* scL = lv_meter_add_scale(meter);
  lv_meter_set_scale_range(meter, scL, 0, 220, 270, 135);
  lv_meter_set_scale_ticks(meter, scL, 12, 2, 7, lv_color_hex(0x33424F));
  lv_meter_set_scale_major_ticks(meter, scL, 3, 3, 11, lv_color_hex(0x90A4AE), 8);
  lv_obj_set_style_text_color(meter, lv_color_hex(0x90A4AE), LV_PART_TICKS);
  lv_obj_set_style_text_font(meter, &lv_font_montserrat_14, LV_PART_TICKS);
  indArco = lv_meter_add_arc(meter, scL, 7, lv_color_hex(0x00B0FF), -2);
  lv_meter_set_indicator_start_value(meter, indArco, 0);
  lv_meter_set_indicator_end_value(meter, indArco, 0);
  meterMax = 220;

  lblVel = lv_label_create(gCockpit);
  lv_label_set_text(lblVel, "0");
  lv_obj_set_style_text_font(lblVel, &lv_font_montserrat_40, 0);
  lv_obj_set_style_text_color(lblVel, lv_color_white(), 0);
  lv_obj_set_width(lblVel, 130);
  lv_obj_set_style_text_align(lblVel, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_align_to(lblVel, meter, LV_ALIGN_CENTER, 0, -16);
  lblComb = lv_label_create(gCockpit);
  lv_label_set_text(lblComb, "--%");
  lv_obj_set_style_text_font(lblComb, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(lblComb, lv_color_hex(0xFFC107), 0);
  lv_obj_align_to(lblComb, meter, LV_ALIGN_CENTER, 0, 20);
  barFuel = lv_bar_create(gCockpit);
  lv_obj_set_size(barFuel, 84, 8);
  lv_obj_align_to(barFuel, meter, LV_ALIGN_CENTER, 0, 40);
  lv_bar_set_range(barFuel, 0, 100);
  lv_obj_set_style_bg_color(barFuel, lv_color_hex(0x16202F), LV_PART_MAIN);
  lv_obj_set_style_bg_color(barFuel, lv_color_hex(0xFFC107), LV_PART_INDICATOR);
  lv_obj_set_style_radius(barFuel, 4, LV_PART_INDICATOR);
  rotulo(gCockpit, "COMB", &lv_font_montserrat_14, 0x607D8B, LV_ALIGN_LEFT_MID, 58, 62);

  // ----- mostrador DIREITO: RPM (0-8 mil) + temperatura -----
  meter2 = lv_meter_create(gCockpit);
  lv_obj_set_size(meter2, 150, 150);
  lv_obj_align(meter2, LV_ALIGN_RIGHT_MID, -4, -8);
  lv_obj_set_style_bg_opa(meter2, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width(meter2, 0, 0);
  lv_obj_set_style_pad_all(meter2, 2, 0);
  lv_meter_scale_t* scR = lv_meter_add_scale(meter2);
  lv_meter_set_scale_range(meter2, scR, 0, 8, 270, 135);
  lv_meter_set_scale_ticks(meter2, scR, 9, 2, 7, lv_color_hex(0x33424F));
  lv_meter_set_scale_major_ticks(meter2, scR, 1, 3, 11, lv_color_hex(0x90A4AE), 8);
  lv_obj_set_style_text_color(meter2, lv_color_hex(0x90A4AE), LV_PART_TICKS);
  lv_obj_set_style_text_font(meter2, &lv_font_montserrat_14, LV_PART_TICKS);
  lv_meter_indicator_t* redR = lv_meter_add_scale_lines(meter2, scR, lv_color_hex(0xFF1744), lv_color_hex(0xFF1744), false, 0);
  lv_meter_set_indicator_start_value(meter2, redR, 6);
  lv_meter_set_indicator_end_value(meter2, redR, 8);
  indArco2 = lv_meter_add_arc(meter2, scR, 7, lv_color_hex(0x00E5FF), -2);
  lv_meter_set_indicator_start_value(meter2, indArco2, 0);
  lv_meter_set_indicator_end_value(meter2, indArco2, 0);

  lblRpm = lv_label_create(gCockpit);
  lv_label_set_text(lblRpm, "0");
  lv_obj_set_style_text_font(lblRpm, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(lblRpm, lv_color_white(), 0);
  lv_obj_set_width(lblRpm, 130);
  lv_obj_set_style_text_align(lblRpm, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_align_to(lblRpm, meter2, LV_ALIGN_CENTER, 0, -14);
  lblTemp = lv_label_create(gCockpit);
  lv_label_set_text(lblTemp, "--C");
  lv_obj_set_style_text_font(lblTemp, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(lblTemp, lv_color_hex(0x4CAF50), 0);
  lv_obj_align_to(lblTemp, meter2, LV_ALIGN_CENTER, 0, 20);
  barTemp = lv_bar_create(gCockpit);
  lv_obj_set_size(barTemp, 84, 8);
  lv_obj_align_to(barTemp, meter2, LV_ALIGN_CENTER, 0, 40);
  lv_bar_set_range(barTemp, 40, 120);
  lv_obj_set_style_bg_color(barTemp, lv_color_hex(0x16202F), LV_PART_MAIN);
  lv_obj_set_style_bg_color(barTemp, lv_color_hex(0x4CAF50), LV_PART_INDICATOR);
  lv_obj_set_style_radius(barTemp, 4, LV_PART_INDICATOR);
  rotulo(gCockpit, "TEMP", &lv_font_montserrat_14, 0x607D8B, LV_ALIGN_RIGHT_MID, -92, 62);

  // ----- fora: tensao (centro embaixo) e hora (centro em cima) -----
  lblVolt = rotulo(gCockpit, "--V", &lv_font_montserrat_28, 0x00E676, LV_ALIGN_BOTTOM_MID, 0, -2);
  lblHora = rotulo(gCockpit, "--:--", &lv_font_montserrat_14, 0xB0BEC5, LV_ALIGN_TOP_MID, 0, 2);
  criarPopup(scr);
}

// ============ Estilo 5: PERFORMANCE (espelha o render do produto) ============
// Conta-giro central grande (azul->vermelho), COOLANT+termometro a ESQUERDA,
// VOLTAGE + SPEED a DIREITA, e barra de MANUTENCAO embaixo. 320x240.
void montarCockpit5() {
  lv_obj_t* scr = baseCockpit(0x000000);   // preto puro: fica mais escuro/imerso no painel (ST7789 e LCD, nao AMOLED)

  // ---------- conta-giro central com BANDA EM DEGRADE (azul fraco->forte, vermelho no fim) ----------
  meter = lv_meter_create(gCockpit);
  lv_obj_set_size(meter, 152, 152);   // menor: garante que NADA das laterais encoste no arco
  lv_obj_align(meter, LV_ALIGN_CENTER, 0, -6);
  lv_obj_set_style_bg_opa(meter, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width(meter, 0, 0);
  lv_obj_set_style_pad_all(meter, 2, 0);
  lv_meter_scale_t* sc = lv_meter_add_scale(meter);
  lv_meter_set_scale_range(meter, sc, 0, 8, 270, 135);
  // tracinhos FINOS (81) — anel graduado como na referencia
  lv_meter_set_scale_ticks(meter, sc, 81, 2, 9, lv_color_hex(0x152430));
  lv_meter_set_scale_major_ticks(meter, sc, 10, 3, 16, lv_color_hex(0xECEFF1), 12);
  lv_obj_set_style_text_color(meter, lv_color_hex(0xFFFFFF), LV_PART_TICKS);
  lv_obj_set_style_text_font(meter, &lv_font_montserrat_14, LV_PART_TICKS);
  // HALO suave ATRAS (tracos mais largos e apagados) -> da o "brilho" das bordas
  lv_meter_indicator_t* hAzul = lv_meter_add_scale_lines(meter, sc, lv_color_hex(0x123A57), lv_color_hex(0x2C86BE), true, 4);
  lv_meter_set_indicator_start_value(meter, hAzul, 0);
  lv_meter_set_indicator_end_value(meter, hAzul, 6);
  lv_meter_indicator_t* hVerm = lv_meter_add_scale_lines(meter, sc, lv_color_hex(0x7A2A18), lv_color_hex(0x8A1018), true, 4);
  lv_meter_set_indicator_start_value(meter, hVerm, 6);
  lv_meter_set_indicator_end_value(meter, hVerm, 8);
  // UM UNICO arco por cima: degrade SUAVE e LOCAL. Azul (nao tao escuro) no 0 -> azul vivo no 6.
  lv_meter_indicator_t* gAzul = lv_meter_add_scale_lines(meter, sc, lv_color_hex(0x2A6296), lv_color_hex(0x7FD8FF), true, 0);
  lv_meter_set_indicator_start_value(meter, gAzul, 0);
  lv_meter_set_indicator_end_value(meter, gAzul, 6);
  // zona alta 6..8 em vermelho VIVO (nao escurece ate o fim)
  lv_meter_indicator_t* gVerm = lv_meter_add_scale_lines(meter, sc, lv_color_hex(0xFF6A2A), lv_color_hex(0xF51828), true, 0);
  lv_meter_set_indicator_start_value(meter, gVerm, 6);
  lv_meter_set_indicator_end_value(meter, gVerm, 8);
  // NAO ha segundo arco: o anel graduado e o unico arco; o RPM aparece no numero central.
  indArco = NULL;
  meterMax = 8;

  // ---------- MOLDURA fina 3D em volta do mostrador ("capinha" tipo painel de moto) ----------
  // aro externo ESCURO + sombra suave (parece levantado); aro interno CLARO (brilho da borda).
  // Um tiquinho mais grossa que antes (2->3 e 1->2), mas ainda discreta.
  lv_obj_t* aroExt = lv_obj_create(gCockpit);
  lv_obj_set_size(aroExt, 164, 164);
  lv_obj_align(aroExt, LV_ALIGN_CENTER, 0, -6);
  lv_obj_set_style_bg_opa(aroExt, LV_OPA_TRANSP, 0);
  lv_obj_set_style_radius(aroExt, LV_RADIUS_CIRCLE, 0);
  lv_obj_set_style_border_color(aroExt, lv_color_hex(0x0C1824), 0);
  lv_obj_set_style_border_width(aroExt, 3, 0);
  lv_obj_set_style_shadow_color(aroExt, lv_color_hex(0x000000), 0);
  lv_obj_set_style_shadow_width(aroExt, 6, 0);
  lv_obj_set_style_shadow_opa(aroExt, LV_OPA_30, 0);
  lv_obj_clear_flag(aroExt, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_t* aroInt = lv_obj_create(gCockpit);
  lv_obj_set_size(aroInt, 158, 158);
  lv_obj_align(aroInt, LV_ALIGN_CENTER, 0, -6);
  lv_obj_set_style_bg_opa(aroInt, LV_OPA_TRANSP, 0);
  lv_obj_set_style_radius(aroInt, LV_RADIUS_CIRCLE, 0);
  lv_obj_set_style_border_color(aroInt, lv_color_hex(0x46607A), 0);   // brilho fino da borda
  lv_obj_set_style_border_width(aroInt, 2, 0);
  lv_obj_clear_flag(aroInt, LV_OBJ_FLAG_SCROLLABLE);

  // ---------- LUZ do RPM que SOBE na arco (marcador pequeno; nao tapa o numero central) ----------
  rpmMarker = lv_obj_create(gCockpit);
  lv_obj_set_size(rpmMarker, 10, 10);
  lv_obj_set_style_radius(rpmMarker, LV_RADIUS_CIRCLE, 0);
  lv_obj_set_style_bg_color(rpmMarker, lv_color_hex(0xEAF6FF), 0);   // luz branco-azulada
  lv_obj_set_style_border_width(rpmMarker, 0, 0);
  lv_obj_set_style_shadow_color(rpmMarker, lv_color_hex(0x35C6FF), 0);
  lv_obj_set_style_shadow_width(rpmMarker, 12, 0);                    // brilho ao redor
  lv_obj_set_style_shadow_opa(rpmMarker, LV_OPA_COVER, 0);
  lv_obj_clear_flag(rpmMarker, LV_OBJ_FLAG_SCROLLABLE);

  // ---------- DIVISORIAS entre os parametros (ganchinho + toque de azul do arco, depois reto) ----------
  // Espelhadas em cima/baixo dos dois lados. Pontos em coordenadas do gCockpit.
  static lv_point_t dLT[] = {{104, 30}, {96, 34}, {8, 34}};      // ESQ cima  (sob a hora)
  static lv_point_t dLM[] = {{78, 82}, {72, 86}, {8, 86}};       // ESQ baixo (entre temp e comb)
  static lv_point_t dRT[] = {{216, 30}, {224, 34}, {312, 34}};   // DIR cima  (sobre a tensao)
  static lv_point_t dRM[] = {{242, 106}, {250, 110}, {312, 110}};// DIR baixo (entre tensao e velocidade)
  lv_point_t* divs[4] = {dLT, dLM, dRT, dRM};
  for (int i = 0; i < 4; i++) {
    lv_obj_t* ln = lv_line_create(gCockpit);
    lv_line_set_points(ln, divs[i], 3);
    lv_obj_set_style_line_color(ln, lv_color_hex(0x243849), 0);
    lv_obj_set_style_line_width(ln, 1, 0);
    lv_obj_set_style_line_rounded(ln, true, 0);
  }
  // acento AZUL curtinho na ponta (perto do arco) — "aquela cor vindo do arco"
  static lv_point_t aLT[] = {{110, 27}, {104, 30}};
  static lv_point_t aLM[] = {{84, 79}, {78, 82}};
  static lv_point_t aRT[] = {{210, 27}, {216, 30}};
  static lv_point_t aRM[] = {{236, 103}, {242, 106}};
  lv_point_t* accs[4] = {aLT, aLM, aRT, aRM};
  for (int i = 0; i < 4; i++) {
    lv_obj_t* ln = lv_line_create(gCockpit);
    lv_line_set_points(ln, accs[i], 2);
    lv_obj_set_style_line_color(ln, lv_color_hex(0x2C86BE), 0);
    lv_obj_set_style_line_width(ln, 2, 0);
    lv_obj_set_style_line_rounded(ln, true, 0);
  }

  lblRpm = lv_label_create(gCockpit);           // numero grande no centro (RPM real)
  lv_label_set_text(lblRpm, "0");
  lv_obj_set_style_text_font(lblRpm, &lv_font_montserrat_40, 0);
  lv_obj_set_style_text_color(lblRpm, lv_color_white(), 0);
  lv_obj_set_width(lblRpm, 140);
  lv_obj_set_style_text_align(lblRpm, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_align_to(lblRpm, meter, LV_ALIGN_CENTER, 0, -6);
  lv_obj_t* rpmU = lv_label_create(gCockpit);   // "RPM"
  lv_label_set_text(rpmU, "RPM");
  lv_obj_set_style_text_font(rpmU, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(rpmU, lv_color_hex(0x90A4AE), 0);
  lv_obj_align_to(rpmU, meter, LV_ALIGN_CENTER, 0, 20);
  lv_obj_t* x1 = lv_label_create(gCockpit);     // "x1000" na base do mostrador
  lv_label_set_text(x1, "x1000");
  lv_obj_set_style_text_font(x1, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(x1, lv_color_hex(0x546E7A), 0);
  lv_obj_align_to(x1, meter, LV_ALIGN_CENTER, 0, 44);

  // ---------- topo-esquerda: relogio ----------
  lblHora = lv_label_create(gCockpit);
  lv_label_set_text(lblHora, "--:--");
  lv_obj_set_style_text_font(lblHora, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(lblHora, lv_color_white(), 0);
  lv_obj_align(lblHora, LV_ALIGN_TOP_LEFT, 8, 4);

  // ---------- coluna ESQUERDA: TEMPERATURA (termometro) + COMBUSTIVEL embaixo ----------
  rotulo(gCockpit, "TEMP.", &lv_font_montserrat_14, 0x78909C, LV_ALIGN_TOP_LEFT, 8, 38);
  // termometro azul (haste + bulbo)
  lv_obj_t* thStem = lv_obj_create(gCockpit);
  lv_obj_set_size(thStem, 5, 15);
  lv_obj_align(thStem, LV_ALIGN_TOP_LEFT, 11, 55);
  lv_obj_set_style_bg_color(thStem, lv_color_hex(0x00B0FF), 0);
  lv_obj_set_style_border_width(thStem, 0, 0);
  lv_obj_set_style_radius(thStem, 3, 0);
  lv_obj_clear_flag(thStem, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_t* thBulb = lv_obj_create(gCockpit);
  lv_obj_set_size(thBulb, 11, 11);
  lv_obj_align(thBulb, LV_ALIGN_TOP_LEFT, 8, 67);
  lv_obj_set_style_bg_color(thBulb, lv_color_hex(0x00B0FF), 0);
  lv_obj_set_style_border_width(thBulb, 0, 0);
  lv_obj_set_style_radius(thBulb, 6, 0);
  lv_obj_clear_flag(thBulb, LV_OBJ_FLAG_SCROLLABLE);
  lblTemp = lv_label_create(gCockpit);
  lv_label_set_text(lblTemp, "--C");
  lv_obj_set_style_text_font(lblTemp, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(lblTemp, lv_color_white(), 0);
  lv_obj_align(lblTemp, LV_ALIGN_TOP_LEFT, 18, 54);

  // COMBUSTIVEL embaixo da temperatura (abreviado + % + barra estreita p/ NAO tocar o mostrador)
  rotulo(gCockpit, "COMB.", &lv_font_montserrat_14, 0x78909C, LV_ALIGN_TOP_LEFT, 8, 90);
  lblComb = lv_label_create(gCockpit);
  lv_label_set_text(lblComb, "--");
  lv_obj_set_style_text_font(lblComb, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(lblComb, lv_color_hex(0xFFC107), 0);
  lv_obj_align(lblComb, LV_ALIGN_TOP_LEFT, 8, 106);
  barFuel = lv_bar_create(gCockpit);            // nivel de combustivel (estreita: x10..x64)
  lv_obj_set_size(barFuel, 54, 8);
  lv_obj_align(barFuel, LV_ALIGN_TOP_LEFT, 10, 138);
  lv_bar_set_range(barFuel, 0, 100);
  lv_obj_set_style_bg_color(barFuel, lv_color_hex(0x16202F), LV_PART_MAIN);
  lv_obj_set_style_bg_color(barFuel, lv_color_hex(0xFFC107), LV_PART_INDICATOR);
  lv_obj_set_style_radius(barFuel, 4, LV_PART_INDICATOR);

  // SAUDE DA BATERIA embaixo do combustivel (icone estilo iPhone; so aparece com o carro DESLIGADO)
  rotulo(gCockpit, "SAUDE BAT.", &lv_font_montserrat_14, 0x78909C, LV_ALIGN_TOP_LEFT, 8, 158);
  criarBateriaIphone(gCockpit, LV_ALIGN_TOP_LEFT, 10, 176, 46, 18, false);

  // ---------- coluna DIREITA: ALTERNADOR/BATERIA + tensao + VELOCIDADE ----------
  // rotulo dinamico: "ALTERNADOR" com o motor ligado, "BATERIA" desligado (atualizarCockpit
  // troca o texto). Caixa de largura fixa + alinhado a direita p/ nao mudar de lugar.
  lblVoltTit = lv_label_create(gCockpit);
  lv_label_set_text(lblVoltTit, "ALTERNADOR");
  lv_obj_set_style_text_font(lblVoltTit, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(lblVoltTit, lv_color_hex(0x78909C), 0);
  lv_obj_set_width(lblVoltTit, 150);
  lv_obj_set_style_text_align(lblVoltTit, LV_TEXT_ALIGN_RIGHT, 0);
  lv_obj_align(lblVoltTit, LV_ALIGN_TOP_RIGHT, -8, 38);
  lblVolt = lv_label_create(gCockpit);
  lv_label_set_text(lblVolt, "--V");
  lv_obj_set_style_text_font(lblVolt, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(lblVolt, lv_color_white(), 0);
  lv_obj_align(lblVolt, LV_ALIGN_TOP_RIGHT, -8, 54);
  barTemp = lv_bar_create(gCockpit);            // nivel da tensao (reaproveita barTemp)
  lv_obj_set_size(barTemp, 44, 7);
  lv_obj_align(barTemp, LV_ALIGN_TOP_RIGHT, -28, 88);
  lv_bar_set_range(barTemp, 0, 100);
  lv_obj_set_style_bg_color(barTemp, lv_color_hex(0x16202F), LV_PART_MAIN);
  lv_obj_set_style_bg_color(barTemp, lv_color_hex(0x00B0FF), LV_PART_INDICATOR);
  lv_obj_set_style_radius(barTemp, 4, LV_PART_INDICATOR);
  lv_obj_t* batIco = lv_obj_create(gCockpit);   // iconezinho de bateria (estatico)
  lv_obj_set_size(batIco, 15, 9);
  lv_obj_align(batIco, LV_ALIGN_TOP_RIGHT, -10, 87);
  lv_obj_set_style_bg_opa(batIco, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_color(batIco, lv_color_hex(0x00B0FF), 0);
  lv_obj_set_style_border_width(batIco, 1, 0);
  lv_obj_set_style_radius(batIco, 1, 0);
  lv_obj_clear_flag(batIco, LV_OBJ_FLAG_SCROLLABLE);

  rotulo(gCockpit, "VELOC.", &lv_font_montserrat_14, 0x78909C, LV_ALIGN_TOP_RIGHT, -8, 120);
  lblVel = lv_label_create(gCockpit);
  lv_label_set_text(lblVel, "0");
  lv_obj_set_style_text_font(lblVel, &lv_font_montserrat_40, 0);
  lv_obj_set_style_text_color(lblVel, lv_color_white(), 0);
  lv_obj_align(lblVel, LV_ALIGN_TOP_RIGHT, -8, 152);
  rotulo(gCockpit, "km/h", &lv_font_montserrat_14, 0x78909C, LV_ALIGN_TOP_RIGHT, -8, 194);

  // ---------- rodape: DATA (centralizada, com uma linha fina em cima) ----------
  lv_obj_t* linha = lv_obj_create(gCockpit);
  lv_obj_set_size(linha, LV_W - 24, 2);
  lv_obj_align(linha, LV_ALIGN_BOTTOM_MID, 0, -26);
  lv_obj_set_style_bg_color(linha, lv_color_hex(0x16202F), 0);
  lv_obj_set_style_border_width(linha, 0, 0);
  lblData = lv_label_create(gCockpit);
  lv_label_set_text(lblData, "--/--/----");
  lv_obj_set_style_text_font(lblData, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(lblData, lv_color_hex(0xB0BEC5), 0);
  lv_obj_align(lblData, LV_ALIGN_BOTTOM_MID, 0, -7);

  criarPopup(scr);
}

// ---------- Dispatcher: monta o painel do estilo escolhido ----------
// ============================================================
//  Tema 6 "SAUDE" (v7): tela principal simples, sem jargao.
//  Barra de status verde/amarelo/vermelho + 3 numeros grandes
//  (temperatura, bateria, combustivel). A barra reaproveita a lista
//  de alertas que o atualizarCockpit ja calcula.
// ============================================================
void montarCockpit6() {
  baseCockpit(0x05070D);

  // ----- barra de STATUS (topo) -----
  sdBand = lv_obj_create(gCockpit);
  lv_obj_set_size(sdBand, 300, 44);
  lv_obj_set_pos(sdBand, 10, 10);
  lv_obj_set_style_radius(sdBand, 9, 0);
  lv_obj_set_style_border_width(sdBand, 2, 0);
  lv_obj_set_style_bg_color(sdBand, lv_color_hex(0x0E3320), 0);
  lv_obj_set_style_border_color(sdBand, lv_color_hex(0x69F0AE), 0);
  lv_obj_set_style_pad_all(sdBand, 0, 0);
  lv_obj_clear_flag(sdBand, LV_OBJ_FLAG_SCROLLABLE);
  sdBandIco = lv_label_create(sdBand);
  lv_label_set_text(sdBandIco, LV_SYMBOL_OK);
  lv_obj_set_style_text_font(sdBandIco, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(sdBandIco, lv_color_hex(0x69F0AE), 0);
  lv_obj_align(sdBandIco, LV_ALIGN_LEFT_MID, 12, 0);
  sdBandTxt = lv_label_create(sdBand);
  lv_label_set_text(sdBandTxt, "TUDO CERTO");
  lv_obj_set_style_text_font(sdBandTxt, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(sdBandTxt, lv_color_hex(0x69F0AE), 0);
  lv_obj_align(sdBandTxt, LV_ALIGN_CENTER, 12, 0);

  // ----- titulos das 3 colunas -----
  rotulo(gCockpit, "TEMPERATURA", &lv_font_montserrat_14, 0x78909C, LV_ALIGN_TOP_MID, -100, 74);
  rotulo(gCockpit, "BATERIA",     &lv_font_montserrat_14, 0x78909C, LV_ALIGN_TOP_MID,    0, 74);
  rotulo(gCockpit, "COMBUST.",    &lv_font_montserrat_14, 0x78909C, LV_ALIGN_TOP_MID,  100, 74);

  // ----- 3 numeros GRANDES -----
  sdTemp = lv_label_create(gCockpit);
  lv_label_set_text(sdTemp, "--");
  lv_obj_set_style_text_font(sdTemp, &lv_font_montserrat_40, 0);
  lv_obj_set_style_text_color(sdTemp, lv_color_white(), 0);
  lv_obj_align(sdTemp, LV_ALIGN_TOP_MID, -100, 96);
  sdBat = lv_label_create(gCockpit);
  lv_label_set_text(sdBat, "--");
  lv_obj_set_style_text_font(sdBat, &lv_font_montserrat_40, 0);
  lv_obj_set_style_text_color(sdBat, lv_color_white(), 0);
  lv_obj_align(sdBat, LV_ALIGN_TOP_MID, 0, 96);
  sdComb = lv_label_create(gCockpit);
  lv_label_set_text(sdComb, "--");
  lv_obj_set_style_text_font(sdComb, &lv_font_montserrat_40, 0);
  lv_obj_set_style_text_color(sdComb, lv_color_white(), 0);
  lv_obj_align(sdComb, LV_ALIGN_TOP_MID, 100, 96);

  // ----- barra de combustivel -----
  sdFuel = lv_bar_create(gCockpit);
  lv_obj_set_size(sdFuel, 260, 10);
  lv_obj_align(sdFuel, LV_ALIGN_TOP_MID, 0, 158);
  lv_bar_set_range(sdFuel, 0, 100);
  lv_obj_set_style_bg_color(sdFuel, lv_color_hex(0x16202F), LV_PART_MAIN);
  lv_obj_set_style_radius(sdFuel, 5, LV_PART_MAIN);
  lv_obj_set_style_bg_color(sdFuel, lv_color_hex(0x4DD0E1), LV_PART_INDICATOR);
  lv_obj_set_style_radius(sdFuel, 5, LV_PART_INDICATOR);

  // ----- rodape (km ou detalhe do status) -----
  sdBottom = lv_label_create(gCockpit);
  lv_label_set_text(sdBottom, "");
  lv_obj_set_style_text_font(sdBottom, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(sdBottom, lv_color_hex(0x546E7A), 0);
  lv_obj_align(sdBottom, LV_ALIGN_BOTTOM_MID, 0, -8);
}

void montarCockpit() {
  // zera todos os handles (cada estilo cria so os que usa; atualizarCockpit checa NULL)
  meter = NULL; indArco = NULL; barRpm = NULL; barVel = NULL; meterMax = 10;
  meter2 = NULL; indArco2 = NULL; barFuel = NULL; barTemp = NULL;
  lblVel = lblRpm = lblTemp = lblData = lblVoltTit = lblVolt = lblComb = lblHora = NULL;
  popup = NULL; popupMsg = NULL; popupIcon = NULL;
  batBody = NULL; batFill = NULL; batTxt = NULL; batNub = NULL;
  rpmMarker = NULL;
  sdBand = sdBandTxt = sdBandIco = sdTemp = sdBat = sdComb = sdFuel = sdBottom = NULL;
  switch (cockpit_estilo) {
    case 1: montarCockpit1(); break;
    case 2: montarCockpit2(); break;
    case 3: montarCockpit3(); break;
    case 4: montarCockpit4(); break;
    case 5: montarCockpit5(); break;
    case 6: montarCockpit6(); break;
    default: montarCockpit0();
  }
}

// Bateria estilo iPhone. A TENSAO em texto aparece sempre (ligado = alternador,
// desligado = bateria). Mas o ICONE de saude (11.0V vazio -> 12.6V cheio) so faz
// sentido com o carro DESLIGADO: ligado, os ~14V sao do alternador, nao da bateria.
static void atualizarBateria(float v, bool ligado) {
  if (batTxt) {   // tensao em texto: sempre
    char b[10];
    if (v > 0.5f) snprintf(b, sizeof(b), "%.1fV", v); else snprintf(b, sizeof(b), "--V");
    lv_label_set_text(batTxt, b);
  }
  if (!batBody) return;
  if (ligado) {   // esconde o icone de saude com o motor ligado
    lv_obj_add_flag(batBody, LV_OBJ_FLAG_HIDDEN);
    if (batNub) lv_obj_add_flag(batNub, LV_OBJ_FLAG_HIDDEN);
    return;
  }
  lv_obj_clear_flag(batBody, LV_OBJ_FLAG_HIDDEN);
  if (batNub) lv_obj_clear_flag(batNub, LV_OBJ_FLAG_HIDDEN);
  if (!batFill) return;
  float pct = (v - 11.0f) / 1.6f;
  if (pct < 0) pct = 0;
  if (pct > 1) pct = 1;
  int w = (int)(pct * batInnerW + 0.5f);
  if (w < 3 && v > 0.5f) w = 3;   // sempre mostra um tracinho se ha leitura valida
  lv_obj_set_width(batFill, w);
  uint32_t cor = (pct < 0.20f) ? 0xFF3B30 : (pct < 0.50f ? 0xFFCC00 : 0x34C759);
  lv_obj_set_style_bg_color(batFill, lv_color_hex(cor), 0);
}

// ---------- Atualiza o cockpit com dados REAIS ----------
void atualizarCockpit(DadosCarro &d) {
  static int t = 0, blinkT = 0; static bool blink = false;
  static int alertIdx = 0, alertCnt = 0;
  static char alerts[6][20];
  static int last_arc = -1, last_band = -1, last_alertIdx = -1;
  static int last_sdst = -99, last_sdai = -99;   // v7 tema Saude: estado/aviso da barra

  if (pagina_montada_nova) {
    last_arc = -1; last_band = -1; last_alertIdx = -1; alertCnt = 0; popup_shown = false;
    last_sdst = -99; last_sdai = -99;
    pagina_montada_nova = false;
  }

  int rpm = d.rpm > 0 ? d.rpm : 0;
  int vel = d.velocidade > 0 ? d.velocidade : 0;
  bool ligado = (rpm > 0);

  // Atualizacao GENERICA (funciona em qualquer estilo -> checa NULL em cada widget).
  char b[24];
  if (lblVel) { snprintf(b, sizeof(b), "%d", vel);  lv_label_set_text(lblVel, b); }
  if (lblRpm) { snprintf(b, sizeof(b), "%d", rpm);  lv_label_set_text(lblRpm, b); }

  int arc = rpm / 1000;
  if (cockpit_estilo == 4) {
    // Painel Duplo: ESQUERDA = velocidade (0-220), DIREITA = RPM (0-8 mil)
    static int last_vel_c = -1, last_rpm_c = -1;
    if (meter && indArco && vel != last_vel_c) { lv_meter_set_indicator_end_value(meter, indArco, vel); last_vel_c = vel; }
    int ra = arc > 8 ? 8 : arc;
    if (meter2 && indArco2 && ra != last_rpm_c) { lv_meter_set_indicator_end_value(meter2, indArco2, ra); last_rpm_c = ra; }
    if (barFuel && d.combust >= 0) lv_bar_set_value(barFuel, d.combust, LV_ANIM_OFF);
    if (barTemp && d.temp_motor > -40) lv_bar_set_value(barTemp, d.temp_motor, LV_ANIM_OFF);
  } else {
    if (arc > meterMax) arc = meterMax;   // nao deixa o arco passar do fim da escala
    if (arc != last_arc) {
      if (meter && indArco) lv_meter_set_indicator_end_value(meter, indArco, arc);
      last_arc = arc;
    }
  }
  if (cockpit_estilo == 5) {   // Performance: barra de COMBUSTIVEL (barFuel) e de TENSAO (barTemp)
    if (barFuel && d.combust >= 0) lv_bar_set_value(barFuel, d.combust, LV_ANIM_OFF);
    if (barTemp && d.tensao > 0) {
      int vp = (int)((d.tensao - 11.0f) / 4.0f * 100.0f);   // 11V=0%  15V=100%
      if (vp < 0) vp = 0; if (vp > 100) vp = 100;
      lv_bar_set_value(barTemp, vp, LV_ANIM_OFF);
    }
    // LUZ do RPM: posiciona o marcador na arco conforme a rotacao (0..8000 -> 135..405 graus)
    if (rpmMarker) {
      int rr = rpm; if (rr > 8000) rr = 8000; if (rr < 0) rr = 0;
      int ang = 135 + (int)((long)rr * 270 / 8000);
      int dx = ((int32_t)68 * lv_trigo_sin((int16_t)((ang + 90) % 360))) >> 15;   // cos
      int dy = ((int32_t)68 * lv_trigo_sin((int16_t)(ang % 360))) >> 15;          // sin
      static int mkx = -999, mky = -999;
      int nx = 160 + dx - 5, ny = 114 + dy - 5;   // -5 = metade do marcador (10px)
      if (nx != mkx || ny != mky) { lv_obj_set_pos(rpmMarker, nx, ny); mkx = nx; mky = ny; }
    }
  }
  if (barRpm) lv_bar_set_value(barRpm, rpm, LV_ANIM_OFF);
  if (barVel) lv_bar_set_value(barVel, vel, LV_ANIM_OFF);

  if (d.temp_motor > -40 && lblTemp) {
    // no classico o rotulo do valor ja diz "TEMP"; nos demais o titulo fica ao lado -> so o numero+C.
    if (cockpit_estilo == 0) snprintf(b, sizeof(b), "TEMP %dC", d.temp_motor);
    else                     snprintf(b, sizeof(b), "%dC", d.temp_motor);
    lv_label_set_text(lblTemp, b);
    int band = d.temp_motor > 100 ? 1 : 0;
    if (band != last_band) {
      uint32_t corOk = (cockpit_estilo == 5) ? 0xFFFFFF : 0x4CAF50;   // Performance: branco; demais: verde
      lv_obj_set_style_text_color(lblTemp, band ? lv_color_hex(0xFF9800) : lv_color_hex(corOk), 0);
      last_band = band;
    }
  }

  if (lblVoltTit) {
    if (cockpit_estilo == 5)   // Performance: palavra inteira, sem simbolo
      lv_label_set_text(lblVoltTit, ligado ? "ALTERNADOR" : "BATERIA");
    else
      lv_label_set_text(lblVoltTit, ligado ? (LV_SYMBOL_CHARGE " ALTERN.") : (LV_SYMBOL_BATTERY_FULL " BAT."));
  }
  if (lblVolt && d.tensao > 0) { snprintf(b, sizeof(b), "%.1fV", d.tensao); lv_label_set_text(lblVolt, b); }
  atualizarBateria(d.tensao, ligado);   // tensao sempre; icone de saude so com carro desligado

  if (lblComb) {
    if (d.combust >= 0) { snprintf(b, sizeof(b), "%d%%", d.combust); lv_label_set_text(lblComb, b); }
    else lv_label_set_text(lblComb, "--");
  }

  t++;
  if (t % 60 == 0) {
    // usa a hora do CACHE (taskRTC), NAO le o RTC (I2C) aqui. Assim a tela nunca
    // trava no barramento -> era isso que reiniciava o aparelho andando.
    uint8_t hh = 0, mm = 0, dd = 1, mo = 1; uint16_t yy = 2026;
    if (xSemaphoreTake(mutex_hora, pdMS_TO_TICKS(30)) == pdTRUE) {
      hh = hora_h; mm = hora_m; dd = data_dia; mo = data_mes; yy = data_ano;
      xSemaphoreGive(mutex_hora);
    }
    if (lblHora) { snprintf(b, sizeof(b), "%02d:%02d", hh, mm); lv_label_set_text(lblHora, b); }
    if (lblData) { snprintf(b, sizeof(b), "%02d/%02d/%04d", dd, mo, yy); lv_label_set_text(lblData, b); }

    alertCnt = 0;
    uint32_t km = (km_total_x100 + km_acumulado_x100) / 100;
    uint32_t ts = rtc_unix_cache;
    // TEMP ALTA so alarma se PERSISTIR >110C por 5s (evita alarme falso de glitch/partida).
    {
      static uint32_t t_quente = 0;
      uint32_t ag = millis();
      if (d.temp_motor > 110 && d.temp_motor <= 130) { if (t_quente == 0) t_quente = ag; }
      else t_quente = 0;
      if (t_quente && ag - t_quente >= 5000) snprintf(alerts[alertCnt++], 20, "TEMP ALTA");
      // v7: aviso ANTECIPADO (102-110C) — heads-up antes de virar critico
      static uint32_t t_subindo = 0;
      if (d.temp_motor > 102 && d.temp_motor <= 110) { if (t_subindo == 0) t_subindo = ag; }
      else t_subindo = 0;
      if (!t_quente && t_subindo && ag - t_subindo >= 5000 && alertCnt < 6)
        snprintf(alerts[alertCnt++], 20, "TEMP SUBINDO");
    }
    if (hora_nao_ajustada) snprintf(alerts[alertCnt++], 20, "AJUSTAR HORA");
    // alertas de tensao: condicao tem que persistir alguns segundos para aparecer (evita falso alarme)
    {
      static uint32_t t_alt = 0, t_sob = 0, t_bat = 0;
      uint32_t agora = millis();
      bool c_alt = ligado && d.tensao > 0 && d.tensao < 12.2f;   // alerta so ABAIXO de 12.2V
      // CORRECAO C: SOBRECARGA com tensao ACIMA de 14.5V (era 15.0V)
      bool c_sob = ligado && d.tensao > 14.5f;
      bool c_bat = !ligado && d.tensao > 0 && d.tensao <= 12.0f;
      if (c_alt) { if (t_alt == 0) t_alt = agora; } else t_alt = 0;
      if (c_sob) { if (t_sob == 0) t_sob = agora; } else t_sob = 0;
      if (c_bat) { if (t_bat == 0) t_bat = agora; } else t_bat = 0;
      if (t_alt && agora - t_alt >= 4000) snprintf(alerts[alertCnt++], 20, "ALTERNADOR");
      // CORRECAO C: SOBRECARGA dispara apos mais de 3s sustentados (era 4s)
      if (t_sob && agora - t_sob >= 3000) snprintf(alerts[alertCnt++], 20, "SOBRECARGA");
      if (t_bat && agora - t_bat >= 4000) snprintf(alerts[alertCnt++], 20, "BATERIA FRACA");
    }
    // v7: aviso PREDITIVO de bateria (tendencia de repouso caindo ao longo dos dias)
    if (alerta_bateria_prev && alertCnt < 6) snprintf(alerts[alertCnt++], 20, "TROCAR BATERIA");
    if (alerta_combustivel_discrep && alertCnt < 6) snprintf(alerts[alertCnt++], 20, "COMBUSTIVEL %.0f%%", fuel_dif_pct);
    for (int i = 0; i < NUM_ITENS_MANUT && alertCnt < 6; i++)
      if (itemVencido(i, km, ts)) snprintf(alerts[alertCnt++], 20, "TROCAR %s", NOMES_ITENS[i]);
    if (alertCnt > 0) alertIdx = alertIdx % alertCnt; else alertIdx = 0;
  }
  if (alertCnt > 1 && t % 130 == 0) alertIdx = (alertIdx + 1) % alertCnt;

  // TEMP ALTA e critico: fica FIXO e piscando forte. Os demais avisos aparecem
  // em ciclo (5s visivel / 15s oculto) p/ nao cobrir a tela o tempo todo.
  bool tempCritica = false;
  for (int i = 0; i < alertCnt; i++) if (strcmp(alerts[i], "TEMP ALTA") == 0) { tempCritica = true; break; }

  // ===== v7 tema SAUDE: atualiza os 3 numeros + a barra de status =====
  if (cockpit_estilo == 6) {
    char sb[16];
    if (sdTemp) {
      if (d.temp_motor > -40) {
        snprintf(sb, sizeof(sb), "%dC", d.temp_motor);
        lv_label_set_text(sdTemp, sb);
        uint32_t c = d.temp_motor > 110 ? 0xFF1744 : (d.temp_motor > 102 ? 0xFFC107 : 0xFFFFFF);
        lv_obj_set_style_text_color(sdTemp, lv_color_hex(c), 0);
      } else lv_label_set_text(sdTemp, "--");
    }
    if (sdBat) {
      if (d.tensao > 0.5f) {
        snprintf(sb, sizeof(sb), "%.1fV", d.tensao);
        lv_label_set_text(sdBat, sb);
        bool ruim = (ligado && (d.tensao < 12.2f || d.tensao > 14.7f)) ||
                    (!ligado && d.tensao <= 12.0f) || alerta_bateria_prev;
        lv_obj_set_style_text_color(sdBat, lv_color_hex(ruim ? 0xFFC107 : 0xFFFFFF), 0);
      } else lv_label_set_text(sdBat, "--");
    }
    if (sdComb) {
      if (d.combust >= 0) {
        snprintf(sb, sizeof(sb), "%d%%", d.combust);
        lv_label_set_text(sdComb, sb);
        lv_obj_set_style_text_color(sdComb, lv_color_hex(d.combust < 10 ? 0xFFC107 : 0xFFFFFF), 0);
        if (sdFuel) lv_bar_set_value(sdFuel, d.combust, LV_ANIM_OFF);
      } else lv_label_set_text(sdComb, "--");
    }
    // barra de status: vermelho (pare) / amarelo (atencao) / verde (ok)
    int st = tempCritica ? 2 : (alertCnt > 0 ? 1 : 0);
    uint32_t bg, brd; const char* ico; const char* msg;
    if (st == 2)      { bg = 0x3A0B0B; brd = 0xFF1744; ico = LV_SYMBOL_WARNING; msg = "PARE - MOTOR QUENTE"; }
    else if (st == 1) { bg = 0x332600; brd = 0xFFC107; ico = LV_SYMBOL_WARNING; msg = alerts[alertIdx]; }
    else              { bg = 0x0E3320; brd = 0x69F0AE; ico = LV_SYMBOL_OK;      msg = "TUDO CERTO"; }
    if (sdBand && st != last_sdst) {
      lv_obj_set_style_bg_color(sdBand, lv_color_hex(bg), 0);
      lv_obj_set_style_border_color(sdBand, lv_color_hex(brd), 0);
      lv_label_set_text(sdBandIco, ico);
      lv_obj_set_style_text_color(sdBandIco, lv_color_hex(brd), 0);
      lv_obj_set_style_text_color(sdBandTxt, lv_color_hex(brd), 0);
      lv_label_set_text(sdBandTxt, msg);
      lv_obj_align(sdBandTxt, LV_ALIGN_CENTER, 12, 0);
      last_sdst = st; last_sdai = alertIdx;
    } else if (sdBandTxt && st == 1 && alertIdx != last_sdai) {
      lv_label_set_text(sdBandTxt, msg);      // amarelo: cicla entre os avisos
      lv_obj_align(sdBandTxt, LV_ALIGN_CENTER, 12, 0);
      last_sdai = alertIdx;
    }
    if (sdBottom) {
      if (st == 0) {
        uint32_t kmv = (km_total_x100 + km_acumulado_x100) / 100;
        snprintf(sb, sizeof(sb), "%lu km", (unsigned long)kmv);
        lv_label_set_text(sdBottom, sb);
      } else if (alerta_bateria_prev && bateria_semanas_est > 0) {
        snprintf(sb, sizeof(sb), "bateria: ~%d sem.", bateria_semanas_est);
        lv_label_set_text(sdBottom, sb);
      } else {
        lv_label_set_text(sdBottom, "");
      }
    }
  }

  static uint32_t alerta_desde = 0;
  if (alertCnt > 0) { if (alerta_desde == 0) alerta_desde = millis(); }
  else alerta_desde = 0;

  blinkT++;
  bool blink_changed = false;
  int blinkDiv = tempCritica ? 18 : 33;                 // temp critica pisca mais rapido (mais forte)
  if (blinkT % blinkDiv == 0) { blink = !blink; blink_changed = true; }

  // janela de exibicao: temp critica SEMPRE; avisos normais 5s on / 15s off (ciclo 20s)
  bool janela = tempCritica || (alerta_desde && ((millis() - alerta_desde) % 20000UL) < 5000UL);

  if (!popup) {
    // tema sem popup (ex.: Saude) — a barra de status ja mostra o estado. Nao mexe.
  } else if (alertCnt == 0 || !janela) {
    if (popup_shown) { lv_obj_add_flag(popup, LV_OBJ_FLAG_HIDDEN); popup_shown = false; }
  } else {
    if (!popup_shown) {
      lv_obj_clear_flag(popup, LV_OBJ_FLAG_HIDDEN); popup_shown = true; blink_changed = true; last_alertIdx = -1;
      // U3: desliza suave de cima pra baixo (estilo notificacao)
      lv_anim_t a; lv_anim_init(&a); lv_anim_set_var(&a, popup);
      lv_anim_set_values(&a, POPUP_Y_FECHADO, POPUP_Y_ABERTO); lv_anim_set_time(&a, 260);
      lv_anim_set_path_cb(&a, lv_anim_path_ease_out);
      lv_anim_set_exec_cb(&a, popupSlideCb); lv_anim_start(&a);
    }
    if (tempCritica) {
      if (last_alertIdx != -2) { lv_label_set_text(popupMsg, "TEMP ALTA"); last_alertIdx = -2; }
    } else {
      if (alertIdx != last_alertIdx) { lv_label_set_text(popupMsg, alerts[alertIdx]); last_alertIdx = alertIdx; }
    }
    if (blink_changed) {
      if (tempCritica) {
        // pisca FORTE: fundo e borda em vermelho vivo, texto branco pulsante
        lv_obj_set_style_bg_color(popup, blink ? lv_color_hex(0x7A0A0A) : lv_color_hex(0x1A0707), 0);
        lv_obj_set_style_border_color(popup, blink ? lv_color_hex(0xFF1744) : lv_color_hex(0x8A0A0A), 0);
        lv_obj_set_style_text_color(popupIcon, blink ? lv_color_hex(0xFFFFFF) : lv_color_hex(0xFF1744), 0);
        lv_obj_set_style_text_color(popupMsg, blink ? lv_color_hex(0xFFFFFF) : lv_color_hex(0xFF5252), 0);
      } else {
        lv_obj_set_style_bg_color(popup, lv_color_hex(0x1A0707), 0);   // restaura fundo padrao
        lv_color_t forte = blink ? lv_color_hex(0xFF1744) : lv_color_hex(0x5A1414);
        lv_color_t txt   = blink ? lv_color_hex(0xFF6B6B) : lv_color_hex(0x7A2A2A);
        lv_obj_set_style_border_color(popup, forte, 0);
        lv_obj_set_style_text_color(popupIcon, forte, 0);
        lv_obj_set_style_text_color(popupMsg, txt, 0);
      }
    }
  }
}

// ============================================================
//  Pagina de Manutencao (LVGL)
// ============================================================
void montarManut() {
  lv_obj_t* scr = lv_scr_act();
  gManut = lv_obj_create(scr);
  lv_obj_set_size(gManut, LV_W, LV_H);
  lv_obj_center(gManut);
  lv_obj_set_style_bg_color(gManut, lv_color_hex(0x05070D), 0);
  lv_obj_set_style_border_width(gManut, 0, 0);
  lv_obj_set_style_pad_all(gManut, 0, 0);
  lv_obj_clear_flag(gManut, LV_OBJ_FLAG_SCROLLABLE);

  lv_obj_t* tit = lv_label_create(gManut);
  lv_label_set_text(tit, "MANUTENCAO");
  lv_obj_set_style_text_font(tit, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(tit, lv_color_hex(0x4DD0E1), 0);
  lv_obj_align(tit, LV_ALIGN_TOP_MID, 0, 5);

  // Lista ROLAVEL (10 itens nao cabem na tela): o titulo fica fixo em cima e a
  // lista rola; o item selecionado e trazido pra vista em atualizarManut().
  manutLista = lv_obj_create(gManut);
  lv_obj_set_size(manutLista, LV_W, LV_H - 24);
  lv_obj_set_pos(manutLista, 0, 24);
  lv_obj_set_style_bg_opa(manutLista, LV_OPA_TRANSP, 0);
  lv_obj_set_style_border_width(manutLista, 0, 0);
  lv_obj_set_style_pad_all(manutLista, 0, 0);
  lv_obj_set_scroll_dir(manutLista, LV_DIR_VER);
  lv_obj_set_scrollbar_mode(manutLista, LV_SCROLLBAR_MODE_OFF);

  manutSel = lv_obj_create(manutLista);
  lv_obj_set_size(manutSel, 308, 38);
  lv_obj_set_style_bg_color(manutSel, lv_color_hex(0x16263A), 0);
  lv_obj_set_style_bg_opa(manutSel, LV_OPA_COVER, 0);
  lv_obj_set_style_border_color(manutSel, lv_color_hex(0x00E5FF), 0);
  lv_obj_set_style_border_width(manutSel, 2, 0);
  lv_obj_set_style_radius(manutSel, 6, 0);
  lv_obj_clear_flag(manutSel, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_set_pos(manutSel, 6, 2);

  for (int i = 0; i < NUM_ITENS_MANUT; i++) {
    int y = 2 + i * 40;
    manutIcon[i] = lv_img_create(manutLista);
    lv_img_set_src(manutIcon[i], ICONES_MANUT[i]);
    lv_obj_set_style_img_recolor(manutIcon[i], lv_color_hex(0x00B0FF), 0);
    lv_obj_set_style_img_recolor_opa(manutIcon[i], LV_OPA_COVER, 0);
    lv_obj_set_pos(manutIcon[i], 8, y + 4);

    manutNome[i] = lv_label_create(manutLista);
    lv_label_set_text(manutNome[i], NOMES_ITENS[i]);
    lv_obj_set_style_text_font(manutNome[i], &lv_font_montserrat_28, 0);
    lv_obj_set_style_text_color(manutNome[i], lv_color_hex(0x00B0FF), 0);
    lv_obj_set_pos(manutNome[i], 48, y + 2);

    manutPct[i] = lv_label_create(manutLista);
    lv_label_set_text(manutPct[i], "--");
    lv_obj_set_style_text_font(manutPct[i], &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_color(manutPct[i], lv_color_hex(0x00B0FF), 0);
    lv_obj_align(manutPct[i], LV_ALIGN_TOP_RIGHT, -12, y + 6);

    manutBar[i] = lv_bar_create(manutLista);
    lv_obj_set_size(manutBar[i], 208, 5);
    lv_obj_set_pos(manutBar[i], 48, y + 31);
    lv_bar_set_range(manutBar[i], 0, 100);
    lv_bar_set_value(manutBar[i], 0, LV_ANIM_OFF);
    lv_obj_set_style_bg_color(manutBar[i], lv_color_hex(0x16263A), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(manutBar[i], LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_radius(manutBar[i], 2, LV_PART_MAIN);
    lv_obj_set_style_bg_color(manutBar[i], lv_color_hex(0x00B0FF), LV_PART_INDICATOR);
    lv_obj_set_style_radius(manutBar[i], 2, LV_PART_INDICATOR);
  }

  manutConfirm = lv_obj_create(gManut);
  lv_obj_set_size(manutConfirm, 280, 100);
  lv_obj_center(manutConfirm);
  lv_obj_set_style_bg_color(manutConfirm, lv_color_hex(0x0A1420), 0);
  lv_obj_set_style_bg_opa(manutConfirm, LV_OPA_COVER, 0);
  lv_obj_set_style_border_color(manutConfirm, lv_color_hex(0x00E5FF), 0);
  lv_obj_set_style_border_width(manutConfirm, 3, 0);
  lv_obj_set_style_radius(manutConfirm, 10, 0);
  lv_obj_clear_flag(manutConfirm, LV_OBJ_FLAG_SCROLLABLE);

  lv_obj_t* cfTit = lv_label_create(manutConfirm);
  lv_label_set_text(cfTit, "RESETAR?");
  lv_obj_set_style_text_font(cfTit, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(cfTit, lv_color_white(), 0);
  lv_obj_align(cfTit, LV_ALIGN_TOP_MID, 0, 4);

  manutConfirmNome = lv_label_create(manutConfirm);
  lv_label_set_text(manutConfirmNome, "");
  lv_obj_set_style_text_font(manutConfirmNome, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(manutConfirmNome, lv_color_hex(0xB0BEC5), 0);
  lv_obj_align(manutConfirmNome, LV_ALIGN_TOP_MID, 0, 36);

  manutConfirmSim = lv_label_create(manutConfirm);
  lv_label_set_text(manutConfirmSim, "SIM");
  lv_obj_set_style_text_font(manutConfirmSim, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(manutConfirmSim, lv_color_hex(0x555E68), 0);
  lv_obj_align(manutConfirmSim, LV_ALIGN_BOTTOM_LEFT, 30, -6);

  manutConfirmNao = lv_label_create(manutConfirm);
  lv_label_set_text(manutConfirmNao, "NAO");
  lv_obj_set_style_text_font(manutConfirmNao, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(manutConfirmNao, lv_color_hex(0x00E5FF), 0);
  lv_obj_align(manutConfirmNao, LV_ALIGN_BOTTOM_RIGHT, -30, -6);

  lv_obj_add_flag(manutConfirm, LV_OBJ_FLAG_HIDDEN);
}

void atualizarManut() {
  static int last_pct[NUM_ITENS_MANUT];   // zerado; a rotina de reset abaixo poe tudo em -1
  static bool init_pct = false;
  if (!init_pct) { for (int i = 0; i < NUM_ITENS_MANUT; i++) last_pct[i] = -1; init_pct = true; }
  static int last_sel = -1;
  static uint32_t prox = 0;
  static bool last_confirm = false;
  static int last_csel = -1;

  if (pagina_montada_nova) {
    for (int i = 0; i < NUM_ITENS_MANUT; i++) last_pct[i] = -1;
    last_sel = -1; prox = 0;
    last_confirm = false; last_csel = -1;
    manut_confirma_reset = false;
    pagina_montada_nova = false;
  }

  uint32_t agora = millis();
  if (agora >= prox) {
    prox = agora + 500;
    uint32_t km_atual = 0;
    if (xSemaphoreTake(mutex_hodometro, pdMS_TO_TICKS(50)) == pdTRUE) {
      km_atual = (km_total_x100 + km_acumulado_x100) / 100; xSemaphoreGive(mutex_hodometro);
    }
    uint32_t ts_atual = rtcNow().unixtime();
    for (int i = 0; i < NUM_ITENS_MANUT; i++) {
      uint16_t pct = itemPercentual(i, km_atual, ts_atual);
      if ((int)pct != last_pct[i]) {
        bool vencido = itemVencido(i, km_atual, ts_atual);
        lv_color_t cor = vencido ? lv_color_hex(0xFF1744)
                                 : (pct >= 80 ? lv_color_hex(0xFFC107) : lv_color_hex(0x00B0FF));
        lv_obj_set_style_text_color(manutNome[i], cor, 0);
        lv_obj_set_style_img_recolor(manutIcon[i], cor, 0);
        int pv = pct > 100 ? 100 : pct;
        lv_bar_set_value(manutBar[i], pv, LV_ANIM_OFF);
        lv_obj_set_style_bg_color(manutBar[i], cor, LV_PART_INDICATOR);
        char pbuf[12];
        if (vencido) snprintf(pbuf, sizeof(pbuf), "VENC.");
        else         snprintf(pbuf, sizeof(pbuf), "%d%%", pct);
        lv_label_set_text(manutPct[i], pbuf);
        lv_obj_set_style_text_color(manutPct[i], cor, 0);
        last_pct[i] = pct;
      }
    }
  }

  int sel = item_manut_selecionado; if (sel >= NUM_ITENS_MANUT) sel = 0;
  if (sel != last_sel) {
    lv_obj_set_pos(manutSel, 6, 2 + sel * 40);
    lv_obj_scroll_to_view(manutNome[sel], LV_ANIM_ON);   // rola a lista p/ mostrar o selecionado
    last_sel = sel;
  }

  bool cf = manut_confirma_reset;
  if (cf != last_confirm) {
    if (cf) {
      lv_label_set_text(manutConfirmNome, NOMES_ITENS[sel]);
      lv_obj_clear_flag(manutConfirm, LV_OBJ_FLAG_HIDDEN);
    } else {
      lv_obj_add_flag(manutConfirm, LV_OBJ_FLAG_HIDDEN);
    }
    last_confirm = cf; last_csel = -1;
  }
  if (cf) {
    int csel = manut_confirma_selecionado;
    if (csel != last_csel) {
      lv_color_t selCor = lv_color_hex(0x00E5FF), dimCor = lv_color_hex(0x555E68);
      lv_obj_set_style_text_color(manutConfirmSim, csel == 0 ? selCor : dimCor, 0);
      lv_obj_set_style_text_color(manutConfirmNao, csel == 1 ? selCor : dimCor, 0);
      last_csel = csel;
    }
  }
}

// ============================================================
//  Pagina de Diagnostico (LVGL)
// ============================================================
static inline void diagShow(lv_obj_t* o, bool vis) {
  if (vis) lv_obj_clear_flag(o, LV_OBJ_FLAG_HIDDEN);
  else     lv_obj_add_flag(o, LV_OBJ_FLAG_HIDDEN);
}

void montarDiag() {
  lv_obj_t* scr = lv_scr_act();
  gDiag = lv_obj_create(scr);
  lv_obj_set_size(gDiag, LV_W, LV_H);
  lv_obj_center(gDiag);
  lv_obj_set_style_bg_color(gDiag, lv_color_hex(0x05070D), 0);
  lv_obj_set_style_border_width(gDiag, 0, 0);
  lv_obj_set_style_pad_all(gDiag, 0, 0);
  lv_obj_clear_flag(gDiag, LV_OBJ_FLAG_SCROLLABLE);

  diagTit = lv_label_create(gDiag);
  lv_label_set_text(diagTit, "DIAGNOSTICO");
  lv_obj_set_style_text_font(diagTit, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(diagTit, lv_color_hex(0x4DD0E1), 0);
  lv_obj_align(diagTit, LV_ALIGN_TOP_MID, 0, 6);

  diagSel = lv_obj_create(gDiag);
  lv_obj_set_size(diagSel, 300, 44);
  lv_obj_set_style_bg_color(diagSel, lv_color_hex(0x16263A), 0);
  lv_obj_set_style_bg_opa(diagSel, LV_OPA_COVER, 0);
  lv_obj_set_style_border_color(diagSel, lv_color_hex(0x00E5FF), 0);
  lv_obj_set_style_border_width(diagSel, 2, 0);
  lv_obj_set_style_radius(diagSel, 6, 0);
  lv_obj_clear_flag(diagSel, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_set_pos(diagSel, 10, 52);

  const char* itens[] = { "Ler codigos", "Apagar codigos", "Voltar" };
  for (int i = 0; i < 3; i++) {
    diagM[i] = lv_label_create(gDiag);
    lv_label_set_text(diagM[i], itens[i]);
    lv_obj_set_style_text_font(diagM[i], &lv_font_montserrat_28, 0);
    lv_obj_set_style_text_color(diagM[i], lv_color_white(), 0);
    lv_obj_set_pos(diagM[i], 24, 58 + i * 52);
  }

  diagMsg = lv_label_create(gDiag);
  lv_label_set_text(diagMsg, "");
  lv_obj_set_style_text_font(diagMsg, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(diagMsg, lv_color_white(), 0);
  lv_obj_align(diagMsg, LV_ALIGN_CENTER, 0, 0);
  lv_obj_add_flag(diagMsg, LV_OBJ_FLAG_HIDDEN);

  // U1: SELO de gravidade (pare / oficina / pode rodar) — grande e colorido
  diagBadge = lv_obj_create(gDiag);
  lv_obj_set_size(diagBadge, 296, 44);
  lv_obj_set_pos(diagBadge, 12, 64);
  lv_obj_set_style_radius(diagBadge, 10, 0);
  lv_obj_set_style_border_width(diagBadge, 0, 0);
  lv_obj_set_style_pad_all(diagBadge, 0, 0);
  lv_obj_clear_flag(diagBadge, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_add_flag(diagBadge, LV_OBJ_FLAG_HIDDEN);
  diagBadgeTxt = lv_label_create(diagBadge);
  lv_obj_set_style_text_font(diagBadgeTxt, &lv_font_montserrat_14, 0);
  lv_obj_center(diagBadgeTxt);

  diagLista = lv_label_create(gDiag);
  lv_label_set_text(diagLista, "");
  lv_obj_set_style_text_font(diagLista, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(diagLista, lv_color_hex(0xFFC107), 0);
  lv_label_set_long_mode(diagLista, LV_LABEL_LONG_WRAP);
  lv_obj_set_width(diagLista, 296);
  lv_obj_set_pos(diagLista, 12, 118);
  lv_obj_add_flag(diagLista, LV_OBJ_FLAG_HIDDEN);

  diagSim = lv_label_create(gDiag);
  lv_label_set_text(diagSim, "SIM");
  lv_obj_set_style_text_font(diagSim, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(diagSim, lv_color_hex(0x555E68), 0);
  lv_obj_align(diagSim, LV_ALIGN_BOTTOM_LEFT, 40, -16);
  lv_obj_add_flag(diagSim, LV_OBJ_FLAG_HIDDEN);

  diagNao = lv_label_create(gDiag);
  lv_label_set_text(diagNao, "NAO");
  lv_obj_set_style_text_font(diagNao, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(diagNao, lv_color_hex(0x00E5FF), 0);
  lv_obj_align(diagNao, LV_ALIGN_BOTTOM_RIGHT, -40, -16);
  lv_obj_add_flag(diagNao, LV_OBJ_FLAG_HIDDEN);
}

void atualizarDiag() {
  static int last_estado = -1, last_msel = -1, last_csel = -1, last_ndtc = -1;
  if (pagina_montada_nova) {
    diag_estado = DIAG_ESTADO_MENU; diag_menu_selecionado = 0;
    last_estado = -1; last_msel = -1; last_csel = -1; last_ndtc = -1;
    pagina_montada_nova = false;
  }
  int est = diag_estado;
  bool refazer = (est != last_estado) ||
                 (est == DIAG_ESTADO_RESULTADO && (int)diag_num_dtcs != last_ndtc);

  if (refazer) {
    bool isMenu = (est == DIAG_ESTADO_MENU);
    bool isConf = (est == DIAG_ESTADO_CONFIRMAR);
    bool isResu = (est == DIAG_ESTADO_RESULTADO);
    diagShow(diagSel, isMenu);
    for (int i = 0; i < 3; i++) diagShow(diagM[i], isMenu);
    diagShow(diagSim, isConf);
    diagShow(diagNao, isConf);
    diagShow(diagLista, isResu && diag_num_dtcs > 0);
    diagShow(diagBadge, isResu && diag_num_dtcs > 0);
    diagShow(diagMsg, !isMenu);

    if (est == DIAG_ESTADO_LENDO) {
      lv_label_set_text(diagMsg, "Lendo...");
      lv_obj_set_style_text_color(diagMsg, lv_color_hex(0x4DD0E1), 0);
      lv_obj_align(diagMsg, LV_ALIGN_CENTER, 0, 0);
    } else if (est == DIAG_ESTADO_APAGANDO) {
      lv_label_set_text(diagMsg, "Apagando...");
      lv_obj_set_style_text_color(diagMsg, lv_color_hex(0x4DD0E1), 0);
      lv_obj_align(diagMsg, LV_ALIGN_CENTER, 0, 0);
    } else if (est == DIAG_ESTADO_APAGADO_OK) {
      lv_label_set_text(diagMsg, LV_SYMBOL_OK " Apagado!");
      lv_obj_set_style_text_color(diagMsg, lv_color_hex(0x4CAF50), 0);
      lv_obj_align(diagMsg, LV_ALIGN_CENTER, 0, 0);
    } else if (isConf) {
      lv_label_set_text(diagMsg, "Apagar tudo?");
      lv_obj_set_style_text_color(diagMsg, lv_color_hex(0xFF5252), 0);
      lv_obj_align(diagMsg, LV_ALIGN_TOP_MID, 0, 50);
    } else if (isResu) {
      if (diag_num_dtcs == 0) {
        lv_label_set_text(diagMsg, LV_SYMBOL_OK " Nenhum codigo");
        lv_obj_set_style_text_color(diagMsg, lv_color_hex(0x4CAF50), 0);
        lv_obj_align(diagMsg, LV_ALIGN_CENTER, 0, 0);
      } else {
        char buf[28];
        snprintf(buf, sizeof(buf), LV_SYMBOL_WARNING " %d codigo(s)", diag_num_dtcs);
        lv_label_set_text(diagMsg, buf);
        lv_obj_set_style_text_color(diagMsg, lv_color_hex(0xFF5252), 0);
        lv_obj_align(diagMsg, LV_ALIGN_TOP_MID, 0, 40);
        // Buffer estatico (nao pesa a pilha da task de tela). Mostra descricao +
        // causa + gravidade em portugues, o mais grave primeiro.
        static char lista[MAX_DTCS * 240]; lista[0] = 0;
        // ordem por gravidade (3->1): quem pode quebrar o motor aparece no topo
        int ordem[MAX_DTCS]; int nord = 0;
        for (int i = 0; i < diag_num_dtcs && i < MAX_DTCS; i++) ordem[nord++] = i;
        for (int a = 0; a < nord - 1; a++)
          for (int b = a + 1; b < nord; b++) {
            const DtcInfo* da = infoDTC(diag_dtcs[ordem[a]]);
            const DtcInfo* db = infoDTC(diag_dtcs[ordem[b]]);
            uint8_t ga = da ? da->gravidade : 0, gb = db ? db->gravidade : 0;
            if (gb > ga) { int t = ordem[a]; ordem[a] = ordem[b]; ordem[b] = t; }
          }
        // U1: SELO com a PIOR gravidade (ordem[0] = mais grave apos ordenar)
        const DtcInfo* pior = nord ? infoDTC(diag_dtcs[ordem[0]]) : NULL;
        uint8_t gmax = pior ? pior->gravidade : 1;
        uint32_t bg, tc; const char* stxt;
        if (gmax >= 3)      { bg = 0x3A0B0B; tc = 0xFF5252; stxt = LV_SYMBOL_WARNING "  PARE O CARRO"; }
        else if (gmax == 2) { bg = 0x33290A; tc = 0xFFC107; stxt = "OFICINA ESTA SEMANA"; }
        else                { bg = 0x0E3320; tc = 0x69F0AE; stxt = LV_SYMBOL_OK "  PODE RODAR"; }
        lv_obj_set_style_bg_color(diagBadge, lv_color_hex(bg), 0);
        lv_obj_set_style_border_width(diagBadge, 2, 0);
        lv_obj_set_style_border_color(diagBadge, lv_color_hex(tc), 0);
        lv_obj_set_style_text_color(diagBadgeTxt, lv_color_hex(tc), 0);
        lv_label_set_text(diagBadgeTxt, stxt);
        for (int k = 0; k < nord; k++) {
          int i = ordem[k];
          const DtcInfo* d = infoDTC(diag_dtcs[i]);
          char linha[240];
          if (d) {
            const char* marca = (d->gravidade == 3) ? LV_SYMBOL_WARNING " " : "";
            snprintf(linha, sizeof(linha), "%s%s  %s\n   %s\n   [%s]\n\n",
                     marca, diag_dtcs[i], d->descricao, d->causa, gravidadeTexto(d->gravidade));
          } else {
            snprintf(linha, sizeof(linha), "%s  (codigo nao catalogado)\n\n", diag_dtcs[i]);
          }
          strncat(lista, linha, sizeof(lista) - strlen(lista) - 1);
        }
        lv_label_set_text(diagLista, lista);
      }
    }
    last_estado = est; last_ndtc = diag_num_dtcs; last_msel = -1; last_csel = -1;
  }

  if (est == DIAG_ESTADO_MENU) {
    int s = diag_menu_selecionado; if (s > 2) s = 0;
    if (s != last_msel) { lv_obj_set_pos(diagSel, 10, 52 + s * 52); last_msel = s; }
  }
  if (est == DIAG_ESTADO_CONFIRMAR) {
    int c = diag_confirma_selecionado;
    if (c != last_csel) {
      lv_color_t sel = lv_color_hex(0x00E5FF), dim = lv_color_hex(0x555E68);
      lv_obj_set_style_text_color(diagSim, c == 0 ? sel : dim, 0);
      lv_obj_set_style_text_color(diagNao, c == 1 ? sel : dim, 0);
      last_csel = c;
    }
  }
}

// ============================================================
//  Pagina de Ajuste de Hora (LVGL)
// ============================================================
static lv_obj_t* ajNum(lv_obj_t* par, int x, int y, int w) {
  lv_obj_t* l = lv_label_create(par);
  lv_label_set_text(l, "00");
  lv_obj_set_style_text_font(l, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(l, lv_color_white(), 0);
  lv_obj_set_width(l, w);
  lv_obj_set_style_text_align(l, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_set_pos(l, x, y);
  return l;
}
static void ajSep(lv_obj_t* par, const char* s, int x, int y) {
  lv_obj_t* l = lv_label_create(par);
  lv_label_set_text(l, s);
  lv_obj_set_style_text_font(l, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(l, lv_color_hex(0x607D8B), 0);
  lv_obj_set_pos(l, x, y);
}

void montarAjuste() {
  lv_obj_t* scr = lv_scr_act();
  gAjuste = lv_obj_create(scr);
  lv_obj_set_size(gAjuste, LV_W, LV_H);
  lv_obj_center(gAjuste);
  lv_obj_set_style_bg_color(gAjuste, lv_color_hex(0x05070D), 0);
  lv_obj_set_style_border_width(gAjuste, 0, 0);
  lv_obj_set_style_pad_all(gAjuste, 0, 0);
  lv_obj_clear_flag(gAjuste, LV_OBJ_FLAG_SCROLLABLE);

  ajTit = lv_label_create(gAjuste);
  lv_label_set_text(ajTit, "AJUSTE HORA");
  lv_obj_set_style_text_font(ajTit, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(ajTit, lv_color_hex(0x4DD0E1), 0);
  lv_obj_align(ajTit, LV_ALIGN_TOP_MID, 0, 8);

  ajCampo[0] = ajNum(gAjuste, 60, 70, 40);   ajSep(gAjuste, "/", 104, 70);
  ajCampo[1] = ajNum(gAjuste, 118, 70, 40);  ajSep(gAjuste, "/", 162, 70);
  ajCampo[2] = ajNum(gAjuste, 178, 70, 78);

  ajCampo[3] = ajNum(gAjuste, 80, 128, 40);  ajSep(gAjuste, ":", 124, 128);
  ajCampo[4] = ajNum(gAjuste, 138, 128, 40); ajSep(gAjuste, ":", 182, 128);
  ajCampo[5] = ajNum(gAjuste, 196, 128, 40);

  ajSalvar = lv_label_create(gAjuste);
  lv_label_set_text(ajSalvar, LV_SYMBOL_OK " SALVAR");
  lv_obj_set_style_text_font(ajSalvar, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(ajSalvar, lv_color_hex(0x546E7A), 0);
  lv_obj_align(ajSalvar, LV_ALIGN_BOTTOM_MID, 0, -18);
}

void atualizarAjuste() {
  static int last_vals[6] = { -1, -1, -1, -1, -1, -1 };
  static int last_estado = -1;
  if (pagina_montada_nova) {
    for (int i = 0; i < 6; i++) last_vals[i] = -1;
    last_estado = -1; pagina_montada_nova = false;
  }

  int vals[6];
  if (nav_modo == NAV_MODO_EDICAO) {
    vals[0] = ajuste_dia; vals[1] = ajuste_mes; vals[2] = ajuste_ano;
    vals[3] = ajuste_hora; vals[4] = ajuste_min; vals[5] = ajuste_seg;
  } else {
    if (xSemaphoreTake(mutex_hora, pdMS_TO_TICKS(50)) == pdTRUE) {
      vals[0] = data_dia; vals[1] = data_mes; vals[2] = (int)data_ano - 2000;
      vals[3] = hora_h; vals[4] = hora_m; vals[5] = hora_s;
      xSemaphoreGive(mutex_hora);
    } else {
      for (int i = 0; i < 6; i++) vals[i] = last_vals[i];
    }
  }

  for (int i = 0; i < 6; i++) {
    if (vals[i] != last_vals[i]) {
      char b[8];
      if (i == 2) snprintf(b, sizeof(b), "20%02d", vals[i]);
      else        snprintf(b, sizeof(b), "%02d", vals[i]);
      lv_label_set_text(ajCampo[i], b);
      last_vals[i] = vals[i];
    }
  }

  int est = ajuste_estado;
  if (est != last_estado) {
    for (int i = 0; i < 6; i++) {
      bool ativo = (est == AJUSTE_ESTADO_DIA + i);
      lv_obj_set_style_text_color(ajCampo[i], ativo ? lv_color_hex(0x00E5FF) : lv_color_white(), 0);
    }
    lv_obj_set_style_text_color(ajSalvar,
      est == AJUSTE_ESTADO_SALVAR ? lv_color_hex(0x00E5FF) : lv_color_hex(0x546E7A), 0);
    last_estado = est;
  }
}

// ============================================================
//  Pagina Sistema (quilometragem + tempo de motor reais)
// ============================================================
void montarSistema() {
  lv_obj_t* scr = lv_scr_act();
  gSistema = lv_obj_create(scr);
  lv_obj_set_size(gSistema, LV_W, LV_H);
  lv_obj_center(gSistema);
  lv_obj_set_style_bg_color(gSistema, lv_color_hex(0x05070D), 0);
  lv_obj_set_style_border_width(gSistema, 0, 0);
  lv_obj_set_style_pad_all(gSistema, 0, 0);
  lv_obj_clear_flag(gSistema, LV_OBJ_FLAG_SCROLLABLE);

  sisTit = lv_label_create(gSistema);
  lv_label_set_text(sisTit, "SISTEMA");
  lv_obj_set_style_text_font(sisTit, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(sisTit, lv_color_hex(0x4DD0E1), 0);
  lv_obj_align(sisTit, LV_ALIGN_TOP_MID, 0, 8);

  lv_obj_t* l1 = lv_label_create(gSistema);
  lv_label_set_text(l1, "QUILOMETRAGEM");
  lv_obj_set_style_text_font(l1, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(l1, lv_color_hex(0x78909C), 0);
  lv_obj_set_pos(l1, 24, 60);

  sisDist = lv_label_create(gSistema);
  lv_label_set_text(sisDist, "0.0 km");
  lv_obj_set_style_text_font(sisDist, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(sisDist, lv_color_white(), 0);
  lv_obj_set_pos(sisDist, 24, 78);

  lv_obj_t* l2 = lv_label_create(gSistema);
  lv_label_set_text(l2, "TEMPO MOTOR");
  lv_obj_set_style_text_font(l2, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(l2, lv_color_hex(0x78909C), 0);
  lv_obj_set_pos(l2, 24, 130);

  sisTempo = lv_label_create(gSistema);
  lv_label_set_text(sisTempo, "0h 00m");
  lv_obj_set_style_text_font(sisTempo, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(sisTempo, lv_color_white(), 0);
  lv_obj_set_pos(sisTempo, 24, 148);

  lv_obj_t* hint = lv_label_create(gSistema);
  lv_label_set_text(hint, LV_SYMBOL_REFRESH " segure MENU p/ zerar");
  lv_obj_set_style_text_font(hint, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(hint, lv_color_hex(0x546E7A), 0);
  lv_obj_align(hint, LV_ALIGN_BOTTOM_MID, 0, -10);

  // versao do firmware (base pro OTA e pra saber o que esta gravado no campo)
  lv_obj_t* lver = lv_label_create(gSistema);
  lv_label_set_text(lver, FIRMWARE_NOME " v" FIRMWARE_VERSION);
  lv_obj_set_style_text_font(lver, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(lver, lv_color_hex(0x37474F), 0);
  lv_obj_align(lver, LV_ALIGN_TOP_RIGHT, -10, 8);

  sisConfirm = lv_obj_create(gSistema);
  lv_obj_set_size(sisConfirm, 280, 100);
  lv_obj_center(sisConfirm);
  lv_obj_set_style_bg_color(sisConfirm, lv_color_hex(0x1A0707), 0);
  lv_obj_set_style_bg_opa(sisConfirm, LV_OPA_COVER, 0);
  lv_obj_set_style_border_color(sisConfirm, lv_color_hex(0xFF1744), 0);
  lv_obj_set_style_border_width(sisConfirm, 3, 0);
  lv_obj_set_style_radius(sisConfirm, 10, 0);
  lv_obj_clear_flag(sisConfirm, LV_OBJ_FLAG_SCROLLABLE);

  lv_obj_t* cft = lv_label_create(sisConfirm);
  lv_label_set_text(cft, "ZERAR TUDO?");
  lv_obj_set_style_text_font(cft, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(cft, lv_color_white(), 0);
  lv_obj_align(cft, LV_ALIGN_TOP_MID, 0, 8);

  sisConfirmSim = lv_label_create(sisConfirm);
  lv_label_set_text(sisConfirmSim, "SIM");
  lv_obj_set_style_text_font(sisConfirmSim, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(sisConfirmSim, lv_color_hex(0x555E68), 0);
  lv_obj_align(sisConfirmSim, LV_ALIGN_BOTTOM_LEFT, 30, -8);

  sisConfirmNao = lv_label_create(sisConfirm);
  lv_label_set_text(sisConfirmNao, "NAO");
  lv_obj_set_style_text_font(sisConfirmNao, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(sisConfirmNao, lv_color_hex(0x00E5FF), 0);
  lv_obj_align(sisConfirmNao, LV_ALIGN_BOTTOM_RIGHT, -30, -8);

  lv_obj_add_flag(sisConfirm, LV_OBJ_FLAG_HIDDEN);
}

void atualizarSistema() {
  static int last_km10 = -1;
  static long last_min = -1;
  static bool last_cf = false;
  static int last_csel = -1;
  if (pagina_montada_nova) {
    last_km10 = -1; last_min = -1; last_cf = false; last_csel = -1;
    sistema_confirma_zerar = false;
    pagina_montada_nova = false;
  }

  uint32_t total = 0; long seg = 0;
  if (xSemaphoreTake(mutex_hodometro, pdMS_TO_TICKS(50)) == pdTRUE) {
    total = km_total_x100 + km_acumulado_x100;
    seg   = (long)segundos_motor_total;
    xSemaphoreGive(mutex_hodometro);
  }

  int km10 = total / 10;
  if (km10 != last_km10) {
    char b[16]; snprintf(b, sizeof(b), "%d.%d km", km10 / 10, km10 % 10);
    lv_label_set_text(sisDist, b);
    last_km10 = km10;
  }

  long minu = seg / 60;
  if (minu != last_min) {
    int h = minu / 60, m = minu % 60;
    char b[16]; snprintf(b, sizeof(b), "%dh %02dm", h, m);
    lv_label_set_text(sisTempo, b);
    last_min = minu;
  }

  bool cf = sistema_confirma_zerar;
  if (cf != last_cf) {
    if (cf) lv_obj_clear_flag(sisConfirm, LV_OBJ_FLAG_HIDDEN);
    else    lv_obj_add_flag(sisConfirm, LV_OBJ_FLAG_HIDDEN);
    last_cf = cf; last_csel = -1;
  }
  if (cf) {
    int c = sistema_confirma_selecionado;
    if (c != last_csel) {
      lv_color_t sel = lv_color_hex(0x00E5FF), dim = lv_color_hex(0x555E68);
      lv_obj_set_style_text_color(sisConfirmSim, c == 0 ? sel : dim, 0);
      lv_obj_set_style_text_color(sisConfirmNao, c == 1 ? sel : dim, 0);
      last_csel = c;
    }
  }
}

// ---------- Paginas simples (placeholder) ----------
void montarPlaceholder(const char* txt) {
  lv_obj_t* scr = lv_scr_act();
  lv_obj_t* l = lv_label_create(scr);
  lv_label_set_text(l, txt);
  lv_obj_set_style_text_font(l, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(l, lv_color_hex(0x4DD0E1), 0);
  lv_obj_center(l);
}

// ============================================================
//  Pagina TEMAS: usuario escolhe o estilo do painel (0-3)
// ============================================================
static const char* TEMAS_NOME[7] = {"Classico", "Ferrari", "Lamborghini", "Tesla", "Painel Duplo", "Performance", "Saude"};

void montarTemas() {
  lv_obj_t* scr = lv_scr_act();
  gTemas = lv_obj_create(scr);
  lv_obj_set_size(gTemas, LV_W, LV_H);
  lv_obj_center(gTemas);
  lv_obj_set_style_bg_color(gTemas, lv_color_hex(0x05070D), 0);
  lv_obj_set_style_border_width(gTemas, 0, 0);
  lv_obj_set_style_pad_all(gTemas, 0, 0);
  lv_obj_clear_flag(gTemas, LV_OBJ_FLAG_SCROLLABLE);

  rotulo(gTemas, "TEMA DO PAINEL", &lv_font_montserrat_14, 0x4DD0E1, LV_ALIGN_TOP_MID, 0, 2);

  // caixa de selecao (fica atras da opcao escolhida). 6 temas -> linhas de 33px.
  temasSel = lv_obj_create(gTemas);
  lv_obj_set_size(temasSel, 300, 28);
  lv_obj_set_style_bg_color(temasSel, lv_color_hex(0x16263A), 0);
  lv_obj_set_style_border_color(temasSel, lv_color_hex(0x00E5FF), 0);
  lv_obj_set_style_border_width(temasSel, 2, 0);
  lv_obj_set_style_radius(temasSel, 6, 0);
  lv_obj_clear_flag(temasSel, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_set_pos(temasSel, 10, 19);

  tema_sel = cockpit_estilo;
  for (int i = 0; i < 7; i++) {   // 7 temas -> linhas de 28px p/ caber (com o rodape)
    lv_obj_t* nome = lv_label_create(gTemas);
    char buf[40];
    snprintf(buf, sizeof(buf), "%s%s", TEMAS_NOME[i], (i == cockpit_estilo) ? "  " LV_SYMBOL_OK : "");
    lv_label_set_text(nome, buf);
    lv_obj_set_style_text_font(nome, &lv_font_montserrat_28, 0);
    lv_obj_set_style_text_color(nome, lv_color_white(), 0);
    lv_obj_set_pos(nome, 22, 22 + i * 28);
    temasOpt[i] = nome;
  }
  rotulo(gTemas, LV_SYMBOL_UP LV_SYMBOL_DOWN " escolhe   " LV_SYMBOL_OK " aplica",
         &lv_font_montserrat_14, 0x607D8B, LV_ALIGN_BOTTOM_MID, 0, -4);
}

void atualizarTemas() {
  static int last_sel = -1, last_ativo = -1;
  if (pagina_montada_nova) { last_sel = -1; last_ativo = -1; pagina_montada_nova = false; }
  if (tema_sel > 6) tema_sel = 0;
  if (tema_sel != last_sel) {
    lv_obj_set_pos(temasSel, 10, 19 + tema_sel * 28);
    last_sel = tema_sel;
  }
  if (cockpit_estilo != last_ativo) {   // atualiza o check do que esta ativo
    for (int i = 0; i < 7; i++) {
      char buf[40];
      snprintf(buf, sizeof(buf), "%s%s", TEMAS_NOME[i], (i == cockpit_estilo) ? "  " LV_SYMBOL_OK : "");
      lv_label_set_text(temasOpt[i], buf);
    }
    last_ativo = cockpit_estilo;
  }
}

// ---------- Monta SO a pagina ativa (economiza RAM do LVGL) ----------
// ============================================================
//  v7: Tela HISTORICO (ultimos eventos com data/hora) - o "relatorio pro mecanico"
// ============================================================
static int hist_last_n = -1;   // controla o redesenho da tela de historico

const char* evtTipoTexto(uint8_t t) {
  switch (t) {
    case 0: return "Codigo (DTC)";
    case 1: return "Temp. alta";
    case 2: return "Bateria";
    case 3: return "Alternador";
    case 4: return "SUPERAQUEC.";
    case 6: return "Combustivel";
    default: return "Info";
  }
}
uint32_t evtTipoCor(uint8_t t) {
  switch (t) {
    case 4: return 0xFF1744;   // superaquecimento - vermelho forte
    case 1: return 0xFF6E40;   // temp alta - laranja
    case 2: return 0xFFC107;   // bateria - amarelo
    case 3: return 0xFFC107;   // alternador - amarelo
    case 0: return 0xFF8A80;   // DTC - rosa
    case 6: return 0xFFC107;   // combustivel - amarelo
    default: return 0x90A4AE;
  }
}

void montarHistorico() {
  lv_obj_t* scr = lv_scr_act();
  gHist = lv_obj_create(scr);
  lv_obj_set_size(gHist, LV_W, LV_H);
  lv_obj_center(gHist);
  lv_obj_set_style_bg_color(gHist, lv_color_hex(0x05070D), 0);
  lv_obj_set_style_border_width(gHist, 0, 0);
  lv_obj_set_style_pad_all(gHist, 0, 0);
  lv_obj_clear_flag(gHist, LV_OBJ_FLAG_SCROLLABLE);

  histTit = lv_label_create(gHist);
  lv_label_set_text(histTit, "HISTORICO");
  lv_obj_set_style_text_font(histTit, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(histTit, lv_color_hex(0x4DD0E1), 0);
  lv_obj_align(histTit, LV_ALIGN_TOP_MID, 0, 8);

  // area rolavel com a lista de eventos
  lv_obj_t* box = lv_obj_create(gHist);
  lv_obj_set_size(box, LV_W - 16, LV_H - 52);
  lv_obj_align(box, LV_ALIGN_BOTTOM_MID, 0, -6);
  lv_obj_set_style_bg_color(box, lv_color_hex(0x0A0E16), 0);
  lv_obj_set_style_border_width(box, 0, 0);
  lv_obj_set_style_pad_all(box, 8, 0);
  lv_obj_set_scroll_dir(box, LV_DIR_VER);
  lv_obj_set_scrollbar_mode(box, LV_SCROLLBAR_MODE_AUTO);

  histLista = lv_label_create(box);
  lv_label_set_text(histLista, "");
  lv_obj_set_style_text_font(histLista, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(histLista, lv_color_hex(0xCFD8DC), 0);
  lv_label_set_long_mode(histLista, LV_LABEL_LONG_WRAP);
  lv_obj_set_width(histLista, LV_W - 40);
  hist_last_n = -1;   // forca o atualizarHistorico a redesenhar na label nova
}

void atualizarHistorico() {
  if (evt_n == hist_last_n) return;  // so redesenha quando muda (ou quando a pagina e remontada)
  hist_last_n = evt_n;
  static char txt[EVT_HIST_N * 90];
  txt[0] = 0;
  if (evt_n == 0) {
    lv_label_set_text(histLista, "Sem eventos ainda.\nCodigos, temperatura alta e\nbateria fraca aparecem aqui\ncom data e hora.");
    return;
  }
  for (int k = 0; k < evt_n; k++) {
    Evento e;
    if (!evtGet(k, e)) break;
    char linha[92];
    // data/hora a partir do timestamp unix (RTC)
    DateTime dt(e.ts);
    char quando[24];
    if (e.ts > 1000000000UL)   // timestamp real do RTC
      snprintf(quando, sizeof(quando), "%02d/%02d %02d:%02d", dt.day(), dt.month(), dt.hour(), dt.minute());
    else
      snprintf(quando, sizeof(quando), "(sem hora)");
    if (e.tipo == 0 && e.cod[0])
      snprintf(linha, sizeof(linha), "%s  %s %s\n", quando, evtTipoTexto(e.tipo), e.cod);
    else if (e.tipo == 1 || e.tipo == 4)
      snprintf(linha, sizeof(linha), "%s  %s %dC\n", quando, evtTipoTexto(e.tipo), e.v);
    else if (e.tipo == 2 || e.tipo == 3)
      snprintf(linha, sizeof(linha), "%s  %s %.1fV\n", quando, evtTipoTexto(e.tipo), e.v / 100.0);
    else if (e.tipo == 6)
      snprintf(linha, sizeof(linha), "%s  %s dif. %.1f%%\n", quando, evtTipoTexto(e.tipo), e.v / 10.0);
    else
      snprintf(linha, sizeof(linha), "%s  %s\n", quando, evtTipoTexto(e.tipo));
    strncat(txt, linha, sizeof(txt) - strlen(txt) - 1);
  }
  lv_label_set_text(histLista, txt);
}

// ============================================================
//  v7: SPLASH + ONBOARDING (primeiro boot). Rodam DENTRO da taskTela, antes
//  do loop principal, alimentando o watchdog (hb_tela) e o LVGL.
// ============================================================
static void telaEspera(uint32_t ms) {
  uint32_t t0 = millis();
  while (millis() - t0 < ms) { hb_tela = millis(); lv_timer_handler(); vTaskDelay(pdMS_TO_TICKS(30)); }
}

// splash rapido com o logo (<2s) - todo boot
void mostrarSplash() {
  lv_obj_t* scr = lv_scr_act();
  lv_obj_clean(scr);
  lv_obj_set_style_bg_color(scr, lv_color_hex(0x05070D), 0);
  lv_obj_t* logo = lv_label_create(scr);
  lv_label_set_text(logo, FIRMWARE_NOME);
  lv_obj_set_style_text_font(logo, &lv_font_montserrat_40, 0);
  lv_obj_set_style_text_color(logo, lv_color_hex(0x4DD0E1), 0);
  lv_obj_align(logo, LV_ALIGN_CENTER, 0, -8);
  lv_obj_t* ver = lv_label_create(scr);
  lv_label_set_text(ver, "v" FIRMWARE_VERSION);
  lv_obj_set_style_text_font(ver, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(ver, lv_color_hex(0x546E7A), 0);
  lv_obj_align(ver, LV_ALIGN_CENTER, 0, 30);
  telaEspera(1500);
  lv_obj_clean(scr);
}

// onboarding guiado - so no primeiro uso
void rodarOnboarding() {
  lv_obj_t* scr = lv_scr_act();
  lv_obj_clean(scr);
  lv_obj_set_style_bg_color(scr, lv_color_hex(0x05070D), 0);
  lv_obj_t* logo = lv_label_create(scr);
  lv_label_set_text(logo, FIRMWARE_NOME);
  lv_obj_set_style_text_font(logo, &lv_font_montserrat_40, 0);
  lv_obj_set_style_text_color(logo, lv_color_hex(0x4DD0E1), 0);
  lv_obj_align(logo, LV_ALIGN_TOP_MID, 0, 40);
  lv_obj_t* msg = lv_label_create(scr);
  lv_obj_set_style_text_font(msg, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(msg, lv_color_white(), 0);
  lv_label_set_long_mode(msg, LV_LABEL_LONG_WRAP);
  lv_obj_set_width(msg, LV_W - 40);
  lv_obj_set_style_text_align(msg, LV_TEXT_ALIGN_CENTER, 0);
  lv_obj_align(msg, LV_ALIGN_CENTER, 0, 20);

  lv_label_set_text(msg, "Bem-vindo!\nDetectando o carro...");
  uint32_t t0 = millis();
  while (millis() - t0 < 8000 && !obd_ok && !kline_ativo) { hb_tela = millis(); lv_timer_handler(); vTaskDelay(pdMS_TO_TICKS(50)); }
  if (obd_ok) {
    lv_obj_set_style_text_color(msg, lv_color_hex(0x69F0AE), 0);
    lv_label_set_text(msg, "Protocolo CAN OK\nLendo seu carro...");
  } else if (kline_ativo) {
    lv_obj_set_style_text_color(msg, lv_color_hex(0x69F0AE), 0);
    lv_label_set_text(msg, "Protocolo K-line OK\nLendo seu carro...");
  } else {
    lv_obj_set_style_text_color(msg, lv_color_hex(0xFFC107), 0);
    lv_label_set_text(msg, "Ligue o carro na\ntomada OBD e de partida");
  }
  telaEspera(2500);
  if (obd_ok || kline_ativo) {
    lv_obj_set_style_text_color(msg, lv_color_hex(0x69F0AE), 0);
    lv_label_set_text(msg, "Tudo certo!\nSeu carro esta pronto.");
    telaEspera(1800);
  }
  lv_obj_clean(scr);
}


// ============================================================
//  Pagina COMBUSTIVEL - somente informacoes uteis ao motorista
// ============================================================
void montarCombustivel() {
  lv_obj_t* scr = lv_scr_act();
  gFuelPage = lv_obj_create(scr); lv_obj_set_size(gFuelPage, LV_W, LV_H); lv_obj_center(gFuelPage);
  lv_obj_set_style_bg_color(gFuelPage, lv_color_hex(0x05070D), 0); lv_obj_set_style_border_width(gFuelPage, 0, 0);
  lv_obj_set_style_pad_all(gFuelPage, 0, 0); lv_obj_clear_flag(gFuelPage, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_t* tit = lv_label_create(gFuelPage); lv_label_set_text(tit, "COMBUSTIVEL");
  lv_obj_set_style_text_font(tit, &lv_font_montserrat_28, 0); lv_obj_set_style_text_color(tit, lv_color_hex(0x4DD0E1), 0);
  lv_obj_align(tit, LV_ALIGN_TOP_MID, 0, 6);
  fuelLblCar = lv_label_create(gFuelPage); lv_obj_set_style_text_font(fuelLblCar, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(fuelLblCar, lv_color_hex(0x90A4AE), 0); lv_obj_align(fuelLblCar, LV_ALIGN_TOP_MID, 0, 40);
  fuelLblNivel = lv_label_create(gFuelPage); lv_obj_set_style_text_font(fuelLblNivel, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(fuelLblNivel, lv_color_white(), 0); lv_obj_align(fuelLblNivel, LV_ALIGN_TOP_LEFT, 14, 67);
  fuelLblUlt = lv_label_create(gFuelPage); lv_obj_set_style_text_font(fuelLblUlt, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(fuelLblUlt, lv_color_hex(0xCFD8DC), 0); lv_obj_set_pos(fuelLblUlt, 14, 108);
  fuelLblDif = lv_label_create(gFuelPage); lv_obj_set_style_text_font(fuelLblDif, &lv_font_montserrat_28, 0);
  lv_obj_set_style_text_color(fuelLblDif, lv_color_hex(0x69F0AE), 0); lv_obj_set_pos(fuelLblDif, 14, 142);
  fuelLblStatus = lv_label_create(gFuelPage); lv_obj_set_style_text_font(fuelLblStatus, &lv_font_montserrat_14, 0);
  lv_obj_set_style_text_color(fuelLblStatus, lv_color_hex(0x90A4AE), 0); lv_obj_set_pos(fuelLblStatus, 14, 190);
}
void atualizarCombustivel(const DadosCarro& d) {
  if (!gFuelPage) return;
  char b[96];
  if (fuel_tanque_l >= 10) snprintf(b,sizeof(b),"%s  |  %.0f L", fuel_veiculo, fuel_tanque_l); else snprintf(b,sizeof(b),"%s", fuel_veiculo);
  lv_label_set_text(fuelLblCar,b);
  if (d.combust >= 0 && fuel_tanque_l >= 10) snprintf(b,sizeof(b),"Nivel %d%%   ~%.1f L", d.combust, fuel_tanque_l*d.combust/100.0f);
  else if (d.combust >= 0) snprintf(b,sizeof(b),"Nivel %d%%", d.combust); else snprintf(b,sizeof(b),"Nivel --");
  lv_label_set_text(fuelLblNivel,b);
  if (fuel_abast_pendente) snprintf(b,sizeof(b),"Abastecimento estimado: %.1f L\nInforme no app quanto a bomba marcou", fuel_l_estimado);
  else if (fuel_l_informado > 0) snprintf(b,sizeof(b),"Bomba: %.1f L   VEICAN: %.1f L", fuel_l_informado, fuel_l_estimado);
  else snprintf(b,sizeof(b),"Aguardando abastecimento");
  lv_label_set_text(fuelLblUlt,b);
  if (fuel_l_informado > 0) {
    snprintf(b,sizeof(b),"Diferenca: %.1f L  (%.1f%%)", fuel_dif_l<0?-fuel_dif_l:fuel_dif_l, fuel_dif_pct);
    lv_obj_set_style_text_color(fuelLblDif, lv_color_hex(alerta_combustivel_discrep?0xFF5252:0x69F0AE), 0);
  } else snprintf(b,sizeof(b),"Diferenca: --");
  lv_label_set_text(fuelLblDif,b);
  uint8_t conf=fuelConfiancaPct();
  if (fuel_metodo==3 || d.combust<0) snprintf(b,sizeof(b),"Analise indisponivel neste veiculo");
  else if (fuel_gnv) snprintf(b,sizeof(b),"Carro com GNV: auto-deteccao desligada");
  else if (fuel_tanque_l<10) snprintf(b,sizeof(b),"Cadastre o veiculo no app");
  else if (!fuel_calibrado) snprintf(b,sizeof(b),"Ativa: alerta 5%%/1L  |  calibre num posto de confianca");
  else snprintf(b,sizeof(b),"Calibrada: alerta ~500ml  |  confianca %u%%",conf);
  lv_label_set_text(fuelLblStatus,b);
}

void construirPagina(uint8_t pag) {
  lv_obj_clean(lv_scr_act());
  lv_obj_set_style_bg_color(lv_scr_act(), lv_color_hex(0x05070D), 0);
  if (pag == 0)      montarCockpit();
  else if (pag == 1) montarCombustivel();
  else if (pag == 2) montarDiag();
  else if (pag == 3) montarSistema();
  else if (pag == 4) montarManut();
  else if (pag == 5) montarAjuste();
  else if (pag == 6) montarTemas();
  else               montarHistorico();   // pag == 7
  pagina_montada_nova = true;
}

// ============================================================
//  Task Tela (LVGL)
// ============================================================
void taskTela(void* param) {
  Serial.println("[Task Tela] LVGL iniciada");
  // REV3: liga a alimentacao do display (MOSFET Q3). ATIVO BAIXO = liga.
  pinMode(TFT_PWR, OUTPUT);
  digitalWrite(TFT_PWR, LOW);
  delay(20);
  lcd.init();
  // A interface e PAISAGEM (320x240) -> a rotacao TEM que ser paisagem: 1, 3, 5 ou 7.
  // (0/2/4/6 sao retrato e deixam metade da tela com "chuvisco" = memoria nao escrita.)
  // 3 = paisagem de cabeca pra cima. Se ficar de cabeca pra baixo use 1; se espelhado use 7 (ou 5).
  lcd.setRotation(3);
  lv_init();
  lv_disp_draw_buf_init(&draw_buf, buf1, NULL, LV_W * 20);
  static lv_disp_drv_t dd;
  lv_disp_drv_init(&dd);
  dd.hor_res = LV_W; dd.ver_res = LV_H; dd.flush_cb = my_disp_flush; dd.draw_buf = &draw_buf;
  lv_disp_drv_register(&dd);

  // v7: splash (logo) + onboarding no primeiro uso, antes do cockpit.
  mostrarSplash();
  if (g_primeiro_uso) rodarOnboarding();

  uint8_t pagina_render = 255;
  bool standby_ativo = false;
  for (;;) {
    hb_tela = millis();
    if (estadoAtual == STANDBY) {
      if (!standby_ativo) {
        lv_obj_clean(lv_scr_act());
        lv_obj_set_style_bg_color(lv_scr_act(), lv_color_black(), 0);
        popup_shown = false;
        standby_ativo = true;
        pagina_render = 255;
      }
      lv_timer_handler();
      vTaskDelay(pdMS_TO_TICKS(50));
      continue;
    }
    standby_ativo = false;

    STAGE_TELA("dados");
    DadosCarro d;
    if (xSemaphoreTake(mutex_dados, pdMS_TO_TICKS(50)) == pdTRUE) { d = dados_publicos; xSemaphoreGive(mutex_dados); }

    if (pagina_atual != pagina_render) {
      STAGE_TELA("construirPagina");
      construirPagina(pagina_atual);
      pagina_render = pagina_atual;
    }
    STAGE_TELA("atualizar");
    if (pagina_atual == 0)      atualizarCockpit(d);
    else if (pagina_atual == 1) atualizarCombustivel(d);
    else if (pagina_atual == 2) atualizarDiag();
    else if (pagina_atual == 3) atualizarSistema();
    else if (pagina_atual == 4) atualizarManut();
    else if (pagina_atual == 5) atualizarAjuste();
    else if (pagina_atual == 6) atualizarTemas();
    else if (pagina_atual == 7) atualizarHistorico();

    STAGE_TELA("lv_timer_handler");
    lv_timer_handler();
    STAGE_TELA("idle");
    vTaskDelay(pdMS_TO_TICKS(15));
  }
}

// ============================================================
//  HISTORICO DE VELOCIDADE MAXIMA por dia (na NVS interna do ESP32).
//  Grava mesmo SEM celular (usa o RTC pra datar). O app sincroniza pelo
//  comando SPEEDHIST e junta com o historico local dele.
// ============================================================
#define SPEED_HIST_MAX 90
struct SpeedDia { uint32_t dia; uint8_t vel; } __attribute__((packed));  // dia = AAAAMMDD
SpeedDia speedHist[SPEED_HIST_MAX];
int speedHistN = 0;
bool speedDirty = false;
uint32_t speedUltFlush = 0;
Preferences speedPrefs;

static uint32_t speedHojeAAAAMMDD() {
  if (!rtc_ok) return 0;
  // cache: a data so muda na virada do dia. Evita ler o RTC (I2C) a cada segundo
  // enquanto anda -> menos trafego no barramento = menos risco de engasgo.
  static uint32_t diaCache = 0, ultLeitura = 0;
  uint32_t agora = millis();
  if (diaCache != 0 && (agora - ultLeitura) < 30000) return diaCache;
  DateTime n = rtcNow();
  ultLeitura = agora;
  diaCache = (uint32_t)n.year() * 10000UL + (uint32_t)n.month() * 100UL + n.day();
  return diaCache;
}

void speedCarregar() {
  speedPrefs.begin("veican", true);   // read-only
  int n = speedPrefs.getInt("sn", 0);
  size_t got = speedPrefs.getBytesLength("shist");
  if (n > 0 && n <= SPEED_HIST_MAX && got == (size_t)n * sizeof(SpeedDia)) {
    speedPrefs.getBytes("shist", speedHist, got);
    speedHistN = n;
  }
  speedPrefs.end();
  Serial.printf("[SPEED] historico carregado: %d dias\n", speedHistN);
}

// estilo do painel (0..5) na NVS. Padrao de fabrica = 5 (Performance).
void cockpitEstiloCarregar() {
  speedPrefs.begin("veican", true);
  cockpit_estilo = speedPrefs.getUChar("dash", 5);   // fresco = Performance (o painel do produto)
  speedPrefs.end();
  if (cockpit_estilo > 6) cockpit_estilo = 5;   // fora da faixa -> volta pro padrao Performance
}
void cockpitEstiloSalvar() {
  speedPrefs.begin("veican", false);
  speedPrefs.putUChar("dash", cockpit_estilo);
  speedPrefs.end();
}

// Offset da temperatura K-line (persistido: o aparelho fica num carro so).
void klineTempOffCarregar() {
  speedPrefs.begin("veican", true);
  kline_temp_off = speedPrefs.getInt("ktoff", 40);
  bool migrado = speedPrefs.getBool("ktoffm1", false);
  speedPrefs.end();
  if (kline_temp_off < -60 || kline_temp_off > 100) kline_temp_off = 40;
  // MIGRACAO (uma vez so): a auto-troca antiga podia deixar offset 0 GRAVADO na NVS,
  // e como isso sobrevive a regravacao do firmware, a temp continuava mostrando o
  // byte cru (ex.: 105 em vez de 65). O PID 05 padrao e A-40, entao um 0 salvo quase
  // sempre e engano -> reseta pra 40 UMA vez. Carro raw-em-C (raro): dono roda
  // KTEMPOFF 0 de novo (a flag ja estara setada, entao nao reseta mais).
  if (!migrado) {
    if (kline_temp_off == 0) kline_temp_off = 40;
    speedPrefs.begin("veican", false);
    speedPrefs.putInt("ktoff", kline_temp_off);
    speedPrefs.putBool("ktoffm1", true);
    speedPrefs.end();
    Serial.printf("[TEMP] migracao offset K-line -> %d (era 0 salvo do bug antigo)\n", kline_temp_off);
  }
}
void klineTempOffSalvar() {
  speedPrefs.begin("veican", false);
  speedPrefs.putInt("ktoff", kline_temp_off);
  speedPrefs.end();
}

// Config do combustivel broadcast (HYFUEL) — persistida: o aparelho fica num
// carro so. Ex.: Honda Civic = ID 0x13A, byte 0, max 255.
void fuelCfgCarregar() {
  speedPrefs.begin("veican", true);
  fuel_custom  = speedPrefs.getBool("fcust", false);   // so usa o salvo se o usuario configurou
  hy_fuel_id   = speedPrefs.getUInt("fid", hy_fuel_id);
  hy_fuel_byte = speedPrefs.getUChar("fbyte", hy_fuel_byte);
  hy_fuel_max  = speedPrefs.getUShort("fmax", hy_fuel_max);
  speedPrefs.end();
  if (hy_fuel_byte > 7) hy_fuel_byte = 7;
  if (hy_fuel_max < 1) hy_fuel_max = 1;
  // MIGRACAO: palpites antigos ERRADOS salvos na NVS -> ignora e usa a tabela nova.
  //  - Civic 13A byte 0 (nem era combustivel)
  //  - Azera 329 byte 1 (lia alto demais na metade pra baixo; o certo e o byte 5)
  if (fuel_custom && ((hy_fuel_id == 0x13A && hy_fuel_byte == 0) ||
                      (hy_fuel_id == 0x329 && hy_fuel_byte == 1))) fuel_custom = false;
}
void fuelCfgSalvar() {
  speedPrefs.begin("veican", false);
  speedPrefs.putBool("fcust", fuel_custom);
  speedPrefs.putUInt("fid", hy_fuel_id);
  speedPrefs.putUChar("fbyte", hy_fuel_byte);
  speedPrefs.putUShort("fmax", hy_fuel_max);
  speedPrefs.end();
}

// Grava o historico de velocidade na flash (NVS). A gravacao na flash DESLIGA o
// cache e pode congelar o nucleo 1 por instantes; andando (transito no CAN) isso
// se agravava e reiniciava. Agora: ANDANDO quase nao grava (throttle 60s); grava
// mesmo e PARADO (velocidade 0) — momento calmo. Menos escrita = sem freeze.
void speedFlush(bool parado) {
  if (!speedDirty) return;
  // ANDANDO NAO grava NUNCA. A gravacao na flash (NVS) desliga o cache e, quando a
  // NVS precisa fazer "garbage collection" (reescrever paginas), o nucleo 1 fica
  // congelado por SEGUNDOS -> era o reboot "so andando". Guarda so PARADO (momento
  // calmo). O maximo do dia so persiste quando o carro para; se reiniciar antes de
  // parar, perde no maximo o recorde de hoje (irrelevante).
  if (!parado) return;
  TRACE_DUR("speedFlush", {
    speedPrefs.begin("veican", false);  // rw
    speedPrefs.putInt("sn", speedHistN);
    speedPrefs.putBytes("shist", speedHist, speedHistN * sizeof(SpeedDia));
    speedPrefs.end();
  });
  speedDirty = false;
  speedUltFlush = millis();
}

// Registra a velocidade atual: guarda o MAXIMO do dia. Chamado ~1x/s pelo loop().
void speedRegistrar(int vel) {
  if (vel <= 0 || vel > 400) return;
  uint32_t dia = speedHojeAAAAMMDD();
  if (dia == 0) return;   // sem RTC nao dateia
  for (int i = 0; i < speedHistN; i++) {
    if (speedHist[i].dia == dia) {
      if (vel > speedHist[i].vel) { speedHist[i].vel = vel; speedDirty = true; }
      return;
    }
  }
  if (speedHistN < SPEED_HIST_MAX) {
    speedHist[speedHistN].dia = dia; speedHist[speedHistN].vel = vel; speedHistN++;
  } else {
    for (int i = 1; i < SPEED_HIST_MAX; i++) speedHist[i - 1] = speedHist[i];  // ring: solta o mais antigo
    speedHist[SPEED_HIST_MAX - 1].dia = dia; speedHist[SPEED_HIST_MAX - 1].vel = vel;
  }
  speedDirty = true;
}

// Monta a resposta: "SPEEDHIST <n>\nAAAAMMDD:vel\n..."
String speedHistString() {
  String r = "SPEEDHIST " + String(speedHistN) + "\n";
  for (int i = 0; i < speedHistN; i++) {
    r += String(speedHist[i].dia) + ":" + String(speedHist[i].vel) + "\n";
  }
  return r;
}

// ============================================================
//  BLUETOOTH (BLE) - comandos do app (espelha comandos uteis)
// ============================================================
#define BLE_SVC_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define BLE_RX_UUID  "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define BLE_TX_UUID  "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
NimBLECharacteristic* pBleTx = nullptr;

// Envia a resposta em pedacos GRANDES (180 bytes). O iPhone/Android negociam MTU ~185,
// entao STATUS e MANUT LIST cabem em 1 pacote. Pedacos pequenos (20 bytes) eram perdidos
// pelo iPhone (mandava rapido demais) e a resposta chegava incompleta. Intervalo maior
// entre pacotes evita perda quando precisa de mais de um (ex.: lista grande de DTCs).
static void bleNotificar(const String& s) {
  if (!pBleTx) return;
  const int CH = 180;
  int n = s.length();
  if (n == 0) return;
  for (int i = 0; i < n; i += CH) {
    int len = (n - i < CH) ? (n - i) : CH;
    pBleTx->setValue((uint8_t*)(s.c_str() + i), len);
    pBleTx->notify();
    vTaskDelay(pdMS_TO_TICKS(40));
  }
}

String executarComandoApp(String cmd) {
  cmd.trim();
  String up = cmd; up.toUpperCase();

  if (up == "STATUS") {
    DadosCarro d = {};
    if (xSemaphoreTake(mutex_dados, pdMS_TO_TICKS(50)) == pdTRUE) { d = dados_publicos; xSemaphoreGive(mutex_dados); }
    float v = (d.tensao > 0) ? d.tensao : lerTensaoADC();
    uint32_t km = (km_total_x100 + km_acumulado_x100) / 100;
    uint32_t seg = segundos_motor_total;
    int mh = seg / 3600, mm = (seg % 3600) / 60;
    char b[200];
    snprintf(b, sizeof(b),
      "km=%lu bat=%.1fV rpm=%d temp=%d vel=%d comb=%d motor=%dh%02dm proto=%s/%dk estado=%s",
      km, v, d.rpm > 0 ? d.rpm : 0, d.temp_motor > -40 ? d.temp_motor : 0, d.velocidade > 0 ? d.velocidade : 0,
      d.combust >= 0 ? d.combust : 0, mh, mm,
      obd_extd ? "29b" : "11b", obd_baud,
      (estadoAtual == STANDBY) ? "STANDBY" : "OPERANDO");
    return String(b);
  }
  if (up == "MANUT LIST") {
    uint32_t km = (km_total_x100 + km_acumulado_x100) / 100;
    uint32_t ts = rtcNow().unixtime();
    String r = "";
    for (int i = 0; i < NUM_ITENS_MANUT; i++) {
      r += String(i) + ":" + NOMES_ITENS[i] + " " + String(itemPercentual(i, km, ts)) + "%";
      r += " int=" + String(itens_manut[i].km_intervalo) + "km";
      if (itens_manut[i].dias_intervalo > 0) r += "/" + String(itens_manut[i].dias_intervalo) + "d";
      r += "\n";
    }
    return r;
  }
  if (up.startsWith("MANUT RESET ")) {
    int n = cmd.substring(12).toInt();
    if (n < 0 || n >= NUM_ITENS_MANUT) return "ERRO: indice 0.." + String(NUM_ITENS_MANUT - 1);
    resetarItem((uint8_t)n);
    return String("OK: ") + NOMES_ITENS[n] + " resetado";
  }
  if (up.startsWith("MANUT KM ")) {
    String args = cmd.substring(9); args.trim();
    int sp = args.indexOf(' ');
    if (sp < 0) return "Uso: MANUT KM <n> <km>";
    int n = args.substring(0, sp).toInt();
    long km = args.substring(sp + 1).toInt();   // signed: pega negativo antes de virar uint gigante
    if (n < 0 || n >= NUM_ITENS_MANUT) return "ERRO: indice 0.." + String(NUM_ITENS_MANUT - 1);
    if (km < 100 || km > 2000000) return "ERRO: km invalido (100..2000000)";
    uint32_t novoKm = (uint32_t) km;
    if (xSemaphoreTake(mutex_manut, pdMS_TO_TICKS(200)) != pdTRUE) return "ERRO: ocupado";
    itens_manut[n].km_intervalo = novoKm;
    xSemaphoreGive(mutex_manut);
    salvarItensManutencao();
    return String("OK: ") + NOMES_ITENS[n] + " intervalo = " + String(novoKm) + " km";
  }
  if (up.startsWith("MANUT DIAS ")) {
    String args = cmd.substring(11); args.trim();
    int sp = args.indexOf(' ');
    if (sp < 0) return "Uso: MANUT DIAS <n> <dias>";
    int n = args.substring(0, sp).toInt();
    long d = args.substring(sp + 1).toInt();
    if (n < 0 || n >= NUM_ITENS_MANUT) return "ERRO: indice 0.." + String(NUM_ITENS_MANUT - 1);
    if (d < 0 || d > 20000) return "ERRO: dias invalido (0..20000)";
    uint32_t dias = (uint32_t) d;
    if (xSemaphoreTake(mutex_manut, pdMS_TO_TICKS(200)) != pdTRUE) return "ERRO: ocupado";
    itens_manut[n].dias_intervalo = dias;
    xSemaphoreGive(mutex_manut);
    salvarItensManutencao();
    return String("OK: ") + NOMES_ITENS[n] + " intervalo = " + String(dias) + " dias";
  }
  if (up == "ODORESET") { formatarHodometro(); return "OK: hodometro zerado"; }
  if (up.startsWith("ODOSET ")) {   // define o odometro no km que o usuario quiser (via app)
    long km = cmd.substring(7).toInt();
    if (km < 0 || km > 2000000) return "ERRO: km invalido (0..2000000)";
    if (xSemaphoreTake(mutex_hodometro, pdMS_TO_TICKS(200)) == pdTRUE) {
      km_total_x100 = (uint32_t) km * 100; km_acumulado_x100 = 0;
      xSemaphoreGive(mutex_hodometro);
    }
    salvarHodometro();
    return "OK: odometro = " + String(km) + " km";
  }
  // Auto-sincroniza a HORA pelo celular (o app manda ao conectar). Acaba com a
  // chatice de ajustar dia/mes/ano no botao. Ex.: SETTIME 1765238400
  if (up.startsWith("SETTIME ")) {
    uint32_t ut = (uint32_t) cmd.substring(8).toInt();
    if (ut < 1672531200UL || ut > 4102444800UL) return "ERRO: horario invalido";  // 2023..2100
    rtcAdjust(DateTime(ut));
    hora_nao_ajustada = false;
    return "OK: hora sincronizada";
  }
  if (up == "SPEEDHIST") return speedHistString();   // historico de velocidade (gravado no aparelho)

  // ===== Combustivel: cadastro simples do veiculo + litros mostrados pela bomba =====
  // App envia: FUEL CAR <capacidade_litros> <nome do carro>
  // Ex.: FUEL CAR 75 Azera 2013
  if (up.startsWith("FUEL CAR ")) {
    String args = cmd.substring(9); args.trim(); int sp=args.indexOf(' ');
    if (sp < 0) return "Uso: FUEL CAR <litros> <veiculo>";
    float tank=args.substring(0,sp).toFloat(); String nome=args.substring(sp+1); nome.trim();
    if (tank < 20 || tank > 200 || nome.length()<2) return "ERRO: dados do veiculo invalidos";
    fuel_tanque_l=tank; strncpy(fuel_veiculo,nome.c_str(),sizeof(fuel_veiculo)-1); fuel_veiculo[sizeof(fuel_veiculo)-1]=0;
    fuel_aprendizado=0; fuel_abast_pendente=false; alerta_combustivel_discrep=false;
    fuel_fator=1.0f; fuel_l_raw=0.0f; fuel_calibrado=false; fuel_gnv=false;   // zera calibracao/GNV (carro novo)
    fuelAnaliseSalvar();
    return "OK: veiculo="+nome+" tanque="+String(tank,1)+"L";
  }
  // Depois de abastecer, o app envia o volume exibido pela bomba (fill NORMAL/suspeito).
  // Ex.: FUEL BOMBA 40.0
  if (up.startsWith("FUEL BOMBA ")) {
    float l=cmd.substring(11).toFloat();
    if (!fuel_abast_pendente) return "ERRO: nenhum abastecimento detectado";
    if (l < 1 || l > 200) return "ERRO: litros invalidos";
    fuelInformarBomba(l);
    return "OK: bomba="+String(l,1)+"L veican="+String(fuel_l_estimado,1)+"L dif="+String(fuel_dif_pct,1)+"%";
  }
  // Abastecimento CONFIAVEL (posto que voce confia): calibra a boia. So use quando
  // tiver certeza que a bomba foi honesta. Depois disso o alerta aperta pra ~500ml.
  // Ex.: FUEL CALIBRAR 40.0
  if (up.startsWith("FUEL CALIBRAR ")) {
    float l=cmd.substring(14).toFloat();
    if (!fuel_abast_pendente) return "ERRO: nenhum abastecimento detectado";
    if (l < 1 || l > 200) return "ERRO: litros invalidos";
    fuelCalibrar(l);
    return "OK: calibrado com "+String(l,1)+"L (fator="+String(fuel_fator,3)+"). Agora alerta a partir de ~500ml.";
  }
  // Carro com GNV: a boia de gasolina cai por software (estimativa do painel) e
  // "sobe" ao religar -> a auto-deteccao daria abastecimento-fantasma. FUEL GNV 1
  // desliga a auto-deteccao nesse carro. Ex.: FUEL GNV 1  (ou 0 p/ so gasolina)
  if (up.startsWith("FUEL GNV ")) {
    int g = cmd.substring(9).toInt();
    fuel_gnv = (g != 0);
    fuel_abast_pendente = false; alerta_combustivel_discrep = false;
    fuelAnaliseSalvar();
    return fuel_gnv ? "OK: GNV ligado (auto-deteccao de abastecimento desativada)"
                    : "OK: GNV desligado (auto-deteccao ativa)";
  }
  if (up == "FUEL STATUS") {
    return "car="+String(fuel_veiculo)+" tank="+String(fuel_tanque_l,1)+" nivel="+String((int)dados_publicos.combust)+
           "% est="+String(fuel_l_estimado,1)+" inf="+String(fuel_l_informado,1)+" dif="+String(fuel_dif_pct,1)+
           "% fator="+String(fuel_fator,3)+(fuel_calibrado?" calibrado":" nao-calib")+(fuel_gnv?" GNV":"")+" conf="+String(fuelConfiancaPct())+"%";
  }

  // ===== Diagnostico (DTCs) via BLE: dispara a leitura na taskCAN e espera o resultado =====
  if (up == "DTC LER") {
    diag_solicitar_leitura = true;
    diag_estado = DIAG_ESTADO_LENDO;
    uint32_t t0 = millis();
    while (diag_estado != DIAG_ESTADO_RESULTADO && millis() - t0 < 6000) vTaskDelay(pdMS_TO_TICKS(50));
    if (diag_estado != DIAG_ESTADO_RESULTADO) return "DTC timeout";
    String r = "DTC " + String(diag_num_dtcs) + "\n";
    if (diag_num_dtcs == 0) r += "Nenhum codigo\n";
    for (int i = 0; i < diag_num_dtcs && i < MAX_DTCS; i++) {
      r += String(diag_dtcs[i]);
      const DtcInfo* d = infoDTC(diag_dtcs[i]);
      if (d) {
        r += " | "; r += d->descricao;
        r += " | Causa: "; r += d->causa;
        r += " | "; r += gravidadeTexto(d->gravidade);
      }
      r += "\n";
    }
    return r;
  }
  if (up == "DTC APAGAR") {
    diag_solicitar_apagar = true;
    diag_estado = DIAG_ESTADO_APAGANDO;
    uint32_t t0 = millis();
    while (diag_estado == DIAG_ESTADO_APAGANDO && millis() - t0 < 6000) vTaskDelay(pdMS_TO_TICKS(50));
    return (diag_estado == DIAG_ESTADO_APAGADO_OK) ? "DTC apagados" : "Falha ao apagar";
  }

  // ===== Calibracao via BLE =====
  if (up.startsWith("VOLTCAL ")) {
    float real = cmd.substring(8).toFloat();
    float lido = lerTensaoADC() / voltcal;
    // valida faixa de bateria e limita o fator (mesma protecao do Serial) — evita
    // que um valor ruim vindo do celular estrague a leitura/os alertas.
    if (real < 5 || real > 20 || lido < 0.5) return "ERRO: use VOLTCAL 12.6 (5..20V)";
    float nv = real / lido;
    if (nv < 0.5 || nv > 2.0) return "ERRO: fator fora da faixa (0.5..2.0)";
    voltcal = nv; salvarConfig();
    return "OK: VOLTCAL=" + String(voltcal, 4);
  }
  if (up.startsWith("KMCAL ")) {
    String args = cmd.substring(6); args.trim();
    int sp = args.indexOf(' ');
    if (sp < 0) return "Uso: KMCAL <real> <mostrado>";
    float real = args.substring(0, sp).toFloat();
    float most = args.substring(sp + 1).toFloat();
    if (real < 0.5 || most < 0.5) return "ERRO: use KMCAL 52 48";
    float nk = km_cal * (real / most);
    if (nk < 0.5 || nk > 2.0) return "ERRO: fator fora da faixa (0.5..2.0)";
    km_cal = nk; salvarConfig();
    return "OK: KMCAL=" + String(km_cal, 4);
  }

  return "Cmds: STATUS | MANUT LIST | MANUT RESET <n> | MANUT KM <n> <km> | MANUT DIAS <n> <dias> | DTC LER | DTC APAGAR | VOLTCAL <v> | KMCAL <r> <m> | ODORESET | FUEL CAR <L> <veiculo> | FUEL BOMBA <L> | FUEL STATUS";
}

// Compativel com NimBLE-Arduino 1.x e 2.x (a assinatura do onWrite mudou na 2.x).
class BleRxCallback : public NimBLECharacteristicCallbacks {
#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& connInfo) override {
#else
  void onWrite(NimBLECharacteristic* c) override {
#endif
    String cmd = String(c->getValue().c_str());
    String resp = executarComandoApp(cmd);
    bleNotificar(resp);
    Serial.printf("[BLE] '%s' -> %s\n", cmd.c_str(), resp.c_str());
  }
};

void initBLE() {
  NimBLEDevice::init("VEICAN");
  NimBLEServer* srv = NimBLEDevice::createServer();
  NimBLEService* svc = srv->createService(BLE_SVC_UUID);
  // NimBLE cria o descritor CCCD automaticamente p/ NOTIFY (nao precisa de BLE2902)
  pBleTx = svc->createCharacteristic(BLE_TX_UUID, NIMBLE_PROPERTY::NOTIFY);
  NimBLECharacteristic* rx = svc->createCharacteristic(BLE_RX_UUID, NIMBLE_PROPERTY::WRITE);
  rx->setCallbacks(new BleRxCallback());
  svc->start();
  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(BLE_SVC_UUID);
  adv->setName("VEICAN");   // poe o nome no pacote de advertising (o app procura por nome)
#if defined(NIMBLE_CPP_VERSION_MAJOR) && (NIMBLE_CPP_VERSION_MAJOR >= 2)
  adv->enableScanResponse(true);
#else
  adv->setScanResponse(true);
#endif
  NimBLEDevice::startAdvertising();
  Serial.println("[BLE] 'VEICAN' anunciando (NimBLE/NUS)");
}

// ============================================================
//  Setup
// ============================================================
void taskSerial(void* param);
void taskBotoes(void* param);

// Handles das tarefas criticas (H5: guardados na criacao, sem depender de
// xTaskGetHandle por nome).
TaskHandle_t g_hCAN = NULL, g_hTela = NULL;

// H7: registra o motivo do boot em contadores persistentes (diagnostico de campo).
void contadoresBootRegistrar(esp_reset_reason_t r) {
  Preferences p;
  if (!p.begin("stats", false)) return;
  g_boot_count = p.getULong("bc", 0) + 1;  p.putULong("bc", g_boot_count);
  g_brownout_count = p.getULong("bo", 0);
  g_wdt_count = p.getULong("wd", 0);
  g_panic_count = p.getULong("pn", 0);
  if (r == ESP_RST_BROWNOUT) { g_brownout_count++; p.putULong("bo", g_brownout_count); }
  if (r == ESP_RST_TASK_WDT || r == ESP_RST_INT_WDT || r == ESP_RST_WDT) { g_wdt_count++; p.putULong("wd", g_wdt_count); }
  if (r == ESP_RST_PANIC) { g_panic_count++; p.putULong("pn", g_panic_count); }
  p.end();
  Serial.printf("[STATS] boot#%lu brownout=%lu wdt=%lu panic=%lu\n",
                (unsigned long)g_boot_count, (unsigned long)g_brownout_count,
                (unsigned long)g_wdt_count, (unsigned long)g_panic_count);
}

// MODO DE FALHA SEGURA: chamado quando algo essencial nao pode ser criado
// (mutex/tarefa) ou uma corrupcao grave e detectada. Silencia o CAN e PARA aqui,
// sem reiniciar (evita loop de boot). delay() = vTaskDelay -> alimenta o WDT.
void entrarModoFalhaSegura(const char* motivo) {
  twai_stop();   // garante o CAN em silencio (inofensivo se nao instalado)
  Serial.printf("\n[FALHA SEGURA] %s\n", motivo);
  for (;;) {
    Serial.printf("[FALHA SEGURA] %s -- reinicie o aparelho\n", motivo);
    delay(3000);
  }
}

void setup() {
  // Buffer TX maior p/ absorver rajadas de log sem encher (e sem travar a tarefa
  // que imprime). Combinado com o corte dos logs por ciclo (VERBOSE_CAN=0).
  Serial.setTxBufferSize(2048);
  Serial.begin(115200);
  delay(500);
  Serial.println("\n==== " FIRMWARE_NOME " firmware v" FIRMWARE_VERSION " ====");
  flashStorageInit();   // v7: monta a flash interna (historico + tendencia de bateria)
  analogSetPinAttenuation(PIN_VBAT, ADC_11db);
  esp_reset_reason_t reset_reason = esp_reset_reason();
  esp_sleep_wakeup_cause_t wake_cause = esp_sleep_get_wakeup_cause();
  contadoresBootRegistrar(reset_reason);   // H7: conta boot/brownout/wdt/panic na NVS
  Serial.println("\n=== " FIRMWARE_NOME " v" FIRMWARE_VERSION " LVGL ===");
  const char* reset_str[] = {"UNKNOWN","POWERON","EXT","SW","PANIC","INT_WDT","TASK_WDT","WDT","DEEPSLEEP","BROWNOUT","SDIO"};
  Serial.printf("[Boot] reset_reason=%s wake=%d\n", (reset_reason < 11) ? reset_str[reset_reason] : "?", wake_cause);
  if (g_wdt_magic == 0x5744) {   // marcador valido (RTC_NOINIT sobrevive ao reset)
    Serial.printf("[Boot] >>> reboot anterior foi WATCHDOG: tela travou %lums, botoes %lums\n", g_wdt_tela, g_wdt_btn);
    reboot_wdt_tela = g_wdt_tela; reboot_wdt_btn = g_wdt_btn;   // p/ logar na EEPROM depois que o I2C subir
    g_wdt_magic = 0;   // consome o marcador
  }

  mutex_dados = xSemaphoreCreateMutex();
  mutex_hora = xSemaphoreCreateMutex();
  mutex_hodometro = xSemaphoreCreateMutex();
  mutex_manut = xSemaphoreCreateMutex();
  mutex_debug = xSemaphoreCreateMutex();
  mutex_i2c = xSemaphoreCreateMutex();
  mutex_fs = xSemaphoreCreateMutex();
  // H5: sem mutex nao da pra operar com seguranca (corrida garantida) -> falha segura
  if (!mutex_dados || !mutex_hora || !mutex_hodometro || !mutex_manut ||
      !mutex_debug || !mutex_i2c || !mutex_fs)
    entrarModoFalhaSegura("mutex nao criado (RAM insuficiente)");

  Wire.begin(21, 22);
  Wire.setClock(100000);
  Wire.setTimeOut(50);   // I2C nao pode travar: aborta apos 50ms (ruido do carro andando)

  if (!rtc.begin()) Serial.println("[ERRO] RTC");
  else {
    rtc_ok = true;
    if (rtc.lostPower()) {
      hora_nao_ajustada = true;
      rtcAdjust(DateTime(2026, 1, 1, 0, 0, 0));
      Serial.println("[RTC] sem hora valida -> 01/01/2026, exibindo AJUSTAR HORA");
    }
  }

  if (!carregarDebugHeader()) { Serial.println("[Debug] log virgem, formatando..."); formatarDebugLog(); }
  else Serial.printf("[Debug] log carregado: %u registros\n", debug_log_count);

  debugLog(3, "BOOT", (uint16_t)reset_reason, (uint16_t)wake_cause, (uint8_t)reset_reason);
  if (reboot_wdt_tela || reboot_wdt_btn)
    debugLog(2, "WDT reboot", (uint16_t)reboot_wdt_tela, (uint16_t)reboot_wdt_btn);

  if (!carregarHeader()) { Serial.println("[Logger] EEPROM virgem/versao mudou, formatando..."); formatarEEPROM(); }
  else Serial.printf("[Logger] count=%u total=%lu\n", log_count, log_total);

  if (!carregarConfig()) { Serial.println("[Cfg] config virgem (voltcal=1.0 km_cal=1.0)"); salvarConfig(); }
  else Serial.printf("[Cfg] voltcal=%.4f km_cal=%.4f\n", voltcal, km_cal);

  if (!carregarHodometro()) formatarHodometro();
  else Serial.printf("[Odo] %.2fkm %lus\n", km_total_x100/100.0, segundos_motor_total);

  if (!carregarItensManutencao()) inicializarManutencao();

  bool achou = detectarProtocoloOBD();
  Serial.printf("[CAN] %s -> %s / %dk\n", achou ? "DETECTADO" : "default",
                obd_extd ? "29-bit" : "11-bit", obd_baud);
  delay(300);

  autoteste();

  dados_publicos = {PID_ERRO, PID_ERRO, PID_ERRO, PID_ERRO, PID_ERRO, PID_ERRO, PID_ERRO, PID_ERRO, PID_ERRO, PID_ERRO, PID_ERRO, -1.0};
  ultimo_heartbeat = millis();

  // ===== H1: carrega TODAS as configs ANTES de criar as tarefas =====
  // (evita corrida: taskTela/taskCAN liam cockpit_estilo/kline_temp_off/fuel
  //  config enquanto o setup ainda estava carregando esses valores.)
  speedCarregar();           // historico de velocidade (NVS)
  cockpitEstiloCarregar();   // estilo do painel escolhido
  klineTempOffCarregar();    // calibracao do offset de temperatura K-line
  fuelCfgCarregar();         // config do combustivel broadcast (HYFUEL) salva
  fuelAnaliseCarregar();     // cadastro/estado da analise de abastecimento
  // primeiro uso? le e ja marca (single-thread aqui, sem corrida)
  speedPrefs.begin("veican", true);
  g_primeiro_uso = (speedPrefs.getInt("ob7", 0) == 0);
  speedPrefs.end();
  if (g_primeiro_uso) { speedPrefs.begin("veican", false); speedPrefs.putInt("ob7", 1); speedPrefs.end(); }

  // H5: valida a criacao de cada tarefa. RAM insuficiente -> falha segura em vez
  // de seguir "meio funcionando" e crashar depois.
  bool ok = true;
  ok &= (xTaskCreatePinnedToCore(taskCAN,       "CAN",    8192, NULL, 2, &g_hCAN, 0) == pdPASS);
  ok &= (xTaskCreatePinnedToCore(taskLogger,    "Logger", 4096, NULL, 1, NULL,    0) == pdPASS);
  ok &= (xTaskCreatePinnedToCore(taskAlertas,   "Alertas",4096, NULL, 1, NULL,    0) == pdPASS);
  ok &= (xTaskCreatePinnedToCore(taskHeartbeat, "Heart",  4096, NULL, 1, NULL,    0) == pdPASS);
  ok &= (xTaskCreatePinnedToCore(taskTela,      "Tela",   20480,NULL, 1, &g_hTela,1) == pdPASS);
  ok &= (xTaskCreatePinnedToCore(taskRTC,       "RTC",    4096, NULL, 1, NULL,    1) == pdPASS);
  ok &= (xTaskCreatePinnedToCore(taskSerial,    "Serial", 4096, NULL, 1, NULL,    1) == pdPASS);
  ok &= (xTaskCreatePinnedToCore(taskBotoes,    "Botoes", 6144, NULL, 1, NULL,    1) == pdPASS);   // stack 6144: folga p/ acoes de botao
  if (!ok || !g_hCAN || !g_hTela)
    entrarModoFalhaSegura("tarefa nao criada (RAM insuficiente)");

  Serial.printf("[HEAP] antes do BLE = %u bytes\n", ESP.getFreeHeap());
  initBLE();
  Serial.printf("[HEAP] livre apos setup (BLE ON) = %u bytes\n", ESP.getFreeHeap());

  debugLog(0, "Setup OK v" FIRMWARE_VERSION);
  Serial.println("=== " FIRMWARE_NOME " v" FIRMWARE_VERSION " pronto ===");
  Serial.println("Cmds: DUMP DEBUG FUEL VBAT | VOLTCAL <v> | KMCAL <real> <mostrado>");
  Serial.println("Destrutivos (pedem SIM): RESET ODORESET MANUTRESET DEBUGRESET");
}

void loop() {
  static uint32_t prox_log = 0;
  uint32_t agora = millis();

  if (agora - prox_log >= 30000) {
    prox_log = agora;
    Serial.printf("[HEAP] livre=%u min=%u | hb_tela=%lums hb_btn=%lums\n",
                  ESP.getFreeHeap(), ESP.getMinFreeHeap(),
                  agora - hb_tela, agora - hb_botoes);
  }

  // ===== BLE: garante que volta a ANUNCIAR quando ninguem esta conectado =====
  // Na partida do carro a tensao cai um instante e a conexao BLE cai. Sem isto, o
  // BLE nao reaparecia (so religando na tomada). Aqui, a cada 3s, se nao houver
  // cliente conectado, reativa o anuncio (startAdvertising e idempotente).
  static uint32_t prox_adv = 0;
  if (pBleTx && agora - prox_adv >= 3000) {
    prox_adv = agora;
    NimBLEServer* s = NimBLEDevice::getServer();
    if (s && s->getConnectedCount() == 0) NimBLEDevice::startAdvertising();
  }

  // ===== grava a VELOCIDADE MAXIMA do dia (na NVS, mesmo sem celular) =====
  int velAtual = 0;
  if (xSemaphoreTake(mutex_dados, pdMS_TO_TICKS(20)) == pdTRUE) {
    velAtual = dados_publicos.velocidade; xSemaphoreGive(mutex_dados);
  }
  if (velAtual > 0) speedRegistrar(velAtual);
  speedFlush(velAtual == 0);   // grava na flash preferencialmente PARADO (nao andando)

  checarTravamento();   // watchdog do nucleo 1 (a taskHeartbeat vigia em paralelo no nucleo 0)
  vTaskDelay(pdMS_TO_TICKS(1000));
}

// ============================================================
//  Tasks de entrada (botoes) e Serial
// ============================================================
// Dias do mes (ano2 = ano - 2000). Trata fevereiro bissexto.
static uint8_t diasNoMes(uint8_t mes, uint8_t ano2) {
  static const uint8_t dias[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
  if (mes < 1 || mes > 12) return 31;
  if (mes == 2) {
    uint16_t ano = 2000 + ano2;
    bool bissexto = (ano % 4 == 0 && ano % 100 != 0) || (ano % 400 == 0);
    return bissexto ? 29 : 28;
  }
  return dias[mes - 1];
}
// Garante que o dia escolhido cabe no mes/ano atuais (ex.: 31 -> 30 ao virar p/ abril,
// ou 29/02 -> 28/02 em ano nao bissexto).
static void ajustaDiaValido() {
  uint8_t maxd = diasNoMes(ajuste_mes, ajuste_ano);
  if (ajuste_dia > maxd) ajuste_dia = maxd;
  if (ajuste_dia < 1)    ajuste_dia = 1;
}

// Acao de OK/confirmar — usada pelo MENU (clique curto) e pelo botao ENTER (Rev3).
static void botaoOK() {
  Serial.printf("[BTN] OK (pag=%d, modo=%d)\n", pagina_atual, nav_modo);
  if (manut_confirma_reset) {
    if (manut_confirma_selecionado == 0) resetarItem(item_manut_selecionado);
    manut_confirma_reset = false;
  } else if (sistema_confirma_zerar) {
    if (sistema_confirma_selecionado == 0) formatarHodometro();
    sistema_confirma_zerar = false;
  } else if (pagina_atual == 5 && nav_modo == NAV_MODO_EDICAO) {
    if (ajuste_estado >= AJUSTE_ESTADO_DIA && ajuste_estado < AJUSTE_ESTADO_SEG) {
      ajuste_estado++;
    } else if (ajuste_estado == AJUSTE_ESTADO_SEG) {
      ajuste_estado = AJUSTE_ESTADO_SALVAR;
    } else if (ajuste_estado == AJUSTE_ESTADO_SALVAR) {
      ajustaDiaValido();   // ultima checagem antes de gravar no RTC
      rtcAdjust(DateTime(2000 + ajuste_ano, ajuste_mes, ajuste_dia,
                         ajuste_hora, ajuste_min, ajuste_seg));
      hora_nao_ajustada = false;
      ajuste_estado = AJUSTE_ESTADO_MENU;
      nav_modo = NAV_MODO_VISUALIZACAO;
    }
  } else if (nav_modo == NAV_MODO_VISUALIZACAO) {
    if (pagina_atual == 2) {
      nav_modo = NAV_MODO_EDICAO;
    } else if (pagina_atual == 4) {
      nav_modo = NAV_MODO_EDICAO;
      item_manut_selecionado = 0;
      resetCache();
    } else if (pagina_atual == 5) {
      if (xSemaphoreTake(mutex_hora, pdMS_TO_TICKS(100)) == pdTRUE) {
        ajuste_dia = data_dia; ajuste_mes = data_mes; ajuste_ano = (uint8_t)(data_ano - 2000);
        ajuste_hora = hora_h; ajuste_min = hora_m; ajuste_seg = hora_s;
        xSemaphoreGive(mutex_hora);
      }
      ajuste_estado = AJUSTE_ESTADO_DIA;
      nav_modo = NAV_MODO_EDICAO;
    } else if (pagina_atual == 1 || pagina_atual == 3 || pagina_atual == 7) {
      pagina_atual = (pagina_atual + 1) % TOTAL_PAGINAS;   // Sistema/Historico: OK so avança
    } else if (pagina_atual == 6) {
      nav_modo = NAV_MODO_EDICAO;   // Temas: entra p/ escolher o estilo
    }
  } else {
    if (pagina_atual == 2) {
      switch (diag_estado) {
        case DIAG_ESTADO_MENU:
          if (diag_menu_selecionado == 0) { diag_estado = DIAG_ESTADO_LENDO; diag_solicitar_leitura = true; }
          else if (diag_menu_selecionado == 1) { diag_estado = DIAG_ESTADO_CONFIRMAR; diag_confirma_selecionado = 1; }
          else { nav_modo = NAV_MODO_VISUALIZACAO; }
          break;
        case DIAG_ESTADO_RESULTADO: diag_estado = DIAG_ESTADO_MENU; break;
        case DIAG_ESTADO_CONFIRMAR:
          if (diag_confirma_selecionado == 0) { diag_estado = DIAG_ESTADO_APAGANDO; diag_solicitar_apagar = true; }
          else diag_estado = DIAG_ESTADO_MENU;
          break;
        case DIAG_ESTADO_APAGADO_OK: diag_estado = DIAG_ESTADO_MENU; break;
      }
    } else if (pagina_atual == 4) {
      nav_modo = NAV_MODO_VISUALIZACAO;
    } else if (pagina_atual == 6) {
      cockpit_estilo = tema_sel;   // Temas: aplica e salva o estilo escolhido
      cockpitEstiloSalvar();
      nav_modo = NAV_MODO_VISUALIZACAO;
    }
  }
}

// Leitura ANTI-RUIDO: le o pino 3x em ~0,6ms; so aceita o nivel se os 3 baterem.
// Instavel (ruido eletrico/vibracao no carro) = considera SOLTO (HIGH) e NAO age.
// Isso impede "clique fantasma" andando, que disparava acoes de menu (rtcAdjust/
// NVS) e era a suspeita do travamento da taskBotoes.
static bool lerBotaoEstavel(uint8_t pin) {
  bool a = digitalRead(pin);
  delayMicroseconds(300);
  bool b = digitalRead(pin);
  delayMicroseconds(300);
  bool c = digitalRead(pin);
  return (a == b && b == c) ? a : HIGH;
}

void taskBotoes(void* param) {
  Serial.println("[Task Botoes] iniciada");
  pinMode(BTN_ANT, INPUT_PULLUP);
  pinMode(BTN_MENU, INPUT_PULLUP);
  pinMode(BTN_PRX, INPUT_PULLUP);
  pinMode(BTN_ENTER, INPUT_PULLUP);   // REV3: 4o botao
  bool prev_ant = HIGH, prev_menu = HIGH, prev_prx = HIGH, prev_enter = HIGH;
  uint32_t ultimo_debounce = 0, ultimo_menu = 0, menu_pressionado_em = 0, ultimo_enter = 0;
  bool menu_longpress_disparado = false;
  for (;;) {
    hb_botoes = millis();
    STAGE_BTN("read");
    bool agora_ant = lerBotaoEstavel(BTN_ANT);
    bool agora_menu = lerBotaoEstavel(BTN_MENU);
    bool agora_prx = lerBotaoEstavel(BTN_PRX);
    bool agora_enter = lerBotaoEstavel(BTN_ENTER);
    uint32_t t = millis();

    if (estadoAtual == STANDBY) {
      // MENU ou ENTER acordam o aparelho
      if ((prev_menu == HIGH && agora_menu == LOW) || (prev_enter == HIGH && agora_enter == LOW)) pedido_acordar = true;
      prev_ant = agora_ant; prev_menu = agora_menu; prev_prx = agora_prx; prev_enter = agora_enter;
      vTaskDelay(pdMS_TO_TICKS(50));
      continue;
    }
    if (agora_ant == LOW || agora_menu == LOW || agora_prx == LOW || agora_enter == LOW) contando_pra_sleep = false;

    if (prev_menu == HIGH && agora_menu == LOW) { menu_pressionado_em = t; menu_longpress_disparado = false; Serial.println("[BTN] MENU pressionado"); }
    if (agora_menu == LOW && !menu_longpress_disparado && t - menu_pressionado_em >= LONGPRESS_MS) {
      menu_longpress_disparado = true;
      if (pagina_atual == 0 && nav_modo == NAV_MODO_VISUALIZACAO) {
        pagina_atual = 5;
      } else if (pagina_atual == 4 && nav_modo == NAV_MODO_EDICAO && !manut_confirma_reset) {
        manut_confirma_reset = true;
        manut_confirma_selecionado = 1;
      } else if (pagina_atual == 5 && nav_modo == NAV_MODO_EDICAO) {
        ajuste_estado = AJUSTE_ESTADO_MENU;
        nav_modo = NAV_MODO_VISUALIZACAO;
      } else if (pagina_atual == 3 && nav_modo == NAV_MODO_VISUALIZACAO && !sistema_confirma_zerar) {
        sistema_confirma_zerar = true;
        sistema_confirma_selecionado = 1;
      }
    }

    if (prev_menu == LOW && agora_menu == HIGH) {
      if (!menu_longpress_disparado && t - ultimo_menu > DEBOUNCE_MS) {
        STAGE_BTN("okMenu"); botaoOK(); STAGE_BTN("read");
        ultimo_menu = t;
      }
      menu_longpress_disparado = false;
    }

    // REV3: botao ENTER = OK/confirmar (clique). Atalho: na Manutencao em edicao,
    // ENTER abre o reset do item selecionado (sem precisar segurar MENU 4s).
    if (prev_enter == LOW && agora_enter == HIGH) {
      if (t - ultimo_enter > DEBOUNCE_MS) {
        if (pagina_atual == 4 && nav_modo == NAV_MODO_EDICAO && !manut_confirma_reset) {
          manut_confirma_reset = true;
          manut_confirma_selecionado = 1;   // padrao NAO (seguranca)
        } else {
          STAGE_BTN("okEnter"); botaoOK(); STAGE_BTN("read");
        }
        ultimo_enter = t;
      }
    }

    if (t - ultimo_debounce > DEBOUNCE_MS) {
      if (prev_ant == HIGH && agora_ant == LOW) {
        if (sistema_confirma_zerar) {
          sistema_confirma_selecionado = (sistema_confirma_selecionado == 0) ? 1 : 0;
        } else if (pagina_atual == 5 && nav_modo == NAV_MODO_EDICAO) {
          if (ajuste_estado >= AJUSTE_ESTADO_DIA && ajuste_estado <= AJUSTE_ESTADO_SEG) {
            int idx = ajuste_estado - AJUSTE_ESTADO_DIA;
            volatile uint8_t* valores[] = {&ajuste_dia, &ajuste_mes, &ajuste_ano, &ajuste_hora, &ajuste_min, &ajuste_seg};
            uint8_t limites_min[] = {1, 1, 20, 0, 0, 0};
            uint8_t limites_max[] = {diasNoMes(ajuste_mes, ajuste_ano), 12, 99, 23, 59, 59};
            if (*valores[idx] > limites_min[idx]) (*valores[idx])--;
            else *valores[idx] = limites_max[idx];
            if (idx == 1 || idx == 2) ajustaDiaValido();  // mudou mes/ano -> reajusta o dia
          }
        } else if (nav_modo == NAV_MODO_EDICAO) {
          if (pagina_atual == 4) {
            if (manut_confirma_reset) {
              manut_confirma_selecionado = (manut_confirma_selecionado == 0) ? 1 : 0;
            } else {
              if (item_manut_selecionado == 0) item_manut_selecionado = NUM_ITENS_MANUT - 1;
              else item_manut_selecionado--;
              resetCache();
            }
          } else if (pagina_atual == 2) {
            if (diag_estado == DIAG_ESTADO_MENU) {
              if (diag_menu_selecionado == 0) diag_menu_selecionado = 2;
              else diag_menu_selecionado--;
            } else if (diag_estado == DIAG_ESTADO_CONFIRMAR) {
              diag_confirma_selecionado = (diag_confirma_selecionado == 0) ? 1 : 0;
            }
          } else if (pagina_atual == 6) {
            if (tema_sel == 0) tema_sel = 6; else tema_sel--;
          }
        } else {
          if (pagina_atual == 0) pagina_atual = TOTAL_PAGINAS - 1;
          else pagina_atual--;
        }
        ultimo_debounce = t;
      }

      if (prev_prx == HIGH && agora_prx == LOW) {
        if (sistema_confirma_zerar) {
          sistema_confirma_selecionado = (sistema_confirma_selecionado == 0) ? 1 : 0;
        } else if (pagina_atual == 5 && nav_modo == NAV_MODO_EDICAO) {
          if (ajuste_estado >= AJUSTE_ESTADO_DIA && ajuste_estado <= AJUSTE_ESTADO_SEG) {
            int idx = ajuste_estado - AJUSTE_ESTADO_DIA;
            volatile uint8_t* valores[] = {&ajuste_dia, &ajuste_mes, &ajuste_ano, &ajuste_hora, &ajuste_min, &ajuste_seg};
            uint8_t limites_min[] = {1, 1, 20, 0, 0, 0};
            uint8_t limites_max[] = {diasNoMes(ajuste_mes, ajuste_ano), 12, 99, 23, 59, 59};
            if (*valores[idx] < limites_max[idx]) (*valores[idx])++;
            else *valores[idx] = limites_min[idx];
            if (idx == 1 || idx == 2) ajustaDiaValido();  // mudou mes/ano -> reajusta o dia
          }
        } else if (nav_modo == NAV_MODO_EDICAO) {
          if (pagina_atual == 4) {
            if (manut_confirma_reset) {
              manut_confirma_selecionado = (manut_confirma_selecionado == 0) ? 1 : 0;
            } else {
              item_manut_selecionado = (item_manut_selecionado + 1) % NUM_ITENS_MANUT;
              resetCache();
            }
          } else if (pagina_atual == 2) {
            if (diag_estado == DIAG_ESTADO_MENU) {
              diag_menu_selecionado = (diag_menu_selecionado + 1) % 3;
            } else if (diag_estado == DIAG_ESTADO_CONFIRMAR) {
              diag_confirma_selecionado = (diag_confirma_selecionado == 0) ? 1 : 0;
            }
          } else if (pagina_atual == 6) {
            tema_sel = (tema_sel + 1) % 7;
          }
        } else {
          pagina_atual = (pagina_atual + 1) % TOTAL_PAGINAS;
        }
        ultimo_debounce = t;
      }
    }

    prev_ant = agora_ant; prev_menu = agora_menu; prev_prx = agora_prx; prev_enter = agora_enter;
    STAGE_BTN("idle");
    vTaskDelay(pdMS_TO_TICKS(20));
  }
}

// ============================================================
//  Task Serial
// ============================================================
void taskSerial(void* param) {
  String buf = "";
  for (;;) {
    while (Serial.available()) {
      char c = Serial.read();
      if (c == '\n' || c == '\r') {
        buf.trim();
        if (buf == "RESET SIM") formatarEEPROM();
        else if (buf == "RESET") Serial.println(">>> Apaga TODO o log de viagem. Confirme com: RESET SIM");
        else if (buf == "DUMP") Serial.printf(">>> log=%u/%u km=%.2f motor=%lus tx=%lu rx=%lu to=%lu\n", log_count, MAX_RECORDS, (km_total_x100 + km_acumulado_x100)/100.0, segundos_motor_total, tx_ok, rx_ok, timeouts);
        else if (buf == "ODORESET SIM") formatarHodometro();
        else if (buf == "ODORESET") Serial.println(">>> ZERA km e horas de motor. Confirme com: ODORESET SIM");
        else if (buf == "SLEEP") Serial.println(">>> SLEEP desabilitado nesta versao");
        else if (buf == "MANUTRESET SIM") inicializarManutencao();
        else if (buf == "MANUTRESET") Serial.println(">>> Reseta os 5 itens de manutencao. Confirme com: MANUTRESET SIM");
        else if (buf == "DEBUG") dumpDebugLog();
        else if (buf == "DEBUGRESET SIM") { formatarDebugLog(); Serial.println(">>> Debug log limpo"); }
        else if (buf == "DEBUGRESET") Serial.println(">>> Apaga o log de debug. Confirme com: DEBUGRESET SIM");
        else if (buf == "SPEEDHIST") Serial.print(speedHistString());
        else if (buf == "STATS") Serial.printf(">>> boot#%lu brownout=%lu wdt=%lu panic=%lu busoff=%lu\n",
                   (unsigned long)g_boot_count, (unsigned long)g_brownout_count, (unsigned long)g_wdt_count,
                   (unsigned long)g_panic_count, (unsigned long)g_busoff_count);
#if !MODO_COMERCIAL
        // ===== COMANDOS DE ENGENHARIA (transmitem no barramento / varrem / apagam
        //  DTC / mudam config). Na versao de venda (MODO_COMERCIAL 1) NEM COMPILAM. =====
        else if (buf == "FUEL") { probe_pedir_fuel = true; Serial.println(">>> lendo 0x2F..."); }
        else if (buf == "TEMPSCAN") { probe_temp_scan = true; Serial.println(">>> procurando o PID de temperatura..."); }
        else if (buf == "KLRAW") { probe_klraw = true; Serial.println(">>> dump cru da temperatura K-line..."); }
        else if (buf.startsWith("KTEMPOFF")) {   // calibra offset temp K-line: "KTEMPOFF 0" (VW puro) ou "KTEMPOFF 40" (padrao)
          const char* s = buf.c_str() + 8; while (*s == ' ') s++;
          if (*s) { int v = atoi(s); if (v < -60) v = -60; if (v > 100) v = 100; kline_temp_off = v; klineTempOffSalvar(); Serial.printf(">>> temp K-line = A - %d\n", kline_temp_off); }
          else Serial.printf(">>> offset atual = %d (use: KTEMPOFF 0  ou  KTEMPOFF 40)\n", kline_temp_off);
        }
        else if (buf == "CANDUMP") { probe_candump = true; Serial.println(">>> capturando frames do barramento..."); }
        else if (buf == "FUELWATCH") { probe_fuelwatch = true; Serial.println(">>> observando candidatos de combustivel..."); }
        else if (buf.startsWith("FUELFIND")) {   // acha o byte do combustivel: FUELFIND <pct do tanque>
          const char* s = buf.c_str() + 8; while (*s == ' ') s++;
          fuelfind_pct = (*s) ? atoi(s) : 50;
          probe_fuelfind = true;
          Serial.printf(">>> procurando o byte do combustivel p/ tanque ~%d%%...\n", fuelfind_pct);
        }
        else if (buf.startsWith("HYFUEL ")) {   // ajusta o combustivel broadcast Hyundai: HYFUEL <id_hex> <byte> <max>
          const char* s = buf.c_str() + 7;
          hy_fuel_id = (uint32_t)strtol(s, NULL, 16) & 0x1FFFFFFF;   // #14: dentro da faixa de ID CAN
          const char* p1 = strchr(s, ' ');
          if (p1) { hy_fuel_byte = (uint8_t)atoi(p1 + 1); const char* p2 = strchr(p1 + 1, ' '); if (p2) hy_fuel_max = (uint16_t)atoi(p2 + 1); }
          if (hy_fuel_byte > 7) hy_fuel_byte = 7;                    // #14: byte 0..7
          if (hy_fuel_max < 1) hy_fuel_max = 1;                      // #14: evita divisao por zero
          fuel_metodo = 0;   // forca redeteccao com os novos parametros
          fuel_custom = true;   // marca como custom -> tentado antes da tabela
          fuelCfgSalvar();   // PERSISTE (o aparelho fica nesse carro)
          Serial.printf(">>> HYFUEL id=%lX byte=%d max=%d (salvo, redetectando)\n", (unsigned long)hy_fuel_id, hy_fuel_byte, hy_fuel_max);
        }
        else if (buf.startsWith("PID")) {   // aceita "PID 05" e "PID05"
          const char* s = buf.c_str() + 3; while (*s == ' ') s++;
          if (*s) { probe_pid_pedido = (int)strtol(s, NULL, 16); Serial.printf(">>> sondando PID %02X...\n", probe_pid_pedido); }
          else Serial.println(">>> use: PID 05");
        }
        else if (buf == "KLINE") klineDiagnostico();   // teste K-line (ISO9141/KWP2000)
        else if (buf == "GMLIVE") klineGMLive();        // engenharia reversa do bloco GM 0x21 LID 01 (Montana)
#if !MODO_COMERCIAL
        else if (buf == "SCAN") scanCAN();                // varredura pesada do CAN (Stilo/gateway) [engenharia]
        else if (buf == "SWEEP") scanSweep();             // varre 0x7E0..0x7E7 (ultimo teste Stilo) [engenharia]
#endif
        else if (buf == "DTC") klineDTC();               // le codigos de falha (KWP 0x18 / mode03)
        else if (buf == "DTCLR") Serial.println(">>> Apaga TODOS os codigos de falha. Confirme com: DTCLR SIM");
        else if (buf == "DTCLR SIM") klineDTCClear();    // apaga codigos (KWP 0x14 FF00 / mode04)
        else if (buf == "GMRESET") { gm_rec_n = 0; gm_rec_amostras = 0; Serial.println(">>> gravacao GM zerada. Agora DIRIJA (0->50->0) e depois rode GMDUMP."); }
        else if (buf.startsWith("GMTC1 ")) {           // ponto 1 da calibracao de temp (motor FRIO)
          gm_tc_b1 = gm_last_temp_byte; gm_tc_t1 = atof(buf.c_str() + 6); gm_tc_have1 = true;
          Serial.printf(">>> temp ponto1: byte=0x%02X (%d) = %.0fC. Agora esquente e use GMTC2 <tempQuente>.\n", gm_tc_b1, gm_tc_b1, gm_tc_t1);
        }
        else if (buf.startsWith("GMTC2 ")) {           // ponto 2 (motor QUENTE) -> calcula a,b
          if (!gm_tc_have1) Serial.println(">>> faca GMTC1 <tempFria> primeiro (motor frio).");
          else {
            uint8_t b2 = gm_last_temp_byte; float t2 = atof(buf.c_str() + 6);
            if (b2 == gm_tc_b1) Serial.println(">>> byte igual nos 2 pontos: o byte da temp nao mudou (offset errado?). Ajuste com GMOFF.");
            else {
              gm_temp_a = (t2 - gm_tc_t1) / ((float)b2 - (float)gm_tc_b1);
              gm_temp_b = gm_tc_t1 - gm_temp_a * (float)gm_tc_b1;
              Serial.printf(">>> temp CALIBRADA: a=%.3f b=%.1f  (frio 0x%02X=%.0fC, quente 0x%02X=%.0fC)\n", gm_temp_a, gm_temp_b, gm_tc_b1, gm_tc_t1, b2, t2);
              Serial.printf(">>> confira: agora a tela deve bater com o ponteiro. Me mande esses valores a/b p/ eu fixar no firmware.\n");
            }
          }
        }
        else if (buf == "GMDUMP") {
          Serial.printf("\n===== GMDUMP: %lu amostras, %d bytes =====\n", gm_rec_amostras, gm_rec_n);
          if (gm_rec_amostras < 20) Serial.println("(POUCAS amostras: se voce dirigiu e reconectou, a placa reiniciou no USB. Me avise.)");
          Serial.println("Procuro: byte com min~00 e max ~= velocidade de pico (km/h).");
          for (int i = 0; i < gm_rec_n; i++) {
            int amp = gm_mx[i] - gm_mn[i];
            if (amp > 0) {
              const char* tag = (i == gm_off_rpm || i == gm_off_rpm + 1) ? " <-RPM" : (i == gm_off_temp) ? " <-TEMP" : (i == gm_off_vel) ? " <-VEL" : "";
              Serial.printf(" [%02d] %02X..%02X (%d..%d) amp=%d%s\n", i, gm_mn[i], gm_mx[i], gm_mn[i], gm_mx[i], amp, tag);
            }
          }
          Serial.println("=====================================\n");
        }
        else if (buf.startsWith("GMOFF ")) {            // ajusta offsets do bloco GM ao vivo: GMOFF <rpm> <temp> <vel>
          const char* s = buf.c_str() + 6;
          int rp = atoi(s); const char* p1 = strchr(s, ' ');
          int tp = p1 ? atoi(p1 + 1) : gm_off_temp; const char* p2 = p1 ? strchr(p1 + 1, ' ') : NULL;
          int vl = p2 ? atoi(p2 + 1) : gm_off_vel;
          // #14: offsets dentro do bloco (0..126 p/ RPM que le 2 bytes; -1 desliga temp/vel)
          if (rp >= 0 && rp <= 126) gm_off_rpm = rp;
          if (tp >= -1 && tp <= 127) gm_off_temp = tp;
          if (vl >= -1 && vl <= 127) gm_off_vel = vl;
          Serial.printf(">>> offsets GM: rpm=%d temp=%d vel=%d\n", gm_off_rpm, gm_off_temp, gm_off_vel);
        }
        else if (buf == "VBAT") {
          // CORRECAO 🟡: uma unica leitura do ADC (antes chamava lerTensaoADC() 2x -> valores diferentes)
          float v = lerTensaoADC();
          Serial.printf(">>> ADC: %.2fV (pino %.3fV, voltcal=%.4f)\n", v, v/(VBAT_RATIO*voltcal), voltcal);
        }
        else if (buf.startsWith("VOLTCAL ")) {
          float real = atof(buf.c_str() + 8);
          float lido = lerTensaoADC() / voltcal;
          // #15: exige tensao plausivel (5-20V) e clampeia o fator numa faixa segura (0.5-2.0)
          if (real > 5.0 && real < 20.0 && lido > 0.5) {
            float nv = real / lido; if (nv < 0.5f) nv = 0.5f; if (nv > 2.0f) nv = 2.0f;
            voltcal = nv; salvarConfig();
            Serial.printf(">>> VOLTCAL=%.4f (real=%.2f lido_cru=%.2f). Salvo na EEPROM.\n", voltcal, real, lido);
          } else Serial.println(">>> VOLTCAL: fora da faixa (use ex.: VOLTCAL 12.6, entre 5 e 20V)");
        }
        else if (buf.startsWith("KMCAL ")) {
          const char* s = buf.c_str() + 6;
          float real = atof(s);
          const char* sp = strchr(s, ' ');
          float most = sp ? atof(sp + 1) : 0;
          if (real > 0.5 && most > 0.5) {
            float nk = km_cal * (real / most); if (nk < 0.5f) nk = 0.5f; if (nk > 2.0f) nk = 2.0f;  // #15: faixa segura
            km_cal = nk; salvarConfig();
            Serial.printf(">>> KMCAL=%.4f (real=%.1f mostrado=%.1f). Salvo na EEPROM.\n", km_cal, real, most);
          } else Serial.println(">>> KMCAL invalido. Use: KMCAL 52 48");
        }
        else if (buf.startsWith("ID ")) { probe_reqid = strtol(buf.c_str() + 3, NULL, 16); Serial.printf(">>> probe_reqid=%03X\n", (unsigned)probe_reqid); }
        else if (buf.startsWith("SWEEP22 ")) {
          probe_did_ini = (uint16_t)strtol(buf.c_str() + 8, NULL, 16);
          const char* sp = strchr(buf.c_str() + 8, ' ');
          probe_did_fim = sp ? (uint16_t)strtol(sp + 1, NULL, 16) : probe_did_ini;
          probe_pedir_m22 = true;
        }
        else if (buf.startsWith("M22 ")) { probe_did_ini = probe_did_fim = (uint16_t)strtol(buf.c_str() + 4, NULL, 16); probe_pedir_m22 = true; }
#endif  // !MODO_COMERCIAL (fim dos comandos de engenharia)
        else if (buf.length() > 0) Serial.printf(">>> Desconhecido: '%s'\n", buf.c_str());
        buf = "";
      } else if (buf.length() < 128) buf += c;   // #5: limita o comando (descarta o excesso, nao cresce sem fim)
      else { buf = ""; }                          // passou de 128 sem \n -> descarta (entrada malformada/abuso)
    }
    vTaskDelay(pdMS_TO_TICKS(100));
  }
}
