import 'package:flutter/material.dart';
import '../../data/app_prefs.dart';
import '../../data/history_store.dart';
import '../theme.dart';
import '../widgets/pop.dart';
import 'help_screen.dart';
import 'troubleshoot.dart';

/// Settings – every option is live, saved, and has its own info pop-up.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPrefs.I;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppColors.nearBlack,
      ),
      body: AnimatedBuilder(
        animation: p,
        builder: (context, _) {
          final cards = <Widget>[
            _section('Measurement'),
            _card(
              icon: Icons.square_foot,
              title: 'Unit',
              subtitle: AppPrefs.unitName(p.unit),
              info: const InfoButton(
                title: 'Unit',
                icon: Icons.square_foot,
                what: 'Chooses how lengths and areas are shown: metres, centimetres, feet or inches.',
                how: 'Tap a chip. The measure screen, history and home update immediately.',
                whyFails: 'Saved values are always stored in metres, so changing the unit never changes old measurements – only how they look.',
              ),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final u in DispUnit.values)
                    ChoiceChip(
                      label: Text(AppPrefs.unitName(u)),
                      selected: p.unit == u,
                      onSelected: (_) => p.update(() => p.unit = u),
                    ),
                ],
              ),
            ),
            _card(
              icon: Icons.pin_outlined,
              title: 'Decimals',
              subtitle: '${p.decimals} decimal places  (example: ${p.len(2.34567)})',
              info: const InfoButton(
                title: 'Decimals',
                icon: Icons.pin_outlined,
                what: 'How many digits after the point are shown.',
                how: 'Slide left for rounder numbers, right for more digits.',
                whyFails: 'More digits does not mean more accuracy. Phone-sensor accuracy is about 2–5 %, so 1–2 decimals is honest.',
              ),
              child: Slider(
                value: p.decimals.toDouble(),
                min: 0,
                max: 3,
                divisions: 3,
                label: '${p.decimals}',
                onChanged: (v) => p.update(() => p.decimals = v.round()),
              ),
            ),
            _card(
              icon: Icons.accessibility_new,
              title: 'Phone height above floor',
              subtitle: '${p.len(p.phoneHeight)}   (most important setting)',
              info: const InfoButton(
                title: 'Phone height',
                icon: Icons.accessibility_new,
                what: 'How high your phone is above the floor while you measure. The app turns your tilt angle into a distance using this height.',
                how: 'Hold the phone the way you normally measure (chest height ≈ 1.2–1.5 m), measure that height once with a tape, and set it here.',
                whyFails: 'If this is wrong, EVERY distance is wrong by the same percentage. Too high a value → distances too long. Use Calibrate on the result card to fix it automatically.',
              ),
              child: Slider(
                value: p.phoneHeight.clamp(0.5, 2.2).toDouble(),
                min: 0.5,
                max: 2.2,
                divisions: 34,
                label: p.phoneHeight.toStringAsFixed(2),
                onChanged: (v) => p.update(() => p.phoneHeight = double.parse(v.toStringAsFixed(2))),
              ),
            ),
            _card(
              icon: Icons.tune,
              title: 'Calibration',
              subtitle: 'Correction ×${p.scaleCal.toStringAsFixed(3)}',
              info: const InfoButton(
                title: 'Calibration',
                icon: Icons.tune,
                what: 'A correction factor learned when you press "Calibrate" after a measurement.',
                how: 'Measure a known length, tap Calibrate, type the real length. Reset it here any time.',
                whyFails: 'If results got worse after calibrating, you typed a wrong real length. Press Reset.',
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(140, 42)),
                  onPressed: p.scaleCal == 1.0
                      ? null
                      : () {
                          p.update(() => p.scaleCal = 1.0);
                          _snack(context, 'Calibration reset');
                        },
                  child: const Text('Reset to ×1.000'),
                ),
              ),
            ),
            _section('Camera'),
            _card(
              icon: Icons.high_quality_outlined,
              title: 'Camera quality',
              subtitle: AppPrefs.qualityNames[p.cameraQuality],
              info: const InfoButton(
                title: 'Camera quality',
                icon: Icons.high_quality_outlined,
                what: 'Resolution of the live camera picture.',
                how: 'Pick a level. It is applied the next time the camera opens (or immediately from the measure screen).',
                whyFails: 'Max can fail or get the phone hot on older devices – the app then steps down automatically. It does not change measurement accuracy.',
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < AppPrefs.qualityNames.length; i++)
                    ChoiceChip(
                      label: Text(AppPrefs.qualityNames[i]),
                      selected: p.cameraQuality == i,
                      onSelected: (_) => p.update(() => p.cameraQuality = i),
                    ),
                ],
              ),
            ),
            _card(
              icon: Icons.flashlight_on,
              title: 'Start with flashlight on',
              subtitle: p.keepFlashOn ? 'On' : 'Off',
              info: const InfoButton(
                title: 'Flashlight',
                icon: Icons.flashlight_on,
                what: 'Turns the torch on automatically when the camera opens. You can always toggle it with the bulb button on the measure screen.',
                how: 'Use in dark rooms so you can see the floor corners.',
                whyFails: 'Phones without a flash ignore this. The torch can make the phone warm – switch it off when not needed.',
              ),
              trailing: Switch(
                value: p.keepFlashOn,
                onChanged: (v) => p.update(() => p.keepFlashOn = v),
              ),
            ),
            _card(
              icon: Icons.zoom_in_map,
              title: 'Auto zoom',
              subtitle: p.autoZoom ? 'On – zooms in on far targets' : 'Off – pinch only',
              info: const InfoButton(
                title: 'Auto zoom',
                icon: Icons.zoom_in_map,
                what: 'When the spot you aim at is far away, the camera zooms in by itself so you can touch the exact corner.',
                how: 'Leave it on. You can still pinch with two fingers any time – auto zoom pauses for 3 seconds while you pinch.',
                whyFails: 'Some phones only have 1x zoom on the main lens, so nothing changes. Zooming does not reduce accuracy; distance does.',
              ),
              trailing: Switch(value: p.autoZoom, onChanged: (v) => p.update(() => p.autoZoom = v)),
            ),
            _card(
              icon: Icons.filter_center_focus,
              title: 'Corner assist',
              subtitle: p.cornerAssist ? 'On – rings on detected corners' : 'Off',
              info: const InfoButton(
                title: 'Corner assist',
                icon: Icons.filter_center_focus,
                what: 'Finds sharp corners in the camera picture right away, shows them as rings, and makes your touch snap to the nearest one. Room mode can add them all with AUTO-DETECT.',
                how: 'Aim so the floor and wall edges are visible and lit. Touch near a ring to snap to it.',
                whyFails: 'It finds ANY sharp corner (door handles, furniture, pattern tiles), not only room corners, and needs light and contrast. Use Undo to remove wrong points.',
              ),
              trailing: Switch(value: p.cornerAssist, onChanged: (v) => p.update(() => p.cornerAssist = v)),
            ),
            _card(
              icon: Icons.zoom_in_map,
              title: 'Camera field of view',
              subtitle: p.fovAuto && p.detectedFovDeg != null
                  ? 'Auto: ${p.fov.round()}°  (read from your camera)'
                  : '${p.fovDeg.round()}°  (aligns the drawn line with the picture)',
              info: const InfoButton(
                title: 'Field of view',
                icon: Icons.zoom_in_map,
                what: 'Tells the app how wide your camera sees so the drawn lines and grid sit on the right spot of the picture.',
                how: 'If the line seems to drift away from the real floor point when you turn, change this by 5° steps (typical phones: 60–75°).',
                whyFails: 'A wrong FOV mainly misplaces the drawing. Points added with the crosshair (the main button) are not affected; points you tap far from the centre can be slightly off.',
              ),
              trailing: Switch(value: p.fovAuto, onChanged: (v) => p.update(() => p.fovAuto = v)),
              child: Slider(
                value: p.fovDeg.clamp(45, 90).toDouble(),
                min: 45,
                max: 90,
                divisions: 9,
                label: '${p.fovDeg.round()}°',
                onChanged: (p.fovAuto && p.detectedFovDeg != null) ? null : (v) => p.update(() => p.fovDeg = v.roundToDouble()),
              ),
            ),
            _section('Look & feel'),
            _card(
              icon: Icons.grid_on,
              title: 'Floor grid',
              subtitle: p.grid ? 'Shown (1 m squares)' : 'Hidden',
              info: const InfoButton(
                title: 'Floor grid',
                icon: Icons.grid_on,
                what: 'Draws a 1-metre grid on the floor so you can SEE the scale.',
                how: 'Switch on to visualise lengths; switch off for a cleaner view.',
                whyFails: 'The grid appears only when the phone is aimed downward. It is a visual aid, not a measurement.',
              ),
              trailing: Switch(value: p.grid, onChanged: (v) => p.update(() => p.grid = v)),
            ),
            _card(
              icon: Icons.animation,
              title: 'Animations',
              subtitle: p.animations ? 'Full' : 'Off (faster)',
              info: const InfoButton(
                title: 'Animations',
                icon: Icons.animation,
                what: 'Pop-ups, line drawing, counting numbers and transitions.',
                how: 'Turn off if your phone is slow or you prefer instant screens.',
                whyFails: 'Pop-up and page animations switch off immediately; some effects need the measure screen reopened.',
              ),
              trailing: Switch(value: p.animations, onChanged: (v) => p.update(() => p.animations = v)),
            ),
            _card(
              icon: Icons.vibration,
              title: 'Haptics (vibration)',
              subtitle: p.haptics ? 'On' : 'Off',
              info: const InfoButton(
                title: 'Haptics',
                icon: Icons.vibration,
                what: 'Short vibration when you add a point, finish a measurement or aim wrongly.',
                how: 'Toggle the switch.',
                whyFails: 'No vibration? Check that the phone is not in silent/vibration-off mode or battery saver.',
              ),
              trailing: Switch(value: p.haptics, onChanged: (v) => p.update(() => p.haptics = v)),
            ),
            _section('Help & data'),
            _card(
              icon: Icons.school_outlined,
              title: 'How to use the app',
              subtitle: 'Step-by-step guide',
              onTap: () => showHowTo(context),
            ),
            _card(
              icon: Icons.support_agent,
              title: 'Not working? Why it fails',
              subtitle: 'Every problem with its fix',
              onTap: () => showTroubleshoot(context),
            ),
            _card(
              icon: Icons.delete_outline,
              title: 'Clear history',
              subtitle: '${HistoryStore.I.items.length} saved measurements',
              onTap: () => showPop(
                context,
                icon: Icons.delete_outline,
                title: 'Clear all history?',
                accent: AppColors.errorRed,
                body: const [PopText('This deletes every saved measurement. It cannot be undone.')],
                actions: [
                  Builder(
                    builder: (ctx) => TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                  ),
                  Builder(
                    builder: (ctx) => ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(110, 44),
                        backgroundColor: AppColors.errorRed,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        HistoryStore.I.clear();
                        Navigator.pop(ctx);
                      },
                      child: const Text('Delete'),
                    ),
                  ),
                ],
              ),
            ),
            _card(
              icon: Icons.restart_alt,
              title: 'Reset all settings',
              subtitle: 'Back to defaults',
              onTap: () {
                p.reset();
                _snack(context, 'Settings reset');
              },
            ),
            _section('About'),
            _card(icon: Icons.info_outline, title: 'Version', subtitle: '1.1.0 – sensor measuring'),
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
            children: [
              for (var i = 0; i < cards.length; i++) Appear(index: i, child: cards[i]),
            ],
          );
        },
      ),
    );
  }

  static void _snack(BuildContext c, String m) {
    ScaffoldMessenger.of(c)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  }

  static Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 22, 8, 6),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                color: AppColors.accentCyan, fontWeight: FontWeight.w700, fontSize: 12.5, letterSpacing: 1.2)),
      );

  static Widget _card({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? child,
    Widget? info,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: AppColors.accentCyan),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing,
                  if (info != null) info,
                  if (onTap != null && info == null && trailing == null)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.chevron_right, color: AppColors.textSecondary),
                    ),
                ],
              ),
              if (child != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 4),
                  child: child,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
