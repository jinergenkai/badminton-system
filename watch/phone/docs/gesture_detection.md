# Gesture Detection — Technical Documentation

> **Feature:** Hand-gesture scoring input for the Badminton Score app
> **Platform:** Android only (hand_landmarker uses a JNI bridge to MediaPipe)
> **Status:** Implemented & tuned

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [File Reference](#3-file-reference)
4. [Pipeline Deep-Dive](#4-pipeline-deep-dive)
5. [Coordinate System — Critical Section](#5-coordinate-system--critical-section)
6. [Gesture Classification Logic](#6-gesture-classification-logic)
7. [Smoothing & Timing](#7-smoothing--timing)
8. [Performance Decisions](#8-performance-decisions)
9. [Debug Overlay](#9-debug-overlay)
10. [Integration with Scoring](#10-integration-with-scoring)
11. [Known Issues & Solutions](#11-known-issues--solutions)
12. [Tuning Guide](#12-tuning-guide)
13. [Future Improvements](#13-future-improvements)

---

## 1. Overview

The phone is mounted on a net post or referee chair. One player signals with their hand after each rally. The camera runs silently in the background, detects the gesture, and calls the same scoring functions used by voice and manual tap.

| Gesture | Hold | Action |
|---|---|---|
| 👍 Thumbs Up | 800 ms | `incrementTeamA()` |
| 👎 Thumbs Down | 800 ms | `incrementTeamB()` |
| 🖐 Open Palm | 1 200 ms | `undo()` |

A **3-second cooldown** after any trigger prevents double-scoring.

---

## 2. Architecture

```
CameraController (ResolutionPreset.low)
        │  YUV420 frames @ max 10 fps
        ▼
HandLandmarkerPlugin.detect(image, sensorOrientation)
        │  List<Hand>  (21 Landmark points, normalized 0–1)
        ▼
_toCanonical(landmarks, sensorOrientation)
        │  remaps to portrait space  (up = small y)
        ▼
GestureClassifier.classify(landmarks)
        │  HandGesture enum
        ▼
GestureSmoother.update(gesture)
        │  GestureEvent?  (fires only after hold threshold met)
        ▼
ScoreController._handleGestureEvent(event)
        │
        ├──► incrementTeamA(fromVoice: true)
        ├──► incrementTeamB(fromVoice: true)
        └──► undo()
```

**Streams:**

| Stream | Type | Consumers |
|---|---|---|
| `gestureEvents` | `GestureEvent` | `ScoreController` |
| `frameDataStream` | `GestureFrameData` | `GestureStatusIndicator`, `GestureCameraWidget` (debug) |

The `frameDataStream` only emits when gesture or hold-progress changes by > 2%, preventing unnecessary `setState()` rebuilds.

---

## 3. File Reference

```
lib/
├── controllers/
│   └── score_controller.dart          ← subscribes to gestureEvents
├── services/
│   └── gesture_detection/
│       ├── gesture_detection_service.dart   ← camera + detection pipeline
│       ├── gesture_classifier.dart          ← rule-based 21-point classifier
│       ├── gesture_smoother.dart            ← sliding window + hold timer
│       ├── gesture_overlay_painter.dart     ← CustomPainter for debug mode
│       ├── gesture_camera_widget.dart       ← debug overlay + status indicator
│       └── models/
│           ├── hand_gesture.dart            ← HandGesture enum
│           └── gesture_event.dart           ← GestureEvent, GestureFrameData
├── widgets/
│   └── gesture_indicator.dart         ← bottom-bar button in score screen
└── views/
    └── score_screen.dart              ← mounts Stack with debug overlay
```

**Android:**

```
android/app/src/main/AndroidManifest.xml   ← CAMERA permission
android/app/build.gradle.kts              ← minSdk 24 (required by hand_landmarker)
```

**Dependencies added to `pubspec.yaml`:**

```yaml
hand_landmarker: ^2.1.1   # MediaPipe Hand Landmarker via JNI (Android only)
camera: ^0.11.0            # Camera stream
```

---

## 4. Pipeline Deep-Dive

### 4.1 Camera setup

```dart
CameraController(
  selected,
  ResolutionPreset.low,          // 320×240 — 4× less data than medium
  enableAudio: false,
  imageFormatGroup: ImageFormatGroup.yuv420,  // required by hand_landmarker JNI
)
```

`ResolutionPreset.low` was chosen deliberately. `hand_landmarker` passes raw YUV planes over JNI to the native MediaPipe runtime. At `medium` (720×480) the main isolate was blocked for ~150 ms per frame; at `low` (320×240) it is ~30–50 ms.

### 4.2 Frame throttle

```dart
// Inside startImageStream callback:
final nowMs = DateTime.now().millisecondsSinceEpoch;
if (nowMs - _lastProcessMs < 100) return;  // max 10 fps
_lastProcessMs = nowMs;
```

Camera callbacks dispatch on the **main Dart isolate**. The synchronous JNI call inside `detect()` blocks the isolate for the full detection time. Without throttling, even at low resolution, this could consume 100% of frame time at 30 fps. Capping at 10 fps (100 ms budget) leaves ~60–70 ms free per 100 ms window for Flutter to render.

### 4.3 detect() call

```dart
final hands = _handLandmarker!.detect(image, _sensorOrientation);
```

`detect()` is **synchronous**. It passes YUV planes to the native MediaPipe `HandLandmarker` task via JNI with `rotationDegrees = sensorOrientation`. The GPU delegate is used.

> **Important:** `detect()` returns landmarks in the **original unrotated sensor coordinate space** — not in the display (portrait) coordinate space. See §5 for the critical transform required before classification.

### 4.4 Primary hand selection

When multiple hands are detected, the one with the largest bounding box area (computed from min/max of landmark x/y) is used. This selects the hand closest to the camera.

---

## 5. Coordinate System — Critical Section

This is the most important architectural detail. Getting it wrong produces systematically incorrect classifications (e.g., open palm detected as thumbs down, thumbs up as open palm).

### 5.1 What hand_landmarker returns

`detect(image, sensorOrientation)` passes `sensorOrientation` as `rotationDegrees` to the MediaPipe native task, which **physically rotates the YUV image** before inference. However, **the landmark coordinates are returned in the original unrotated sensor coordinate space** — i.e., the landscape frame the camera naturally captures.

For a typical Android back camera (`sensorOrientation = 90`):

```
Raw sensor frame (landscape, e.g. 1280×720):

  x=0 ──────────────────────── x=1
  │                              │
  │  ← LEFT SIDE OF PHONE        │
  │     (landscape image left)   │
y=0                              │
  │                              │
  │  → RIGHT SIDE OF PHONE       │
  │     (landscape image right)  │
y=1 ──────────────────────────

  x=0 = BOTTOM of phone (portrait)
  x=1 = TOP of phone (portrait)
  y=0 = RIGHT side (portrait)
  y=1 = LEFT side (portrait)
```

**Consequence:** for a thumbs-up gesture in portrait mode, the thumb tip is at the **TOP** of the phone = **small `lm.x`** in sensor space — not small `lm.y` as a naive implementation would assume.

### 5.2 The overlay painter (display)

`GestureOverlayPainter` handles display by rotating the canvas:

```dart
canvas.rotate(sensorOrientation * math.pi / 180);
canvas.scale(size.width / previewSize.height);
// draw landmark at (lm.x - 0.5) * previewSize.width, (lm.y - 0.5) * previewSize.height
```

This makes the visual overlay correct. **But it has no effect on the classifier**, which receives raw coordinates.

### 5.3 _toCanonical() — the fix

Before classification, all landmarks are remapped to **canonical portrait space** where `y = 0` is screen-top and `y = 1` is screen-bottom:

```dart
List<Landmark> _toCanonical(List<Landmark> lms, int sensorOrientation) {
  switch (sensorOrientation) {
    case 90:   return lms.map((l) => Landmark(l.y, l.x,       l.z)).toList();
    case 180:  return lms.map((l) => Landmark(1-l.x, 1-l.y,  l.z)).toList();
    case 270:  return lms.map((l) => Landmark(l.y, 1-l.x,    l.z)).toList();
    default:   return lms;   // 0° — identity
  }
}
```

**Derivation for each case:**

After `canvas.rotate(θ)` in Flutter (CW rotation), the direction that maps to screen-top tells us which raw axis becomes canonical-y:

| sensorOrientation | canvas rotation | screen-UP direction | canonical_y formula |
|---|---|---|---|
| 0° | none | canvas −y | `lm.y` (identity) |
| 90° | 90° CW | canvas −x | `lm.x` |
| 180° | 180° | canvas +y | `1 − lm.y` |
| 270° | 270° CW | canvas +x | `1 − lm.x` |

**Verification (90°, thumbs-up):**
- Thumb tip at screen-TOP → small `lm.x` in sensor space
- After transform: `canonical_y = lm.x` → small → **correct** (top = small y)
- Folded index finger: tip is screen-BELOW pip → `tip.lm.x > pip.lm.x` → `tip.canonical_y > pip.canonical_y` → `tip < pip` is **false** → correctly detected as **folded**

> **Note:** `_toCanonical` only changes which axis is used for classification. The raw (untransformed) landmarks are always passed to `GestureFrameData` for the debug painter, which applies its own canvas rotation.

---

## 6. Gesture Classification Logic

`GestureClassifier` is a pure rule-based classifier. No ML model is required beyond the landmark positions provided by MediaPipe.

### 6.1 MediaPipe landmark indices

```
 0: WRIST
 1- 4: THUMB  (CMC → MCP → IP → TIP)
 5- 8: INDEX  (MCP → PIP → DIP → TIP)
 9-12: MIDDLE (MCP → PIP → DIP → TIP)
13-16: RING   (MCP → PIP → DIP → TIP)
17-20: PINKY  (MCP → PIP → DIP → TIP)
```

### 6.2 Finger extension (non-thumb)

```dart
// In canonical space: y=0 is screen-top
// Extended (pointing up) → TIP.y < PIP.y
bool _isFingerExtended(landmarks, tipIdx, pipIdx) =>
    landmarks[tipIdx].y < landmarks[pipIdx].y;
```

Called with: `(8,6)` index, `(12,10)` middle, `(16,14)` ring, `(20,18)` pinky.

### 6.3 Thumb extension

Uses 3D Euclidean distance (rotation-invariant):

```dart
bool _isThumbExtended(landmarks) {
  final tipToWrist = distance(landmarks[4], landmarks[0]);
  final mcpToWrist = distance(landmarks[2], landmarks[0]);
  return tipToWrist > mcpToWrist * 1.2;
}
```

`1.2×` threshold gives a safety margin against near-neutral thumb positions.

### 6.4 Thumb direction

```dart
// In canonical space: small y = UP
if (landmarks[4].y < landmarks[2].y - 0.04) → ThumbDirection.up
if (landmarks[4].y > landmarks[2].y + 0.04) → ThumbDirection.down
else                                         → ThumbDirection.neutral
```

`0.04` (normalized) is the dead-band threshold. It filters out the thumb being only slightly above/below MCP.

### 6.5 Decision tree

```
thumbExtended?
├── NO  → HandGesture.none
└── YES
    ├── allFingersFolded (index+middle+ring+pinky)?
    │   ├── thumbDirection == up   → HandGesture.thumbsUp
    │   ├── thumbDirection == down → HandGesture.thumbsDown
    │   └── neutral                → HandGesture.none
    └── allFingersExtended?
        ├── YES → HandGesture.openPalm
        └── NO  → HandGesture.none
```

---

## 7. Smoothing & Timing

### 7.1 Sliding window

`GestureSmoother` maintains a queue of the last **6 classified frames**. A gesture is considered *stable* when ≥ **65%** of the frames in the window agree.

```
Window (6 frames):  [👍, 👍, 👍, 👍, none, 👍]
Count of 👍 = 5 / 6 = 83% ≥ 65% → stable
```

Window size 6 at 10 fps = 600 ms of history. This filters single-frame noise without adding noticeable lag.

### 7.2 Hold timer

Once a gesture is stable, a hold timer starts. The gesture must remain stable for the full duration:

| Gesture | Hold required | Reason |
|---|---|---|
| 👍 / 👎 | 800 ms | Fast enough for court use |
| 🖐 Open Palm | 1 200 ms | Extra safety against accidental undo |

If the stable gesture changes mid-hold, the timer resets. This prevents drifting from one gesture to another counting as a hold.

### 7.3 Cooldown

After any trigger, **1 500 ms cooldown** blocks all further triggers. This prevents double-scoring from a slow hand movement. The cooldown is independent of the score controller's voice cooldown — both must be clear for a gesture to score.

### 7.4 Timing at a glance

```
Frame arrives
     ↓
Classify (instant, rule-based)
     ↓
Window fills: ~6 frames × 100ms = ~600ms to reach first stable reading
     ↓
Hold timer: 800ms (score) or 1200ms (undo)
     ─────────────────────────────────────────
     Earliest possible trigger: ~1.4s after gesture started
     Typical: ~1.6–2.0s (accounts for detection jitter)
     ─────────────────────────────────────────
     ↓
Trigger → 1500ms cooldown → ready again
```

---

## 8. Performance Decisions

| Decision | Value | Rationale |
|---|---|---|
| `ResolutionPreset` | `low` (320×240) | 4× less JNI data vs `medium`; hand detection accuracy is unchanged at 1–4m |
| Max detection FPS | 10 fps (100ms gate) | Main isolate blocked ~30–50ms; leaves 50–70ms/frame for UI rendering |
| `numHands` | 1 | Avoids running two full hand inference passes |
| `minHandDetectionConfidence` | 0.6 | Slightly lower than default 0.7 to compensate for lower resolution |
| `HandLandmarkerDelegate` | `GPU` | GPU delegate ~3–5× faster than CPU on modern Android |
| UI stream throttle | >2% hold change or gesture change | Stops the ~10 fps frameDataStream from triggering 10 `setState()`/s on two subscribers |

**Battery note:** Running camera + GPU ML inference continuously will drain battery. At a court session (~1–2 hours), expect ~20–30% additional drain. Users should be advised to enable gesture mode only when needed.

---

## 9. Debug Overlay

Activated by **long-pressing** the camera button in the score screen. A draggable preview window appears on top of the scoring UI.

### What it shows

```
┌─────────────────────────┐ FPS:10
│  [Camera Preview]       │
│                         │
│   ●──●──●──●            │  ← green = extended, red = folded
│  /   |                  │  ← white lines = skeleton connections
│ ●    ●──●──●            │
│  \   |                  │
│   ●──●──●──●            │
│                         │
│ 👍 THUMBS UP  83% stable│  ← gesture label + stability %
│ T:✓ I:✗ M:✗ R:✗ P:✗   │  ← per-finger states
│ Hold: 0.6s / 0.8s ████░│  ← hold progress bar
└─────────────────────────┘
[↺ flip camera]      FPS:10
```

### Overlay coordinate transform

The painter applies `canvas.rotate(sensorOrientation)` + scale before drawing landmarks, matching how `CameraPreview` displays the image. See §5.2 for the derivation.

The preview container uses `AspectRatio(previewSize.height / previewSize.width)` (note: height/width, not width/height) to match the portrait aspect ratio of the rotated camera output, preventing any letterboxing that would misalign the overlay.

### Connection list (MediaPipe standard)

```dart
[0,1],[1,2],[2,3],[3,4],           // Thumb
[0,5],[5,6],[6,7],[7,8],           // Index
[5,9],[9,10],[10,11],[11,12],      // Middle
[9,13],[13,14],[14,15],[15,16],    // Ring
[13,17],[0,17],[17,18],[18,19],[19,20], // Pinky
```

---

## 10. Integration with Scoring

`ScoreController` owns the `GestureDetectionService` and subscribes once when gesture is enabled:

```dart
Future<void> toggleGestureDetection() async {
  if (isGestureActive.value) {
    await _gestureService.stop();
    await _gestureSub?.cancel();
    isGestureActive.value = false;
  } else {
    await _gestureService.start(debugMode: isGestureDebugMode.value);
    _gestureSub = _gestureService.gestureEvents.listen(_handleGestureEvent);
    isGestureActive.value = true;
  }
}

void _handleGestureEvent(GestureEvent event) {
  if (!gameState.isGameActive || isCooldownActive.value) return;

  switch (event.gesture) {
    case HandGesture.thumbsUp:   incrementTeamA(fromVoice: true); break;
    case HandGesture.thumbsDown: incrementTeamB(fromVoice: true); break;
    case HandGesture.openPalm:   undo(); break;
    case HandGesture.none:       break;
  }
}
```

`fromVoice: true` is passed intentionally — it reuses the existing voice cooldown, TTS announcement, and foreground notification update paths. Gesture scoring is identical to voice scoring from the system's perspective.

**Shared cooldown:** `isCooldownActive.value` is checked before applying any gesture event. The score controller's 1 000 ms cooldown (started by `_startCooldown()`) thus also blocks gesture scoring during the cooldown window — preventing voice + gesture from stacking.

---

## 11. Known Issues & Solutions

### Issue 1 — Overlay rotated / misaligned

**Cause:** Naive `(x * width, y * height)` mapping ignores that landmark coordinates are in the raw landscape sensor space, not display/portrait space.

**Solution:** `GestureOverlayPainter` applies `canvas.rotate(sensorOrientation)` and draws landmarks centered at `(lm.x - 0.5) * previewSize.width`. The `AspectRatio` widget in the debug preview uses `previewSize.height / previewSize.width` (portrait ratio).

### Issue 2 — Gestures classified backwards (open palm → thumbs down, thumbs up → open palm)

**Cause:** `_isFingerExtended` checked `TIP.y < PIP.y` using raw sensor coordinates. For `sensorOrientation = 90`, "screen up" = small `lm.x`, so checking `y` tested the horizontal axis instead of vertical.

**Solution:** `_toCanonical()` remaps all landmarks to canonical portrait space before classification. For 90°: `(x,y) → (y, x)`. The y-axis checks in the classifier are then correct.

**The key mistake to avoid:** Using raw landmark coordinates for classification without accounting for `sensorOrientation`. This will always fail on standard Android back cameras (90°).

### Issue 3 — UI lag / frame drop

**Cause:** `detect()` is a synchronous JNI call running on the main Dart isolate. At `ResolutionPreset.medium` (~720×480), each call took ~150 ms, consuming all frame budget.

**Solution:**
- Dropped to `ResolutionPreset.low` (~320×240) → ~30–50 ms per call
- Added 100 ms frame gate → max 10 fps, ~60 ms free for UI between detections
- Throttled `frameDataStream` to emit only on meaningful state changes

---

## 12. Tuning Guide

All timing constants live in `gesture_smoother.dart`:

```dart
static const int windowSize = 6;               // frames in stability window
static const double stabilityThreshold = 0.65; // fraction needed to be "stable"
static const Duration holdDuration         = Duration(milliseconds: 800);
static const Duration holdDurationUndo     = Duration(milliseconds: 1200);
static const Duration cooldownAfterTrigger = Duration(milliseconds: 1500);
```

**If gestures trigger too easily / false positives:**
- Raise `stabilityThreshold` → 0.75–0.80
- Raise `holdDuration` → 1000–1200 ms
- Raise `windowSize` → 8

**If gestures feel sluggish / hard to trigger:**
- Lower `stabilityThreshold` → 0.60
- Lower `holdDuration` → 600 ms
- Lower `windowSize` → 5

**If double-scoring occurs:**
- Raise `cooldownAfterTrigger` → 2000–3000 ms

**Camera performance constants live in `gesture_detection_service.dart`:**

```dart
static const int _frameIntervalMs = 100;  // min ms between processed frames
```

Lower this (e.g. 66 ms = ~15 fps) if your device handles it without jank. Higher (e.g. 150 ms = ~7 fps) if still lagging.

**Classifier threshold in `gesture_classifier.dart`:**

```dart
static const double _thumbDirectionThreshold = 0.04;
```

Raise if thumbs-up/down is being confused when the thumb is only slightly tilted. Lower if the user needs to hold an extreme position to register direction.

---

## 13. Future Improvements

### High priority

- **iOS support:** `hand_landmarker` is Android-only. For iOS, implement a platform channel calling the MediaPipe iOS Swift SDK or Vision framework `VNDetectHumanHandPoseRequest`.
- **Background isolate:** Move `detect()` to a dedicated `Isolate` with a `ReceivePort` to avoid blocking the main isolate entirely. Requires testing whether the JNI context is accessible from non-main isolates.

### Medium priority

- **Distance warning:** If bounding box area < 4% of frame, show "Move closer" hint. At 3–4m users sometimes drift too far.
- **Low-light detection:** If FPS drops below 5 for > 3s, surface a "Poor lighting" warning.
- **Customizable gesture mapping:** Allow users to remap which gesture scores which team in Settings.

### Low priority

- **Haptic feedback on hold start/progress:** A subtle vibration tick as the hold ring fills gives tactile confirmation the gesture is being held correctly.
- **Two-hand support:** Currently only the largest detected hand is used. A second player gesture (smaller bounding box) is always ignored.
- **WearOS integration:** Forward gesture events to the watch display (show hold progress ring on watch face).
