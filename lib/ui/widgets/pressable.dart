import 'package:flutter/material.dart';
import '../../data/app_prefs.dart';
import '../theme.dart';

/// Wraps any widget with hover (mouse / stylus), press and glow animations.
/// Touch: shrinks slightly and glows while pressed. Mouse: grows and glows on hover.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color glow;
  final double radius;
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.glow = AppColors.accentCyan,
    this.radius = 20,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final anim = AppPrefs.I.animations;
    final dur = anim ? const Duration(milliseconds: 170) : Duration.zero;
    final active = _hover || _down;
    final scale = !anim ? 1.0 : (_down ? 0.95 : (_hover ? 1.04 : 1.0));
    return MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: scale,
          duration: dur,
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: dur,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              boxShadow: active
                  ? [BoxShadow(color: widget.glow.withOpacity(0.45), blurRadius: 22, spreadRadius: 1)]
                  : const [],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
