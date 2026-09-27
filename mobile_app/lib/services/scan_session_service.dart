import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════
//  PBEDS (Plant Bioelectric Early Detection System)
//  Scan Session Service — Simpan riwayat scan per batang
// ═══════════════════════════════════════════════════════════════

class ScanResult {
  final String id;            // UUID unik per sesi scan
  final String idTanaman;     // Contoh: "Kopi-A01"
  final DateTime waktuScan;
  final String status;        // NORMAL | STRES | KRITIS
  final double voltaseMean;
  final double baselineMean;
  final double baselineStd;
  final double zScore;
  final double confidence;    // 0.0 - 1.0
  final String kondisiCuaca;  // cerah | mendung | hujan_ringan | hujan_deras
  final String rekomendasiSiram;
  final String rekomendasiPupuk;
  final String dosis;
  final int durasiScanDetik;

  const ScanResult({
    required this.id,
    required this.idTanaman,
    required this.waktuScan,
    required this.status,
    required this.voltaseMean,
    required this.baselineMean,
    required this.baselineStd,
    required this.zScore,
    required this.confidence,
    required this.kondisiCuaca,
    required this.rekomendasiSiram,
    required this.rekomendasiPupuk,
    required this.dosis,
    required this.durasiScanDetik,
  });

  Map<String, dynamic> toJson() => {
    'id'               : id,
    'id_tanaman'       : idTanaman,
    'waktu_scan'       : waktuScan.toIso8601String(),
    'status'           : status,
    'voltase_mean'     : voltaseMean,
    'baseline_mean'    : baselineMean,
    'baseline_std'     : baselineStd,
    'z_score'          : zScore,
    'confidence'       : confidence,
    'kondisi_cuaca'    : kondisiCuaca,
    'rekomendasi_siram': rekomendasiSiram,
    'rekomendasi_pupuk': rekomendasiPupuk,
    'dosis'            : dosis,
    'durasi_scan_detik': durasiScanDetik,
  };

  factory ScanResult.fromJson(Map<String, dynamic> json) => ScanResult(
    id               : json['id']                as String,
    idTanaman        : json['id_tanaman']        as String,
    waktuScan        : DateTime.parse(json['waktu_scan'] as String),
    status           : json['status']            as String,
    voltaseMean      : (json['voltase_mean']     as num).toDouble(),
    baselineMean     : (json['baseline_mean']    as num).toDouble(),
    baselineStd      : (json['baseline_std']     as num).toDouble(),
    zScore           : (json['z_score']          as num).toDouble(),
    confidence       : (json['confidence']       as num).toDouble(),
    kondisiCuaca     : json['kondisi_cuaca']     as String,
    rekomendasiSiram : json['rekomendasi_siram'] as String,
    rekomendasiPupuk : json['rekomendasi_pupuk'] as String,
    dosis            : json['dosis']             as String,
    durasiScanDetik  : (json['durasi_scan_detik'] as num).toInt(),
  );

  /// Confidence berbasis Z-score
  static double hitungConfidence(double zScore, String status) {
    final absZ = zScore.abs();
    if (status == 'NORMAL')  return (1.0 - (absZ / 1.5)).clamp(0.5, 1.0);
    if (status == 'STRES')   return ((absZ - 1.5) / 1.5).clamp(0.5, 0.95);
    if (status == 'KRITIS')  return ((absZ - 3.0) / 3.0 + 0.8).clamp(0.8, 0.99);
    return 0.5;
  }
}

// ═══════════════════════════════════════════════════════════════
//  ScanSessionService — CRUD ke SharedPreferences
// ═══════════════════════════════════════════════════════════════
class ScanSessionService {
  static const String _storageKey = 'pbeds_scan_history';

  /// Simpan hasil scan baru
  static Future<void> simpan(ScanResult result) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await ambilSemua();
    all.insert(0, result); // terbaru di atas

    // Batasi 500 riwayat
    final limited = all.take(500).toList();
    final jsonList = limited.map((r) => jsonEncode(r.toJson())).toList();
    await prefs.setStringList(_storageKey, jsonList);
  }

  /// Ambil semua riwayat scan
  static Future<List<ScanResult>> ambilSemua() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_storageKey) ?? [];
    return jsonList
        .map((s) => ScanResult.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  /// Filter berdasarkan status
  static Future<List<ScanResult>> filterStatus(String status) async {
    final all = await ambilSemua();
    if (status == 'SEMUA') return all;
    return all.where((r) => r.status == status).toList();
  }

  /// Hapus semua riwayat
  static Future<void> hapusSemua() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  /// Hapus satu entry berdasarkan ID
  static Future<void> hapusSatu(String id) async {
    final all = await ambilSemua();
    all.removeWhere((r) => r.id == id);
    final prefs = await SharedPreferences.getInstance();
    final jsonList = all.map((r) => jsonEncode(r.toJson())).toList();
    await prefs.setStringList(_storageKey, jsonList);
  }

  /// Statistik ringkas
  static Future<Map<String, int>> statistik() async {
    final all = await ambilSemua();
    return {
      'total' : all.length,
      'normal': all.where((r) => r.status == 'NORMAL').length,
      'stres' : all.where((r) => r.status == 'STRES').length,
      'kritis': all.where((r) => r.status == 'KRITIS').length,
    };
  }
}
