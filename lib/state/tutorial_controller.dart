/// Tutorial controller – P4
/// Step-by-step guided demos for each mode.
class TutorialStep {
  final String title;
  final String body;
  final String? assetPath; // assets/tutorial/...
  final String? voicePrompt;

  const TutorialStep({
    required this.title,
    required this.body,
    this.assetPath,
    this.voicePrompt,
  });
}

class TutorialController {
  int currentIndex = 0;
  List<TutorialStep> steps = const [];

  bool get isActive => steps.isNotEmpty;
  bool get isFirst => currentIndex == 0;
  bool get isLast => currentIndex >= steps.length - 1;
  TutorialStep? get current =>
      steps.isEmpty ? null : steps[currentIndex.clamp(0, steps.length - 1).toInt()];

  void start(List<TutorialStep> newSteps) {
    steps = newSteps;
    currentIndex = 0;
  }

  void next() {
    if (!isLast) currentIndex++;
  }

  void previous() {
    if (!isFirst) currentIndex--;
  }

  void skip() {
    steps = const [];
    currentIndex = 0;
  }

  void complete() {
    steps = const [];
    currentIndex = 0;
  }

  // -- Pre-built tutorials -----------------------------------------

  static const distanceTutorial = [
    TutorialStep(
      title: 'Distance',
      body: 'Point at the first corner or edge, then tap START.',
      voicePrompt: 'Point at the first point, then tap start',
    ),
    TutorialStep(
      title: 'Move to endpoint',
      body: 'Slowly move the phone to the second point. The line updates live.',
      voicePrompt: 'Move to the endpoint',
    ),
    TutorialStep(
      title: 'Set end point',
      body: 'When the reticle is green, tap SET END POINT. The endpoint is never auto-locked.',
      voicePrompt: 'Tap set end point',
    ),
  ];

  static const roomTutorial = [
    TutorialStep(
      title: 'Scan the floor',
      body: 'Point at the floor and move slowly to cover the room.',
    ),
    TutorialStep(
      title: 'Scan the walls',
      body: 'Slowly turn to capture each wall. Corners will snap automatically.',
    ),
    TutorialStep(
      title: 'Scan the ceiling',
      body: 'Look up to capture ceiling height for volume.',
    ),
  ];

  static const levelTutorial = [
    TutorialStep(
      title: 'Surface mode',
      body: 'Place the phone edge on the object to check if it is level.',
    ),
    TutorialStep(
      title: 'Camera mode',
      body: 'Point at a surface to read its tilt from the plane.',
    ),
    TutorialStep(
      title: 'Calibrate',
      body: 'Place on a known flat surface and tap Calibrate to zero the offset.',
    ),
  ];
}
