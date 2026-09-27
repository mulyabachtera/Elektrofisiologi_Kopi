"""
============================================================
PBEDS (Plant Bioelectric Early Detection System) Backend — AI Service
Memuat model 1D-CNN dan menjalankan inference real-time
============================================================
"""

import numpy as np
import os
import sys
from collections import deque
from scipy.signal import butter, filtfilt

# Tambahkan path ai_simulator agar bisa import model
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'ai_simulator'))

from config import MODEL_PATH, WINDOW_SIZE, SAMPLE_RATE

# ── Konstanta Preprocessing (sama dengan Script 2) ────────────
LOW_CUTOFF   = 0.01
HIGH_CUTOFF  = 4.5
FILTER_ORDER = 4


def _bandpass_filter(signal: np.ndarray) -> np.ndarray:
    nyquist = SAMPLE_RATE / 2.0
    b, a = butter(FILTER_ORDER,
                  [LOW_CUTOFF / nyquist, HIGH_CUTOFF / nyquist],
                  btype='bandpass')
    return filtfilt(b, a, signal).astype(np.float32)


def _zscore_normalize(signal: np.ndarray) -> np.ndarray:
    mean, std = np.mean(signal), np.std(signal)
    return ((signal - mean) / (std + 1e-8)).astype(np.float32)


class AIService:
    """
    Service AI inference untuk PBEDS (Plant Bioelectric Early Detection System).
    Maintains buffer 200 titik data terakhir (sliding window real-time).
    """

    def __init__(self):
        self.model = None
        self.buffer: deque = deque(maxlen=WINDOW_SIZE)
        self._load_model()

    def _load_model(self):
        """Load model Keras dari file."""
        try:
            import tensorflow as tf
            abs_model_path = os.path.abspath(
                os.path.join(os.path.dirname(__file__), MODEL_PATH)
            )
            if os.path.exists(abs_model_path):
                self.model = tf.keras.models.load_model(abs_model_path)
                print(f"[AI] ✅ Model dimuat dari: {abs_model_path}")
            else:
                print(f"[AI] ⚠️  Model tidak ditemukan: {abs_model_path}")
                print("[AI]    Menggunakan rule-based fallback.")
        except Exception as e:
            print(f"[AI] ⚠️  Gagal load model: {e}")
            print("[AI]    Menggunakan rule-based fallback.")

    def add_data_point(self, voltase_mv: float):
        """Tambahkan satu titik data baru ke buffer."""
        self.buffer.append(voltase_mv)

    def predict(
        self,
        voltase_mv: float,
        baseline_mean: float | None = None,
        baseline_std:  float | None = None,
    ) -> dict:
        """
        Prediksi status tanaman.

        Args:
            voltase_mv    : Voltase terbaru dalam milliVolt
            baseline_mean : Mean baseline individu (dari fase KALIBRASI firmware)
            baseline_std  : Standar deviasi baseline individu

        Returns:
            dict: {status, confidence, z_score, voltase_mean_mv, model_used, buffer_filled}
        """
        self.add_data_point(voltase_mv)
        buffer_filled = len(self.buffer) >= WINDOW_SIZE

        # ── Prioritas 1: Adaptive baseline dari firmware (scan mode) ──
        if baseline_mean is not None and baseline_std is not None and baseline_std > 0.01:
            return self._predict_adaptive(voltase_mv, baseline_mean, baseline_std)

        # ── Prioritas 2: 1D-CNN jika buffer penuh ─────────────────
        if self.model is not None and buffer_filled:
            return self._predict_cnn()

        # ── Fallback: Rule-based ───────────────────────────────────
        return self._predict_rule_based(voltase_mv, buffer_filled)

    def _predict_cnn(self) -> dict:
        """Inference menggunakan model 1D-CNN."""
        signal = np.array(self.buffer, dtype=np.float32)

        # Preprocessing
        filtered   = _bandpass_filter(signal)
        normalized = _zscore_normalize(filtered)
        X = normalized[np.newaxis, :, np.newaxis]  # (1, 200, 1)

        prob_stress = float(self.model.predict(X, verbose=0)[0][0])
        is_stress   = prob_stress >= 0.5
        confidence  = prob_stress if is_stress else (1.0 - prob_stress)

        # Level keparahan
        voltase_mean = float(np.mean(self.buffer))
        voltase_range = float(np.max(self.buffer) - np.min(self.buffer))
        if is_stress and (confidence > 0.85 or voltase_range > 8.0):
            status = "KRITIS"
        elif is_stress:
            status = "STRES"
        else:
            status = "NORMAL"

        return {
            "status"          : status,
            "confidence"      : round(confidence, 4),
            "prob_stress"     : round(prob_stress, 4),
            "voltase_mean_mv" : round(voltase_mean, 3),
            "model_used"      : "1D-CNN",
            "buffer_filled"   : True,
        }

    def _predict_adaptive(self, voltase_mv: float,
                           baseline_mean: float, baseline_std: float) -> dict:
        """
        Prediksi berbasis Z-score terhadap baseline individu tanaman.
        Metode ini PALING AKURAT karena memperhitungkan variasi antar individu.

        Z-score = (voltase - baseline_mean) / baseline_std
        |z| < 1.5  → NORMAL
        1.5 ≤ |z| < 3.0 → STRES
        |z| ≥ 3.0  → KRITIS
        """
        z = (voltase_mv - baseline_mean) / max(baseline_std, 0.01)
        abs_z = abs(z)

        if abs_z >= 3.0:
            status     = "KRITIS"
            confidence = min(0.99, 0.80 + (abs_z - 3.0) / 10.0)
        elif abs_z >= 1.5:
            status     = "STRES"
            confidence = min(0.95, 0.60 + (abs_z - 1.5) / 5.0)
        else:
            status     = "NORMAL"
            confidence = min(0.99, 0.70 + (1.5 - abs_z) / 3.0)

        return {
            "status"          : status,
            "confidence"      : round(confidence, 4),
            "z_score"         : round(z, 4),
            "prob_stress"     : round(abs_z / 4.5, 4),  # normalized 0-1
            "voltase_mean_mv" : round(voltase_mv, 3),
            "baseline_mean"   : round(baseline_mean, 3),
            "baseline_std"    : round(baseline_std, 3),
            "model_used"      : "Adaptive-Baseline (Z-score)",
            "buffer_filled"   : True,
        }

    def _predict_rule_based(self, voltase_mv: float, buffer_filled: bool) -> dict:
        """Fallback: Rule-based threshold jika model belum siap."""
        v = voltase_mv
        if v < 6.0 or v > 20.0:
            status, confidence = "KRITIS", 0.90
        elif v < 9.0 or v > 16.0:
            status, confidence = "STRES", 0.75
        else:
            status, confidence = "NORMAL", 0.85

        return {
            "status"          : status,
            "confidence"      : confidence,
            "prob_stress"     : confidence if status != "NORMAL" else 0.15,
            "voltase_mean_mv" : round(voltase_mv, 3),
            "model_used"      : "Rule-based (model belum dimuat)" if not buffer_filled
                                else "Rule-based (buffer mengisi...)",
            "buffer_filled"   : buffer_filled,
        }


# Singleton instance
ai_service = AIService()
