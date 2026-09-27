import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';

// ═══════════════════════════════════════════════════════════════
//  Model: Data sensor lengkap dari ESP32 (v3.0 — Scan Mode)
// ═══════════════════════════════════════════════════════════════
class SensorData {
  final double voltaseMv;
  final DateTime timestamp;
  final String status;      // NORMAL | STRES | KRITIS | KALIBRASI | STANDBY
  final String faseScan;    // STANDBY | KALIBRASI | ANALISIS | SELESAI
  final double baselineMean;
  final double baselineStd;
  final double zScore;
  final int detikScan;
  final int nilaiAdc;

  const SensorData({
    required this.voltaseMv,
    required this.timestamp,
    required this.status,
    this.faseScan    = 'STANDBY',
    this.baselineMean = 0.0,
    this.baselineStd  = 0.0,
    this.zScore       = 0.0,
    this.detikScan    = 0,
    this.nilaiAdc     = 0,
  });

  factory SensorData.fromJson(Map<dynamic, dynamic> json) {
    return SensorData(
      voltaseMv    : (json['voltase']       as num?)?.toDouble() ?? 0.0,
      nilaiAdc     : (json['nilai_adc']     as num?)?.toInt()    ?? 0,
      status       : json['status']         as String?           ?? 'STANDBY',
      faseScan     : json['fase_scan']      as String?           ?? 'STANDBY',
      baselineMean : (json['baseline_mean'] as num?)?.toDouble() ?? 0.0,
      baselineStd  : (json['baseline_std']  as num?)?.toDouble() ?? 0.0,
      zScore       : (json['z_score']       as num?)?.toDouble() ?? 0.0,
      detikScan    : (json['detik_scan']    as num?)?.toInt()    ?? 0,
      timestamp    : DateTime.fromMillisecondsSinceEpoch(
                       (json['timestamp_ms'] as num?)?.toInt() ?? 0),
    );
  }

  bool get isSelesai   => faseScan == 'SELESAI';
  bool get isKalibrasi => faseScan == 'KALIBRASI';
  bool get isAnalisis  => faseScan == 'ANALISIS';
  bool get isStandby   => faseScan == 'STANDBY';

  /// Progress kalibrasi 0.0–1.0
  double get progressKalibrasi => (detikScan / 30).clamp(0.0, 1.0);

  /// Progress analisis 0.0–1.0
  double get progressAnalisis => (detikScan / 180).clamp(0.0, 1.0);
}

// ═══════════════════════════════════════════════════════════════
//  FirebaseService — Real-time RTDB + Demo Mode
// ═══════════════════════════════════════════════════════════════
class FirebaseService {
  static const String _sensorPath = 'sensor_data/node_1';

  // ── Firebase real-time stream ─────────────────────────────
  Stream<SensorData> listenToVoltageStream() {
    final ref = FirebaseDatabase.instance.ref(_sensorPath);
    return ref.onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return _emptyData();
      return SensorData.fromJson(data);
    });
  }

  // ── Kirim command scan ke Firebase (opsional) ─────────────
  Future<void> mulaiScan(String idTanaman) async {
    final ref = FirebaseDatabase.instance.ref(_sensorPath);
    await ref.update({
      'command'    : 'MULAI_SCAN',
      'id_tanaman' : idTanaman,
      'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> writeTestData(double voltase, String status) async {
    final ref = FirebaseDatabase.instance.ref(_sensorPath);
    await ref.set({
      'voltase'      : voltase,
      'status'       : status,
      'fase_scan'    : 'ANALISIS',
      'baseline_mean': 12.0,
      'baseline_std' : 0.5,
      'z_score'      : (voltase - 12.0) / 0.5,
      'detik_scan'   : 90,
      'timestamp_ms' : DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ── Demo Mode ─────────────────────────────────────────────
  final Random _random = Random();
  int _tick = 0;
  bool _isStressMode = false;
  String _faseSim = 'KALIBRASI';
  int _detikSim = 0;
  final double _baselineSim = 12.0;

  Stream<SensorData> getDemoStream() async* {
    while (true) {
      await Future.delayed(const Duration(milliseconds: 100));
      _tick++;
      _detikSim = (_tick * 100) ~/ 1000;

      // Simulasi fase: 30 detik kalibrasi → 180 detik analisis → reset
      if (_detikSim < 30) {
        _faseSim = 'KALIBRASI';
      } else if (_detikSim < 210) {
        _faseSim = 'ANALISIS';
      } else {
        _tick = 0;
        _detikSim = 0;
        _isStressMode = !_isStressMode;
        _faseSim = 'KALIBRASI';
        if (kDebugMode) {
          print('[DemoMode] Reset scan. Stress: $_isStressMode');
        }
      }

      final voltage = _generateVoltage();
      final zScore  = (voltage - _baselineSim) / 0.6;
      final status  = _faseSim == 'KALIBRASI'
          ? 'KALIBRASI'
          : _determineStatusZScore(zScore);

      yield SensorData(
        voltaseMv    : voltage,
        timestamp    : DateTime.now(),
        status       : status,
        faseScan     : _faseSim,
        baselineMean : _baselineSim,
        baselineStd  : 0.6,
        zScore       : double.parse(zScore.toStringAsFixed(3)),
        detikScan    : _faseSim == 'KALIBRASI' ? _detikSim : _detikSim - 30,
        nilaiAdc     : (voltage / 0.000125).toInt(),
      );
    }
  }

  double _generateVoltage() {
    double noise = (_random.nextDouble() - 0.5) * 0.8;
    double wave  = sin(_tick * 0.08) * 1.5;
    if (_isStressMode && _faseSim == 'ANALISIS') {
      double stressTrend = -0.015 * ((_tick - 300) % 1800);
      double spike = _random.nextDouble() < 0.05
          ? (_random.nextDouble() * 6.0 - 3.0) : 0.0;
      return _baselineSim + wave + noise * 2 + stressTrend + spike;
    }
    return _baselineSim + wave + noise;
  }

  String _determineStatusZScore(double z) {
    final absZ = z.abs();
    if (absZ >= 3.0) return 'KRITIS';
    if (absZ >= 1.5) return 'STRES';
    return 'NORMAL';
  }

  SensorData _emptyData() {
    return SensorData(
      voltaseMv : 0.0,
      timestamp : DateTime.now(),
      status    : 'TIDAK TERHUBUNG',
      faseScan  : 'STANDBY',
    );
  }
}
