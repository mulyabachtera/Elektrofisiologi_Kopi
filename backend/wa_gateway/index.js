/**
 * ============================================================
 * PBEDS (Plant Bioelectric Early Detection System) - WhatsApp Gateway Server
 * Menggunakan Baileys (unofficial WA Web client)
 * ============================================================
 * Cara pakai:
 *   npm install
 *   node index.js
 *   → Scan QR code dengan WhatsApp di HP Anda
 *   → Server siap di http://localhost:3001
 *
 * API Endpoint:
 *   POST /send
 *   Body: { "number": "6281234567890", "message": "Halo!" }
 * ============================================================
 */

import makeWASocket, {
  DisconnectReason,
  useMultiFileAuthState,
} from "@whiskeysockets/baileys";
import express from "express";
import qrcode from "qrcode-terminal";
import pino from "pino";
import { Boom } from "@hapi/boom";

const PORT = 3001;
const AUTH_FOLDER = "./auth_session"; // Folder menyimpan session WA

// ── State Global ──────────────────────────────────────────────
let sock = null;
let isConnected = false;
let messageQueue = []; // Antrian pesan saat belum terhubung

// ── Express Server ────────────────────────────────────────────
const app = express();
app.use(express.json());

/**
 * GET / — Cek status gateway
 */
app.get("/", (req, res) => {
  res.json({
    service: "PBEDS (Plant Bioelectric Early Detection System) WhatsApp Gateway",
    status: isConnected ? "CONNECTED" : "DISCONNECTED",
    message: isConnected
      ? "Siap mengirim pesan WhatsApp"
      : "Belum terhubung - scan QR code dulu",
  });
});

/**
 * POST /send — Kirim pesan WhatsApp
 * Body: { "number": "6281234567890", "message": "Teks pesan" }
 */
app.post("/send", async (req, res) => {
  const { number, message } = req.body;

  if (!number || !message) {
    return res.status(400).json({ success: false, error: "number dan message wajib diisi" });
  }

  if (!isConnected || !sock) {
    // Masukkan ke antrian jika belum connect
    messageQueue.push({ number, message });
    return res.status(503).json({
      success: false,
      error: "Gateway belum terhubung ke WhatsApp. Pesan masuk antrian.",
      queued: true,
    });
  }

  try {
    // Format nomor: harus diakhiri @s.whatsapp.net
    const jid = number.includes("@") ? number : `${number}@s.whatsapp.net`;
    await sock.sendMessage(jid, { text: message });

    console.log(`✅ Pesan terkirim ke ${number}`);
    res.json({ success: true, to: number, message_length: message.length });
  } catch (err) {
    console.error("❌ Gagal kirim pesan:", err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── Fungsi Koneksi Baileys ─────────────────────────────────────
async function connectToWhatsApp() {
  const { state, saveCreds } = await useMultiFileAuthState(AUTH_FOLDER);

  sock = makeWASocket({
    auth: state,
    // Matikan log verbose agar terminal tidak penuh
    logger: pino({ level: "silent" }),
    printQRInTerminal: false, // Kita handle QR sendiri
  });

  // ── Event: QR Code (scan dengan HP) ───────────────────────
  sock.ev.on("connection.update", async (update) => {
    const { connection, lastDisconnect, qr } = update;

    if (qr) {
      console.log("\n╔══════════════════════════════════════╗");
      console.log("║  SCAN QR CODE INI DENGAN WHATSAPP!   ║");
      console.log("╚══════════════════════════════════════╝");
      console.log("Buka WhatsApp → Perangkat Tertaut → Tautkan Perangkat\n");
      qrcode.generate(qr, { small: true });
    }

    if (connection === "close") {
      isConnected = false;
      const shouldReconnect =
        (lastDisconnect?.error instanceof Boom)
          ? lastDisconnect.error.output?.statusCode !== DisconnectReason.loggedOut
          : true;

      console.log("⚠️  Koneksi terputus. Reconnect:", shouldReconnect);
      if (shouldReconnect) {
        setTimeout(connectToWhatsApp, 3000);
      } else {
        console.log("❌ Logged out. Hapus folder auth_session/ lalu restart.");
      }
    }

    if (connection === "open") {
      isConnected = true;
      console.log("\n✅ WhatsApp terhubung!");
      console.log(`📱 Nomor: ${sock.user?.id}`);
      console.log(`🌐 Gateway aktif di http://localhost:${PORT}\n`);

      // Kirim antrian pesan yang tertunda
      if (messageQueue.length > 0) {
        console.log(`📤 Mengirim ${messageQueue.length} pesan tertunda...`);
        for (const item of messageQueue) {
          const jid = `${item.number}@s.whatsapp.net`;
          await sock.sendMessage(jid, { text: item.message });
        }
        messageQueue = [];
      }
    }
  });

  // ── Event: Simpan kredensial session ──────────────────────
  sock.ev.on("creds.update", saveCreds);
}

// ── Start ──────────────────────────────────────────────────────
console.log("╔══════════════════════════════════════╗");
console.log("║  PBEDS (Plant Bioelectric Early Detection System)       ║");
console.log("╚══════════════════════════════════════╝");

app.listen(PORT, () => {
  console.log(`\n🚀 Express server berjalan di http://localhost:${PORT}`);
  console.log("⏳ Menghubungkan ke WhatsApp...\n");
});

connectToWhatsApp();
