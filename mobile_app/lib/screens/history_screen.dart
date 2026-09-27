import 'package:flutter/material.dart';
import '../services/scan_session_service.dart';
import '../theme/app_colors.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<ScanResult> _results = [];
  String _filterStatus = 'SEMUA';
  bool _loading = true;
  Map<String, int> _statistik = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final results = await ScanSessionService.filterStatus(_filterStatus);
    final stats   = await ScanSessionService.statistik();
    setState(() {
      _results   = results;
      _statistik = stats;
      _loading   = false;
    });
  }

  Future<void> _hapusSemua() async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A2D1E),
        title: const Text('Hapus Semua Riwayat?',
          style: TextStyle(color: Colors.white)),
        content: const Text('Data scan yang tersimpan akan dihapus permanen.',
          style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (konfirmasi == true) {
      await ScanSessionService.hapusSemua();
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundColor,
        elevation: 0,
        title: const Text('📋 Riwayat Scan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          if (_results.isNotEmpty)
            IconButton(
              onPressed: _hapusSemua,
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54),
              tooltip: 'Hapus semua',
            ),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(
            color: AppColors.primaryGreen))
        : RefreshIndicator(
            onRefresh: _loadData,
            color: AppColors.primaryGreen,
            child: CustomScrollView(slivers: [
              SliverToBoxAdapter(child: _buildStatistikRow()),
              SliverToBoxAdapter(child: _buildFilterBar()),
              _results.isEmpty
                ? SliverFillRemaining(child: _buildEmptyState())
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _buildScanCard(_results[i]),
                      childCount: _results.length,
                    ),
                  ),
            ]),
          ),
    );
  }

  // ── Statistik ──────────────────────────────────────────────
  Widget _buildStatistikRow() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Total', '${_statistik['total'] ?? 0}', Colors.white),
          _buildDivider(),
          _buildStatItem('Normal', '${_statistik['normal'] ?? 0}',
            const Color(0xFF4CAF50)),
          _buildDivider(),
          _buildStatItem('Stres', '${_statistik['stres'] ?? 0}',
            const Color(0xFFF57C00)),
          _buildDivider(),
          _buildStatItem('Kritis', '${_statistik['kritis'] ?? 0}',
            const Color(0xFFD32F2F)),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) =>
    Column(children: [
      Text(value, style: TextStyle(
        color: color, fontSize: 22, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
    ]);

  Widget _buildDivider() => Container(
    width: 1, height: 36, color: Colors.white12);

  // ── Filter Bar ─────────────────────────────────────────────
  Widget _buildFilterBar() {
    final filters = ['SEMUA', 'NORMAL', 'STRES', 'KRITIS'];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: filters.map((f) {
          final selected = _filterStatus == f;
          return GestureDetector(
            onTap: () {
              setState(() => _filterStatus = f);
              _loadData();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                  ? _filterColor(f).withOpacity(0.25)
                  : Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? _filterColor(f) : Colors.transparent),
              ),
              child: Text(f,
                style: TextStyle(
                  color: selected ? _filterColor(f) : Colors.white54,
                  fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Scan Card ──────────────────────────────────────────────
  Widget _buildScanCard(ScanResult r) {
    final statusColor = _statusColor(r.status);
    final cuacaEmoji  = _cuacaEmoji(r.kondisiCuaca);

    return Dismissible(
      key: Key(r.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.red),
      ),
      confirmDismiss: (_) async {
        await ScanSessionService.hapusSatu(r.id);
        _loadData();
        return false; // handle manual
      },
      child: GestureDetector(
        onTap: () => _showDetail(r),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: statusColor.withOpacity(0.25)),
          ),
          child: Row(children: [
            // Status badge
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor.withOpacity(0.15),
              ),
              child: Icon(_statusIcon(r.status), color: statusColor, size: 24),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(r.idTanaman, style: const TextStyle(
                  color: Colors.white, fontSize: 15,
                  fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                Text(cuacaEmoji, style: const TextStyle(fontSize: 14)),
              ]),
              const SizedBox(height: 2),
              Text(_formatWaktu(r.waktuScan),
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 6),
              Text(r.rekomendasiSiram,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            // Status chip
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(r.status,
                  style: TextStyle(color: statusColor,
                    fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 4),
              Text('${(r.confidence * 100).toInt()}%',
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ]),
          ]),
        ),
      ),
    );
  }

  // ── Detail Bottom Sheet ────────────────────────────────────
  void _showDetail(ScanResult r) {
    final statusColor = _statusColor(r.status);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2D1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 20),
            Row(children: [
              Text(r.idTanaman, style: const TextStyle(
                color: Colors.white, fontSize: 22,
                fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12)),
                child: Text(r.status, style: TextStyle(
                  color: statusColor, fontWeight: FontWeight.bold)),
              ),
            ]),
            Text(_formatWaktu(r.waktuScan),
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 20),

            _detailRow('Voltase Rata-rata', '${r.voltaseMean.toStringAsFixed(3)} mV'),
            _detailRow('Baseline Mean',     '${r.baselineMean.toStringAsFixed(3)} mV'),
            _detailRow('Baseline Std',      '${r.baselineStd.toStringAsFixed(3)} mV'),
            _detailRow('Z-Score',           r.zScore.toStringAsFixed(3)),
            _detailRow('Confidence',        '${(r.confidence * 100).toInt()}%'),
            _detailRow('Durasi Scan',       '${r.durasiScanDetik} detik'),
            _detailRow('Cuaca',             _cuacaLabel(r.kondisiCuaca)),
            const Divider(color: Colors.white12, height: 32),
            _detailSection('💧 Rekomendasi Siram', r.rekomendasiSiram),
            const SizedBox(height: 12),
            _detailSection('🌱 Rekomendasi Pupuk', r.rekomendasiPupuk),
            const SizedBox(height: 4),
            Text('Dosis: ${r.dosis}',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        Text(value,  style: const TextStyle(
          color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    ),
  );

  Widget _detailSection(String title, String content) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(
      color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
    const SizedBox(height: 4),
    Text(content, style: const TextStyle(
      color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
  ]);

  Widget _buildEmptyState() => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.history_rounded, size: 72, color: Colors.white.withOpacity(0.2)),
    const SizedBox(height: 16),
    const Text('Belum ada riwayat scan',
      style: TextStyle(color: Colors.white54, fontSize: 16)),
    const SizedBox(height: 8),
    Text('Lakukan scan tanaman untuk mulai menyimpan riwayat',
      style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
      textAlign: TextAlign.center),
  ]));

  // ── Helpers ────────────────────────────────────────────────
  Color _statusColor(String s) {
    switch (s) {
      case 'NORMAL': return const Color(0xFF4CAF50);
      case 'STRES':  return const Color(0xFFF57C00);
      case 'KRITIS': return const Color(0xFFD32F2F);
      default:       return Colors.white54;
    }
  }

  Color _filterColor(String f) {
    switch (f) {
      case 'NORMAL': return const Color(0xFF4CAF50);
      case 'STRES':  return const Color(0xFFF57C00);
      case 'KRITIS': return const Color(0xFFD32F2F);
      default:       return AppColors.primaryGreen;
    }
  }

  IconData _statusIcon(String s) {
    switch (s) {
      case 'NORMAL': return Icons.eco_rounded;
      case 'STRES':  return Icons.thermostat_rounded;
      case 'KRITIS': return Icons.warning_rounded;
      default:       return Icons.help_outline_rounded;
    }
  }

  String _cuacaEmoji(String c) {
    switch (c) {
      case 'cerah':       return '☀️';
      case 'mendung':     return '🌤';
      case 'hujanRingan': return '🌧';
      case 'hujanDeras':  return '⛈';
      default:            return '🌡';
    }
  }

  String _cuacaLabel(String c) {
    switch (c) {
      case 'cerah':       return 'Cerah ☀️';
      case 'mendung':     return 'Mendung 🌤';
      case 'hujanRingan': return 'Hujan Ringan 🌧';
      case 'hujanDeras':  return 'Hujan Deras ⛈';
      default:            return c;
    }
  }

  String _formatWaktu(DateTime dt) {
    final bulan = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agt', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${dt.day} ${bulan[dt.month]} ${dt.year} • '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')} WIB';
  }
}
