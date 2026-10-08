import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/pop.dart';

/// "Not working?" – every known failure with the reason and the fix.
Future<void> showTroubleshoot(BuildContext context) {
  return showPop(
    context,
    icon: Icons.support_agent,
    title: 'Not working? Why it fails',
    accent: AppColors.warningAmber,
    body: const [
      PopBlock(
        icon: Icons.no_photography_outlined,
        color: AppColors.errorRed,
        heading: 'Camera is black / no permission pop-up',
        text: 'Android only shows the permission pop-up twice. If you tapped "Don\'t allow" twice it is blocked: '
            'phone Settings → Apps → Measure Reality → Permissions → Camera → Allow. Or tap "Open phone Settings" on the camera screen.',
      ),
      PopBlock(
        icon: Icons.videocam_off_outlined,
        color: AppColors.errorRed,
        heading: 'Camera error / "could not start"',
        text: 'Another app (WhatsApp, camera, video call) is holding the camera. Close it, then tap "Try again". Very high camera quality on old phones can also fail – choose Medium.',
      ),
      PopBlock(
        icon: Icons.flashlight_on,
        color: AppColors.warningAmber,
        heading: 'Flashlight does nothing',
        text: 'Some phones turn the torch off while the camera is switching or when the phone is hot. Tap it again. If the phone has no flash the app says so.',
      ),
      PopBlock(
        icon: Icons.straighten,
        color: AppColors.warningAmber,
        heading: 'Numbers are wrong',
        text: '1) Set "Phone height" in Settings to the real height of your phone above the floor.  2) Stand still – walking between points breaks the maths.  '
            '3) Aim at the FLOOR (not the wall). 4) Use Calibrate with a known length (like a 2 m tape).',
      ),
      PopBlock(
        icon: Icons.sensors_off,
        color: AppColors.warningAmber,
        heading: '"Motion sensors unavailable"',
        text: 'Your phone has no gyroscope/accelerometer or battery-saver is blocking them. Turn off battery saver and restart the app.',
      ),
      PopBlock(
        icon: Icons.touch_app_outlined,
        color: AppColors.accentCyan,
        heading: 'Pinch zoom not working',
        text: 'Use two fingers on the camera area (not on the buttons). Some phones only allow 1x zoom on the main lens.',
      ),
    ],
  );
}
