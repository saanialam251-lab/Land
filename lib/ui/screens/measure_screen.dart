import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/app_prefs.dart';
import '../../data/auth_service.dart';
import '../../data/history_store.dart';
import '../../measure/sensor_engine.dart';
import '../measure_overlay.dart';
import '../theme.dart';
import '../widgets/camera_view.dart';
import '../widgets/pop.dart';
import 'help_screen.dart';

/// Camera + measurement screen.
class MeasureScreen extends StatefulWidget {
  const MeasureScreen({super.key});

  @override
  State<MeasureScreen> createState() => _MeasureScreenState();
}

class _MeasureScreenState extends State<MeasureScreen> with TickerProviderStateMixin {
  final cam = CamController();
  final engine = SensorEngine();
  late final AnimationController _pulse;
  late final AnimationController _draw;
  late final AnimationController _result;
  late final AnimationController _flash;
  double _steadyT = 0; // 0..1, smoothed "phone is steady" amount for the crosshair colour

  static bool _tutorialShown = false;

  MMode mode = MMode.distance;
  final List<WorldPoint> points = [];
  bool closed = false;
  bool done = false;
  double resultMeters = 0;
  double? resultArea;
  double? resultPerimeter;
  String? toast;
  double _baseZoom = 1;
  bool showMath = false;
  DateTime _lastPinch = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _autoTimer;
  Size _box = const Size(360, 800);

  AppPrefs get prefs => AppPrefs.I;
  double get hEff => prefs.phoneHeight * prefs.scaleCal;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
    _draw = AnimationController(vsync: this, duration: const Duration(milliseconds: 550), value: 1);
    _result = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    cam.init();
    engine.start();
    prefs.detectFov();
    _autoTimer = Timer.periodic(const Duration(milliseconds: 400), (_) => _autoZoomTick());
    if (!_tutorialShown) {
      _tutorialShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showHowTo(context);
      });
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pulse.dispose();
    _draw.dispose();
    _result.dispose();
    _flash.dispose();
    engine.dispose();
    cam.dispose();
    super.dispose();
  }

  void _buzz({bool strong = false}) {
    if (prefs.animations && !strong) _flash.forward(from: 0);
    if (!prefs.haptics) return;
    if (strong) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  void _say(String msg) {
    setState(() => toast = msg);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && toast == msg) setState(() => toast = null);
    });
  }

  void _reset({MMode? newMode}) {
    setState(() {
      points.clear();
      closed = false;
      done = false;
      resultArea = null;
      resultPerimeter = null;
      resultMeters = 0;
      if (newMode != null) mode = newMode;
    });
    _result.reset();
    engine.resetYaw();
  }

  // ── Actions ─────────────────────────────────────────────────────────

  /// Automatic zoom: far target → zoom in smoothly, near target → zoom out.
  void _autoZoomTick() {
    if (!mounted || !prefs.autoZoom || cam.state != CamState.ready || done) return;
    if (DateTime.now().difference(_lastPinch).inMilliseconds < 3500) return; // user is pinching
    final d = engine.floorDistance(hEff);
    final target = d == null ? 1.0 : (d / 3.0).clamp(1.0, math.min(cam.maxZoom, 4.0)).toDouble();
    final next = cam.zoom + (target - cam.zoom) * 0.5;
    if ((next - cam.zoom).abs() > 0.06) cam.setZoom(next);
  }

  /// Snap a tap to a nearby detected corner (corner assist).
  Offset _snap(Offset tap) {
    if (!prefs.cornerAssist) return tap;
    Offset best = tap;
    var bestD = 44.0;
    for (final c in cam.corners) {
      final o = cam.cornerToScreen(c, _box);
      final dd = (o - tap).distance;
      if (dd < bestD) {
        bestD = dd;
        best = o;
      }
    }
    return best;
  }

  /// [at] = tapped pixel; null = the centre crosshair.
  void _addPoint({Offset? at}) {
    if (done) return;
    if (!engine.sensorsAvailable) {
      _say('Motion sensors not available on this phone.');
      return;
    }
    // Pressing the screen tilts the phone, so measure from the steady reading just before the touch.
    final pose = engine.stablePose();
    final px = at == null ? null : _snap(at);
    WorldPoint? floorAt() => px == null
        ? engine.floorPoint(hEff, pose: pose)
        : engine.floorFromPixel(px.dx, px.dy, _box.width, _box.height, prefs.fov, cam.zoom, hEff, pose: pose);

    if (mode == MMode.height) {
      if (points.isEmpty) {
        final p = floorAt();
        if (p == null) {
          _say('Touch the FLOOR at the base of the object (not the wall).');
          _buzz(strong: true);
          return;
        }
        setState(() => points.add(p));
        _draw.forward(from: 0);
        _buzz();
      } else {
        final top = px == null
            ? engine.topPoint(points.first, hEff, pose: pose)
            : engine.topFromPixel(points.first, px.dx, px.dy, _box.width, _box.height, prefs.fov, cam.zoom, pose: pose);
        if (top == null) return;
        final height = top.u + hEff;
        if (height < 0.02) {
          _say('Top must be higher than the base. Touch the top of the object.');
          return;
        }
        setState(() {
          points.add(top);
          resultMeters = height;
          done = true;
        });
        _draw.forward(from: 0);
        _finish();
      }
      return;
    }

    final p = floorAt();
    if (p == null) {
      _say('That spot is not on the floor (too high or too far). Touch a floor point – pinch to zoom for far ones.');
      _buzz(strong: true);
      return;
    }
    setState(() => points.add(p));
    _draw.forward(from: 0);
    _buzz();
    if (mode == MMode.distance && points.length == 2) {
      setState(() {
        resultMeters = points[0].horizontalTo(points[1]);
        done = true;
      });
      _finish();
    }
  }

  /// Room mode: take every detected floor corner in view and build the room.
  void _autoCorners() {
    final pose = engine.stablePose();
    final found = <MapEntry<double, WorldPoint>>[];
    for (final c in cam.corners) {
      final o = cam.cornerToScreen(c, _box);
      final p = engine.floorFromPixel(o.dx, o.dy, _box.width, _box.height, prefs.fov, cam.zoom, hEff, pose: pose);
      if (p == null) continue;
      final d = math.sqrt(p.e * p.e + p.n * p.n);
      if (d < 0.8 || d > 15) continue;
      found.add(MapEntry(c.score, p));
    }
    found.sort((a, b) => b.key.compareTo(a.key));
    final chosen = <WorldPoint>[];
    for (final f in found) {
      if (chosen.every((q) => q.horizontalTo(f.value) > 0.6)) chosen.add(f.value);
      if (chosen.length >= 8) break;
    }
    if (chosen.length < 3) {
      _say('Not enough floor corners found. Aim so floor + wall edges are visible and well lit, or touch the corners yourself.');
      _buzz(strong: true);
      return;
    }
    chosen.sort((a, b) => math.atan2(a.e, a.n).compareTo(math.atan2(b.e, b.n)));
    setState(() {
      points
        ..clear()
        ..addAll(chosen);
      closed = false;
    });
    _draw.forward(from: 0);
    _buzz(strong: true);
    _say('${chosen.length} corners detected – fix any wrong ones with Undo, then tap CLOSE.');
  }

  void _closeRoom() {
    if (points.length < 3) {
      _say('Add at least 3 corners first.');
      return;
    }
    setState(() {
      closed = true;
      done = true;
      resultArea = FloorMath.polygonArea(points);
      resultPerimeter = FloorMath.perimeter(points);
      resultMeters = resultPerimeter!;
    });
    _finish();
  }

  void _finish() {
    _buzz(strong: true);
    _result.forward(from: 0);
  }

  void _undo() {
    if (points.isEmpty) return;
    setState(() {
      points.removeLast();
      closed = false;
      done = false;
      resultArea = null;
      resultPerimeter = null;
    });
    _result.reset();
    _buzz();
  }

  void _save() {
    HistoryStore.I.add(SavedMeasurement(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      mode: mode.name,
      meters: resultMeters,
      sqMeters: resultArea,
      points: points.length,
      at: DateTime.now(),
    ));
    _say(AuthService.I.loggedIn ? 'Saved to your account ✓' : 'Saved to History ✓');
    _reset();
  }

  Future<void> _calibrate() async {
    final ctrl = TextEditingController();
    final measured = resultMeters;
    await showPop(
      context,
      icon: Icons.straighten,
      title: 'Calibrate',
      body: [
        const PopText(
            'Measure something whose real length you know (a door, a tape-measured line on the floor). '
            'Type the real length below in METRES and the app will correct itself.'),
        PopText('This measurement said: ${prefs.len(measured)}', bold: true, color: Colors.white),
        TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Real length in metres (e.g. 2.5)',
            labelStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
          ),
        ),
      ],
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        Builder(
          builder: (ctx) => ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(120, 44)),
            onPressed: () {
              final real = double.tryParse(ctrl.text.replaceAll(',', '.'));
              if (real == null || real <= 0) {
                _say('Type the real length as a number, e.g. 2.5');
                return;
              }
              if (measured <= 0.01) {
                _say('Measure something first, then calibrate.');
                return;
              }
              final factor = (real / measured).clamp(0.3, 3.0).toDouble();
              prefs.update(() => prefs.scaleCal = (prefs.scaleCal * factor).clamp(0.3, 3.0).toDouble());
              Navigator.pop(ctx);
              _reset();
              _say('Calibrated. Measure again.');
            },
            child: const Text('Apply'),
          ),
        ),
      ],
    );
    ctrl.dispose();
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, box) {
          _box = Size(box.maxWidth, box.maxHeight);
          return Stack(
            fit: StackFit.expand,
            children: [
              // Camera + pinch-to-zoom
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _addPoint(at: d.localPosition),
                onScaleStart: (_) => _baseZoom = cam.zoom,
                onScaleUpdate: (d) {
                  if (d.pointerCount >= 2) {
                    _lastPinch = DateTime.now();
                    cam.setZoom(_baseZoom * d.scale);
                  }
                },
                child: CameraView(cam: cam),
              ),

              // Measurement overlay
              IgnorePointer(
                child: AnimatedBuilder(
                  animation: Listenable.merge([cam, engine, prefs]),
                  builder: (context, _) => CustomPaint(
                    size: Size(box.maxWidth, box.maxHeight),
                    painter: MeasureOverlayPainter(
                      engine: engine,
                      points: points,
                      mode: mode,
                      closed: closed,
                      done: done,
                      zoom: cam.zoom,
                      phoneHeight: hEff,
                      pulse: _pulse,
                      draw: _draw,
                      prefs: prefs,
                      cam: cam,
                    ),
                  ),
                ),
              ),

              // Reticle
              IgnorePointer(child: Center(child: _reticle())),
              IgnorePointer(
                child: Center(
                  child: Transform.translate(
                    offset: const Offset(0, 68),
                    child: AnimatedBuilder(
                      animation: engine,
                      builder: (context, _) {
                        final show = engine.sensorsAvailable && cam.state == CamState.ready && !done;
                        final steady = engine.isSteady;
                        final c = steady ? AppColors.successGreen : AppColors.warningAmber;
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          transitionBuilder: (w, a) => FadeTransition(
                            opacity: a,
                            child: ScaleTransition(scale: Tween<double>(begin: 0.85, end: 1).animate(a), child: w),
                          ),
                          child: !show
                              ? const SizedBox.shrink(key: ValueKey('none'))
                              : Container(
                                  key: ValueKey(steady),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: c.withOpacity(0.8)),
                                  ),
                                  child: Text(steady ? '● Steady' : 'Hold still',
                                      style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
                                ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: AnimatedBuilder(
                  animation: _flash,
                  builder: (context, _) => _flash.isAnimating
                      ? Container(color: Colors.white.withOpacity(0.22 * (1 - _flash.value)))
                      : const SizedBox.shrink(),
                ),
              ),

              // Top bar
              Align(alignment: Alignment.topCenter, child: _slideIn(const Offset(0, -40), SafeArea(child: _topBar()))),

              // Side toggles: auto zoom, corner assist, math
              Positioned(
                right: 12,
                top: MediaQuery.of(context).padding.top + 64,
                child: AnimatedBuilder(
                  animation: Listenable.merge([prefs]),
                  builder: (context, _) => Column(
                    children: [
                      _roundBtn(Icons.zoom_in_map, prefs.autoZoom ? 'Auto zoom ON' : 'Auto zoom OFF', () {
                        prefs.update(() => prefs.autoZoom = !prefs.autoZoom);
                        _say(prefs.autoZoom
                            ? 'Auto zoom ON – zooms in on far targets for you'
                            : 'Auto zoom OFF – pinch to zoom yourself');
                      }, active: prefs.autoZoom),
                      const SizedBox(height: 8),
                      _roundBtn(Icons.filter_center_focus, prefs.cornerAssist ? 'Corner assist ON' : 'Corner assist OFF', () {
                        prefs.update(() => prefs.cornerAssist = !prefs.cornerAssist);
                        _say(prefs.cornerAssist
                            ? 'Corner assist ON – rings show detected corners; touches snap to them'
                            : 'Corner assist OFF');
                      }, active: prefs.cornerAssist),
                      const SizedBox(height: 8),
                      _roundBtn(Icons.functions, 'Show the maths', () => setState(() => showMath = !showMath),
                          active: showMath, color: AppColors.successGreen),
                    ],
                  ),
                ),
              ),

              // Tip / warning box (animated) + live maths panel
              Positioned(
                top: MediaQuery.of(context).padding.top + 64,
                left: 12,
                right: 68,
                child: AnimatedBuilder(
                  animation: Listenable.merge([engine, cam, prefs]),
                  builder: (context, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _tipBox(),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutBack,
                        alignment: Alignment.topCenter,
                        child: showMath
                            ? Padding(padding: const EdgeInsets.only(top: 8), child: _mathPanel())
                            : const SizedBox(width: double.infinity),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom panel
              Align(alignment: Alignment.bottomCenter, child: _slideIn(const Offset(0, 60), _bottomPanel())),
            ],
          );
        },
      ),
    );
  }

  _Tip? _currentTip() {
    if (toast != null) return _Tip(Icons.info_outline, 'Note', toast!, AppColors.warningAmber, false);
    if (done) return null;
    if (cam.state != CamState.ready) return null;
    if (!engine.sensorsAvailable) {
      return _Tip(Icons.sensors_off, 'No motion sensors',
          'Turn off battery saver and restart the app.', AppColors.errorRed, false);
    }
    if (engine.turnRate > 70) {
      return _Tip(Icons.speed, 'Too fast!',
          'You are moving the phone too fast (${engine.turnRate.toStringAsFixed(0)}°/s). Move SLOWLY and hold steady before touching a point.',
          AppColors.errorRed, true);
    }
    if (cam.brightness < 45 && !cam.torch) {
      return _Tip(Icons.flashlight_on, 'Too dark',
          'Corners cannot be seen. Tap the bulb (top right) to turn the flashlight on.', AppColors.warningAmber, true);
    }
    final d = engine.floorDistance(hEff);
    if (mode != MMode.height || points.isEmpty) {
      if (d == null) {
        return _Tip(Icons.south, 'Aim at the floor',
            'The crosshair is above the horizon. Tilt the phone down until the circle turns blue, or touch a floor spot.',
            AppColors.accentCyan, true);
      }
      if (d > 6.5) {
        return _Tip(Icons.zoom_in, 'Too far (${prefs.len(d)})',
            'Accuracy drops with distance. ${prefs.autoZoom ? 'Auto zoom is helping – ' : ''}pinch with two fingers to zoom, or step closer.',
            AppColors.warningAmber, true);
      }
    }
    return null;
  }

  Widget _tipBox() {
    final t = _currentTip();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutBack,
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -0.5), end: Offset.zero).animate(a),
          child: ScaleTransition(scale: Tween<double>(begin: 0.9, end: 1).animate(a), child: c),
        ),
      ),
      child: t == null
          ? const SizedBox(key: ValueKey('none'), width: double.infinity)
          : GestureDetector(
              key: ValueKey(t.title),
              onTap: () {
                if (t.title == 'Too dark') cam.toggleTorch();
                if (t.title.startsWith('Too far')) cam.setZoom(math.min(cam.maxZoom, cam.zoom + 1));
                if (toast != null) setState(() => toast = null);
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.78),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: t.color, width: 1.6),
                  boxShadow: [BoxShadow(color: t.color.withOpacity(0.35), blurRadius: 16)],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(t.wiggle ? math.sin(_pulse.value * math.pi * 8) * 3 : 0, 0),
                        child: child,
                      ),
                      child: Icon(t.icon, color: t.color, size: 28),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.title,
                              style: TextStyle(color: t.color, fontWeight: FontWeight.w800, fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(t.text,
                              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  String _f(double v, [int d = 2]) => v.toStringAsFixed(d);

  List<String> _mathLines() {
    final h = hEff;
    final deg = 180 / math.pi;
    final L = <String>[];
    L.add('h = phone height × calibration');
    L.add('  = ${_f(prefs.phoneHeight)} × ${_f(prefs.scaleCal, 3)} = ${_f(h)} m');
    final a = engine.pitchDown * deg;
    L.add('α (tilt, gravity sensor) = ${_f(a, 1)}°');
    L.add('ψ (turn, gyroscope) = ${_f(engine.yaw * deg, 1)}°');
    final d = engine.floorDistance(h);
    L.add(d == null
        ? 'Crosshair: not on floor (need 3° < α < 87°)'
        : 'Crosshair  d = h / tan α\n  = ${_f(h)} / tan(${_f(a, 1)}°) = ${_f(d)} m');
    L.add('');

    double dist(WorldPoint p) => math.sqrt(p.e * p.e + p.n * p.n);
    double az(WorldPoint p) => math.atan2(p.e, p.n) * deg;

    switch (mode) {
      case MMode.distance:
        if (points.isEmpty) {
          L.add('Distance A→B uses the law of cosines:');
          L.add('  AB² = d₁² + d₂² − 2·d₁·d₂·cos Δψ');
          L.add('Mark A and B to see the numbers.');
        } else {
          for (var i = 0; i < points.length && i < 2; i++) {
            final p = points[i];
            final di = dist(p);
            final ai = math.atan(h / di) * deg;
            final nm = i == 0 ? 'A' : 'B';
            L.add('$nm: α=${_f(ai, 1)}°  d${i + 1} = h/tan α = ${_f(di)} m');
            L.add('   ψ${i + 1} = ${_f(az(p), 1)}°');
          }
          if (points.length >= 2) {
            final d1 = dist(points[0]), d2 = dist(points[1]);
            var dp = (az(points[1]) - az(points[0])).abs();
            if (dp > 180) dp = 360 - dp;
            final c2 = d1 * d1 + d2 * d2 - 2 * d1 * d2 * math.cos(dp / deg);
            L.add('Δψ = |ψ₂ − ψ₁| = ${_f(dp, 1)}°');
            L.add('AB² = ${_f(d1 * d1)} + ${_f(d2 * d2)} − 2·${_f(d1)}·${_f(d2)}·cos(${_f(dp, 1)}°)');
            L.add('    = ${_f(c2)}');
            L.add('AB = √${_f(c2)} = ${_f(math.sqrt(c2 < 0 ? 0 : c2))} m');
          }
        }
        break;
      case MMode.room:
        L.add('Each corner → floor position (E,N) = d·(sin ψ, cos ψ)');
        for (var i = 0; i < points.length; i++) {
          final p = points[i];
          L.add('P${i + 1}: d=${_f(dist(p))} m  ψ=${_f(az(p), 1)}°  → (${_f(p.e)}, ${_f(p.n)})');
        }
        if (points.length >= 2) {
          L.add('Perimeter = Σ |Pᵢ Pᵢ₊₁| = ${_f(FloorMath.perimeter(points, closed: points.length > 2))} m');
        }
        if (points.length >= 3) {
          var sum = 0.0;
          for (var i = 0; i < points.length; i++) {
            final p = points[i], q = points[(i + 1) % points.length];
            sum += p.e * q.n - q.e * p.n;
          }
          L.add('Shoelace: S = Σ(Eᵢ·Nᵢ₊₁ − Eᵢ₊₁·Nᵢ) = ${_f(sum)}');
          L.add('Area = |S| / 2 = ${_f(sum.abs() / 2)} m²');
        } else {
          L.add('Area needs 3+ corners (shoelace formula).');
        }
        break;
      case MMode.height:
        L.add('Height  H = h + d·tan β');
        if (points.isNotEmpty) {
          final b = points.first;
          final db = dist(b);
          L.add('Base: d = h/tan α = ${_f(db)} m');
          if (points.length >= 2) {
            final top = points[1];
            final beta = math.atan(top.u / db) * deg;
            L.add('Top: β = ${_f(beta, 1)}° above the horizon');
            L.add('H = ${_f(h)} + ${_f(db)}·tan(${_f(beta, 1)}°)');
            L.add('  = ${_f(resultMeters)} m');
          } else {
            L.add('Now aim/touch the TOP to get β.');
          }
        } else {
          L.add('Mark the base on the floor first.');
        }
        break;
    }
    L.add('');
    L.add('Accuracy ≈ 2–5 %. Error grows when α is small (far points).');
    return L;
  }

  Widget _mathPanel() {
    final lines = _mathLines();
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: _box.height * 0.34),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.successGreen.withOpacity(0.7)),
        boxShadow: [BoxShadow(color: AppColors.successGreen.withOpacity(0.25), blurRadius: 18)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.functions, color: AppColors.successGreen, size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Live maths',
                    style: TextStyle(color: AppColors.successGreen, fontWeight: FontWeight.w800)),
              ),
              GestureDetector(
                onTap: () => setState(() => showMath = false),
                child: const Icon(Icons.close, color: Colors.white54, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Flexible(
            child: SingleChildScrollView(
              child: Text(
                lines.join('\n'),
                style: const TextStyle(
                    color: Colors.white, fontSize: 11.5, height: 1.35, fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reticle() {
    return AnimatedBuilder(
      animation: Listenable.merge([engine, _pulse]),
      builder: (context, _) {
        final ok = mode == MMode.height && points.isNotEmpty
            ? true
            : engine.floorDistance(hEff) != null;
        _steadyT += ((engine.isSteady ? 1.0 : 0.0) - _steadyT) * 0.12;
        final c = !ok
            ? AppColors.warningAmber
            : Color.lerp(AppColors.accentCyan, AppColors.successGreen, _steadyT)!;
        final s = 56.0 + (6 - 4 * _steadyT) * _pulse.value;
        return SizedBox(
          width: 90,
          height: 90,
          child: Center(
            child: Container(
              width: s,
              height: s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.withOpacity(0.85), width: 2.5),
                boxShadow: [BoxShadow(color: c.withOpacity(0.35), blurRadius: 14)],
              ),
              child: Center(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _roundBtn(IconData icon, String tip, VoidCallback onTap,
      {bool active = false, Color? color}) {
    return Tooltip(
      message: tip,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? (color ?? AppColors.accentCyan) : Colors.black54,
          boxShadow: active
              ? [BoxShadow(color: (color ?? AppColors.accentCyan).withOpacity(0.6), blurRadius: 16)]
              : null,
        ),
        child: IconButton(
          icon: Icon(icon, color: active ? Colors.black : Colors.white),
          onPressed: onTap,
        ),
      ),
    );
  }

  Widget _topBar() {
    return AnimatedBuilder(
      animation: cam,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(
          children: [
            _roundBtn(Icons.arrow_back, 'Back', () => Navigator.pop(context)),
            const Spacer(),
            // zoom chip
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cam.zoom > 1.05 ? AppColors.accentCyan : Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${cam.zoom.toStringAsFixed(1)}x',
                  style: TextStyle(
                      color: cam.zoom > 1.05 ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            _roundBtn(
              cam.torch ? Icons.flashlight_on : Icons.flashlight_off,
              'Flashlight',
              () async {
                await cam.toggleTorch();
                if (!cam.torchSupported) _say('This phone has no flashlight for the camera.');
                _buzz();
              },
              active: cam.torch,
              color: AppColors.warningAmber,
            ),
            const SizedBox(width: 8),
            _roundBtn(Icons.high_quality_outlined, 'Camera quality', _qualitySheet),
            const SizedBox(width: 8),
            _roundBtn(Icons.help_outline, 'How to measure', () => showHowTo(context)),
          ],
        ),
      ),
    );
  }

  void _qualitySheet() {
    showPop(
      context,
      icon: Icons.high_quality_outlined,
      title: 'Camera quality',
      body: [
        const PopText(
            'Higher quality = sharper picture but more battery and heat. If the preview lags or the phone gets warm, choose Medium. '
            'If a quality is not supported by your phone the app steps down automatically.'),
        StatefulBuilder(
          builder: (ctx, setS) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < AppPrefs.qualityNames.length; i++)
                ChoiceChip(
                  label: Text(AppPrefs.qualityNames[i]),
                  selected: prefs.cameraQuality == i,
                  onSelected: (_) {
                    prefs.update(() => prefs.cameraQuality = i);
                    setS(() {});
                    cam.applyQuality();
                    _buzz();
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const PopBlock(
          icon: Icons.warning_amber_rounded,
          color: AppColors.warningAmber,
          heading: 'Why it may fail',
          text: 'Another app is using the camera, or the phone is too hot. Close other camera apps and try again.',
        ),
      ],
    );
  }

  String get _instruction {
    if (!engine.sensorsAvailable) return 'Motion sensors unavailable';
    switch (mode) {
      case MMode.distance:
        return points.isEmpty
            ? 'TOUCH the floor (or tap SET START) to mark the START point'
            : done
                ? 'Done!'
                : 'The dotted line stretches with you. TOUCH the floor or tap SET END';
      case MMode.room:
        return closed
            ? 'Room measured'
            : points.isEmpty
                ? 'Tap AUTO-DETECT, or touch each floor corner'
                : 'Touch the next corner. Tap CLOSE when done';
      case MMode.height:
        return points.isEmpty
            ? 'TOUCH the floor at the BASE of the object'
            : done
                ? 'Done!'
                : 'Tilt up and TOUCH the TOP';
    }
  }

  Widget _bottomPanel() {
    return AnimatedBuilder(
      animation: Listenable.merge([engine, prefs]),
      builder: (context, _) {
        final pad = MediaQuery.of(context).padding.bottom;
        final liveD = engine.floorDistance(hEff);
        final angle = engine.pitchDown * 180 / 3.14159265;
        return Stack(children: [
          // gradient is visual only – taps pass through to the camera
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.88)],
                  ),
                ),
              ),
            ),
          ),
          Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, pad + 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // mode chips
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final m in MMode.values) ...[
                    _modeChip(m),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              AnimatedSize(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutBack,
                child: done ? _resultCard() : _liveCard(liveD, angle),
              ),
              const SizedBox(height: 10),
              Text(_instruction,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              if (mode == MMode.room && !done) ...[
                OutlinedButton.icon(
                  onPressed: _autoCorners,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('AUTO-DETECT CORNERS'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    foregroundColor: AppColors.successGreen,
                    side: const BorderSide(color: AppColors.successGreen),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: _smallBtn(Icons.undo, 'Undo', points.isEmpty ? null : _undo),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: done
                        ? ElevatedButton.icon(
                            onPressed: _save,
                            icon: const Icon(Icons.check),
                            label: const Text('SAVE'),
                          )
                        : _glowWrap(
                            ElevatedButton.icon(
                              onPressed: _addPoint,
                              icon: Icon(mode == MMode.room || points.isEmpty
                                  ? Icons.add_location_alt_outlined
                                  : Icons.flag_outlined),
                              label: Text(_pointButtonLabel()),
                            ),
                            strong: points.isNotEmpty,
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: mode == MMode.room && !done
                        ? _smallBtn(Icons.crop_square, 'Close', points.length >= 3 ? _closeRoom : null)
                        : _smallBtn(Icons.refresh, 'Reset', _reset),
                  ),
                ],
              ),
            ],
          ),
          ),
        ]);
      },
    );
  }

  String _pointButtonLabel() {
    if (mode == MMode.height) return points.isEmpty ? 'SET BASE' : 'SET TOP';
    if (mode == MMode.distance) return points.isEmpty ? 'SET START' : 'SET END';
    return 'ADD POINT';
  }

  /// Soft pulsing glow behind a button; stronger while the next tap finishes something.
  Widget _glowWrap(Widget child, {bool strong = false}) {
    if (!prefs.animations) return child;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, c) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentCyan.withOpacity((strong ? 0.22 : 0.08) + 0.30 * _pulse.value),
              blurRadius: 12 + 14 * _pulse.value,
            ),
          ],
        ),
        child: c,
      ),
      child: child,
    );
  }

  /// Fade + slide entrance for the top bar and bottom panel.
  Widget _slideIn(Offset from, Widget child) {
    if (!prefs.animations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, v, c) => Opacity(
        opacity: v.clamp(0.0, 1.0).toDouble(),
        child: Transform.translate(offset: Offset(from.dx * (1 - v), from.dy * (1 - v)), child: c),
      ),
      child: child,
    );
  }

  Widget _smallBtn(IconData i, String label, VoidCallback? onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(i, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: Colors.white,
        side: BorderSide(color: onTap == null ? Colors.white24 : Colors.white54),
      ),
    );
  }

  Widget _modeChip(MMode m) {
    final sel = mode == m;
    final names = {MMode.distance: 'Distance', MMode.room: 'Room', MMode.height: 'Height'};
    final icons = {MMode.distance: Icons.straighten, MMode.room: Icons.crop_square, MMode.height: Icons.height};
    return GestureDetector(
      onTap: () {
        if (mode != m) {
          _buzz();
          _reset(newMode: m);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutBack,
        padding: EdgeInsets.symmetric(horizontal: sel ? 16 : 12, vertical: 9),
        decoration: BoxDecoration(
          color: sel ? AppColors.accentCyan : Colors.white12,
          borderRadius: BorderRadius.circular(22),
          boxShadow: sel ? [BoxShadow(color: AppColors.accentCyan.withOpacity(0.5), blurRadius: 14)] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icons[m], size: 18, color: sel ? Colors.black : Colors.white),
            const SizedBox(width: 6),
            Text(names[m]!,
                style: TextStyle(
                    color: sel ? Colors.black : Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _liveCard(double? liveD, double angleDeg) {
    final txt = !engine.sensorsAvailable
        ? '—'
        : liveD == null
            ? (mode == MMode.height && points.isNotEmpty ? 'Aim at the top' : 'Aim lower ↓')
            : 'Crosshair is ${prefs.len(liveD)} away';
    return Container(
      key: const ValueKey('live'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(txt,
                style: const TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          Text('tilt ${angleDeg.toStringAsFixed(0)}°  •  pts ${points.length}',
              style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
        ],
      ),
    );
  }

  /// Typical (1-sigma) error of the current result in metres, from the error model.
  double? _resultSigma() {
    if (points.length < 2) return null;
    if (mode == MMode.distance) return MeasureError.segmentSigma(points[0], points[1], hEff);
    if (mode == MMode.height) {
      final base = points[0], top = points[1];
      final d = math.sqrt(base.e * base.e + base.n * base.n);
      if (d < 0.05) return null;
      return MeasureError.heightSigma(d, math.atan2(top.u, d), hEff);
    }
    return null;
  }

  Widget _resultCard() {
    return ScaleTransition(
      key: const ValueKey('result'),
      scale: CurvedAnimation(parent: _result, curve: Curves.elasticOut),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.75),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.successGreen.withOpacity(0.7), width: 1.5),
          boxShadow: [BoxShadow(color: AppColors.successGreen.withOpacity(0.35), blurRadius: 24)],
        ),
        child: Column(
          children: [
            CountText(
              value: mode == MMode.room ? (resultArea ?? 0) : resultMeters,
              format: (v) => mode == MMode.room ? prefs.area(v) : prefs.len(v),
              style: const TextStyle(
                  fontSize: 44, fontWeight: FontWeight.w800, color: Colors.white, fontFamily: 'monospace'),
            ),
            if (_resultSigma() != null) ...[
              const SizedBox(height: 2),
              Text('typical error ${MeasureError.label(_resultSigma()!, prefs.len)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 13.5)),
              if (_resultSigma()! > resultMeters * 0.06 && resultMeters > 0)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Far points are less exact. Stand 2-4 m away for the best accuracy.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.warningAmber, fontSize: 12.5)),
                ),
            ],
            if (mode == MMode.room)
              Text('Perimeter ${prefs.len(resultPerimeter ?? 0)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 15)),
            if (mode == MMode.distance)
              TextButton.icon(
                onPressed: _calibrate,
                icon: const Icon(Icons.tune, size: 18),
                label: Text(prefs.scaleCal == 1.0 ? 'Calibrate once for best accuracy' : 'Not exact? Calibrate'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tip {
  final IconData icon;
  final String title;
  final String text;
  final Color color;
  final bool wiggle;
  const _Tip(this.icon, this.title, this.text, this.color, this.wiggle);
}
