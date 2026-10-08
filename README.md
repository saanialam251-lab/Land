# Measure Reality – AR Precision Measurement App

**Expanded Build Spec v2** implementation in Flutter.


## Platform

**Android only.** iOS is not included.

## First-time setup

```bash
./tool/bootstrap_platforms.sh
# or:
flutter create . --project-name measure_reality --org com.measurereality --platforms=android
flutter pub get
flutter test
flutter build apk --release
```

Do **not** run `flutter build ios` — this project is Android-only.


## Golden Rules (apply to everything)

1. The endpoint is **never** auto-locked. Only the SET END POINT button (or a deliberate tap) commits it.
2. One obvious primary action on screen at every state. Secondary actions stay small.
3. Never show fake precision. Every number carries a confidence level and an error range.
4. UI never touches the AR render loop. Heavy work runs off the main thread / isolates.
5. Every feature works offline.

## Architecture

```
lib/
├── core/          units, fractions, perf governor, logger
├── measure/       pure Dart (geometry, filters, confidence, models)
├── ar/            native channel provider + mock
├── state/         measure_controller + mode handlers
├── data/          settings, repositories, exporters
├── feedback/      haptics, sound, voice
└── ui/            theme, painters, screens, sheets, widgets
```

Native bridges live in `native/android/` and `native/ios/` and are copied into the platform folders by `tool/patch_platforms.sh`.

## Phases

| Phase | Scope |
|-------|-------|
| **P1** | Core engine, Distance + basic modes, Home, Measure, History, Settings, CI |
| **P2** | Snap, Grid, Level/Vertical, mode handlers split, sensor fusion |
| **P3** | Room scan, Object mode, calibration, plane fitting, depth |
| **P4** | Tutorial, help sheets, haptics/sound/voice, quality governor, debug |
| **P5** | Export (PDF/CSV/JSON/PNG/SVG), projects, compare, estimators, video |
| **P6** | Replay tests, device matrix, release workflow |

**Build Phase 1 and validate accuracy + FPS before adding visual polish or advanced modes.**

## Getting Started

```bash
flutter pub get
./tool/patch_platforms.sh
flutter run
```

## CI

- `.github/workflows/android-apk.yml` – build + test + APK
- `.github/workflows/release.yml` – tagged release (P6)

## Accuracy Notes (shown in-app)

Phone AR measurement is typically within 1–3 % in good conditions.  
LiDAR/ToF devices are better; depth-less devices are worse at long range.  
The app labels “Estimate” for trig height, room scans, and any measurement without depth or plane support.  
Not a replacement for certified instruments where legal/safety-critical accuracy is required.

## Accounts (Supabase login)

1. Create a project at supabase.com.
2. Dashboard → **SQL Editor** → New query → paste everything from `supabase/setup.sql` → **Run**.
3. Dashboard → **Project Settings → API** → copy the *Project URL* and the *anon / publishable* key.
4. Paste them into `lib/config/supabase_config.dart` (the only file to edit).

Login uses the **first word** of the name (capitals ignored) plus the phone number.
Each account has its **own history stored in the database**: log in on any phone (or after reinstalling) and the same history appears. Saves made offline upload automatically later.
The tables are locked: the app can only call the functions in `supabase/setup.sql`, and history functions need the secret session token created at login.

## Getting the most accurate measurements

- Set **Phone height** in Settings (height of the camera above the floor), then tap **Calibrate** once on a known length (a tape measure). This fixes every later measurement.
- Stand still and wait for the crosshair to turn **green** ("Steady") before tapping. The app measures from the steady reading just *before* your finger touched the screen.
- Stay 2–4 m from the points. Error grows quickly with distance (d = h / tan a), so the result card shows a *typical error* next to the value.
- The camera field of view is read from your phone automatically (Settings → Camera field of view).
