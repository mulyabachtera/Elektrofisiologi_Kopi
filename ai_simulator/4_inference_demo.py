"""
=============================================================
PBEDS (Plant Bioelectric Early Detection System) - Inference Demo
Script 4: Inference Pipeline Demo
=============================================================
Tujuan : Simulasi end-to-end inference — seperti yang akan
         terjadi saat hardware sudah terhubung ke Firebase.
         Input = array voltase mentah (dari ESP32 via Firebase)
         Output = {"status": "NORMAL/STRES", "confidence": 0.97}

Cara pakai:
  python 4_inference_demo.py
  python 4_inference_demo.py --mode stress   (simulasi sinyal stres)
  python 4_inference_demo.py --mode normal   (simulasi sinyal normal)
=============================================================
"""

import numpy as np
import os
import json
import time
import argparse
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from scipy.signal import butter, filtfilt

# ── Konfigurasi (harus sama dengan script sebelumnya) ─────────
SAMPLE_RATE  = 10
WINDOW_SIZE  = 200
LOW_CUTOFF   = 0.01
HIGH_CUTOFF  = 4.5
FILTER_ORDER = 4

MODEL_DIR = os.path.join(os.path.dirname(__file__), "model")
DATA_DIR  = os.path.join(os.path.dirname(__file__), "data")


# ═══════════════════════════════════════════════════════════════
#  PREPROCESSING FUNCTIONS (duplikasi dari Script 2 untuk portabilitas)
# ═══════════════════════════════════════════════════════════════
def bandpass_filter(signal: np.ndarray) -> np.ndarray:
    nyquist = SAMPLE_RATE / 2.0
    b, a = butter(FILTER_ORDER,
                  [LOW_CUTOFF / nyquist, HIGH_CUTOFF / nyquist],
                  btype='bandpass')
    return filtfilt(b, a, signal).astype(np.float32)


def zscore_normalize(signal: np.ndarray) -> np.ndarray:
    mean, std = np.mean(signal), np.std(signal)
    return ((signal - mean) / (std + 1e-8)).astype(np.float32)


def preprocess_signal(raw_signal: np.ndarray) -> np.ndarray:
    """
    Preprocessing pipeline lengkap untuk satu sinyal.
    Input : array voltase mentah (panjang >= WINDOW_SIZE)
    Output: window siap prediksi, shape (1, WINDOW_SIZE, 1)
    """
    # Ambil window terakhir jika sinyal lebih panjang
    if len(raw_signal) > WINDOW_SIZE:
        raw_signal = raw_signal[-WINDOW_SIZE:]
    elif len(raw_signal) < WINDOW_SIZE:
        # Pad dengan nilai mean jika terlalu pendek
        pad = np.full(WINDOW_SIZE - len(raw_signal), np.mean(raw_signal))
        raw_signal = np.concatenate([pad, raw_signal])

    filtered    = bandpass_filter(raw_signal)
    normalized  = zscore_normalize(filtered)
    return normalized[np.newaxis, :, np.newaxis]  # shape: (1, 200, 1)


# ═══════════════════════════════════════════════════════════════
#  INFERENCE ENGINE
# ═══════════════════════════════════════════════════════════════
class PBEDSInferenceEngine:
    """
    Engine inference utama PBEDS (Plant Bioelectric Early Detection System).
    Siap diintegrasikan ke backend FastAPI atau langsung di edge device.
    """
    def __init__(self):
        self.model = None
        self._load_model()

    def _load_model(self):
        import tensorflow as tf
        model_path = os.path.join(MODEL_DIR, "pbeds_model.keras")
        if os.path.exists(model_path):
            print(f"🧠 Memuat model dari: {model_path}")
            self.model = tf.keras.models.load_model(model_path)
            print("✅ Model berhasil dimuat!")
        else:
            print("⚠️  Model belum ada. Jalankan dulu: python 3_train_model.py")
            print("   Demo akan berjalan dengan threshold rule-based sementara.")

    def predict(self, raw_signal: np.ndarray) -> dict:
        """
        Prediksi status tanaman dari sinyal voltase mentah.

        Args:
            raw_signal: Array voltase (mV) dari sensor, panjang >= 200 titik

        Returns:
            dict dengan keys: status, confidence, voltase_mean_mv,
                              voltase_range_mv, model_used
        """
        t_start = time.perf_counter()

        voltase_mean = float(np.mean(raw_signal))
        voltase_range = float(np.max(raw_signal) - np.min(raw_signal))

        if self.model is not None:
            # ── Mode AI: gunakan 1D-CNN ──────────────────────
            X = preprocess_signal(raw_signal)
            prob_stress = float(self.model.predict(X, verbose=0)[0][0])
            is_stress   = prob_stress >= 0.5
            confidence  = prob_stress if is_stress else (1.0 - prob_stress)
            model_used  = "1D-CNN (TensorFlow)"
        else:
            # ── Fallback: Rule-based threshold ────────────────
            # Logika sederhana berdasarkan range voltase
            is_stress   = voltase_range > 5.0 or voltase_mean < 8.0
            prob_stress = 0.85 if is_stress else 0.15
            confidence  = 0.85
            model_used  = "Rule-based (model belum ditraining)"

        # Tentukan level keparahan
        if is_stress:
            if confidence > 0.85 or voltase_range > 8.0:
                status = "KRITIS"
            else:
                status = "STRES"
        else:
            status = "NORMAL"

        t_elapsed_ms = (time.perf_counter() - t_start) * 1000

        return {
            "status"          : status,
            "confidence"      : round(confidence, 4),
            "prob_stress"     : round(prob_stress, 4),
            "voltase_mean_mv" : round(voltase_mean, 3),
            "voltase_range_mv": round(voltase_range, 3),
            "model_used"      : model_used,
            "inference_ms"    : round(t_elapsed_ms, 2),
        }


# ═══════════════════════════════════════════════════════════════
#  SIGNAL SIMULATORS
# ═══════════════════════════════════════════════════════════════
def simulate_normal_signal() -> np.ndarray:
    t = np.linspace(0, 20, WINDOW_SIZE)
    baseline = 12.0
    wave = 1.2 * np.sin(2 * np.pi * 0.05 * t)
    noise = np.random.normal(0, 0.3, WINDOW_SIZE)
    return (baseline + wave + noise).astype(np.float32)


def simulate_stress_signal() -> np.ndarray:
    t = np.linspace(0, 20, WINDOW_SIZE)
    baseline = 12.0 - 0.25 * t  # depolarisasi
    wave = 4.0 * np.sin(2 * np.pi * 0.2 * t)
    noise = np.random.normal(0, 0.8, WINDOW_SIZE)
    spikes = np.zeros(WINDOW_SIZE)
    for idx in np.random.randint(20, WINDOW_SIZE - 20, 4):
        h = np.random.uniform(5, 9)
        spikes[idx:idx+4] += [h * 0.4, h, h * 0.6, h * 0.2]
    return (baseline + wave + noise + spikes).astype(np.float32)


# ═══════════════════════════════════════════════════════════════
#  VISUALISASI HASIL
# ═══════════════════════════════════════════════════════════════
def visualize_result(signal: np.ndarray, result: dict, mode: str):
    COLOR_MAP = {"NORMAL": "#013E37", "STRES": "#F57C00", "KRITIS": "#D32F2F"}
    status = result["status"]
    color  = COLOR_MAP.get(status, "#333")

    t = np.linspace(0, len(signal) / SAMPLE_RATE, len(signal))

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 7), gridspec_kw={'height_ratios': [3, 1]})
    fig.patch.set_facecolor('#F8F5E4')

    # ── Subplot 1: Sinyal ──────────────────────────────────────
    ax1.set_facecolor('#F8F5E4')
    ax1.plot(t, signal, color=color, linewidth=1.5, label=f'Voltase (mV)')
    ax1.axhline(np.mean(signal), color=color, linestyle='--', alpha=0.5,
                linewidth=1, label=f'Mean: {np.mean(signal):.2f} mV')
    ax1.fill_between(t, signal, np.mean(signal), alpha=0.15, color=color)
    ax1.set_title(
        f"PBEDS (Plant Bioelectric Early Detection System) — Analisis Sinyal Bioelektrik Tanaman Kopi\n"
        f"Mode Simulasi: {mode.upper()}",
        fontsize=13, fontweight='bold', color='#333'
    )
    ax1.set_ylabel("Voltase (mV)", fontsize=11)
    ax1.legend(loc='upper right')
    ax1.grid(True, alpha=0.3, color='gray')

    # Status box
    ax1.text(0.02, 0.95, f"STATUS: {status}",
             transform=ax1.transAxes,
             fontsize=14, fontweight='bold', color=color,
             verticalalignment='top',
             bbox=dict(boxstyle='round,pad=0.5', facecolor='white', alpha=0.8,
                       edgecolor=color, linewidth=2))

    # ── Subplot 2: Result JSON ─────────────────────────────────
    ax2.set_facecolor('#013E37')
    result_text = json.dumps(result, indent=2)
    ax2.text(0.02, 0.95, result_text,
             transform=ax2.transAxes,
             fontsize=8.5, color='#FFEFB3',
             verticalalignment='top', fontfamily='monospace')
    ax2.set_xticks([])
    ax2.set_yticks([])
    ax2.set_title("Output JSON Inference", color='#FFEFB3', fontsize=10,
                  loc='left', pad=4)

    plt.tight_layout()
    out_path = os.path.join(DATA_DIR, f"inference_result_{mode}.png")
    os.makedirs(DATA_DIR, exist_ok=True)
    plt.savefig(out_path, dpi=150, bbox_inches='tight')
    plt.show()
    print(f"📸 Visualisasi disimpan: {out_path}")


# ═══════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════
def main():
    parser = argparse.ArgumentParser(description='PBEDS (Plant Bioelectric Early Detection System) Inference Demo')
    parser.add_argument('--mode', choices=['normal', 'stress', 'both'],
                        default='both', help='Mode sinyal yang diuji')
    args = parser.parse_args()

    print("=" * 60)
    print("  PBEDS (Plant Bioelectric Early Detection System) Inference Pipeline Demo")
    print("=" * 60)

    engine = PBEDSInferenceEngine()

    modes = ['normal', 'stress'] if args.mode == 'both' else [args.mode]

    for mode in modes:
        print(f"\n{'─' * 50}")
        print(f"  Menguji sinyal: {mode.upper()}")
        print(f"{'─' * 50}")

        signal = simulate_normal_signal() if mode == 'normal' else simulate_stress_signal()
        result = engine.predict(signal)

        print(f"\n  📋 Hasil Inference:")
        print(json.dumps(result, indent=4))

        # Emoji status
        emoji = {"NORMAL": "🌿", "STRES": "⚠️", "KRITIS": "🚨"}.get(result["status"], "❓")
        print(f"\n  {emoji}  Status Final : {result['status']}")
        print(f"      Confidence  : {result['confidence'] * 100:.1f}%")
        print(f"      Waktu proses: {result['inference_ms']} ms")

        visualize_result(signal, result, mode)

    print("\n" + "=" * 60)
    print("  ✅ Demo inference selesai!")
    print("  🎯 Sistem siap — tinggal tunggu hardware untuk data nyata.")
    print("=" * 60)


if __name__ == "__main__":
    main()
