"""
=============================================================
PBEDS (Plant Bioelectric Early Detection System) - Preprocessing Pipeline
Script 2: Preprocessing Sinyal Bioelektrik
=============================================================
Tujuan : Membersihkan noise dari sinyal mentah dan
         mempersiapkan data dalam format yang siap untuk training.
Input  : data/X_raw.npy, data/y_raw.npy
Output : data/X_processed.npy, data/y_processed.npy
=============================================================
Pipeline:
  1. Bandpass Filter (0.01 - 4.5 Hz) → hapus DC drift & high-freq noise
  2. Normalisasi Z-score per sinyal
  3. Sliding Window → potong sinyal panjang menjadi window kecil
=============================================================
"""

import numpy as np
import os
import matplotlib.pyplot as plt
from scipy.signal import butter, filtfilt, sosfilt, butter as sos_butter

# ── Konfigurasi ───────────────────────────────────────────────
SAMPLE_RATE   = 10     # Hz
LOW_CUTOFF    = 0.01   # Hz (hapus DC drift / baseline wandering)
HIGH_CUTOFF   = 4.5    # Hz (hapus noise EMI frekuensi tinggi)
FILTER_ORDER  = 4      # Orde filter Butterworth

WINDOW_SIZE   = 200    # titik per window (= 20 detik)
STRIDE        = 50     # langkah geser (50% overlap)

DATA_DIR = os.path.join(os.path.dirname(__file__), "data")


# ═══════════════════════════════════════════════════════════════
#  FILTER BUTTERWORTH BANDPASS
# ═══════════════════════════════════════════════════════════════
def bandpass_filter(signal: np.ndarray, fs: int = SAMPLE_RATE,
                    low: float = LOW_CUTOFF, high: float = HIGH_CUTOFF,
                    order: int = FILTER_ORDER) -> np.ndarray:
    """
    Filter Butterworth Bandpass.
    - Menghapus frekuensi di bawah LOW_CUTOFF  (drift baseline, gerak tanaman lambat)
    - Menghapus frekuensi di atas HIGH_CUTOFF  (noise EMI dari power line, dll)
    - Menggunakan filtfilt (zero-phase) agar tidak ada phase distortion
    """
    nyquist = fs / 2.0
    low_norm  = low  / nyquist
    high_norm = high / nyquist

    # Clamp agar tidak di luar (0, 1)
    low_norm  = max(0.001, min(low_norm, 0.999))
    high_norm = max(0.001, min(high_norm, 0.999))

    b, a = butter(order, [low_norm, high_norm], btype='bandpass')
    return filtfilt(b, a, signal).astype(np.float32)


# ═══════════════════════════════════════════════════════════════
#  NORMALISASI Z-SCORE PER SINYAL
# ═══════════════════════════════════════════════════════════════
def zscore_normalize(signal: np.ndarray) -> np.ndarray:
    """
    Normalisasi Z-score: (x - mean) / std
    Membuat setiap sinyal memiliki mean=0 dan std=1.
    Penting agar model tidak bias terhadap amplitudo absolut.
    """
    mean = np.mean(signal)
    std  = np.std(signal)
    if std < 1e-8:  # hindari pembagian nol
        return signal - mean
    return ((signal - mean) / std).astype(np.float32)


# ═══════════════════════════════════════════════════════════════
#  SLIDING WINDOW
# ═══════════════════════════════════════════════════════════════
def sliding_window(signal: np.ndarray, label: int,
                   window: int = WINDOW_SIZE, stride: int = STRIDE):
    """
    Potong satu sinyal panjang menjadi banyak window kecil.
    Hasilnya: lebih banyak sampel untuk training.
    """
    X_windows, y_windows = [], []
    for start in range(0, len(signal) - window + 1, stride):
        X_windows.append(signal[start:start + window])
        y_windows.append(label)
    return X_windows, y_windows


# ═══════════════════════════════════════════════════════════════
#  PIPELINE UTAMA
# ═══════════════════════════════════════════════════════════════
def preprocess_dataset(X: np.ndarray, y: np.ndarray):
    """
    Jalankan seluruh pipeline preprocessing.
    """
    print(f"  Input : {X.shape} sinyal mentah")

    X_filtered   = np.array([bandpass_filter(sig) for sig in X])
    X_normalized = np.array([zscore_normalize(sig) for sig in X_filtered])

    # Sliding window → expand dataset
    X_win, y_win = [], []
    for sig, label in zip(X_normalized, y):
        xw, yw = sliding_window(sig, label)
        X_win.extend(xw)
        y_win.extend(yw)

    X_out = np.array(X_win, dtype=np.float32)
    y_out = np.array(y_win, dtype=np.int32)

    print(f"  Output: {X_out.shape} windows (setelah sliding window)")
    return X_out, y_out


# ═══════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════
def main():
    print("=" * 60)
    print("  PBEDS (Plant Bioelectric Early Detection System) Preprocessing Pipeline")
    print("=" * 60)

    # Load data mentah
    X_path = os.path.join(DATA_DIR, "X_raw.npy")
    y_path = os.path.join(DATA_DIR, "y_raw.npy")

    if not os.path.exists(X_path):
        print("❌ ERROR: data/X_raw.npy tidak ditemukan!")
        print("   Jalankan dulu: python 1_generate_dataset.py")
        return

    X = np.load(X_path)
    y = np.load(y_path)
    print(f"\n📂 Data dimuat: {X.shape}, Labels: {np.bincount(y)}")

    # Visualisasi: sebelum vs sesudah filter
    print("\n📊 Membuat visualisasi filter...")
    fig, axes = plt.subplots(2, 2, figsize=(14, 7))
    fig.suptitle("Perbandingan Sinyal Sebelum & Sesudah Filter", fontsize=13, fontweight='bold')
    t = np.linspace(0, X.shape[1] / SAMPLE_RATE, X.shape[1])

    for col, (idx, label, color) in enumerate([(0, 'NORMAL', '#013E37'), (len(X)//2, 'STRES', '#D32F2F')]):
        raw = X[idx]
        filtered = bandpass_filter(raw)
        normalized = zscore_normalize(filtered)

        axes[0, col].plot(t, raw, color=color, alpha=0.7, linewidth=1)
        axes[0, col].set_title(f'{label} — Mentah', color=color, fontweight='bold')
        axes[0, col].set_ylabel("Voltase (mV)")
        axes[0, col].grid(True, alpha=0.3)

        axes[1, col].plot(t, normalized, color=color, linewidth=1.2)
        axes[1, col].set_title(f'{label} — Setelah Filter + Normalisasi', color=color, fontweight='bold')
        axes[1, col].set_ylabel("Amplitude (normalized)")
        axes[1, col].set_xlabel("Waktu (detik)")
        axes[1, col].grid(True, alpha=0.3)

    plt.tight_layout()
    plot_path = os.path.join(DATA_DIR, "preprocessing_result.png")
    plt.savefig(plot_path, dpi=150, bbox_inches='tight')
    plt.show()
    print(f"📸 Plot disimpan: {plot_path}")

    # Proses & simpan
    print("\n⚙️  Menjalankan preprocessing pipeline...")
    X_proc, y_proc = preprocess_dataset(X, y)

    np.save(os.path.join(DATA_DIR, "X_processed.npy"), X_proc)
    np.save(os.path.join(DATA_DIR, "y_processed.npy"), y_proc)

    print(f"\n✅ Preprocessing selesai!")
    print(f"   Shape : {X_proc.shape}")
    print(f"   Kelas : {np.bincount(y_proc)} (Normal, Stres)")
    print(f"   Tersimpan: data/X_processed.npy, data/y_processed.npy")
    print("\n✅ Script 2 selesai! Lanjutkan ke: python 3_train_model.py")


if __name__ == "__main__":
    main()
