# Laporan Analisis Proyek & Desain AI Sistem Elektrofisiologi Kopi

Dokumen ini merupakan rangkuman eksekutif dari *Kerangka Acuan Kerja (KAK), Product Requirements Document (PRD), dan Proposal* terkait pengembangan Sistem Elektrofisiologi Cerdas Tanaman Kopi Berbasis AI (PBEDS), serta rancangan awal untuk simulasi Artificial Intelligence (AI).

---

## 1. Latar Belakang & Tujuan
*   **Masalah Utama:** Penurunan produktivitas Kopi Arabika di Indonesia hingga 30%-40% karena penanganan stres (kekeringan, nutrisi, hama) yang terlambat akibat mengandalkan observasi visual (seperti klorosis/nekrosis).
*   **Solusi Bioteknologi:** Menganalisis *Action Potential (AP)* dan *Variation Potential (VP)* pada tanaman. Gelombang mikrovolt listrik ini akan merespons stres **7 - 14 hari lebih cepat** sebelum gejala fisik terlihat oleh mata manusia.
*   **Tujuan Proyek:** Membangun ekosistem *Internet of Things* (IoT) dan *Machine Learning* terintegrasi untuk mendeteksi dini kesehatan tanaman.

## 2. Arsitektur Ekosistem Sistem
Sistem ini terbagi menjadi tiga pilar utama:

### A. Perangkat Keras (Node Sensor IoT)
*   **Mikrokontroler:** ESP32-S3 DevKit (Dual-Core, terintegrasi WiFi & BLE).
*   **Modul ADC (Analog-to-Digital Converter):** Menggunakan **ADS1256 24-bit** untuk pembacaan presisi level medis/industri. Pada tahap prototipe/Lite, menggunakan ADS1115 16-bit.
*   **Elektroda:** *Ag/AgCl Medical Grade Hydrogel* dipadukan dengan kabel terperisai (*shielded*) RG174 untuk meminimalisir *noise* (derau) elektromagnetik.
*   **Sensor Ekstra:** DHT22 (Suhu Lingkungan), Capacitive Soil Moisture (Kelembapan Tanah), dan BH1750 (Intensitas Cahaya).
*   **Catu Daya:** Baterai Lithium 18650 didukung proteksi TP4056 dan Boost Converter MT3608.

### B. Backend & Cloud Server (Rumah AI)
*   **Database:** Firebase Realtime Database (RTDB) untuk menyimpan *stream* data secara *live*.
*   **Server Processing:** Python & FastAPI. Menjadi jembatan antara Database dan Model AI.
*   **Notifikasi Gateway:** API otomatis (Webhook) untuk mengirimkan pesan WhatsApp ke petani saat anomali terdeteksi.

### C. Aplikasi Mobile (User Interface)
*   **Framework:** Flutter (Dart) - Mendukung Android & iOS.
*   **Fitur Dasbor:**
    *   *Live ECG Graph:* Menampilkan *waveform* gelombang tanaman secara real-time.
    *   *Plant Status Indicator:* Indikator visual kesehatan tanaman (Hijau, Kuning, Merah).
    *   *Log History:* Riwayat log deteksi stres tanaman.

---

## 3. Desain Sistem Artificial Intelligence (AI)
Karena *hardware* dalam proses pengiriman, pengembangan AI akan difokuskan pada tahap simulasi menggunakan bahasa pemrograman Python.

*   **Tipe Data:** *Time-Series Data* (Rangkaian waktu dari nilai tegangan listrik/Voltase).
*   **Arsitektur Model (Kandidat):** 
    1.  **1D-CNN (1-Dimensional Convolutional Neural Network):** Sangat tangguh untuk klasifikasi pola gelombang *(waveform recognition)*.
    2.  **Random Forest / XGBoost:** Sebagai opsi *fallback* yang ringan berbasis ekstraksi fitur matematis.
*   **Kategori Klasifikasi Output:**
    *   `Normal` (Tegangan stabil di kisaran baseline).
    *   `High Stress / Drought` (Terjadi tren Depolarisasi tajam dan persisten).
*   **Target Akurasi:** Nilai *F1-Score* di atas **88%**.

### Langkah Pembuatan Mockup AI (Sambil Menunggu Hardware)
1.  **Dataset Generator:** Membuat skrip Python penghasil *dummy data* yang mensimulasikan gelombang *Action Potential* tanaman sehat dan tanaman stres dengan penambahan *noise* alami.
2.  **Data Preprocessing:** Memfilter *noise* dari sinyal *(Signal Processing/Filtering)*.
3.  **Model Training:** Membangun model 1D-CNN sederhana menggunakan TensorFlow/Keras untuk mengklasifikasi dataset buatan tersebut.
4.  **Inference Pipeline:** Membuat fungsi simulasi yang menerima sinyal masuk, lalu mengembalikan status "Sehat" atau "Stres".

---

## 4. Roadmap Proyek (Rencana Eksekusi)
*   **Phase 1 (Minggu 1 - 4):** Proof of Concept (PoC) & Pengujian hardware di breadboard.
*   **Phase 2 (Minggu 5 - 12):** Minimum Viable Product (MVP) - Pembuatan Firmware C++, Backend FastAPI, & Aplikasi Flutter.
*   **Phase 3 (Minggu 13 - 20):** Field Test - Uji coba lapangan pada 5 titik lokasi perkebunan kopi.
*   **Phase 4 (Minggu 21 - 26):** Komersialisasi & Fabrikasi Massal (Skala).

---

## 5. Ringkasan Anggaran (RAB)
*   **Biaya Komponen per Unit (BOM):** ± Rp 970.000,- (Termasuk ESP32, ADC 24-bit, Sensor, Baterai, Enclosure Waterproof IP65, dan PCB).
*   **Total Investasi R&D Proyek:** Rp 256.025.000,- (Meliputi Riset, Fabrikasi, Cloud Server, Pengujian Lapangan, dan Tenaga Ahli).

*Dokumen ini dibuat otomatis sebagai panduan kerja pengembangan tim pengembang perangkat lunak PBEDS.*
