import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firebase_service.dart';
import '../services/recommendation_engine.dart';
import '../services/scan_session_service.dart';
import '../theme/app_colors.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with TickerProviderStateMixin {

  // ── State Scan ─────────────────────────────────────────────
  bool _scanAktif = false;
  bool _scanSelesai = false;
  String _idTanaman = '';
  KondisiCuaca _cuacaTerpilih = KondisiCuaca.cerah;

  // ── Data dari Firebase ─────────────────────────────────────
  final FirebaseService _fbService = FirebaseService();
  StreamSubscription<SensorData>? _sub;
  SensorData? _dataLive;

  // ── Hasil Scan ─────────────────────────────────────────────
  String _statusHasil = '';
  double _voltaseMean = 0.0;
  double _baselineMean = 0.0;
  double _baselineStd = 0.0;
  double _zScoreFinal = 0.0;
  List<double> _voltaseBuffer = [];
  PlantRecommendation? _rekomendasi;

  // ── Animasi ────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late AnimationController _resultCtrl;
  late Animation<double> _pulseAnim;
  late Animation<double> _resultAnim;

  // ── Input Controller ───────────────────────────────────────
  final _idController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _resultCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700),
    );
    _resultAnim = CurvedAnimation(parent: _resultCtrl, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulseCtrl.dispose();
    _resultCtrl.dispose();
    _idController.dispose();
    super.dispose();
  }

  // ── Mulai Scan ─────────────────────────────────────────────
  void _mulaiScan() {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _idTanaman    = _idController.text.trim();
      _scanAktif    = true;
      _scanSelesai  = false;
      _voltaseBuffer = [];
      _rekomendasi  = null;
    });
    HapticFeedback.mediumImpact();

    _sub = _fbService.getDemoStream().listen((data) {
      if (!mounted) return;
      setState(() => _dataLive = data);

      if (data.faseScan == 'ANALISIS') {
        _voltaseBuffer.add(data.voltaseMv);
      }

      if (data.isSelesai || data.faseScan == 'SELESAI') {
        _selesaikanScan(data);
      }
    });
  }

  // ── Selesaikan Scan ────────────────────────────────────────
  void _selesaikanScan(SensorData data) {
    _sub?.cancel();

    final mean = _voltaseBuffer.isEmpty
        ? data.voltaseMv
        : _voltaseBuffer.reduce((a, b) => a + b) / _voltaseBuffer.length;

    final rekomendasi = RecommendationEngine.generate(
      status: data.status.contains('KRITIS') || _cekStatusBuffer()  == 'KRITIS'
          ? 'KRITIS' : _cekStatusBuffer(),
      zScore: data.zScore,
      cuaca: _cuacaTerpilih,
    );

    setState(() {
      _scanAktif   = false;
      _scanSelesai = true;
      _statusHasil   = _cekStatusBuffer().isNotEmpty ? _cekStatusBuffer() : data.status;
      _voltaseMean   = double.parse(mean.toStringAsFixed(3));
      _baselineMean  = data.baselineMean;
      _baselineStd   = data.baselineStd;
      _zScoreFinal   = data.zScore;
      _rekomendasi   = rekomendasi;
    });

    _resultCtrl.forward(from: 0);
    HapticFeedback.heavyImpact();
    _simpanHasil(rekomendasi);
  }

  String _cekStatusBuffer() {
    if (_voltaseBuffer.isEmpty) return '';
    // Hitung status dominan dari buffer
    final statuses = _voltaseBuffer.map((v) {
      if (_baselineStd == 0) return 'NORMAL';
      final z = (v - _baselineMean) / (_baselineStd > 0 ? _baselineStd : 1);
      if (z.abs() >= 3.0) return 'KRITIS';
      if (z.abs() >= 1.5) return 'STRES';
      return 'NORMAL';
    }).toList();
    // Status terbanyak
    final counts = <String, int>{};
    for (final s in statuses) counts[s] = (counts[s] ?? 0) + 1;
    return counts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  Future<void> _simpanHasil(PlantRecommendation r) async {
    final confidence = ScanResult.hitungConfidence(_zScoreFinal, _statusHasil);
    final result = ScanResult(
      id               : DateTime.now().millisecondsSinceEpoch.toString(),
      idTanaman        : _idTanaman,
      waktuScan        : DateTime.now(),
      status           : _statusHasil,
      voltaseMean      : _voltaseMean,
      baselineMean     : _baselineMean,
      baselineStd      : _baselineStd,
      zScore           : _zScoreFinal,
      confidence       : confidence,
      kondisiCuaca     : _cuacaTerpilih.name,
      rekomendasiSiram : r.rekomendasiSiram,
      rekomendasiPupuk : r.rekomendasiPupuk,
      dosis            : r.dosis,
      durasiScanDetik  : 210,
    );
    await ScanSessionService.simpan(result);
  }

  void _resetScan() {
    setState(() {
      _scanSelesai = false;
      _scanAktif   = false;
      _idController.clear();
      _dataLive    = null;
      _rekomendasi = null;
    });
    _resultCtrl.reset();
  }

  // ═══════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundColor,
        elevation: 0,
        title: const Text('🔬 Scan Tanaman',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          if (!_scanAktif && !_scanSelesai) _buildFormPanel(),
          if (_scanAktif)                   _buildScanningPanel(),
          if (_scanSelesai)                 _buildHasilPanel(),
        ]),
      ),
    );
  }

  // ── Panel Input ────────────────────────────────────────────
  Widget _buildFormPanel() {
    return Form(
      key: _formKey,
      child: Column(children: [
        // Ilustrasi
        ScaleTransition(
          scale: _pulseAnim,
          child: Container(
            width: 140, height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppColors.primaryGreen.withOpacity(0.3),
                AppColors.primaryGreen.withOpacity(0.05),
              ]),
            ),
            child: const Icon(Icons.sensors_rounded,
              size: 72, color: AppColors.primaryGreen),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Scan Bioelektrik Tanaman',
          style: TextStyle(color: Colors.white, fontSize: 18,
            fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Tancapkan elektroda ke batang, lalu mulai scan',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
          textAlign: TextAlign.center),
        const SizedBox(height: 24),

        // ID Tanaman
        _buildInputCard(),
        const SizedBox(height: 16),

        // Pilih Cuaca
        _buildCuacaSelector(),
        const SizedBox(height: 24),

        // Tombol Mulai
        SizedBox(
          width: double.infinity, height: 54,
          child: ElevatedButton.icon(
            onPressed: _mulaiScan,
            icon: const Icon(Icons.play_arrow_rounded, size: 28),
            label: const Text('MULAI SCAN',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                letterSpacing: 1.2)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('⏱ Durasi: ~3.5 menit per tanaman',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
      ]),
    );
  }

  Widget _buildInputCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ID Tanaman', style: TextStyle(
          color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextFormField(
          controller: _idController,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Contoh: Kopi-A01, Blok-B-No5',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
            prefixIcon: const Icon(Icons.local_florist_rounded,
              color: AppColors.primaryGreen),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Masukkan ID tanaman' : null,
        ),
      ]),
    );
  }

  Widget _buildCuacaSelector() {
    final options = [
      (KondisiCuaca.cerah,       '☀️', 'Cerah'),
      (KondisiCuaca.mendung,     '🌤', 'Mendung'),
      (KondisiCuaca.hujanRingan, '🌧', 'Hujan Ringan'),
      (KondisiCuaca.hujanDeras,  '⛈', 'Hujan Deras'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Kondisi Cuaca Sekarang', style: TextStyle(
          color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: options.map((o) {
          final selected = _cuacaTerpilih == o.$1;
          return GestureDetector(
            onTap: () => setState(() => _cuacaTerpilih = o.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primaryGreen.withOpacity(0.25)
                    : Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: selected ? AppColors.primaryGreen : Colors.transparent,
                  width: 1.5),
              ),
              child: Text('${o.$2} ${o.$3}',
                style: TextStyle(
                  color: selected ? AppColors.primaryGreen : Colors.white70,
                  fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          );
        }).toList()),
      ]),
    );
  }

  // ── Panel Scanning ─────────────────────────────────────────
  Widget _buildScanningPanel() {
    final data = _dataLive;
    final fase = data?.faseScan ?? 'KALIBRASI';
    final progress = fase == 'KALIBRASI'
        ? (data?.progressKalibrasi ?? 0.0)
        : (data?.progressAnalisis ?? 0.0);
    final detik = data?.detikScan ?? 0;
    final totalDetik = fase == 'KALIBRASI' ? 30 : 180;
    final sisaDetik = (totalDetik - detik).clamp(0, totalDetik);

    return Column(children: [
      const SizedBox(height: 16),
      // Animasi pulsing
      ScaleTransition(
        scale: _pulseAnim,
        child: Container(
          width: 120, height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _faseColor(fase).withOpacity(0.15),
            border: Border.all(color: _faseColor(fase), width: 2),
          ),
          child: Icon(_faseIcon(fase), size: 56, color: _faseColor(fase)),
        ),
      ),
      const SizedBox(height: 16),
      Text(_faseLabel(fase),
        style: TextStyle(color: _faseColor(fase),
          fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text('ID: $_idTanaman',
        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
      const SizedBox(height: 24),

      // Progress bar
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          // Stepper fase
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _buildFaseStep('Kalibrasi', fase != 'KALIBRASI'),
            _buildFaseLine(),
            _buildFaseStep('Analisis', fase == 'SELESAI'),
            _buildFaseLine(),
            _buildFaseStep('Selesai', false),
          ]),
          const SizedBox(height: 16),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(_faseColor(fase)),
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${(progress * 100).toInt()}%',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text('Sisa: ${_formatDetik(sisaDetik)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ]),
      ),
      const SizedBox(height: 16),

      // Data live
      if (data != null) Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildLiveMetric('Voltase', '${data.voltaseMv.toStringAsFixed(2)} mV',
              Icons.bolt_rounded),
            _buildLiveMetric('Z-Score', data.zScore.toStringAsFixed(2),
              Icons.analytics_rounded),
            _buildLiveMetric('Baseline', '${data.baselineMean.toStringAsFixed(2)} mV',
              Icons.straighten_rounded),
          ],
        ),
      ),
      const SizedBox(height: 24),
      OutlinedButton(
        onPressed: () { _sub?.cancel(); _resetScan(); },
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white54,
          side: const BorderSide(color: Colors.white24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: const Text('Batalkan Scan'),
      ),
    ]);
  }

  // ── Panel Hasil ────────────────────────────────────────────
  Widget _buildHasilPanel() {
    final r = _rekomendasi;
    if (r == null) return const SizedBox();
    final confidence = ScanResult.hitungConfidence(_zScoreFinal, _statusHasil);

    return ScaleTransition(
      scale: _resultAnim,
      child: Column(children: [
        // Status card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                r.warnaPrioritas.withOpacity(0.3),
                r.warnaPrioritas.withOpacity(0.1),
              ],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: r.warnaPrioritas.withOpacity(0.5)),
          ),
          child: Column(children: [
            Icon(r.iconPrioritas, size: 48, color: r.warnaPrioritas),
            const SizedBox(height: 8),
            Text(_statusHasil,
              style: TextStyle(color: r.warnaPrioritas,
                fontSize: 28, fontWeight: FontWeight.bold)),
            Text('ID: $_idTanaman',
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _buildHasilMetric('Voltase Rata2',
                '${_voltaseMean.toStringAsFixed(2)} mV'),
              _buildHasilMetric('Baseline',
                '${_baselineMean.toStringAsFixed(2)} mV'),
              _buildHasilMetric('Z-Score', _zScoreFinal.toStringAsFixed(2)),
              _buildHasilMetric('Confidence',
                '${(confidence * 100).toInt()}%'),
            ]),
          ]),
        ),
        const SizedBox(height: 16),

        // Rekomendasi Siram
        _buildRekomendasiCard(
          judul: '💧 Rekomendasi Penyiraman',
          isi: r.rekomendasiSiram,
          sub: r.urgensiSiram,
          subColor: r.warnaPrioritas,
        ),
        const SizedBox(height: 12),

        // Rekomendasi Pupuk
        _buildRekomendasiCard(
          judul: '🌱 Rekomendasi Pupuk',
          isi: r.rekomendasiPupuk,
          sub: r.dosis,
          subColor: Colors.lightGreen,
          extra: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              _infoRow('Cara', r.caraPemakaian),
              _infoRow('Waktu Terbaik', r.waktuTerbaik),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Peringatan
        if (r.peringatan.isNotEmpty && r.peringatan != '-')
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: r.warnaPrioritas.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: r.warnaPrioritas.withOpacity(0.3)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded,
                color: r.warnaPrioritas, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(r.peringatan,
                style: TextStyle(color: Colors.white.withOpacity(0.8),
                  fontSize: 12, height: 1.4))),
            ]),
          ),
        const SizedBox(height: 24),

        // Tombol aksi
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _resetScan,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Scan Berikutnya'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _bagikanHasil(),
              icon: const Icon(Icons.share_rounded),
              label: const Text('Bagikan'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 24),
      ]),
    );
  }

  // ── Helper Widgets ─────────────────────────────────────────
  Widget _buildFaseStep(String label, bool done) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? AppColors.primaryGreen : Colors.white24,
        ),
        child: done
          ? const Icon(Icons.check, size: 12, color: Colors.white)
          : null,
      ),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
    ]);
  }

  Widget _buildFaseLine() => Container(
    width: 40, height: 2, margin: const EdgeInsets.only(bottom: 16),
    color: Colors.white12,
  );

  Widget _buildLiveMetric(String label, String value, IconData icon) =>
    Column(children: [
      Icon(icon, color: AppColors.primaryGreen, size: 20),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(
        color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
    ]);

  Widget _buildHasilMetric(String label, String value) =>
    Column(children: [
      Text(value, style: const TextStyle(
        color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
    ]);

  Widget _buildRekomendasiCard({
    required String judul,
    required String isi,
    required String sub,
    required Color subColor,
    Widget? extra,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.07),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withOpacity(0.1)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(judul, style: const TextStyle(
        color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text(isi, style: const TextStyle(
        color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
      if (sub.isNotEmpty && sub != '-') ...[
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: subColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(sub, style: TextStyle(
            color: subColor, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      ],
      if (extra != null) extra,
    ]),
  );

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: RichText(text: TextSpan(children: [
      TextSpan(text: '$label: ',
        style: const TextStyle(color: Colors.white54, fontSize: 11)),
      TextSpan(text: value,
        style: const TextStyle(color: Colors.white70, fontSize: 11)),
    ])),
  );

  void _bagikanHasil() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fitur share akan segera hadir!')));
  }

  Color _faseColor(String fase) {
    switch (fase) {
      case 'KALIBRASI': return Colors.blue;
      case 'ANALISIS':  return AppColors.primaryGreen;
      case 'SELESAI':   return Colors.amber;
      default:          return Colors.white54;
    }
  }

  IconData _faseIcon(String fase) {
    switch (fase) {
      case 'KALIBRASI': return Icons.tune_rounded;
      case 'ANALISIS':  return Icons.psychology_rounded;
      default:          return Icons.hourglass_top_rounded;
    }
  }

  String _faseLabel(String fase) {
    switch (fase) {
      case 'KALIBRASI': return 'Kalibrasi Baseline...';
      case 'ANALISIS':  return 'Analisis AI Berjalan...';
      default:          return 'Memulai...';
    }
  }

  String _formatDetik(int detik) {
    final m = detik ~/ 60;
    final s = detik % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
