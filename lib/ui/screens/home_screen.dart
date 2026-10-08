import 'package:flutter/material.dart';
import '../../data/app_prefs.dart';
import '../../data/auth_service.dart';
import '../../data/history_store.dart';
import '../theme.dart';
import '../widgets/account_dialog.dart';
import '../widgets/pressable.dart';
import '../widgets/pop.dart';
import 'help_screen.dart';
import 'history_screen.dart';
import 'measure_screen.dart';
import 'settings_screen.dart';
import 'troubleshoot.dart';

/// Home – every button works and opens an animated pop-up / screen.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _glow;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  void _go(Widget page) => Navigator.of(context).push(fadeSlide(page));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Appear(
              index: 0,
              child: Row(
                children: [
                  const Icon(Icons.straighten, color: AppColors.accentCyan, size: 30),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Measure Reality',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                  const AccountIconButton(),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Not working? Fix it',
                    icon: const Icon(Icons.support_agent, color: AppColors.warningAmber),
                    onPressed: () => showTroubleshoot(context),
                  ),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: AuthService.I,
              builder: (context, _) {
                final u = AuthService.I.user;
                if (u == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8, left: 2),
                  child: Text('Hi, ${u.firstName} 👋',
                      style: const TextStyle(fontSize: 16, color: AppColors.successGreen, fontWeight: FontWeight.w600)),
                );
              },
            ),
            const SizedBox(height: 22),
            Appear(
              index: 1,
              child: AnimatedBuilder(
                animation: _glow,
                builder: (context, child) => Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accentCyan.withOpacity(0.15 + 0.3 * _glow.value),
                        blurRadius: 18 + 16 * _glow.value,
                      ),
                    ],
                  ),
                  child: child,
                ),
                child: ElevatedButton.icon(
                  onPressed: () => _go(const MeasureScreen()),
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(70)),
                  icon: const Icon(Icons.camera_alt, size: 28),
                  label: const Text('Quick Measure', style: TextStyle(fontSize: 21)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Appear(
              index: 2,
              child: OutlinedButton.icon(
                onPressed: () => showHowTo(context),
                icon: const Icon(Icons.school_outlined),
                label: const Text('How to measure a room'),
              ),
            ),
            const SizedBox(height: 18),
            Appear(
              index: 3,
              child: Row(
                children: [
                  Expanded(child: _tile(Icons.history, 'History', () => _go(const HistoryScreen()))),
                  const SizedBox(width: 10),
                  Expanded(child: _tile(Icons.menu_book_outlined, 'Tutorials', () => showHowTo(context))),
                  const SizedBox(width: 10),
                  Expanded(child: _tile(Icons.settings, 'Settings', () => _go(const SettingsScreen()))),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Appear(
              index: 4,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('How it measures',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                          const Spacer(),
                          InfoButton(
                            title: 'How it measures',
                            icon: Icons.sensors,
                            what: 'Uses your phone\'s tilt and turn sensors plus how high you hold the phone to compute floor distances – like a surveyor\'s tool.',
                            how: 'Stand still, aim the circle at floor points, tap SET START, then move your aim: a dotted line stretches with you. Tap SET END and the app shows the length with unit marks.',
                            whyFails: 'Wrong "Phone height" in Settings, walking between points, or aiming near the horizon give wrong numbers. Calibrate once with a known length.',
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      AnimatedBuilder(
                        animation: AppPrefs.I,
                        builder: (context, _) => Text(
                          'Phone height ${AppPrefs.I.len(AppPrefs.I.phoneHeight)} • Camera ${AppPrefs.qualityNames[AppPrefs.I.cameraQuality]}\nTypical error 2–5 % up to ~5 m',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Appear(
              index: 5,
              child: const Text('Recent',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
            const SizedBox(height: 8),
            Appear(
              index: 6,
              child: AnimatedBuilder(
                animation: Listenable.merge([HistoryStore.I, AppPrefs.I]),
                builder: (context, _) {
                  final items = HistoryStore.I.items.take(6).toList();
                  if (items.isEmpty) {
                    return Container(
                      height: 80,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.glass,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text('No measurements yet – tap Quick Measure',
                          style: TextStyle(color: AppColors.textSecondary)),
                    );
                  }
                  return SizedBox(
                    height: 90,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final m = items[i];
                        return GestureDetector(
                          onTap: () => _go(const HistoryScreen()),
                          child: Container(
                            width: 140,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.glass,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  m.sqMeters != null ? AppPrefs.I.area(m.sqMeters!) : AppPrefs.I.len(m.meters),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                                ),
                                Text(m.mode,
                                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(IconData i, String label, VoidCallback onTap) {
    return _PressTile(icon: i, label: label, onTap: onTap);
  }
}

class _PressTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PressTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.accentCyan, size: 28),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
