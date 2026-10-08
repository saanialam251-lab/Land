import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// A point in space relative to the phone, East/Up/North in metres.
/// (Yaw is zeroed when the engine starts, so "North" = where you first pointed.)
class WorldPoint {
  final double e, u, n;
  const WorldPoint(this.e, this.u, this.n);

  double horizontalTo(WorldPoint o) {
    final de = e - o.e, dn = n - o.n;
    return math.sqrt(de * de + dn * dn);
  }

  double to3D(WorldPoint o) {
    final de = e - o.e, du = u - o.u, dn = n - o.n;
    return math.sqrt(de * de + du * du + dn * dn);
  }
}

/// Where a world point lands on the screen.
class ScreenPt {
  final double x, y;
  const ScreenPt(this.x, this.y);
}

/// The phone's orientation at one moment (radians).
class Pose {
  final double pitchDown, roll, yaw;

  /// True when the pose is the median of a steady window of readings.
  final bool steady;
  const Pose(this.pitchDown, this.roll, this.yaw, {this.steady = false});
}

class _Sample {
  final int us;
  final double pitch, roll, yaw;
  final bool trusted; // accelerometer was measuring gravity only (hand not accelerating)
  const _Sample(this.us, this.pitch, this.roll, this.yaw, this.trusted);
}

/// Error propagation for the floor-distance formula  d = h / tan(a).
///   dd/da = h / sin^2(a)      (angle error grows quickly for far points)
///   dd/dh = 1 / tan(a) = d/h  (a wrong phone height scales every distance)
class MeasureError {
  /// 1-sigma error (metres) of one floor point at horizontal distance [d].
  static double pointSigma(double d, double h,
      {double angleSigmaDeg = 0.4, double heightSigma = 0.02}) {
    if (d <= 0 || h <= 0) return 0;
    final a = math.atan2(h, d); // angle below the horizon
    final sa = math.sin(a);
    final dA = h / (sa * sa) * (angleSigmaDeg * math.pi / 180);
    final dH = d / h * heightSigma;
    return math.sqrt(dA * dA + dH * dH);
  }

  /// Typical error (metres) of the distance between two floor points.
  static double segmentSigma(WorldPoint a, WorldPoint b, double h,
      {double yawSigmaDeg = 0.6}) {
    final da = math.sqrt(a.e * a.e + a.n * a.n);
    final db = math.sqrt(b.e * b.e + b.n * b.n);
    final sa = pointSigma(da, h);
    final sb = pointSigma(db, h);
    final sy = yawSigmaDeg * math.pi / 180;
    return math.sqrt(sa * sa + sb * sb + da * da * sy * sy + db * db * sy * sy);
  }

  /// Typical error (metres) of an object height measured from base to top.
  static double heightSigma(double baseDist, double topElevationRad, double h,
      {double angleSigmaDeg = 0.4}) {
    final c = math.cos(topElevationRad);
    final sd = pointSigma(baseDist, h);
    final dA = baseDist / (c * c) * (angleSigmaDeg * math.pi / 180);
    final dD = math.tan(topElevationRad).abs() * sd;
    return math.sqrt(dA * dA + dD * dD + 0.02 * 0.02);
  }

  /// Short text like "±4 cm" in the user's unit.
  static String label(double meters, String Function(double) fmt) => '±${fmt(meters)}';
}

/// Turns the phone's accelerometer + gyroscope into a "virtual tape measure".
///
/// How it measures (no ARCore needed):
///  • Pitch (tilt) comes from gravity (accelerometer).
///  • Turning (yaw) comes from integrating the gyroscope.
///  • A floor point seen at angle [pitchDown] below the horizon from a phone held
///    [phoneHeight] above the floor is at horizontal distance  h / tan(pitchDown).
///  • Two such points + the turn angle between them give the distance between
///    them (law of cosines) – exactly what a surveyor does.
class SensorEngine extends ChangeNotifier {
  StreamSubscription? _accSub;
  StreamSubscription? _gyroSub;

  double _ax = 0, _ay = 9.8, _az = 0;
  bool _haveAcc = false;
  int _lastGyroUs = 0;
  double _lastRate = 0;

  /// This phone's own reading of "1 g" (learned while it is held still).
  double _gRef = 9.81;
  bool _steadyAccel = true;

  /// Gyroscope resting offset per axis (rad/s), learned while the phone is still.
  double _bx = 0, _by = 0, _bz = 0;

  final List<_Sample> _buf = [];
  int _lastNotifyUs = 0;

  /// Radians the camera looks BELOW the horizon (negative = looking up).
  double pitchDown = 0;
  /// Phone roll in radians (0 = portrait upright).
  double roll = 0;
  /// Heading relative to start, radians, clockwise-positive.
  double yaw = 0;

  /// Smoothed turning speed, degrees per second.
  double turnRate = 0;

  /// True while the phone is held still enough for a precise reading.
  bool get isSteady => _steadyAccel && turnRate < 4.0;

  bool sensorsAvailable = true;
  bool started = false;
  int _ticks = 0;
  Timer? _watchdog;

  Future<void> start() async {
    if (started) return;
    started = true;
    try {
      _accSub = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen(
        _onAcc,
        onError: (_) => _fail(),
        cancelOnError: false,
      );
      _gyroSub = gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval).listen(
        _onGyro,
        onError: (_) {},
        cancelOnError: false,
      );
      // If no sensor event arrives within 2 s, tell the UI.
      _watchdog = Timer(const Duration(seconds: 2), () {
        if (_ticks == 0) _fail();
      });
    } catch (_) {
      _fail();
    }
  }

  void _fail() {
    sensorsAvailable = false;
    notifyListeners();
  }

  void stop() {
    _accSub?.cancel();
    _gyroSub?.cancel();
    _watchdog?.cancel();
    _accSub = null;
    _gyroSub = null;
    started = false;
  }

  void resetYaw() {
    yaw = 0;
    _buf.clear();
    notifyListeners();
  }

  void _onAcc(AccelerometerEvent e) {
    _ticks++;
    if (!sensorsAvailable) sensorsAvailable = true;
    final raw = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    var dev = 0.0;
    if (!_haveAcc) {
      _ax = e.x;
      _ay = e.y;
      _az = e.z;
      _haveAcc = true;
      if (raw > 8.5 && raw < 11.0) _gRef = raw;
    } else {
      // How far is this reading from pure gravity? A big difference means the
      // hand is accelerating, so the reading says little about the tilt: trust it less.
      dev = (raw - _gRef).abs();
      _steadyAccel = dev < 0.35;
      final k = dev < 0.4 ? 0.18 : (dev < 1.2 ? 0.06 : 0.015);
      _ax += k * (e.x - _ax);
      _ay += k * (e.y - _ay);
      _az += k * (e.z - _az);
      if (_steadyAccel && turnRate < 3.0) {
        _gRef = (_gRef + 0.01 * (raw - _gRef)).clamp(9.3, 10.3).toDouble();
      }
    }
    final g = math.sqrt(_ax * _ax + _ay * _ay + _az * _az);
    if (g < 1) return;
    // Back camera looks along -z of the device. (Normalised by the measured |a|.)
    pitchDown = math.asin((_az / g).clamp(-1.0, 1.0));
    if (_ax.abs() + _ay.abs() > 1.5) {
      roll = math.atan2(-_ax, _ay);
    }

    final nowUs = DateTime.now().microsecondsSinceEpoch;
    _buf.add(_Sample(nowUs, pitchDown, roll, yaw, dev < 0.5));
    while (_buf.isNotEmpty && nowUs - _buf.first.us > 1500000) {
      _buf.removeAt(0);
    }
    // ~30 UI updates per second is plenty and keeps the screen smooth.
    if (nowUs - _lastNotifyUs >= 33000) {
      _lastNotifyUs = nowUs;
      notifyListeners();
    }
  }

  void _onGyro(GyroscopeEvent e) {
    _ticks++;
    final now = DateTime.now().microsecondsSinceEpoch;
    // Remove the gyro's resting offset (this is what causes slow "drift").
    final wx = e.x - _bx, wy = e.y - _by, wz = e.z - _bz;
    final mag = math.sqrt(wx * wx + wy * wy + wz * wz) * 180 / math.pi; // deg/s

    if (_lastGyroUs != 0 && _haveAcc) {
      final dt = (now - _lastGyroUs) / 1e6;
      if (dt > 0 && dt < 0.2) {
        final g = math.sqrt(_ax * _ax + _ay * _ay + _az * _az);
        if (g > 1) {
          // Rotation rate about the world's vertical axis (trapezoid integration).
          final rate = (wx * _ax + wy * _ay + wz * _az) / g;
          yaw -= 0.5 * (rate + _lastRate) * dt;
          _lastRate = rate;
        }
      } else {
        _lastRate = 0;
      }
    }

    // Phone held still -> whatever the gyro reports is its resting offset: learn it.
    if (mag < 1.5 && _steadyAccel) {
      const kb = 0.01;
      _bx += kb * (e.x - _bx);
      _by += kb * (e.y - _by);
      _bz += kb * (e.z - _bz);
    }

    turnRate += 0.2 * (mag - turnRate);
    _lastGyroUs = now;
  }

  // ── Steady pose ──────────────────────────────────────────────────────

  static double _median(List<double> v) {
    final c = List<double>.from(v)..sort();
    final m = c.length ~/ 2;
    return c.length.isOdd ? c[m] : (c[m - 1] + c[m]) / 2;
  }

  /// The phone's orientation just BEFORE the finger touched the screen.
  ///
  /// Pressing a button always tilts the phone a little. So instead of using the
  /// reading at the moment of the tap, take the median of the newest steady
  /// stretch of readings that is at least ~0.2 s old.
  Pose stablePose() {
    final now = DateTime.now().microsecondsSinceEpoch;
    var anchor = -1;
    for (var i = _buf.length - 1; i >= 0; i--) {
      if (now - _buf[i].us >= 220000 && _buf[i].trusted) {
        anchor = i;
        break;
      }
    }
    if (anchor < 0) return Pose(pitchDown, roll, yaw);
    final a = _buf[anchor];
    final pitches = <double>[], rolls = <double>[], yaws = <double>[];
    for (var i = anchor; i >= 0; i--) {
      final smp = _buf[i];
      if (a.us - smp.us > 500000) break;
      if (!smp.trusted) continue;
      if ((smp.pitch - a.pitch).abs() > 0.0105 || (smp.yaw - a.yaw).abs() > 0.014) break;
      pitches.add(smp.pitch);
      rolls.add(smp.roll);
      yaws.add(smp.yaw);
    }
    if (pitches.length < 3) return Pose(a.pitch, a.roll, a.yaw);
    return Pose(_median(pitches), _median(rolls), _median(yaws), steady: true);
  }

  // ── Measuring ────────────────────────────────────────────────────────

  static const _minDownDeg = 3.0;
  static const _maxDownDeg = 87.0;

  /// Horizontal distance to the floor point under the crosshair, or null if the
  /// phone is aimed too high (horizon) / not at the floor.
  /// Pass [pose] (from [stablePose]) to measure from a steady reading.
  double? floorDistance(double phoneHeight, {Pose? pose}) {
    final a = pose?.pitchDown ?? pitchDown;
    final deg = a * 180 / math.pi;
    if (deg < _minDownDeg || deg > _maxDownDeg) return null;
    return phoneHeight / math.tan(a);
  }

  /// World position of the floor point under the crosshair.
  WorldPoint? floorPoint(double phoneHeight, {Pose? pose}) {
    final d = floorDistance(phoneHeight, pose: pose);
    if (d == null) return null;
    final y = pose?.yaw ?? yaw;
    return WorldPoint(d * math.sin(y), -phoneHeight, d * math.cos(y));
  }

  /// Un-normalised world direction (E,U,N) of the ray through a screen pixel.
  List<double> rayDir(double px, double py, double w, double h, double fovDeg, double zoom,
      {Pose? pose}) {
    final pitch = pose?.pitchDown ?? pitchDown;
    final rl = pose?.roll ?? roll;
    final yw = pose?.yaw ?? yaw;
    final fpx = (h / 2) / math.tan(fovDeg * math.pi / 360) * zoom;
    final xd = px - w / 2, yd = h / 2 - py;
    final cr = math.cos(rl), sr = math.sin(rl);
    final xc = xd * cr + yd * sr;
    final yc = -xd * sr + yd * cr;
    final ca = math.cos(pitch), sa = math.sin(pitch);
    final cs = math.cos(yw), ss = math.sin(yw);
    final e = xc * cs + yc * sa * ss + fpx * ca * ss;
    final u = yc * ca - fpx * sa;
    final n = -xc * ss + yc * sa * cs + fpx * ca * cs;
    return [e, u, n];
  }

  /// Floor point under a tapped pixel (null if the pixel is above the horizon
  /// or the point would be unreasonably far).
  WorldPoint? floorFromPixel(double px, double py, double w, double h, double fovDeg,
      double zoom, double phoneHeight, {Pose? pose}) {
    final d = rayDir(px, py, w, h, fovDeg, zoom, pose: pose);
    if (d[1] >= -1e-9) return null;
    final hor = math.sqrt(d[0] * d[0] + d[2] * d[2]);
    if (hor < 1e-9) return null;
    final below = math.atan2(-d[1], hor) * 180 / math.pi;
    if (below < _minDownDeg) return null;
    final t = phoneHeight / -d[1];
    if (t * hor > 40) return null;
    return WorldPoint(t * d[0], -phoneHeight, t * d[2]);
  }

  /// Top point for height mode from a tapped pixel, above the base location.
  WorldPoint? topFromPixel(WorldPoint base, double px, double py, double w, double h,
      double fovDeg, double zoom, {Pose? pose}) {
    final d = rayDir(px, py, w, h, fovDeg, zoom, pose: pose);
    final hor = math.sqrt(d[0] * d[0] + d[2] * d[2]);
    if (hor < 1e-9) return null;
    final baseD = math.sqrt(base.e * base.e + base.n * base.n);
    final k = baseD / hor;
    return WorldPoint(d[0] * k, d[1] * k, d[2] * k);
  }

  /// Point at the top of an object whose base is [base] (height mode).
  WorldPoint topPoint(WorldPoint base, double phoneHeight, {Pose? pose}) {
    final a = pose?.pitchDown ?? pitchDown;
    final y = pose?.yaw ?? yaw;
    final d = math.sqrt(base.e * base.e + base.n * base.n);
    final u = -math.tan(a) * d; // relative to phone
    return WorldPoint(d * math.sin(y), u, d * math.cos(y));
  }

  /// Project a world point to the screen. Returns null when behind the camera.
  ScreenPt? project(WorldPoint p, double w, double h, double fovDeg, double zoom) {
    final a = pitchDown, s = yaw;
    final ca = math.cos(a), sa = math.sin(a), cs = math.cos(s), ss = math.sin(s);
    // camera basis
    final xc = p.e * cs - p.n * ss; // right
    final yc = p.e * sa * ss + p.u * ca + p.n * sa * cs; // up
    final zc = p.e * ca * ss - p.u * sa + p.n * ca * cs; // forward
    if (zc < 0.05) return null;
    final fpx = (h / 2) / math.tan(fovDeg * math.pi / 360) * zoom;
    // compensate phone roll
    final cr = math.cos(roll), sr = math.sin(roll);
    final xd = xc * cr - yc * sr;
    final yd = xc * sr + yc * cr;
    return ScreenPt(w / 2 + xd / zc * fpx, h / 2 - yd / zc * fpx);
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

/// Pure geometry helpers.
class FloorMath {
  /// Polygon area (shoelace) on the floor plane, metres².
  static double polygonArea(List<WorldPoint> pts) {
    if (pts.length < 3) return 0;
    double s = 0;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      s += a.e * b.n - b.e * a.n;
    }
    return s.abs() / 2;
  }

  static double perimeter(List<WorldPoint> pts, {bool closed = true}) {
    if (pts.length < 2) return 0;
    double s = 0;
    for (var i = 0; i < pts.length - 1; i++) {
      s += pts[i].horizontalTo(pts[i + 1]);
    }
    if (closed && pts.length > 2) s += pts.last.horizontalTo(pts.first);
    return s;
  }
}
