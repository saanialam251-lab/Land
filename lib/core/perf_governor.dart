/// Adaptive Quality Governor – Section 2.4
/// Thermal + battery + FPS driven.
/// User sees a small "Performance: Balanced" chip only when level changes, never a popup.
enum QualityLevel {
  full, // 0 – stable 60 FPS
  balanced, // 1 – FPS < 50
  lean, // 2 – FPS < 40 or device hot
  safe, // 3 – severe thermal throttling
}

class QualityState {
  final QualityLevel level;
  final String label;
  final bool showChip;

  const QualityState({
    this.level = QualityLevel.full,
    this.label = 'Performance: Full',
    this.showChip = false,
  });

  QualityState copyWith({
    QualityLevel? level,
    String? label,
    bool? showChip,
  }) {
    return QualityState(
      level: level ?? this.level,
      label: label ?? this.label,
      showChip: showChip ?? this.showChip,
    );
  }
}

class PerfGovernor {
  QualityState _state = const QualityState();
  QualityLevel _lastLevel = QualityLevel.full;
  int _consecutiveOverBudget = 0;

  QualityState get state => _state;

  /// Call every frame with measured frame time (ms) and thermal flags.
  void onFrame({
    required double frameTimeMs,
    required bool isDeviceHot,
    required bool isThermalThrottling,
  }) {
    if (frameTimeMs > 16.6) {
      _consecutiveOverBudget++;
    } else {
      _consecutiveOverBudget = 0;
    }

    QualityLevel newLevel;
    if (isThermalThrottling) {
      newLevel = QualityLevel.safe;
    } else if (isDeviceHot ||
        (_consecutiveOverBudget >= 10 && frameTimeMs > 25)) {
      newLevel = QualityLevel.lean;
    } else if (_consecutiveOverBudget >= 10 || frameTimeMs > 20) {
      newLevel = QualityLevel.balanced;
    } else {
      newLevel = QualityLevel.full;
    }

    if (newLevel != _lastLevel) {
      _lastLevel = newLevel;
      _state = QualityState(
        level: newLevel,
        label: 'Performance: ${_label(newLevel)}',
        showChip: true,
      );
    }
  }

  void hideChip() {
    _state = _state.copyWith(showChip: false);
  }

  // -- Capability queries ------------------------------------------

  bool get allowBlur => _lastLevel == QualityLevel.full;
  bool get allowParticles =>
      _lastLevel == QualityLevel.full || _lastLevel == QualityLevel.balanced;
  bool get allowFeaturePoints =>
      _lastLevel == QualityLevel.full || _lastLevel == QualityLevel.balanced;
  bool get allowMarkerPulse => _lastLevel == QualityLevel.full;

  int get targetFps {
    switch (_lastLevel) {
      case QualityLevel.lean:
      case QualityLevel.safe:
        return 30;
      default:
        return 60;
    }
  }

  int get depthHz {
    switch (_lastLevel) {
      case QualityLevel.full:
        return 30;
      default:
        return 15;
    }
  }

  String _label(QualityLevel l) {
    switch (l) {
      case QualityLevel.full:
        return 'Full';
      case QualityLevel.balanced:
        return 'Balanced';
      case QualityLevel.lean:
        return 'Lean';
      case QualityLevel.safe:
        return 'Safe';
    }
  }
}
