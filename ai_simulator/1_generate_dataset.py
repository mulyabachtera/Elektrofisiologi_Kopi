"""
=============================================================
PBEDS (Plant Bioelectric Early Detection System) - Simulasi Dataset
Script 1: Generator Dataset Sinyal AP/VP Tanaman Kopi
=============================================================
Tujuan : Membuat dataset sinyal bioelektrik sintetis (dummy)
         untuk melatih model AI sambil menunggu hardware tiba.
Output : File .npy di folder data/
         - data/X_train.npy  -> Array sinyal (N, 200)
         - data/y_train.npy  -> Label (N,) : 0=Normal, 1=Stres
=============================================================
"""

import numpy as np
import os
import matplotlib.pyplot as plt
from scipy.signal import butter, filtfilt

# ── Konfigurasi ───────────────────────────────────────────────
SAMPLE_RATE      = 10      # Hz (ADS1115 kita baca 10x/detik)
SIGNAL_DURATION  = 20      # detik per sinyal
N_SAMPLES_CLASS  = 500     # jumlah sinyal per kelas
SIGNAL_LENGTH    = SAMPLE_RATE * SIGNAL_DURATION  # = 200 titik
BASELINE_VOLTAGE = 12.0    # mV baseline tanaman kopi sehat
RANDOM_SEED      = 42

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "data")

np.random.seed(RANDOM_SEED)

# ═══════════════════════════════════════════════════════════════
#  GENERATOR SINYAL NORMAL (Action Potential - Tanaman Sehat)
# ═══════════════════════════════════════════════════════════════
def generate_normal_signal(n: int = SIGNAL_LENGTH) -> np.ndarray:
    """
    Simulasi sinyal AP tanaman kopi sehat:
    - Baseline stabil di ~12 mV
    - Osilasi sinus lembut (variasi ritme sirkadian)
    - Noise Gaussian ringan (kondisi lapangan)
    - Sesekali ada spike kecil (AP spontan normal)
    """
    t = np.linspace(0, SIGNAL_DURATION, n)

    # Komponen 1: Baseline
    baseline = BASELINE_VOLTAGE

    # Komponen 2: Osilasi sirkadian lambat (0.05 Hz)
    slow_wave = 1.2 * np.sin(2 * np.pi * 0.05 * t)

    # Komponen 3: Variasi kecil frekuensi menengah (0.3 Hz)
    mid_wave = 0.4 * np.sin(2 * np.pi * 0.3 * t + np.random.uniform(0, 2*np.pi))

    # Komponen 4: Noise Gaussian (derau sensor + lingkungan)
    noise = np.random.normal(0, 0.3, n)

    # Komponen 5: AP spontan sesekali (1-3 spike kecil acak)
    signal = baseline + slow_wave + mid_wave + noise
    n_spikes = np.random.randint(1, 4)
    for _ in range(n_spikes):
        idx = np.random.randint(20, n - 20)
        spike_height = np.random.uniform(1.0, 2.5)
        signal[idx]     += spike_height
        signal[idx + 1] += spike_height * 0.6
        signal[idx + 2] += spike_height * 0.2

    return signal.astype(np.float32)


# ═══════════════════════════════════════════════════════════════
#  GENERATOR SINYAL STRES (Variation Potential - Tanaman Stres)
# ═══════════════════════════════════════════════════════════════
def generate_stress_signal(n: int = SIGNAL_LENGTH) -> np.ndarray:
    """
    Simulasi sinyal VP tanaman kopi yang mengalami stres (kekeringan/hama):
    - Depolarisasi: baseline turun progresif dari ~12mV ke ~6-8 mV
    - Amplitudo fluktuasi lebih besar
    - Spike VP karakteristik: lonjakan tajam dan cepat
    - Noise lebih tinggi (metabolisme tanaman kacau)
    - Frekuensi lebih tidak beraturan
    """
    t = np.linspace(0, SIGNAL_DURATION, n)

    # Komponen 1: Depolarisasi progresif (baseline turun)
    depolarization_rate = np.random.uniform(0.15, 0.35)  # mV/detik
    baseline = BASELINE_VOLTAGE - depolarization_rate * t

    # Komponen 2: Osilasi tidak teratur, amplitudo besar
    chaotic_freq = np.random.uniform(0.1, 0.5)
    large_wave = np.random.uniform(2.5, 5.0) * np.sin(
        2 * np.pi * chaotic_freq * t + np.random.uniform(0, 2*np.pi)
    )

    # Komponen 3: Komponen harmonik (stres menambah frekuensi)
    harmonic = np.random.uniform(0.5, 1.5) * np.sin(
        2 * np.pi * (chaotic_freq * 2.3) * t
    )

    # Komponen 4: Noise lebih tinggi
    noise = np.random.normal(0, 0.8, n)

    # Komponen 5: VP Spikes — karakteristik paling khas stres
    # VP muncul 2-6 kali, berbentuk lonjakan besar dan cepat
    signal = baseline + large_wave + harmonic + noise
    n_vp_spikes = np.random.randint(2, 7)
    for _ in range(n_vp_spikes):
        idx = np.random.randint(10, n - 10)
        spike_height = np.random.uniform(3.5, 8.0)  # Jauh lebih besar dari normal
        # Bentuk VP: naik cepat, turun lebih lambat
        signal[idx - 1] += spike_height * 0.3
        signal[idx]     += spike_height
        signal[idx + 1] += spike_height * 0.7
        signal[idx + 2] += spike_height * 0.4
        signal[idx + 3] += spike_height * 0.15

    return signal.astype(np.float32)


# ═══════════════════════════════════════════════════════════════
#  GENERATE & SIMPAN DATASET
# ═══════════════════════════════════════════════════════════════
def main():
    print("=" * 60)
    print("  PBEDS (Plant Bioelectric Early Detection System) Dataset Generator - Sinyal AP/VP Tanaman Kopi")
    print("=" * 60)

    # Buat folder output
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print(f"\n📁 Output folder: {OUTPUT_DIR}")

    # Generate sinyal
    print(f"\n⚙️  Membuat {N_SAMPLES_CLASS} sinyal NORMAL...")
    X_normal = np.array([generate_normal_signal() for _ in range(N_SAMPLES_CLASS)])
    y_normal = np.zeros(N_SAMPLES_CLASS, dtype=np.int32)

    print(f"⚙️  Membuat {N_SAMPLES_CLASS} sinyal STRES...")
    X_stress = np.array([generate_stress_signal() for _ in range(N_SAMPLES_CLASS)])
    y_stress = np.ones(N_SAMPLES_CLASS, dtype=np.int32)

    # Gabungkan dan acak
    X = np.vstack([X_normal, X_stress])
    y = np.concatenate([y_normal, y_stress])

    shuffle_idx = np.random.permutation(len(X))
    X, y = X[shuffle_idx], y[shuffle_idx]

    print(f"\n✅ Dataset dibuat:")
    print(f"   Total sinyal : {len(X)}")
    print(f"   Panjang tiap sinyal : {SIGNAL_LENGTH} titik ({SIGNAL_DURATION} detik @ {SAMPLE_RATE} Hz)")
    print(f"   Shape X : {X.shape}")
    print(f"   Kelas   : {np.bincount(y)} (Normal, Stres)")

    # Simpan
    np.save(os.path.join(OUTPUT_DIR, "X_raw.npy"), X)
    np.save(os.path.join(OUTPUT_DIR, "y_raw.npy"), y)
    print(f"\n💾 Tersimpan: data/X_raw.npy, data/y_raw.npy")

    # Visualisasi contoh
    print("\n📊 Membuat visualisasi contoh sinyal...")
    fig, axes = plt.subplots(2, 2, figsize=(14, 7))
    fig.suptitle("Contoh Sinyal Bioelektrik Tanaman Kopi", fontsize=14, fontweight='bold')

    t = np.linspace(0, SIGNAL_DURATION, SIGNAL_LENGTH)

    for i, ax in enumerate(axes.flat[:2]):
        ax.plot(t, X_normal[i], color='#013E37', linewidth=1.2)
        ax.set_title(f"NORMAL #{i+1}", color='#013E37', fontweight='bold')
        ax.set_ylabel("Voltase (mV)")
        ax.set_xlabel("Waktu (detik)")
        ax.axhline(BASELINE_VOLTAGE, color='gray', linestyle='--', alpha=0.5, linewidth=0.8)
        ax.set_ylim(0, 25)
        ax.grid(True, alpha=0.3)

    for i, ax in enumerate(axes.flat[2:]):
        ax.plot(t, X_stress[i], color='#D32F2F', linewidth=1.2)
        ax.set_title(f"STRES #{i+1}", color='#D32F2F', fontweight='bold')
        ax.set_ylabel("Voltase (mV)")
        ax.set_xlabel("Waktu (detik)")
        ax.axhline(BASELINE_VOLTAGE, color='gray', linestyle='--', alpha=0.5, linewidth=0.8)
        ax.set_ylim(0, 25)
        ax.grid(True, alpha=0.3)

    plt.tight_layout()
    plot_path = os.path.join(OUTPUT_DIR, "contoh_sinyal.png")
    plt.savefig(plot_path, dpi=150, bbox_inches='tight')
    plt.show()
    print(f"📸 Plot disimpan: {plot_path}")

    print("\n✅ Script 1 selesai! Lanjutkan ke: python 2_preprocess.py")


if __name__ == "__main__":
    main()
