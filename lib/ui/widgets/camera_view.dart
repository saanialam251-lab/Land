import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../measure/corner_detector.dart';
import '../../data/app_prefs.dart';

enum CamState { checking, denied, permanentlyDenied, noCamera, ready, error }

/// Owns the camera: permission, preview, flashlight, zoom, quality.
class CamController extends ChangeNotifier with WidgetsBindingObserver {
  CameraController? controller;
  CamState state = CamState.checking;
  String error = '';
  bool torch = false;
  bool torchSupported = true;
  double zoom = 1.0;
  double minZoom = 1.0;
  double maxZoom = 1.0;
  bool _busy = false;
  bool _disposed = false;

  // Live image analysis (corner assist + light check)
  List<Corner> corners = const [];
  double brightness = 128;
  int imgW = 4, imgH = 3;
  int _lastProc = 0;

  /// Map a detected corner (image coords) to screen pixels for a cover-fitted
  /// portrait preview of the landscape sensor image.
  Offset cornerToScreen(Corner c, Size s) {
    final w = imgW.toDouble(), h = imgH.toDouble();
    final nx = 1 - c.y, ny = c.x;
    final scale = (s.width / h) > (s.height / w) ? s.width / h : s.height / w;
    return Offset(s.width / 2 + (nx - 0.5) * h * scale, s.height / 2 + (ny - 0.5) * w * scale);
  }

  void _onImage(CameraImage img) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastProc < 280) return;
    _lastProc = now;
    try {
      final p = img.planes[0];
      final r = CornerDetector.detect(p.bytes, img.width, img.height, p.bytesPerRow);
      corners = r.corners;
      brightness = r.brightness;
      imgW = img.width;
      imgH = img.height;
      _notify();
    } catch (_) {}
  }

  static const _presets = [
    ResolutionPreset.low,
    ResolutionPreset.medium,
    ResolutionPreset.high,
    ResolutionPreset.veryHigh,
    ResolutionPreset.max,
  ];

  CamController() {
    WidgetsBinding.instance.addObserver(this);
    torch = AppPrefs.I.keepFlashOn;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.inactive || s == AppLifecycleState.paused) {
      _release();
    } else if (s == AppLifecycleState.resumed) {
      if (controller == null) init();
    }
  }

  Future<void>? _releasing;

  Future<void> _release() {
    final f = _doRelease();
    _releasing = f;
    return f;
  }

  Future<void> _doRelease() async {
    final c = controller;
    controller = null;
    if (c != null) {
      state = CamState.checking;
      _notify();
      try {
        await c.dispose();
      } catch (_) {}
    }
  }

  Future<void> init() async {
    if (_busy || _disposed) return;
    _busy = true;
    try {
      await _releasing;
    } catch (_) {}
    if (_disposed) {
      _busy = false;
      return;
    }
    state = CamState.checking;
    _notify();
    try {
      var status = await Permission.camera.status;
      if (!status.isGranted) {
        status = await Permission.camera.request(); // system pop-up
      }
      if (status.isPermanentlyDenied || status.isRestricted) {
        state = CamState.permanentlyDenied;
        return;
      }
      if (!status.isGranted) {
        state = CamState.denied;
        return;
      }

      final cams = await availableCameras();
      if (cams.isEmpty) {
        state = CamState.noCamera;
        return;
      }
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );

      late CameraController c;
      var level = AppPrefs.I.cameraQuality;
      while (true) {
        c = CameraController(back, _presets[level],
            enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
        try {
          await c.initialize();
          break;
        } on CameraException {
          await c.dispose();
          if (level == 0) rethrow;
          level--; // this phone can't do that quality – step down
        }
      }
      if (_disposed) {
        await c.dispose();
        return;
      }
      try {
        minZoom = await c.getMinZoomLevel();
        maxZoom = await c.getMaxZoomLevel();
      } catch (_) {
        minZoom = 1;
        maxZoom = 1;
      }
      zoom = zoom.clamp(minZoom, maxZoom).toDouble();
      try {
        await c.setZoomLevel(zoom);
      } catch (_) {}
      controller = c;
      state = CamState.ready;
      try {
        await c.startImageStream(_onImage);
      } catch (_) {}
      if (torch) await _applyTorch();
    } on CameraException catch (e) {
      error = '${e.code}: ${e.description ?? ''}';
      state = (e.code == 'CameraAccessDenied' || e.code == 'CameraAccessDeniedWithoutPrompt')
          ? CamState.permanentlyDenied
          : CamState.error;
    } catch (e) {
      error = '$e';
      state = CamState.error;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> _applyTorch() async {
    final c = controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.setFlashMode(torch ? FlashMode.torch : FlashMode.off);
      torchSupported = true;
    } catch (_) {
      torch = false;
      torchSupported = false;
    }
  }

  Future<void> toggleTorch() async {
    torch = !torch;
    await _applyTorch();
    _notify();
  }

  Future<void> setZoom(double z) async {
    final c = controller;
    if (c == null) return;
    zoom = z.clamp(minZoom, maxZoom).toDouble();
    _notify();
    try {
      await c.setZoomLevel(zoom);
    } catch (_) {}
  }

  /// Apply a new quality from Settings/quality sheet (restarts the camera).
  Future<void> applyQuality() async {
    await _release();
    await init();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final c = controller;
    controller = null;
    c?.dispose();
    super.dispose();
  }
}

/// Renders the preview or a friendly message for every failure case.
class CameraView extends StatelessWidget {
  final CamController cam;
  const CameraView({super.key, required this.cam});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: cam,
      builder: (context, _) {
        switch (cam.state) {
          case CamState.ready:
            final c = cam.controller;
            if (c == null || !c.value.isInitialized || c.value.previewSize == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: c.value.previewSize!.height,
                  height: c.value.previewSize!.width,
                  child: CameraPreview(c),
                ),
              ),
            );
          case CamState.checking:
            return const Center(child: CircularProgressIndicator());
          case CamState.denied:
            return _Message(
              icon: Icons.camera_alt_outlined,
              text: 'Camera permission is needed to measure.\nTap the button and choose "Allow".',
              button: 'Allow camera',
              onPressed: cam.init,
            );
          case CamState.permanentlyDenied:
            return _Message(
              icon: Icons.no_photography_outlined,
              text: 'Camera access is blocked.\nOpen Settings → Permissions → Camera → Allow, then come back.',
              button: 'Open phone Settings',
              onPressed: () => openAppSettings(),
            );
          case CamState.noCamera:
            return _Message(
              icon: Icons.videocam_off_outlined,
              text: 'No camera found on this device.',
              button: 'Try again',
              onPressed: cam.init,
            );
          case CamState.error:
            return _Message(
              icon: Icons.error_outline,
              text: 'Could not start the camera.\nClose other apps using the camera and try again.\n\n${cam.error}',
              button: 'Try again',
              onPressed: cam.init,
            );
        }
      },
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final String button;
  final VoidCallback onPressed;

  const _Message({
    required this.icon,
    required this.text,
    required this.button,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4)),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onPressed, child: Text(button)),
          ],
        ),
      ),
    );
  }
}
