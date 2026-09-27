"""
============================================================
PBEDS (Plant Bioelectric Early Detection System) Backend — Firebase Listener Service
Subscribe ke Firebase RTDB dan trigger AI inference
============================================================
"""

import threading
import time
from datetime import datetime
import firebase_admin
from firebase_admin import credentials, db

from config import (FIREBASE_CREDENTIALS_PATH, FIREBASE_DATABASE_URL,
                    FIREBASE_SENSOR_PATH, ALERT_ON_STATUS)
from services.ai_service import ai_service
from services.notif_service import send_alert

# ── State Global ──────────────────────────────────────────────
_firebase_initialized = False
_listener_thread: threading.Thread = None
_latest_raw_data: dict = {}       # Data mentah dari Firebase
_latest_ai_result: dict = {}      # Hasil inference AI terbaru
_history: list = []               # Riwayat 100 data terakhir
MAX_HISTORY = 100


def _init_firebase():
    """Inisialisasi Firebase Admin SDK (sekali saja)."""
    global _firebase_initialized
    if _firebase_initialized:
        return

    try:
        cred = credentials.Certificate(FIREBASE_CREDENTIALS_PATH)
        firebase_admin.initialize_app(cred, {"databaseURL": FIREBASE_DATABASE_URL})
        _firebase_initialized = True
        print(f"[Firebase] ✅ Terhubung ke {FIREBASE_DATABASE_URL}")
    except FileNotFoundError:
        print(f"[Firebase] ❌ File credentials tidak ditemukan: {FIREBASE_CREDENTIALS_PATH}")
        print("[Firebase]    Download dari Firebase Console → Project Settings → Service Accounts")
    except Exception as e:
        print(f"[Firebase] ❌ Gagal inisialisasi: {e}")


def _on_data_change(event):
    """Callback dipanggil setiap ada perubahan data di Firebase."""
    global _latest_raw_data, _latest_ai_result, _history

    data = event.data
    if not data or not isinstance(data, dict):
        return

    _latest_raw_data = data
    voltase = float(data.get("voltase", 0.0))
    timestamp_ms = int(data.get("timestamp_ms", time.time() * 1000))

    # Jalankan AI inference
    ai_result = ai_service.predict(voltase)
    ai_result["timestamp"] = datetime.fromtimestamp(
        timestamp_ms / 1000
    ).strftime("%Y-%m-%d %H:%M:%S")
    ai_result["voltase_raw"] = voltase

    _latest_ai_result = ai_result

    # Simpan ke history
    _history.append(ai_result.copy())
    if len(_history) > MAX_HISTORY:
        _history.pop(0)

    # Log ke terminal
    status = ai_result["status"]
    conf   = ai_result["confidence"]
    print(
        f"[Data] {ai_result['timestamp']} | "
        f"Voltase: {voltase:.3f} mV | "
        f"AI: {status} ({conf*100:.1f}%)"
    )

    # Kirim notifikasi WhatsApp jika perlu
    if status in ALERT_ON_STATUS:
        send_alert(status, voltase, conf)


def _listener_loop():
    """Loop yang mendengarkan Firebase secara terus-menerus."""
    _init_firebase()
    if not _firebase_initialized:
        print("[Firebase] ❌ Listener tidak bisa dimulai.")
        return

    ref = db.reference(FIREBASE_SENSOR_PATH)
    print(f"[Firebase] 👂 Mendengarkan: /{FIREBASE_SENSOR_PATH}")

    # Subscribe ke perubahan data
    ref.listen(_on_data_change)


def start_listener():
    """Mulai Firebase listener di background thread."""
    global _listener_thread
    if _listener_thread and _listener_thread.is_alive():
        print("[Firebase] Listener sudah berjalan.")
        return

    _listener_thread = threading.Thread(
        target=_listener_loop,
        daemon=True,
        name="FirebaseListener"
    )
    _listener_thread.start()
    print("[Firebase] 🚀 Listener dimulai di background thread.")


def get_latest_data() -> dict:
    """Ambil data + hasil AI terbaru."""
    return {
        "raw_firebase": _latest_raw_data,
        "ai_result"   : _latest_ai_result,
    }


def get_history() -> list:
    """Ambil riwayat data terakhir."""
    return _history.copy()
