import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/app_prefs.dart';
import '../measure/sensor_engine.dart';
import 'theme.dart';
import 'widgets/camera_view.dart';

enum MMode { distance, room, height }

/// Draws the floor grid, the measured lines, points and distance labels
/// on top of the camera, projected from the phone's sensors.
class MeasureOverlayPainter extends CustomPainter {
  final SensorEngine engine;
  final List<WorldPoint> points;
  final MMode mode;
  final bool closed;
  final bool done;
  final double zoom;
  final double phoneHeight;
  final Animation<double> pulse; // 0..1 repeating
  final Animation<double> draw; // 0..1 when a point is added
  final AppPrefs prefs;
  final CamController cam;

  MeasureOverlayPainter({
    required this.engine,
    required this.points,
    required this.mode,
    required this.closed,
    required this.done,
    required this.zoom,
    required this.phoneHeight,
    required this.pulse,
    required this.draw,
    required this.prefs,
    required this.cam,
  }) : super(repaint: Listenable.merge([engine, pulse, draw, cam]));

  ScreenPt? _p(WorldPoint w, Size s) => engine.project(w, s.width, s.height, prefs.fov, zoom);

  @override
  void paint(Canvas canvas, Size size) {
    if (prefs.grid) _grid(canvas, size);
    if (prefs.cornerAssist && !done) _corners(canvas, size);

    // Live point under the reticle
    WorldPoint? live;
    if (mode == MMode.height && points.isNotEmpty) {
      live = engine.topPoint(points.first, phoneHeight);
    } else {
      live = engine.floorPoint(phoneHeight);
    }

    final all = <WorldPoint>[...points];

    // Fill the room polygon
    if (mode == MMode.room && all.length >= 3) {
      final path = Path();
      var ok = true;
      for (var i = 0; i < all.length; i++) {
        final sp = _p(all[i], size);
        if (sp == null) {
          ok = false;
          break;
        }
        if (i == 0) {
          path.moveTo(sp.x, sp.y);
        } else {
          path.lineTo(sp.x, sp.y);
        }
      }
      if (ok) {
        path.close();
        canvas.drawPath(
          path,
          Paint()
            ..color = AppColors.accentCyan.withOpacity(closed ? 0.22 : 0.10)
            ..style = PaintingStyle.fill,
        );
      }
    }

    // Segments between placed points
    final segCount = all.length < 2 ? 0 : all.length - 1;
    for (var i = 0; i < segCount; i++) {
      final isLast = i == segCount - 1;
      final t = isLast && prefs.animations ? Curves.easeOutCubic.transform(draw.value) : 1.0;
      _segment(canvas, size, all[i], all[i + 1], progress: t, solid: true);
    }
    if (mode == MMode.room && closed && all.length > 2) {
      _segment(canvas, size, all.last, all.first, progress: 1, solid: true);
    }

    // Rubber band to the reticle
    if (!closed && live != null && all.isNotEmpty) {
      if (!(mode != MMode.room && all.length >= 2)) {
        _segment(canvas, size, all.last, live, progress: 1, solid: false);
        final lp = _p(live, size);
        if (lp != null) _ghost(canvas, Offset(lp.x, lp.y));
      }
    }

    // Points
    for (var i = 0; i < all.length; i++) {
      final sp = _p(all[i], size);
      if (sp == null) continue;
      final age = i == all.length - 1 ? (prefs.animations ? draw.value : 1.0) : 1.0;
      _dot(canvas, Offset(sp.x, sp.y), AppColors.successGreen, age, '${i + 1}');
      if (mode != MMode.room && age > 0.6) {
        if (i == 0) {
          _tag(canvas, Offset(sp.x, sp.y), mode == MMode.height ? 'BASE' : 'START', AppColors.successGreen);
        } else if (i == all.length - 1) {
          _tag(canvas, Offset(sp.x, sp.y), mode == MMode.height ? 'TOP' : 'END', AppColors.accentCyan);
        }
      }
    }
  }

  void _corners(Canvas canvas, Size size) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withOpacity(0.85);
    final glow = Paint()..color = AppColors.accentCyan.withOpacity(0.25 + 0.2 * pulse.value);
    for (final c in cam.corners) {
      final o = cam.cornerToScreen(c, size);
      if (o.dx < 0 || o.dy < 0 || o.dx > size.width || o.dy > size.height) continue;
      final r = 6 + 5 * c.score;
      canvas.drawCircle(o, r + 4 * pulse.value, glow);
      canvas.drawCircle(o, r, ring);
    }
  }

  void _grid(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const range = 6;
    for (var k = -range; k <= range; k++) {
      final fade = (1 - (k.abs() / (range + 1))).clamp(0.0, 1.0).toDouble();
      paint.color = Colors.white.withOpacity(0.05 + 0.22 * fade);
      // lines parallel to North (constant East) and parallel to East (constant North)
      for (var j = -range; j < range; j++) {
        final a = _p(WorldPoint(k.toDouble(), -phoneHeight, j.toDouble()), size);
        final b = _p(WorldPoint(k.toDouble(), -phoneHeight, (j + 1).toDouble()), size);
        if (a != null && b != null) canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), paint);
        final c = _p(WorldPoint(j.toDouble(), -phoneHeight, k.toDouble()), size);
        final d = _p(WorldPoint((j + 1).toDouble(), -phoneHeight, k.toDouble()), size);
        if (c != null && d != null) canvas.drawLine(Offset(c.x, c.y), Offset(d.x, d.y), paint);
      }
    }
  }

  void _segment(Canvas canvas, Size size, WorldPoint a, WorldPoint b,
      {required double progress, required bool solid}) {
    final pa = _p(a, size), pb = _p(b, size);
    if (pa == null || pb == null) return;
    final o1 = Offset(pa.x, pa.y);
    final full = Offset(pb.x, pb.y);
    final o2 = Offset.lerp(o1, full, progress)!;

    final color = solid ? AppColors.accentCyan : AppColors.warningAmber;
    // glow
    canvas.drawLine(
      o1,
      o2,
      Paint()
        ..color = color.withOpacity(0.45)
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    if (solid) {
      // faint guide + bright dots slowly marching along the line
      canvas.drawLine(
        o1,
        o2,
        Paint()
          ..color = color.withOpacity(0.35)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
      _dotted(canvas, o1, o2, color, pulse.value * 13, radius: 3.4, gap: 13);
      _flow(canvas, o1, o2);
    } else {
      // the line being stretched from the start point to the crosshair
      _dotted(canvas, o1, o2, color, pulse.value * 12, radius: 3.8, gap: 12);
    }

    // label
    final len = (mode == MMode.height ? (a.u - b.u).abs() : a.horizontalTo(b));
    final dist = len * 1.0;
    final mid = Offset.lerp(o1, o2, 0.5)!;
    _label(canvas, size, mid, prefs.len(dist), color);

    // end tick marks like a tape measure
    _ticks(canvas, o1, o2, color);
    if (progress >= 1) _unitTicks(canvas, size, a, b, color);
  }

  /// Round dots along a line, marching from a to b.
  void _dotted(Canvas canvas, Offset a, Offset b, Color c, double phase,
      {double radius = 3.4, double gap = 12}) {
    final total = (b - a).distance;
    if (total < 1) return;
    final dir = (b - a) / total;
    final paint = Paint()..color = c;
    var d = (prefs.animations ? phase : 0.0) % gap;
    while (d <= total) {
      canvas.drawCircle(a + dir * d, radius, paint);
      d += gap;
    }
  }

  String _trim(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  String _tickText(double meters) {
    switch (prefs.unit) {
      case DispUnit.m:
        return _trim(meters);
      case DispUnit.cm:
        return _trim(meters * 100);
      case DispUnit.ft:
        return _trim(meters / 0.3048);
      case DispUnit.inch:
        return _trim(meters / 0.0254);
    }
  }

  /// Small ruler marks along the line in the chosen unit (m, cm, ft, in).
  void _unitTicks(Canvas canvas, Size size, WorldPoint a, WorldPoint b, Color color) {
    final total = mode == MMode.height ? (a.u - b.u).abs() : a.horizontalTo(b);
    if (total < 0.05) return;
    final imperial = prefs.unit == DispUnit.ft || prefs.unit == DispUnit.inch;
    final unitM = imperial ? 0.3048 : 1.0;
    final List<double> steps = imperial
        ? const [0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0]
        : const [0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0];
    var step = steps.last * unitM;
    for (final s in steps) {
      if (total / (s * unitM) <= 8) {
        step = s * unitM;
        break;
      }
    }
    final pa = _p(a, size), pb = _p(b, size);
    if (pa == null || pb == null) return;
    final v = Offset(pb.x - pa.x, pb.y - pa.y);
    final l = v.distance;
    if (l < 60) return;
    final nrm = Offset(-v.dy / l, v.dx / l);
    final line = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var k = 1; k < 40; k++) {
      final t = (k * step) / total;
      if (t >= 0.97) break;
      final w = WorldPoint(
        a.e + (b.e - a.e) * t,
        a.u + (b.u - a.u) * t,
        a.n + (b.n - a.n) * t,
      );
      final sp = _p(w, size);
      if (sp == null) continue;
      final c = Offset(sp.x, sp.y);
      canvas.drawLine(c - nrm * 7, c + nrm * 7, line);
      final tp = TextPainter(
        text: TextSpan(
          text: _tickText(k * step),
          style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800, shadows: const [
            Shadow(color: Colors.black, blurRadius: 3),
          ]),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final at = c + nrm * 16 - Offset(tp.width / 2, tp.height / 2);
      tp.paint(canvas, at);
    }
  }

  /// Pulsing ring where the stretching line currently ends.
  void _ghost(Canvas canvas, Offset c) {
    final r = 9 + 5 * pulse.value;
    canvas.drawCircle(
      c,
      r + 7,
      Paint()
        ..color = AppColors.warningAmber.withOpacity(0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = AppColors.warningAmber.withOpacity(0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    canvas.drawCircle(c, 3, Paint()..color = Colors.white);
  }

  /// Small pill label (START / END) above a point.
  void _tag(Canvas canvas, Offset at, String text, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: at - const Offset(0, 30), width: tp.width + 14, height: tp.height + 6),
      const Radius.circular(10),
    );
    canvas.drawRRect(rect, Paint()..color = color);
    tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Color c, double phase) {
    final total = (b - a).distance;
    if (total < 1) return;
    final dir = (b - a) / total;
    final paint = Paint()
      ..color = c
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const dash = 12.0, gap = 9.0;
    var d = -phase;
    while (d < total) {
      final s = math.max(d, 0.0);
      final e = math.min(d + dash, total);
      if (e > s) canvas.drawLine(a + dir * s, a + dir * e, paint);
      d += dash + gap;
    }
  }

  void _flow(Canvas canvas, Offset a, Offset b) {
    final total = (b - a).distance;
    if (total < 20) return;
    final t = pulse.value;
    final p = Offset.lerp(a, b, t)!;
    canvas.drawCircle(p, 5, Paint()..color = Colors.white.withOpacity(0.9));
  }

  void _ticks(Canvas canvas, Offset a, Offset b, Color c) {
    final v = b - a;
    final l = v.distance;
    if (l < 30) return;
    final n = Offset(-v.dy / l, v.dx / l) * 9;
    final p = Paint()
      ..color = c
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(a - n, a + n, p);
    canvas.drawLine(b - n, b + n, p);
  }

  void _dot(Canvas canvas, Offset c, Color color, double age, String text) {
    final pop = Curves.elasticOut.transform(age.clamp(0.0, 1.0).toDouble());
    final r = 11 * pop;
    final ring = 14 + 10 * pulse.value;
    canvas.drawCircle(c, ring, Paint()..color = color.withOpacity(0.35 * (1 - pulse.value)));
    canvas.drawCircle(c, r + 3, Paint()..color = Colors.black54);
    canvas.drawCircle(c, r, Paint()..color = color);
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    if (pop > 0.6) tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  void _label(Canvas canvas, Size size, Offset at, String text, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: at - const Offset(0, 22), width: tp.width + 22, height: tp.height + 12),
      const Radius.circular(14),
    );
    canvas.drawRRect(rect, Paint()..color = Colors.black.withOpacity(0.72));
    canvas.drawRRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant MeasureOverlayPainter old) => true;
}
