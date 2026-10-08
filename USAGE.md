# Measure Reality – how to use

1. Open the app → **Quick Measure** → tap **Allow** on the camera pop-up.
2. Settings → **Phone height**: set the real height of your phone above the floor (default 1.4 m).
3. Stand still. **Touch** the start point on the floor, then **touch** the end point. Far away? Pinch with two fingers (or let Auto zoom do it) and touch the exact corner. The line + length appear.
   * **Room** mode: tap **AUTO-DETECT CORNERS** (or touch each corner), fix with Undo, tap **CLOSE** → area + perimeter.
   * **Height** mode: base on floor, then tilt up to the top → **SET TOP**.
5. **Calibrate** (result card) with a known length to remove systematic error. **SAVE** keeps it in History.

Right-side buttons: auto zoom · corner assist · live maths panel. Warning boxes appear if you move too fast, a point is too far, or it is too dark.

Buttons on the camera: back · zoom chip (pinch with 2 fingers) · flashlight · camera quality · help.

## How it measures
Accelerometer gives tilt, gyroscope gives turning. A floor point seen `α` below the horizon from height `h` is
`h / tan α` away; two points + the turn angle give their distance (law of cosines).
Accuracy ≈ 2–5 % up to ~5 m. It is NOT a laser: walking between points, wrong phone height, or aiming near the horizon give errors.

## Why things fail → see the in-app **Not working?** button (home, top right) and the (i) button next to every setting.
