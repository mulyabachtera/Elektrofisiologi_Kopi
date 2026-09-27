import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/dashboard_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/history_screen.dart';
import 'theme/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  await Firebase.initializeApp();
  runApp(const PBEDSApp());
}

class PBEDSApp extends StatelessWidget {
  const PBEDSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PBEDS — Plant Bioelectric Early Detection System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryGreen,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: AppColors.backgroundColor,
      ),
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late AnimationController _navCtrl;

  static const _screens = [
    DashboardScreen(),
    ScanScreen(),
    HistoryScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _navCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300));
    _navCtrl.forward();
  }

  @override
  void dispose() {
    _navCtrl.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    if (index == _selectedIndex) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedIndex = index);
    _navCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      body: FadeTransition(
        opacity: _navCtrl,
        child: _screens[_selectedIndex],
      ),
      bottomNavigationBar: _buildNavBar(),
    );
  }

  Widget _buildNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1F12),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.08), width: 1)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.dashboard_rounded,
                Icons.dashboard_outlined, 'Dashboard'),
              _buildNavItem(1, Icons.biotech_rounded,
                Icons.biotech_outlined, 'Scan'),
              _buildNavItem(2, Icons.history_rounded,
                Icons.history_outlined, 'Riwayat'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int idx, IconData activeIcon,
      IconData inactiveIcon, String label) {
    final isActive = _selectedIndex == idx;
    return GestureDetector(
      onTap: () => _onNavTap(idx),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primaryGreen.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              isActive ? activeIcon : inactiveIcon,
              key: ValueKey(isActive),
              size: 24,
              color: isActive ? AppColors.primaryGreen : Colors.white38,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(
            color: isActive ? AppColors.primaryGreen : Colors.white38,
            fontSize: 11,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          )),
        ]),
      ),
    );
  }
}
