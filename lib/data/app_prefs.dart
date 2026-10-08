import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DispUnit { m, cm, ft, inch }

/// Global, persistent app settings. Every screen listens to this
/// (ChangeNotifier) so a change in Settings shows up instantly everywhere.
class AppPrefs extends ChangeNotifier {
  AppPrefs._();
  static final AppPrefs I = AppPrefs._();

  DispUnit unit = DispUnit.m;
  int decimals = 2; // 0..3
  /// 0=low 1=medium 2=high 3=veryHigh 4=max
  int cameraQuality = 2;
  double phoneHeight = 1.4; // metres – height of the phone above the floor
  double fovDeg = 65; // manual vertical field of view (used when auto-detect is off / unavailable)
  bool fovAuto = true; // use the FOV read from the camera hardware
  double? detectedFovDeg; // real FOV from the phone's camera, once detected

  /// The field of view actually used for tapped points and the drawn lines.
  double get fov => (fovAuto && detectedFovDeg != null) ? detectedFovDeg! : fovDeg;

  static const _camChannel = MethodChannel('measure_reality/camera_info');

  /// Asks Android for the real camera field of view (silently ignored if unavailable).
  Future<void> detectFov() async {
    if (detectedFovDeg != null) return;
    try {
      final v = await _camChannel.invokeMethod<double>('getFovDeg');
      if (v != null && v > 30 && v < 120) {
        detectedFovDeg = v;
        notifyListeners();
        await _save();
      }
    } catch (_) {}
  }
  double scaleCal = 1.0; // calibration multiplier (reference-length trick)
  bool haptics = true;
  bool grid = true;
  bool animations = true;
  bool keepFlashOn = false;
  bool autoZoom = true;
  bool cornerAssist = true;

  static const qualityNames = ['Low', 'Medium', 'High', 'Very high', 'Max'];

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      unit = DispUnit.values[(p.getInt('unit') ?? 0).clamp(0, DispUnit.values.length - 1).toInt()];
      decimals = (p.getInt('decimals') ?? 2).clamp(0, 3).toInt();
      cameraQuality = (p.getInt('cameraQuality') ?? 2).clamp(0, 4).toInt();
      phoneHeight = p.getDouble('phoneHeight') ?? 1.4;
      fovDeg = p.getDouble('fovDeg') ?? 65;
      fovAuto = p.getBool('fovAuto') ?? true;
      detectedFovDeg = p.getDouble('detectedFov');
      scaleCal = p.getDouble('scaleCal') ?? 1.0;
      haptics = p.getBool('haptics') ?? true;
      grid = p.getBool('grid') ?? true;
      animations = p.getBool('animations') ?? true;
      keepFlashOn = p.getBool('keepFlashOn') ?? false;
      autoZoom = p.getBool('autoZoom') ?? true;
      cornerAssist = p.getBool('cornerAssist') ?? true;
    } catch (_) {
      // Storage unavailable – keep defaults, app still works.
    }
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('unit', unit.index);
      await p.setInt('decimals', decimals);
      await p.setInt('cameraQuality', cameraQuality);
      await p.setDouble('phoneHeight', phoneHeight);
      await p.setDouble('fovDeg', fovDeg);
      await p.setBool('fovAuto', fovAuto);
      final df = detectedFovDeg;
      if (df != null) await p.setDouble('detectedFov', df);
      await p.setDouble('scaleCal', scaleCal);
      await p.setBool('haptics', haptics);
      await p.setBool('grid', grid);
      await p.setBool('animations', animations);
      await p.setBool('keepFlashOn', keepFlashOn);
      await p.setBool('autoZoom', autoZoom);
      await p.setBool('cornerAssist', cornerAssist);
    } catch (_) {}
  }

  void update(void Function() change) {
    change();
    notifyListeners();
    _save();
  }

  void reset() {
    update(() {
      unit = DispUnit.m;
      decimals = 2;
      cameraQuality = 2;
      phoneHeight = 1.4;
      fovAuto = true;
      fovDeg = 65;
      scaleCal = 1.0;
      haptics = true;
      grid = true;
      animations = true;
      keepFlashOn = false;
      autoZoom = true;
      cornerAssist = true;
    });
  }

  /// Format metres in the user's chosen unit.
  String len(double meters) {
    switch (unit) {
      case DispUnit.m:
        return '${meters.toStringAsFixed(decimals)} m';
      case DispUnit.cm:
        return '${(meters * 100).toStringAsFixed(decimals > 1 ? 1 : decimals)} cm';
      case DispUnit.ft:
        return '${(meters / 0.3048).toStringAsFixed(decimals)} ft';
      case DispUnit.inch:
        return '${(meters / 0.0254).toStringAsFixed(decimals > 1 ? 1 : decimals)} in';
    }
  }

  String area(double sqMeters) {
    switch (unit) {
      case DispUnit.m:
      case DispUnit.cm:
        return '${sqMeters.toStringAsFixed(decimals)} m²';
      case DispUnit.ft:
      case DispUnit.inch:
        return '${(sqMeters / 0.09290304).toStringAsFixed(decimals)} ft²';
    }
  }

  static String unitName(DispUnit u) {
    switch (u) {
      case DispUnit.m:
        return 'Metres';
      case DispUnit.cm:
        return 'Centimetres';
      case DispUnit.ft:
        return 'Feet';
      case DispUnit.inch:
        return 'Inches';
    }
  }
}
