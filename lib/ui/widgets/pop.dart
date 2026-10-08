import 'package:flutter/material.dart';
import '../../data/app_prefs.dart';
import '../theme.dart';

Duration _d(int ms) => AppPrefs.I.animations ? Duration(milliseconds: ms) : Duration.zero;

/// Animated pop-up that springs up from the bottom with a scale + fade.
Future<T?> showPop<T>(
  BuildContext context, {
  required IconData icon,
  required String title,
  required List<Widget> body,
  Color accent = AppColors.accentCyan,
  List<Widget>? actions,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'close',
    barrierColor: Colors.black54,
    transitionDuration: _d(420),
    pageBuilder: (ctx, a, b) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, sec, _) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1).animate(curved),
            child: Padding(
              padding: MediaQuery.of(ctx).viewInsets,
              child: Center(
              child: Material(
                color: Colors.transparent,
                child: PopGlow(
                  builder: (g) => Container(
                  constraints: BoxConstraints(
                    maxWidth: 420,
                    maxHeight: MediaQuery.of(ctx).size.height * 0.82,
                  ),
                  margin: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF151A23),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: accent.withOpacity(0.25 + 0.30 * g)),
                    boxShadow: [
                      BoxShadow(color: accent.withOpacity(0.16 + 0.22 * g), blurRadius: 28 + 26 * g, spreadRadius: 2),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: accent.withOpacity(0.15),
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: accent.withOpacity(0.15 + 0.35 * g), blurRadius: 16)],
                              ),
                              child: Icon(icon, color: accent, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(title,
                                  style: const TextStyle(
                                      fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white54),
                              onPressed: () => Navigator.of(ctx).pop(),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < body.length; i++) Appear(index: i, child: body[i]),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: actions ??
                              [
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(120, 44),
                                    backgroundColor: accent,
                                  ),
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('Got it'),
                                ),
                              ],
                        ),
                      ),
                    ],
                  ),
                ),
                ),
              ),
            ),
            ),
          ),
        ),
      );
    },
  );
}

/// Slowly breathing glow value (0..1) for the pop-up frame.
class PopGlow extends StatefulWidget {
  final Widget Function(double glow) builder;
  const PopGlow({super.key, required this.builder});

  @override
  State<PopGlow> createState() => _PopGlowState();
}

class _PopGlowState extends State<PopGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    if (AppPrefs.I.animations) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppPrefs.I.animations) return widget.builder(0.5);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => widget.builder(Curves.easeInOut.transform(_c.value)),
    );
  }
}

/// A paragraph / bullet used inside pop-ups.
class PopText extends StatelessWidget {
  final String text;
  final bool bold;
  final Color? color;
  const PopText(this.text, {super.key, this.bold = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: TextStyle(
            color: color ?? Colors.white70,
            fontSize: 14.5,
            height: 1.45,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      );
}

/// A labelled block: "Why it fails" etc.
class PopBlock extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String heading;
  final String text;
  const PopBlock({
    super.key,
    required this.icon,
    required this.color,
    required this.heading,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(heading,
                      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13.5)),
                  const SizedBox(height: 3),
                  Text(text,
                      style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Small (i) button that opens a detailed pop-up for an option.
class InfoButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final String what;
  final String how;
  final String whyFails;
  const InfoButton({
    super.key,
    required this.title,
    required this.icon,
    required this.what,
    required this.how,
    required this.whyFails,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'About $title',
      icon: const Icon(Icons.info_outline, color: AppColors.accentCyan, size: 22),
      onPressed: () => showPop(
        context,
        icon: icon,
        title: title,
        body: [
          PopBlock(icon: Icons.help_outline, color: AppColors.accentCyan, heading: 'What it does', text: what),
          PopBlock(icon: Icons.touch_app_outlined, color: AppColors.successGreen, heading: 'How to use', text: how),
          PopBlock(icon: Icons.warning_amber_rounded, color: AppColors.warningAmber, heading: 'If it does not work / why it fails', text: whyFails),
        ],
      ),
    );
  }
}

/// Fade + slide-up entrance, staggered by [index].
class Appear extends StatelessWidget {
  final Widget child;
  final int index;
  const Appear({super.key, required this.child, this.index = 0});

  @override
  Widget build(BuildContext context) {
    if (!AppPrefs.I.animations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 450 + index * 70),
      curve: Curves.easeOutCubic,
      builder: (context, v, c) => Opacity(
        opacity: v.clamp(0.0, 1.0).toDouble(),
        child: Transform.translate(offset: Offset(0, (1 - v) * 28), child: c),
      ),
      child: child,
    );
  }
}

/// Number that smoothly counts to its new value.
class CountText extends StatelessWidget {
  final double value;
  final String Function(double) format;
  final TextStyle style;
  const CountText({super.key, required this.value, required this.format, required this.style});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: _d(350),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(format(v), style: style),
    );
  }
}

/// Page route: fade + slight slide up.
Route<T> fadeSlide<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: _d(380),
    reverseTransitionDuration: _d(260),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, a, __, child) {
      final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: c,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(c),
          child: child,
        ),
      );
    },
  );
}
