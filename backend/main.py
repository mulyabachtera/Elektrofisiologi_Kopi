"""
============================================================
PBEDS (Plant Bioelectric Early Detection System) Backend — FastAPI Server Utama
============================================================
Menjalankan:
  uvicorn main:app --reload --host 0.0.0.0 --port 8000

Dokumentasi API otomatis:
  http://localhost:8000/docs
============================================================
"""

from fastapi import FastAPI, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from datetime import datetime
import uvicorn

from config import SERVER_HOST, SERVER_PORT, WA_TARGET_NUMBER
from services.firebase_listener import start_listener, get_latest_data, get_history
from services.notif_service import send_test_message, send_alert
from services.ai_service import ai_service

# ── Inisialisasi FastAPI ──────────────────────────────────────
app = FastAPI(
    title="PBEDS (Plant Bioelectric Early Detection System) API",
    description=(
        "Plant Bioelectric Early Detection System — "
        "Server AI untuk monitoring elektrofisiologi tanaman kopi"
    ),
    version="1.0.0",
)

# Izinkan akses dari Flutter app / browser mana saja (CORS)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Event: Startup ────────────────────────────────────────────
@app.on_event("startup")
async def on_startup():
    print("\n╔══════════════════════════════════════╗")
    print("║  PBEDS (Plant Bioelectric Early Detection System)  ║")
    print("║  AI + Firebase + WhatsApp Gateway     ║")
    print("╚══════════════════════════════════════╝\n")
    # Mulai dengarkan Firebase di background
    start_listener()


# ── Endpoints ─────────────────────────────────────────────────

@app.get("/", tags=["Status"])
def root():
    """Status server PBEDS (Plant Bioelectric Early Detection System)."""
    return {
        "service" : "PBEDS (Plant Bioelectric Early Detection System) API",
        "version" : "1.0.0",
        "status"  : "running",
        "waktu"   : datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "docs"    : "http://localhost:8000/docs",
    }


@app.get("/status", tags=["Data"])
def get_status():
    """Data dan status AI terbaru dari sensor ESP32."""
    data = get_latest_data()
    if not data["ai_result"]:
        return JSONResponse(
            status_code=503,
            content={
                "pesan": "Belum ada data dari sensor. "
                         "Pastikan ESP32 terhubung dan mengirim data ke Firebase."
            },
        )
    return data


@app.get("/history", tags=["Data"])
def get_history_data(limit: int = 50):
    """
    Riwayat data terakhir dari sensor.
    
    - **limit**: Jumlah data yang dikembalikan (default 50, max 100)
    """
    history = get_history()
    limit = min(limit, 100)
    return {
        "total"  : len(history),
        "limit"  : limit,
        "data"   : history[-limit:],
    }


@app.post("/test-notif", tags=["Notifikasi"])
def test_notification(nomor: str = None):
    """
    Kirim pesan WhatsApp test untuk verifikasi WA Gateway.
    
    - **nomor**: Nomor tujuan (opsional, default ke nomor di config)
    """
    result = send_test_message(nomor)
    if result.get("success"):
        return {"success": True, "pesan": "Test message terkirim!", "detail": result}
    return JSONResponse(
        status_code=500,
        content={"success": False, "error": result.get("error", "Unknown error")},
    )


@app.get("/simulate", tags=["Testing"])
def simulate_data(voltase_mv: float = 7.5):
    """
    Simulasi penerimaan data sensor untuk testing AI inference.
    
    - **voltase_mv**: Nilai voltase yang akan ditest (default 7.5 = KRITIS)
    """
    ai_result = ai_service.predict(voltase_mv)
    
    # Trigger notifikasi jika status alert
    from config import ALERT_ON_STATUS
    if ai_result["status"] in ALERT_ON_STATUS:
        send_alert(ai_result["status"], voltase_mv, ai_result["confidence"])
    
    return {
        "input_voltase_mv": voltase_mv,
        "ai_result"       : ai_result,
        "notif_triggered" : ai_result["status"] in ALERT_ON_STATUS,
    }


# ── Entry Point ───────────────────────────────────────────────
if __name__ == "__main__":
    uvicorn.run("main:app", host=SERVER_HOST, port=SERVER_PORT, reload=True)
