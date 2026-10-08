import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/pop.dart';

/// Pop-up with the step-by-step guide.
Future<void> showHowTo(BuildContext context) {
  return showPop(
    context,
    icon: Icons.school_outlined,
    title: 'How to measure a room',
    body: const [
      PopBlock(
        icon: Icons.looks_one_outlined,
        color: AppColors.accentCyan,
        heading: 'Stand still, hold the phone steady',
        text: 'Hold the phone upright. Do NOT walk between points – stay in one spot and only turn. '
            'Set "Phone height" in Settings to the real height of your phone above the floor (default 1.4 m).',
      ),
      PopBlock(
        icon: Icons.touch_app_outlined,
        color: AppColors.accentCyan,
        heading: 'TOUCH the points on the floor',
        text: 'Touch the start point on the screen, then the end point. Far away (e.g. you are at the door)? '
            'Pinch with two fingers to zoom in – or let Auto zoom do it – then touch the exact corner. Touches snap to detected corner rings.',
      ),
      PopBlock(
        icon: Icons.auto_awesome,
        color: AppColors.successGreen,
        heading: 'Room: auto-detect corners',
        text: 'In Room mode tap AUTO-DETECT CORNERS. The app finds floor corners in view immediately. Remove wrong ones with Undo or add missing ones by touching, then tap CLOSE for area + perimeter.',
      ),
      PopBlock(
        icon: Icons.height,
        color: AppColors.successGreen,
        heading: 'Height mode',
        text: 'Touch the floor at the BASE of a door/wall, then tilt up and touch the TOP.',
      ),
      PopBlock(
        icon: Icons.functions,
        color: AppColors.successGreen,
        heading: 'See the maths',
        text: 'Tap the Σ-style "functions" button on the right of the camera to open the live maths panel: tilt, turn, distances, law of cosines, shoelace area – with your real numbers.',
      ),
      PopBlock(
        icon: Icons.warning_amber_rounded,
        color: AppColors.warningAmber,
        heading: 'Warning boxes',
        text: 'The app tells you when you move too fast, a point is too far, the room is too dark, or the phone is aimed above the floor.',
      ),
      PopBlock(
        icon: Icons.tune,
        color: AppColors.warningAmber,
        heading: 'For best accuracy',
        text: 'Measure one thing you know (e.g. a 2 m tape line) and tap "Calibrate". Use the flashlight in dark rooms.',
      ),
      PopBlock(
        icon: Icons.info_outline,
        color: AppColors.errorRed,
        heading: 'Honest limits',
        text: 'This uses phone sensors, not a laser or walking tracking. Typical error is 2–5 % up to ~5 m and grows with distance. You must measure from ONE standing spot; walking from start to end is not supported yet.',
      ),
    ],
  );
}
