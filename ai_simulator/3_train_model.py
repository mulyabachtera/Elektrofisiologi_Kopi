"""
=============================================================
PBEDS (Plant Bioelectric Early Detection System) - Model Training
Script 3: Training Model 1D-CNN
=============================================================
Tujuan : Melatih model Deep Learning (1D-CNN) untuk mengklasifikasi
         sinyal bioelektrik tanaman kopi: Normal vs Stres.
Input  : data/X_processed.npy, data/y_processed.npy
Output : model/pbeds_model.keras  (model siap pakai)
         model/training_history.png
Target : F1-Score >= 0.88
=============================================================
"""

import numpy as np
import os
import matplotlib.pyplot as plt
from sklearn.model_selection import train_test_split
from sklearn.metrics import (classification_report, confusion_matrix,
                             f1_score, ConfusionMatrixDisplay)

# TensorFlow / Keras
import tensorflow as tf
from tensorflow.keras import layers, models, callbacks, optimizers  # type: ignore

# ── Konfigurasi ───────────────────────────────────────────────
WINDOW_SIZE  = 200     # panjang window (harus sama dengan Script 2)
BATCH_SIZE   = 32
EPOCHS       = 60
LEARNING_RATE = 0.001
TEST_SPLIT   = 0.2
VAL_SPLIT    = 0.15
RANDOM_SEED  = 42

DATA_DIR  = os.path.join(os.path.dirname(__file__), "data")
MODEL_DIR = os.path.join(os.path.dirname(__file__), "model")
CLASS_NAMES = ["NORMAL", "STRES"]

tf.random.set_seed(RANDOM_SEED)
np.random.seed(RANDOM_SEED)


# ═══════════════════════════════════════════════════════════════
#  ARSITEKTUR MODEL 1D-CNN
# ═══════════════════════════════════════════════════════════════
def build_model(input_length: int = WINDOW_SIZE) -> tf.keras.Model:
    """
    Arsitektur 1D-CNN untuk klasifikasi waveform bioelektrik.

    Mengapa 1D-CNN?
    - Sangat efektif untuk menangkap pola lokal dalam time-series
    - Ringan dan cepat (cocok untuk edge deployment di masa depan)
    - Terbukti baik untuk sinyal ECG/EEG (data bioelektrik serupa)

    Lapisan:
      Block 1: Deteksi pola mikro (spike kecil AP)
      Block 2: Deteksi pola meso (bentuk gelombang VP)
      Block 3: Feature agregat global
      Classifier: Dense layers dengan regularisasi Dropout
    """
    inp = layers.Input(shape=(input_length, 1), name="sinyal_input")

    # ── Block 1: Feature Extraction Tingkat Rendah ─────────────
    x = layers.Conv1D(32, kernel_size=7, padding='same', activation='relu',
                      name="conv1_a")(inp)
    x = layers.BatchNormalization(name="bn1_a")(x)
    x = layers.Conv1D(32, kernel_size=5, padding='same', activation='relu',
                      name="conv1_b")(x)
    x = layers.BatchNormalization(name="bn1_b")(x)
    x = layers.MaxPooling1D(pool_size=2, name="pool1")(x)
    x = layers.Dropout(0.2, name="drop1")(x)

    # ── Block 2: Feature Extraction Tingkat Menengah ──────────
    x = layers.Conv1D(64, kernel_size=5, padding='same', activation='relu',
                      name="conv2_a")(x)
    x = layers.BatchNormalization(name="bn2_a")(x)
    x = layers.Conv1D(64, kernel_size=3, padding='same', activation='relu',
                      name="conv2_b")(x)
    x = layers.BatchNormalization(name="bn2_b")(x)
    x = layers.MaxPooling1D(pool_size=2, name="pool2")(x)
    x = layers.Dropout(0.25, name="drop2")(x)

    # ── Block 3: Feature Agregat ──────────────────────────────
    x = layers.Conv1D(128, kernel_size=3, padding='same', activation='relu',
                      name="conv3")(x)
    x = layers.BatchNormalization(name="bn3")(x)
    x = layers.GlobalAveragePooling1D(name="gap")(x)

    # ── Classifier Head ───────────────────────────────────────
    x = layers.Dense(64, activation='relu', name="dense1")(x)
    x = layers.Dropout(0.35, name="drop3")(x)
    x = layers.Dense(32, activation='relu', name="dense2")(x)
    out = layers.Dense(1, activation='sigmoid', name="output")(x)

    model = models.Model(inputs=inp, outputs=out, name="PBEDS_1DCNN")
    return model


# ═══════════════════════════════════════════════════════════════
#  PLOT TRAINING HISTORY
# ═══════════════════════════════════════════════════════════════
def plot_history(history, save_path: str):
    fig, axes = plt.subplots(1, 2, figsize=(13, 5))
    fig.suptitle("Riwayat Training Model PBEDS (Plant Bioelectric Early Detection System) 1D-CNN", fontsize=13, fontweight='bold')

    # Loss
    axes[0].plot(history.history['loss'],     label='Training Loss',   color='#013E37', linewidth=2)
    axes[0].plot(history.history['val_loss'], label='Validation Loss', color='#D32F2F', linewidth=2, linestyle='--')
    axes[0].set_title("Loss")
    axes[0].set_xlabel("Epoch")
    axes[0].set_ylabel("Binary Crossentropy")
    axes[0].legend()
    axes[0].grid(True, alpha=0.3)

    # Accuracy
    axes[1].plot(history.history['accuracy'],     label='Training Accuracy',   color='#013E37', linewidth=2)
    axes[1].plot(history.history['val_accuracy'], label='Validation Accuracy', color='#D32F2F', linewidth=2, linestyle='--')
    axes[1].axhline(0.88, color='orange', linestyle=':', linewidth=1.5, label='Target F1=0.88')
    axes[1].set_title("Accuracy")
    axes[1].set_xlabel("Epoch")
    axes[1].set_ylabel("Accuracy")
    axes[1].legend()
    axes[1].grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(save_path, dpi=150, bbox_inches='tight')
    plt.show()
    print(f"📸 Plot training tersimpan: {save_path}")


# ═══════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════
def main():
    print("=" * 60)
    print("  PBEDS (Plant Bioelectric Early Detection System) Model Training — 1D-CNN")
    print(f"  TensorFlow versi: {tf.__version__}")
    print("=" * 60)

    os.makedirs(MODEL_DIR, exist_ok=True)

    # ── Load Data ─────────────────────────────────────────────
    X_path = os.path.join(DATA_DIR, "X_processed.npy")
    y_path = os.path.join(DATA_DIR, "y_processed.npy")

    if not os.path.exists(X_path):
        print("❌ data/X_processed.npy tidak ditemukan!")
        print("   Jalankan dulu: python 2_preprocess.py")
        return

    X = np.load(X_path)
    y = np.load(y_path)
    print(f"\n📂 Data dimuat: {X.shape}, Labels: {np.bincount(y)}")

    # Reshape untuk Conv1D: (samples, timesteps, channels=1)
    X = X[..., np.newaxis]

    # ── Split Train / Test ────────────────────────────────────
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=TEST_SPLIT, random_state=RANDOM_SEED, stratify=y
    )
    print(f"   Train: {X_train.shape[0]} | Test: {X_test.shape[0]}")

    # ── Bangun Model ──────────────────────────────────────────
    model = build_model(input_length=WINDOW_SIZE)
    model.summary()

    model.compile(
        optimizer=optimizers.Adam(learning_rate=LEARNING_RATE),
        loss='binary_crossentropy',
        metrics=['accuracy'],
    )

    # ── Callbacks ─────────────────────────────────────────────
    model_path = os.path.join(MODEL_DIR, "pbeds_model.keras")
    cb_list = [
        callbacks.EarlyStopping(
            monitor='val_loss', patience=10, restore_best_weights=True,
            verbose=1
        ),
        callbacks.ReduceLROnPlateau(
            monitor='val_loss', factor=0.5, patience=5,
            min_lr=1e-6, verbose=1
        ),
        callbacks.ModelCheckpoint(
            model_path, monitor='val_accuracy',
            save_best_only=True, verbose=0
        ),
    ]

    # ── Training ──────────────────────────────────────────────
    print(f"\n🚀 Mulai training ({EPOCHS} epoch maks, batch={BATCH_SIZE})...")
    history = model.fit(
        X_train, y_train,
        epochs=EPOCHS,
        batch_size=BATCH_SIZE,
        validation_split=VAL_SPLIT,
        callbacks=cb_list,
        verbose=1,
    )

    # ── Evaluasi ──────────────────────────────────────────────
    print("\n📊 Evaluasi pada Test Set...")
    y_pred_proba = model.predict(X_test, verbose=0).flatten()
    y_pred = (y_pred_proba >= 0.5).astype(int)

    f1 = f1_score(y_test, y_pred)
    print("\n" + "=" * 60)
    print(f"  F1-Score: {f1:.4f}  {'✅ TARGET TERCAPAI!' if f1 >= 0.88 else '⚠️ Belum capai target 0.88'}")
    print("=" * 60)
    print("\nClassification Report:")
    print(classification_report(y_test, y_pred, target_names=CLASS_NAMES))

    # Confusion Matrix
    cm = confusion_matrix(y_test, y_pred)
    fig, ax = plt.subplots(figsize=(6, 5))
    disp = ConfusionMatrixDisplay(confusion_matrix=cm, display_labels=CLASS_NAMES)
    disp.plot(ax=ax, colorbar=False, cmap='Greens')
    ax.set_title(f"Confusion Matrix (F1={f1:.3f})", fontweight='bold')
    cm_path = os.path.join(MODEL_DIR, "confusion_matrix.png")
    plt.savefig(cm_path, dpi=150, bbox_inches='tight')
    plt.show()

    # ── Plot History ──────────────────────────────────────────
    plot_history(history, os.path.join(MODEL_DIR, "training_history.png"))

    # ── Simpan model ──────────────────────────────────────────
    print(f"\n💾 Model disimpan: {model_path}")
    print("\n✅ Script 3 selesai! Lanjutkan ke: python 4_inference_demo.py")


if __name__ == "__main__":
    main()
