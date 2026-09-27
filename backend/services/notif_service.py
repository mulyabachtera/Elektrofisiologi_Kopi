"""
============================================================
PBEDS (Plant Bioelectric Early Detection System) Backend — Notification Service
Kirim notifikasi WhatsApp via WA Gateway (Baileys - localhost)
============================================================
"""

import requests
import time
from datetime import datetime
from config import WA_GATEWAY_URL, WA_TARGET_NUMBER, ALERT_COOLDOWN_MINUTES

# ── Cooldown tracker ──────────────────────────────────────────
_last_alert_time: dict = {}   # {status: timestamp}
_last_status: str = "NORMAL"


def _format_message(status: str, voltase: float, confidence: float) -> str:
    """Buat pesan WhatsApp yang informatif."""
    waktu  = datetime.now().strftime("%d %B %Y, %H:%M WIB")
    emoji  = {"NORMAL": "✅", "STRES": "⚠️", "KRITIS": "🚨"}.get(status, "❓")

    pesan  = f"{emoji} *PBEDS (Plant Bioelectric Early Detection System) ALERT - {status}*\n\n"
    pesan += f"🌱 *Tanaman Kopi* (node_1)\n"
    pesan += f"📊 Status    : *{status}*\n"
    pesan += f"⚡ Voltase   : {voltase:.2f} mV\n"
    pesan += f"🎯 Confidence: {confidence*100:.1f}%\n"
    pesan += f"🕐 Waktu     : {waktu}\n\n"

    if status == "KRITIS":
        pesan += "🔴 *SEGERA periksa tanaman Anda!*\n"
        pesan += "Tanaman dalam kondisi kritis — kemungkinan kekeringan atau serangan hama berat."
    elif status == "STRES":
        pesan += "🟡 *Perhatian diperlukan.*\n"
        pesan += "Tanaman menunjukkan tanda stres — periksa kondisi air dan hama."

    pesan += "\n\n_Pesan otomatis dari sistem PBEDS (Plant Bioelectric Early Detection System)_"
    return pesan


def send_alert(status: str, voltase: float, confidence: float) -> bool:
    """
    Kirim notifikasi WhatsApp jika kondisi memenuhi syarat.
    Rules:
    - Hanya kirim untuk status STRES atau KRITIS
    - Cooldown: tidak kirim lagi dalam X menit
    - Selalu kirim jika eskalasi STRES → KRITIS
    """
    global _last_status

    if status == "NORMAL":
        _last_status = "NORMAL"
        return False

    now          = time.time()
    last_time    = _last_alert_time.get(status, 0)
    cooldown_sec = ALERT_COOLDOWN_MINUTES * 60
    eskalasi     = (_last_status == "STRES" and status == "KRITIS")

    if (now - last_time < cooldown_sec) and not eskalasi:
        print(f"[Notif] ⏳ Cooldown aktif untuk {status}. Skip.")
        return False

    pesan = _format_message(status, voltase, confidence)

    try:
        response = requests.post(
            f"{WA_GATEWAY_URL}/send",
            json={"number": WA_TARGET_NUMBER, "message": pesan},
            timeout=10,
        )
        result = response.json()

        if result.get("success"):
            _last_alert_time[status] = now
            _last_status = status
            print(f"[Notif] ✅ Alert {status} terkirim ke {WA_TARGET_NUMBER}")
            return True
        else:
            print(f"[Notif] ❌ Gagal: {result.get('error')}")
            return False

    except requests.exceptions.ConnectionError:
        print("[Notif] ❌ WA Gateway tidak aktif di localhost:3001!")
        return False
    except Exception as e:
        print(f"[Notif] ❌ Error: {e}")
        return False


def send_test_message(nomor: str = None) -> dict:
    """Kirim pesan test untuk verifikasi WA Gateway."""
    target = nomor or WA_TARGET_NUMBER
    waktu  = datetime.now().strftime("%d/%m/%Y %H:%M:%S")
    pesan  = (
        "✅ *PBEDS (Plant Bioelectric Early Detection System) Test Message*\n\n"
        "WA Gateway berhasil terhubung!\n"
        "Sistem siap mengirim notifikasi kondisi tanaman kopi.\n\n"
        f"_Test: {waktu}_"
    )
    try:
        resp = requests.post(
            f"{WA_GATEWAY_URL}/send",
            json={"number": target, "message": pesan},
            timeout=10,
        )
        return resp.json()
    except Exception as e:
        return {"success": False, "error": str(e)}
