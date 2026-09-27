/*
 * ============================================================
 *  PBEDS (Plant Bioelectric Early Detection System)
 *  Firmware v3.0 — Scan Mode + Adaptive Baseline Calibration
 * ============================================================
 *  Hardware:
 *    - ESP32 DevKit (USB Type-C, 30-pin)
 *    - Modul ADS1115 16-bit ADC (I2C: SDA=21, SCL=22)
 *    - Elektroda (tempel pada batang/daun kopi)
 *
 *  Library yang dibutuhkan (install via Arduino Library Manager):
 *    1. Adafruit ADS1X15   (by Adafruit)
 *
 *  Alur Scan:
 *    [STANDBY] → [KALIBRASI 30s] → [ANALISIS 3 menit] → [SELESAI]
 *
 *  Alur Data:
 *    Elektroda → ADS1115 → ESP32 → WiFi → Firebase RTDB → Flutter App
 * ============================================================
 */

#include <Adafruit_ADS1X15.h>
#include <HTTPClient.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <Wire.h>
#include <math.h>

// ============================================================
//  ★ KONFIGURASI WAJIB — ISI SEBELUM UPLOAD ★
// ============================================================
const char* WIFI_SSID     = "MyBach25";
const char* WIFI_PASSWORD = "apakegeh113";

const String FIREBASE_HOST = "https://elektrofisiologi-kopi-default-rtdb.asia-southeast1.firebasedatabase.app";
const String FIREBASE_PATH = "/sensor_data/node_1.json";
// ============================================================

// ── Durasi Fase Scan ─────────────────────────────────────────
const unsigned long DURASI_KALIBRASI_MS = 30000;   // 30 detik kalibrasi
const unsigned long DURASI_ANALISIS_MS  = 180000;  // 3 menit analisis

// ── Sampling & Pengiriman ────────────────────────────────────
const unsigned long BACA_INTERVAL  = 100;   // 10 Hz
const unsigned long KIRIM_INTERVAL = 1000;  // Kirim ke Firebase setiap 1 detik

// ── Objek ADS1115 ────────────────────────────────────────────
Adafruit_ADS1115 ads;

// ── Enum Fase Scan ───────────────────────────────────────────
enum FaseScan { STANDBY, KALIBRASI, ANALISIS, SELESAI };
FaseScan faseSaatIni = STANDBY;

// ── Variabel Kalibrasi (Adaptive Baseline) ───────────────────
float   bufferKalibrasi[300];     // Tampung 300 sampel (30 detik × 10 Hz)
int     indexKalibrasi = 0;
float   baselineMean   = 0.0;
float   baselineStd    = 0.0;
bool    baselineSiap   = false;

// ── Variabel Waktu Fase ──────────────────────────────────────
unsigned long waktuMulaiKalibrasi = 0;
unsigned long waktuMulaiAnalisis  = 0;
unsigned long lastBacaTime        = 0;
unsigned long lastKirimTime       = 0;

// ── Buffer Data Terkini ──────────────────────────────────────
float   voltaseMvTerkini = 0.0;
int16_t adcRawTerkini    = 0;
float   zScoreTerkini    = 0.0;
String  statusTerkini    = "STANDBY";
bool    wifiTerhubung    = false;

// ============================================================
//  FUNGSI: Hubungkan ke WiFi
// ============================================================
void hubungkanWiFi() {
  Serial.print("\nMenghubungkan ke WiFi: ");
  Serial.print(WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  int percobaan = 0;
  while (WiFi.status() != WL_CONNECTED && percobaan < 30) {
    delay(500);
    Serial.print(".");
    percobaan++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    wifiTerhubung = true;
    Serial.println("\n✓ WiFi Terhubung! IP: " + WiFi.localIP().toString());
  } else {
    wifiTerhubung = false;
    Serial.println("\n✗ WiFi GAGAL. Mode Offline (Serial Monitor).");
  }
}

// ============================================================
//  FUNGSI: Hitung Mean dari array
// ============================================================
float hitungMean(float* arr, int n) {
  float sum = 0;
  for (int i = 0; i < n; i++) sum += arr[i];
  return sum / n;
}

// ============================================================
//  FUNGSI: Hitung Standar Deviasi dari array
// ============================================================
float hitungStd(float* arr, int n, float mean) {
  float sumSq = 0;
  for (int i = 0; i < n; i++) sumSq += pow(arr[i] - mean, 2);
  return sqrt(sumSq / n);
}

// ============================================================
//  FUNGSI: Tentukan Status berdasarkan Z-Score
//          (Adaptive — tidak bergantung pada nilai absolut)
// ============================================================
String tentukanStatusZScore(float zScore) {
  float absZ = abs(zScore);
  if (absZ >= 3.0) return "KRITIS";
  if (absZ >= 1.5) return "STRES";
  return "NORMAL";
}

// ============================================================
//  FUNGSI: Kirim Data ke Firebase
// ============================================================
bool kirimKeFirebase(String jsonPayload) {
  if (WiFi.status() != WL_CONNECTED) {
    hubungkanWiFi();
    if (!wifiTerhubung) return false;
  }

  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  http.begin(client, FIREBASE_HOST + FIREBASE_PATH);
  http.addHeader("Content-Type", "application/json");
  http.setTimeout(5000);

  int code = http.PUT(jsonPayload);
  http.end();

  return (code == 200 || code == 204);
}

// ============================================================
//  FUNGSI: Bangun JSON payload sesuai fase
// ============================================================
String bangunPayload(String fase) {
  unsigned long detikScan = 0;
  if (fase == "KALIBRASI") {
    detikScan = (millis() - waktuMulaiKalibrasi) / 1000;
  } else if (fase == "ANALISIS" || fase == "SELESAI") {
    detikScan = (millis() - waktuMulaiAnalisis) / 1000;
  }

  String json = "{";
  json += "\"voltase\":"       + String(voltaseMvTerkini, 5) + ",";
  json += "\"nilai_adc\":"     + String(adcRawTerkini)       + ",";
  json += "\"status\":\""      + statusTerkini               + "\",";
  json += "\"fase_scan\":\""   + fase                        + "\",";
  json += "\"baseline_mean\":" + String(baselineMean, 4)     + ",";
  json += "\"baseline_std\":"  + String(baselineStd, 4)      + ",";
  json += "\"z_score\":"       + String(zScoreTerkini, 4)    + ",";
  json += "\"detik_scan\":"    + String(detikScan)           + ",";
  json += "\"timestamp_ms\":"  + String(millis());
  json += "}";
  return json;
}

// ============================================================
//  SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n╔══════════════════════════════════════════════╗");
  Serial.println("║  PBEDS (Plant Bioelectric Early Detection)    ║");
  Serial.println("║  Firmware v3.0 — Scan Mode                   ║");
  Serial.println("╚══════════════════════════════════════════════╝");

  // Inisialisasi ADS1115
  Wire.begin();
  ads.setGain(GAIN_ONE); // ±4.096V, 0.125mV/bit
  if (!ads.begin()) {
    Serial.println("[ADS1115] ✗ GAGAL! Cek kabel I2C: SDA→GPIO21, SCL→GPIO22");
    while (1) delay(1000);
  }
  Serial.println("[ADS1115] ✓ Terhubung! (±4.096V, 0.125mV/bit)");

  hubungkanWiFi();

  Serial.println("\n[Sistem] ★ STANDBY — Menunggu perintah scan dari App...");
  Serial.println("Fase       | ADC_Raw  | Voltase(mV) | Z-Score | Status");
  Serial.println("-----------|----------|-------------|---------|--------");

  // Kirim status STANDBY ke Firebase
  statusTerkini = "STANDBY";
  String payload = bangunPayload("STANDBY");
  kirimKeFirebase(payload);
}

// ============================================================
//  LOOP UTAMA
// ============================================================
void loop() {
  unsigned long sekarang = millis();

  // ── Baca Sensor: 10 Hz ──────────────────────────────────────
  if (sekarang - lastBacaTime >= BACA_INTERVAL) {
    lastBacaTime = sekarang;

    adcRawTerkini    = ads.readADC_SingleEnded(0);
    voltaseMvTerkini = ads.computeVolts(adcRawTerkini) * 1000.0;

    // ── FSM (Finite State Machine) Fase Scan ──────────────────
    switch (faseSaatIni) {

      // ── STANDBY: Menunggu —————————————————————————————————
      case STANDBY:
        statusTerkini  = "STANDBY";
        zScoreTerkini  = 0.0;
        // AUTO-START: langsung mulai kalibrasi setelah 3 detik
        // Untuk produk: bisa diganti trigger dari Firebase (command dari App)
        if (sekarang > 3000 && !baselineSiap) {
          faseSaatIni          = KALIBRASI;
          waktuMulaiKalibrasi  = sekarang;
          indexKalibrasi       = 0;
          Serial.println("\n[KALIBRASI] Dimulai — Rekam baseline 30 detik...");
        }
        break;

      // ── KALIBRASI: Rekam baseline individu ────────────────
      case KALIBRASI:
        statusTerkini = "KALIBRASI";
        if (indexKalibrasi < 300) {
          bufferKalibrasi[indexKalibrasi++] = voltaseMvTerkini;
        }

        // Kalibrasi selesai setelah 30 detik
        if (sekarang - waktuMulaiKalibrasi >= DURASI_KALIBRASI_MS) {
          // Hitung statistik baseline
          baselineMean = hitungMean(bufferKalibrasi, indexKalibrasi);
          baselineStd  = hitungStd(bufferKalibrasi, indexKalibrasi, baselineMean);
          if (baselineStd < 0.01) baselineStd = 0.01; // Hindari pembagian nol

          baselineSiap          = true;
          faseSaatIni           = ANALISIS;
          waktuMulaiAnalisis    = sekarang;

          Serial.println("\n[KALIBRASI] ✓ Selesai!");
          Serial.printf("  Baseline Mean : %.3f mV\n", baselineMean);
          Serial.printf("  Baseline Std  : %.3f mV\n", baselineStd);
          Serial.println("[ANALISIS] Dimulai — 3 menit analisis...");
        }
        break;

      // ── ANALISIS: Hitung Z-score real-time ─────────────────
      case ANALISIS:
        if (baselineSiap) {
          zScoreTerkini = (voltaseMvTerkini - baselineMean) / baselineStd;
          statusTerkini = tentukanStatusZScore(zScoreTerkini);
        }

        // Analisis selesai setelah 3 menit
        if (sekarang - waktuMulaiAnalisis >= DURASI_ANALISIS_MS) {
          faseSaatIni = SELESAI;
          Serial.println("\n[SELESAI] Scan selesai!");
        }
        break;

      // ── SELESAI: Kirim hasil final, reset ──────────────────
      case SELESAI:
        // Kirim payload SELESAI ke Firebase (sekali)
        {
          String payloadFinal = bangunPayload("SELESAI");
          bool ok = kirimKeFirebase(payloadFinal);
          Serial.println("[SELESAI] Payload final " + String(ok ? "terkirim ✓" : "gagal ✗"));
        }

        // Reset untuk scan berikutnya
        faseSaatIni  = STANDBY;
        baselineSiap = false;
        indexKalibrasi = 0;
        statusTerkini  = "STANDBY";
        zScoreTerkini  = 0.0;
        Serial.println("[STANDBY] Siap scan berikutnya...\n");
        delay(2000);
        break;
    }

    // Serial output
    Serial.printf("%-10s | %-8d | %9.3f mV | %7.3f | %s\n",
      statusTerkini.c_str(), adcRawTerkini, voltaseMvTerkini,
      zScoreTerkini, statusTerkini.c_str());
  }

  // ── Kirim ke Firebase: 1 Hz ────────────────────────────────
  if (sekarang - lastKirimTime >= KIRIM_INTERVAL && wifiTerhubung) {
    lastKirimTime = sekarang;

    String faseStr = "";
    switch (faseSaatIni) {
      case STANDBY:  faseStr = "STANDBY";  break;
      case KALIBRASI: faseStr = "KALIBRASI"; break;
      case ANALISIS:  faseStr = "ANALISIS";  break;
      case SELESAI:   faseStr = "SELESAI";   break;
    }

    String payload = bangunPayload(faseStr);
    bool ok = kirimKeFirebase(payload);
    // (Log Firebase sudah di Serial dari fungsi lain)
  }
}
