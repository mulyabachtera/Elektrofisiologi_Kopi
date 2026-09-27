"""
============================================================
PBEDS (Plant Bioelectric Early Detection System) Backend — Konfigurasi Utama
============================================================
Isi file .env di folder backend/ dengan nilai yang sesuai.
Contoh:
  FIREBASE_CREDENTIALS_PATH=./firebase_credentials.json
  WA_GATEWAY_URL=http://localhost:3001
  WA_TARGET_NUMBER=6281234567890
  ALERT_COOLDOWN_MINUTES=10
============================================================
"""

import os
from dotenv import load_dotenv

load_dotenv()

# ── Firebase ─────────────────────────────────────────────────
FIREBASE_CREDENTIALS_PATH = os.getenv(
    "FIREBASE_CREDENTIALS_PATH", "./firebase_credentials.json"
)
FIREBASE_DATABASE_URL = os.getenv(
    "FIREBASE_DATABASE_URL",
    "https://elektrofisiologi-kopi-default-rtdb.asia-southeast1.firebasedatabase.app",
)
FIREBASE_SENSOR_PATH = os.getenv("FIREBASE_SENSOR_PATH", "sensor_data/node_1")

# ── WhatsApp Gateway ──────────────────────────────────────────
WA_GATEWAY_URL = os.getenv("WA_GATEWAY_URL", "http://localhost:3001")
WA_TARGET_NUMBER = os.getenv("WA_TARGET_NUMBER", "6281234567890")  # Nomor HP petani

# ── Deteksi & Alert ───────────────────────────────────────────
ALERT_COOLDOWN_MINUTES = int(os.getenv("ALERT_COOLDOWN_MINUTES", "10"))
# Status yang memicu notifikasi (STRES dan/atau KRITIS)
ALERT_ON_STATUS = ["STRES", "KRITIS"]

# ── Model AI ─────────────────────────────────────────────────
MODEL_PATH = os.getenv(
    "MODEL_PATH",
    "../ai_simulator/model/pbeds_model.keras",
)
WINDOW_SIZE = 200   # Harus sama dengan script training
SAMPLE_RATE = 10    # Hz

# ── Server ────────────────────────────────────────────────────
SERVER_HOST = os.getenv("SERVER_HOST", "0.0.0.0")
SERVER_PORT  = int(os.getenv("SERVER_PORT", "8000"))
