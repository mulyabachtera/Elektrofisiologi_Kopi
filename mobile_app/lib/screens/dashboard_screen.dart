import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_colors.dart';
import '../services/firebase_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  // ── Data Grafik ────────────────────────────────────────────
  final List<FlSpot> _voltagePoints = [];
  static const int _maxPoints = 100;
  int _xTick = 0;

  // ── Metrik Sensor ──────────────────────────────────────────
  double _currentVoltage = 12.0;
  double _minVoltage = double.infinity;
  double _maxVoltage = double.negativeInfinity;
  String _plantStatus = 'MENGHUBUNGKAN...';
  String _statusSubtitle = 'Memulai demo mode...';
  int _sampleCount = 0;

  // ── Service & Stream ───────────────────────────────────────
  final FirebaseService _firebaseService = FirebaseService();
  StreamSubscription<SensorData>? _dataSubscription;

  // ── Animasi ────────────────────────────────────────────────
  late AnimationController _pulseController;
  late AnimationController _cardController;
  late Animation<double> _pulseAnim;
  late Animation<double> _cardAnim;

  // ── Warna Status ───────────────────────────────────────────
  Color _statusColor = AppColors.primaryGreen;
  IconData _statusIcon = Icons.eco;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _prefillDemoData();
    _startListening();
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _cardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _cardAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _cardController, curve: Curves.easeOut),
    );

    _cardController.forward();
  }

  void _prefillDemoData() {
    final random = Random();
    for (int i = 0; i < 60; i++) {
      final v = 12.0 + sin(i * 0.1) * 1.5 + (random.nextDouble() - 0.5) * 0.5;
      _voltagePoints.add(FlSpot(i.toDouble(), v));
      _updateMinMax(v);
    }
    _xTick = 60;
  }

  void _startListening() {
    _dataSubscription = _firebaseService.getDemoStream().listen((data) {
      if (!mounted) return;
      setState(() {
        _currentVoltage = data.voltaseMv;
        _sampleCount++;

        // Tambah titik baru ke grafik
        _voltagePoints.add(FlSpot(_xTick.toDouble(), data.voltaseMv));
        if (_voltagePoints.length > _maxPoints) {
          _voltagePoints.removeAt(0);
        }
        _xTick++;

        _updateMinMax(data.voltaseMv);
        _updateStatus(data.status);
      });
    });
  }

  void _updateMinMax(double v) {
    if (v < _minVoltage) _minVoltage = v;
    if (v > _maxVoltage) _maxVoltage = v;
  }

  void _updateStatus(String status) {
    switch (status) {
      case 'KRITIS':
        _plantStatus = 'KRITIS ⚠️';
        _statusSubtitle = 'Sinyal depolarisasi ekstrem terdeteksi!';
        _statusColor = const Color(0xFFD32F2F);
        _statusIcon = Icons.warning_rounded;
        break;
      case 'STRES':
        _plantStatus = 'STRES';
        _statusSubtitle = 'Pola VP/AP abnormal — monitoring ketat';
        _statusColor = const Color(0xFFF57C00);
        _statusIcon = Icons.thermostat_rounded;
        break;
      default:
        _plantStatus = 'NORMAL';
        _statusSubtitle = 'Voltase stabil — tanaman sehat';
        _statusColor = AppColors.primaryGreen;
        _statusIcon = Icons.eco_rounded;
    }
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _pulseController.dispose();
    _cardController.dispose();
    super.dispose();
  }

  // ── Chart Y-axis range ──────────────────────────────────────
  double get _chartMinY {
    if (_voltagePoints.isEmpty) return 0;
    return (_voltagePoints.map((e) => e.y).reduce(min) - 3).clamp(-5, 20);
  }

  double get _chartMaxY {
    if (_voltagePoints.isEmpty) return 20;
    return (_voltagePoints.map((e) => e.y).reduce(max) + 3).clamp(0, 30);
  }

  // ── Normalised x untuk label axis ─────────────────────────
  List<FlSpot> get _normalizedPoints {
    if (_voltagePoints.isEmpty) return [];
    final offset = _voltagePoints.first.x;
    return _voltagePoints
        .map((e) => FlSpot(e.x - offset, e.y))
        .toList();
  }

  // ═══════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      body: SafeArea(
        child: FadeTransition(
          opacity: _cardAnim,
          child: CustomScrollView(
            slivers: [
              _buildAppBar(),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildDemoModeBanner(),
                    const SizedBox(height: 12),
                    _buildStatusCard(),
                    const SizedBox(height: 16),
                    _buildMetricRow(),
                    const SizedBox(height: 16),
                    _buildChartCard(),
                    const SizedBox(height: 16),
                    _buildInfoCards(),
                    const SizedBox(height: 24),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── App Bar ────────────────────────────────────────────────
  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 70,
      floating: true,
      pinned: true,
      backgroundColor: AppColors.primaryGreen,
      flexibleSpace: FlexibleSpaceBar(
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.spa_rounded, color: AppColors.accentButter, size: 20),
            const SizedBox(width: 8),
            Text(
              'Elektrofisiologi Kopi',
              style: TextStyle(
                color: AppColors.accentButter,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Transform.scale(
              scale: _statusColor == AppColors.primaryGreen ? 1.0 : _pulseAnim.value,
              child: Icon(
                Icons.circle,
                size: 14,
                color: _statusColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Banner Demo Mode ───────────────────────────────────────
  Widget _buildDemoModeBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFB74D), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: Color(0xFFF57C00), size: 16),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'DEMO MODE — Hardware belum terhubung. Menampilkan simulasi sinyal AP/VP.',
              style: TextStyle(
                color: Color(0xFF795548),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Status Card ────────────────────────────────────────────
  Widget _buildStatusCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_statusColor, _statusColor.withOpacity(0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _statusColor.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Transform.scale(
              scale: _plantStatus.contains('KRITIS') ? _pulseAnim.value : 1.0,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(_statusIcon, color: Colors.white, size: 32),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Status Tanaman',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _plantStatus,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _statusSubtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Metrik 3 Kartu Kecil ───────────────────────────────────
  Widget _buildMetricRow() {
    return Row(
      children: [
        Expanded(
          child: _metricCard(
            label: 'Voltase',
            value: '${_currentVoltage.toStringAsFixed(2)} mV',
            icon: Icons.bolt_rounded,
            color: AppColors.primaryGreen,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricCard(
            label: 'Min/Max',
            value: _minVoltage == double.infinity
                ? '-- / --'
                : '${_minVoltage.toStringAsFixed(1)}/${_maxVoltage.toStringAsFixed(1)}',
            icon: Icons.show_chart_rounded,
            color: const Color(0xFF00695C),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricCard(
            label: 'Sampel',
            value: '$_sampleCount',
            icon: Icons.data_usage_rounded,
            color: const Color(0xFF1B5E20),
          ),
        ),
      ],
    );
  }

  Widget _metricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Grafik ECG Real-time ───────────────────────────────────
  Widget _buildChartCard() {
    final points = _normalizedPoints;

    return Container(
      height: 260,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.monitor_heart_rounded,
                  color: AppColors.accentButter, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Sinyal AP/VP Real-time',
                style: TextStyle(
                  color: AppColors.accentButter,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentButter.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '10 Hz',
                  style: TextStyle(
                    color: AppColors.accentButter,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: points.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.accentButter,
                    ),
                  )
                : LineChart(
                    LineChartData(
                      minY: _chartMinY,
                      maxY: _chartMaxY,
                      clipData: const FlClipData.all(),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 3,
                        getDrawingHorizontalLine: (v) => FlLine(
                          color: Colors.white.withOpacity(0.08),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            interval: 3,
                            getTitlesWidget: (v, m) => Text(
                              '${v.toInt()}mV',
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipItems: (spots) => spots
                              .map((s) => LineTooltipItem(
                                    '${s.y.toStringAsFixed(2)} mV',
                                    const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: points,
                          isCurved: true,
                          curveSmoothness: 0.3,
                          color: AppColors.accentButter,
                          barWidth: 2,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              colors: [
                                AppColors.accentButter.withOpacity(0.25),
                                AppColors.accentButter.withOpacity(0.0),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ],
                    ),
                    duration: Duration.zero,
                  ),
          ),
        ],
      ),
    );
  }

  // ── Info Cards (Legenda) ───────────────────────────────────
  Widget _buildInfoCards() {
    return Row(
      children: [
        _infoChip(
          color: AppColors.primaryGreen,
          label: 'NORMAL',
          desc: '9–16 mV',
        ),
        const SizedBox(width: 8),
        _infoChip(
          color: const Color(0xFFF57C00),
          label: 'STRES',
          desc: '< 9 atau > 16 mV',
        ),
        const SizedBox(width: 8),
        _infoChip(
          color: const Color(0xFFD32F2F),
          label: 'KRITIS',
          desc: '< 6 atau > 20 mV',
        ),
      ],
    );
  }

  Widget _infoChip({
    required Color color,
    required String label,
    required String desc,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Column(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              desc,
              style: TextStyle(
                color: color.withOpacity(0.7),
                fontSize: 9,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
