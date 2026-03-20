# Gesture Detection Feature — Badminton Scoring App

## Tổng quan

Thêm tính năng nhận diện cử chỉ tay (hand gesture) bằng camera để chấm điểm cầu lông, tích hợp vào hệ thống scoring hiện tại (bên cạnh manual tap và voice command).

### Use case chính

- Điện thoại đặt trên giá kẹp ở **cột lưới hoặc ghế trọng tài**, hướng camera về phía **1 người chơi** phụ trách count điểm
- Khoảng cách camera → người chơi: ~3-4m
- Người chơi giơ tay ra hiệu sau mỗi rally, giữ gesture **2 giây** để trigger
- App detect gesture và tự động cộng điểm vào hệ thống hiện tại

### Gesture mapping

| Gesture        | Hành động                | Mô tả                                                           |
| -------------- | ------------------------ | --------------------------------------------------------------- |
| 👍 Thumbs Up   | +1 điểm bên A (bên mình) | Ngón cái hướng lên, các ngón còn lại nắm                        |
| 👎 Thumbs Down | +1 điểm bên B (đối thủ)  | Ngón cái hướng xuống, các ngón còn lại nắm                      |
| 🖐 Open Palm   | Undo điểm cuối           | Bàn tay mở, 5 ngón duỗi thẳng, giữ 2.5s (lâu hơn để tránh nhầm) |

---

## Kiến trúc kỹ thuật

### Package chính

```yaml
# pubspec.yaml
dependencies:
  hand_landmarker: ^2.1.2 # MediaPipe Hand Landmarker qua JNI bridge (Android)
  camera: ^latest # Camera stream (đã có trong app)
```

> **Lưu ý:** `hand_landmarker` hiện chỉ hỗ trợ Android. Nếu cần iOS sau này, cân nhắc viết platform channel riêng với MediaPipe iOS SDK hoặc dùng `google_mlkit_pose_detection` kết hợp custom logic.

### Cấu trúc thư mục đề xuất

```
lib/
├── services/
│   └── gesture_detection/
│       ├── gesture_detection_service.dart    # Service chính, quản lý camera + detection
│       ├── gesture_classifier.dart           # Logic phân loại gesture từ 21 landmarks
│       ├── gesture_smoother.dart             # Smoothing + hold timer logic
│       ├── gesture_overlay_painter.dart      # Vẽ landmark + debug info lên camera preview
│       ├── gesture_camera_widget.dart        # Widget camera với 2 chế độ (debug/production)
│       └── models/
│           ├── hand_gesture.dart             # Enum: thumbsUp, thumbsDown, openPalm, none
│           └── gesture_event.dart            # Event khi gesture được confirm
```

---

## Chi tiết implementation

### 1. Gesture Classifier (`gesture_classifier.dart`)

Nhận input là `List<Landmark>` (21 điểm, mỗi điểm có x, y, z) từ `hand_landmarker` package.

#### 21 Landmark indices (MediaPipe convention)

```
0: WRIST
1-4: THUMB (CMC, MCP, IP, TIP)
5-8: INDEX (MCP, PIP, DIP, TIP)
9-12: MIDDLE (MCP, PIP, DIP, TIP)
13-16: RING (MCP, PIP, DIP, TIP)
17-20: PINKY (MCP, PIP, DIP, TIP)
```

#### Logic phân loại (rule-based, không cần train model)

**Bước 1: Xác định trạng thái từng ngón tay (mở/gập)**

```dart
/// Ngón tay (trừ ngón cái) được coi là "gập" khi:
/// - TIP (đầu ngón) có y > PIP (khớp giữa) → ngón gập xuống
/// Lưu ý: Tọa độ y trong camera: 0 = trên, 1 = dưới
///
/// Ngón cái "duỗi" khi:
/// - Khoảng cách TIP (4) đến WRIST (0) > khoảng cách MCP (2) đến WRIST (0)
/// - Tức ngón cái đang vươn ra xa khỏi lòng bàn tay

bool isFingerExtended(List<Landmark> landmarks, int tipIdx, int pipIdx) {
  return landmarks[tipIdx].y < landmarks[pipIdx].y;
}

bool isThumbExtended(List<Landmark> landmarks) {
  double tipToWrist = distance(landmarks[4], landmarks[0]);
  double mcpToWrist = distance(landmarks[2], landmarks[0]);
  return tipToWrist > mcpToWrist * 1.2; // threshold 1.2 để tránh edge case
}
```

**Bước 2: Xác định hướng ngón cái (lên/xuống)**

```dart
/// Thumbs Up: thumb TIP (4) có y < thumb MCP (2) → ngón cái hướng LÊN
/// Thumbs Down: thumb TIP (4) có y > thumb MCP (2) → ngón cái hướng XUỐNG
/// Thêm điều kiện: góc giữa WRIST-MCP-TIP > 150° để chắc chắn ngón thẳng

enum ThumbDirection { up, down, neutral }

ThumbDirection getThumbDirection(List<Landmark> landmarks) {
  if (landmarks[4].y < landmarks[2].y - threshold) return ThumbDirection.up;
  if (landmarks[4].y > landmarks[2].y + threshold) return ThumbDirection.down;
  return ThumbDirection.neutral;
}
```

**Bước 3: Phân loại gesture**

```dart
HandGesture classify(List<Landmark> landmarks) {
  bool thumbExtended = isThumbExtended(landmarks);
  bool indexFolded = !isFingerExtended(landmarks, 8, 6);
  bool middleFolded = !isFingerExtended(landmarks, 12, 10);
  bool ringFolded = !isFingerExtended(landmarks, 16, 14);
  bool pinkyFolded = !isFingerExtended(landmarks, 20, 18);

  bool allFingersFolded = indexFolded && middleFolded && ringFolded && pinkyFolded;

  // Thumbs Up: ngón cái duỗi + hướng lên + 4 ngón còn lại gập
  if (thumbExtended && allFingersFolded) {
    if (getThumbDirection(landmarks) == ThumbDirection.up) {
      return HandGesture.thumbsUp;
    }
    if (getThumbDirection(landmarks) == ThumbDirection.down) {
      return HandGesture.thumbsDown;
    }
  }

  // Open Palm: tất cả 5 ngón duỗi thẳng
  bool allFingersExtended = !indexFolded && !middleFolded && !ringFolded && !pinkyFolded;
  if (thumbExtended && allFingersExtended) {
    return HandGesture.openPalm;
  }

  return HandGesture.none;
}
```

### 2. Gesture Smoother (`gesture_smoother.dart`)

Xử lý rung tay và hold timer để tránh false positive.

```dart
/// Smoothing strategy:
/// - Dùng sliding window 10 frames gần nhất
/// - Gesture được coi là "stable" khi >= 70% frames trong window cùng classify 1 gesture
/// - Hold timer: bắt đầu đếm khi gesture stable, trigger khi đủ thời gian giữ
/// - Reset timer ngay khi gesture thay đổi hoặc không stable

class GestureSmoother {
  static const int windowSize = 10;
  static const double stabilityThreshold = 0.7; // 70% frames
  static const Duration holdDuration = Duration(seconds: 2);
  static const Duration holdDurationUndo = Duration(milliseconds: 2500); // Undo lâu hơn
  static const Duration cooldownAfterTrigger = Duration(seconds: 3); // Tránh trigger liên tiếp

  final Queue<HandGesture> _window = Queue();
  HandGesture? _currentStableGesture;
  DateTime? _holdStartTime;
  DateTime? _lastTriggerTime;

  /// Gọi mỗi frame, trả về GestureEvent nếu trigger, null nếu chưa
  GestureEvent? update(HandGesture detected) {
    // Thêm vào window
    _window.addLast(detected);
    if (_window.length > windowSize) _window.removeFirst();

    // Tính gesture chiếm đa số trong window
    HandGesture? dominant = _getDominantGesture();

    // Cooldown check
    if (_lastTriggerTime != null &&
        DateTime.now().difference(_lastTriggerTime!) < cooldownAfterTrigger) {
      return null;
    }

    if (dominant != null && dominant != HandGesture.none) {
      if (dominant == _currentStableGesture) {
        // Cùng gesture, kiểm tra hold duration
        Duration requiredHold = (dominant == HandGesture.openPalm)
            ? holdDurationUndo
            : holdDuration;
        if (_holdStartTime != null &&
            DateTime.now().difference(_holdStartTime!) >= requiredHold) {
          _lastTriggerTime = DateTime.now();
          _reset();
          return GestureEvent(gesture: dominant, timestamp: DateTime.now());
        }
      } else {
        // Gesture mới stable, bắt đầu hold timer
        _currentStableGesture = dominant;
        _holdStartTime = DateTime.now();
      }
    } else {
      _reset();
    }

    return null;
  }

  /// Trả về progress (0.0 → 1.0) cho UI hiển thị vòng tròn đếm ngược
  double get holdProgress { ... }

  void _reset() {
    _currentStableGesture = null;
    _holdStartTime = null;
  }
}
```

### 3. Camera Widget với 2 chế độ (`gesture_camera_widget.dart`)

#### Chế độ 1: Production Mode (không hiển thị camera preview)

- Màn hình scoring bình thường, camera chạy ngầm
- Chỉ hiển thị icon nhỏ cho biết camera đang active (🔴 dot)
- Khi detect gesture stable: hiển thị icon gesture đang hold + progress ring (vòng tròn tròn dần đầy)
- Khi trigger: flash animation + haptic feedback + sound (giống voice trigger hiện tại)

#### Chế độ 2: Debug Mode (hiển thị camera preview + overlay)

- Hiển thị camera preview (có thể resize, kéo thả vị trí trên màn hình)
- Overlay lên camera preview:
  - **21 landmark points** (chấm tròn nhỏ, nối bằng đường thẳng theo cấu trúc bàn tay)
  - **Bounding box** quanh bàn tay detected
  - **Label gesture** đang classify: "👍 THUMBS UP", "👎 THUMBS DOWN", "🖐 OPEN PALM", "❌ NONE"
  - **Confidence/stability**: % frames stable trong window (vd: "Stable: 80%")
  - **Hold timer**: đếm ngược "Hold: 1.2s / 2.0s" + progress bar
  - **Trạng thái từng ngón**: hiển thị mở/gập (thumb ✓, index ✗, middle ✗, ring ✗, pinky ✗)
  - **FPS** của detection pipeline
  - **Cooldown indicator**: nếu đang trong cooldown sau trigger
- Có thể toggle giữa front/back camera
- Có nút chụp screenshot debug info

```dart
class GestureCameraWidget extends StatefulWidget {
  final bool debugMode;          // true = hiển thị preview + overlay, false = chạy ngầm
  final Function(GestureEvent) onGestureDetected;  // Callback khi gesture trigger

  // ...
}
```

#### UI Integration

```dart
/// Thêm button camera vào màn hình scoring hiện tại
/// Đặt cạnh các button hiện có (manual score, voice toggle)

// Button bật/tắt gesture detection
IconButton(
  icon: Icon(gestureEnabled ? Icons.videocam : Icons.videocam_off),
  onPressed: () => toggleGestureDetection(),
)

// Long press button camera → toggle debug mode
// Hoặc: Thêm vào Settings screen toggle Debug/Production mode
```

### 4. Gesture Detection Service (`gesture_detection_service.dart`)

Service trung tâm quản lý toàn bộ pipeline.

```dart
class GestureDetectionService {
  final HandLandmarkerPlugin _handLandmarker;
  final GestureClassifier _classifier;
  final GestureSmoother _smoother;

  bool _isRunning = false;
  bool _debugMode = false;

  // Stream để widget lắng nghe
  final StreamController<GestureFrameData> _frameDataController;  // Cho debug overlay
  final StreamController<GestureEvent> _gestureEventController;   // Cho scoring system

  /// Bắt đầu detection pipeline
  Future<void> start({bool debugMode = false}) async {
    _debugMode = debugMode;
    _isRunning = true;

    // Init camera
    // Init hand landmarker plugin
    // Bắt đầu listen camera stream

    _controller.startImageStream((CameraImage image) {
      if (!_isRunning) return;

      // 1. Detect hand landmarks
      List<Hand> hands = await _handLandmarker.detect(image);

      // 2. Lấy bàn tay lớn nhất (gần camera nhất)
      Hand? primaryHand = _selectPrimaryHand(hands);

      // 3. Classify gesture
      HandGesture gesture = HandGesture.none;
      if (primaryHand != null) {
        gesture = _classifier.classify(primaryHand.landmarks);
      }

      // 4. Smooth + hold check
      GestureEvent? event = _smoother.update(gesture);

      // 5. Emit frame data cho debug UI
      if (_debugMode) {
        _frameDataController.add(GestureFrameData(
          hands: hands,
          classifiedGesture: gesture,
          stability: _smoother.stability,
          holdProgress: _smoother.holdProgress,
          fps: _fpsCounter.current,
        ));
      }

      // 6. Emit gesture event nếu trigger
      if (event != null) {
        _gestureEventController.add(event);
      }
    });
  }

  /// Chọn bàn tay "chính" — bàn tay có bounding box lớn nhất (gần camera nhất)
  Hand? _selectPrimaryHand(List<Hand> hands) {
    if (hands.isEmpty) return null;
    return hands.reduce((a, b) =>
      a.boundingBoxArea > b.boundingBoxArea ? a : b
    );
  }

  Future<void> stop() async { ... }
  void toggleDebugMode() { ... }
}
```

### 5. Tích hợp vào Scoring System hiện tại

```dart
/// Trong main scoring screen/controller, lắng nghe gesture events
/// và gọi cùng scoring functions đã có

gestureService.gestureEvents.listen((GestureEvent event) {
  switch (event.gesture) {
    case HandGesture.thumbsUp:
      // Gọi hàm scoring hiện tại: +1 bên A (bên mình)
      scoreManager.incrementScore(Side.left);  // hoặc Side.a
      _playFeedback(); // haptic + sound
      break;
    case HandGesture.thumbsDown:
      // +1 bên B (đối thủ)
      scoreManager.incrementScore(Side.right);  // hoặc Side.b
      _playFeedback();
      break;
    case HandGesture.openPalm:
      // Undo — gọi hàm undo hiện tại
      scoreManager.undoLastScore();
      _playUndoFeedback();
      break;
  }
});
```

> **Quan trọng:** Gesture detection phải tôn trọng cooldown hiện tại của hệ thống scoring (5 giây giữa các lần score từ voice). Nên dùng chung cooldown manager hoặc ít nhất check trước khi apply score.

---

## Debug Overlay Painter (`gesture_overlay_painter.dart`)

```dart
class GestureOverlayPainter extends CustomPainter {
  final GestureFrameData frameData;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Vẽ landmark points (21 chấm tròn)
    // Màu: xanh lá = ngón đang duỗi, đỏ = ngón đang gập

    // 2. Vẽ connections giữa landmarks (đường nối khớp tay)
    // MediaPipe hand connection pairs:
    // WRIST→THUMB_CMC→THUMB_MCP→THUMB_IP→THUMB_TIP
    // WRIST→INDEX_MCP→INDEX_PIP→INDEX_DIP→INDEX_TIP
    // ... tương tự cho middle, ring, pinky
    // INDEX_MCP→MIDDLE_MCP→RING_MCP→PINKY_MCP (nối ngang)

    // 3. Vẽ bounding box quanh bàn tay

    // 4. Vẽ label gesture + stability %
    // Vd: "👍 THUMBS UP — 85% stable"

    // 5. Vẽ hold progress ring (vòng tròn tròn dần)
    // Arc từ 0° đến 360° theo holdProgress (0.0 → 1.0)
    // Màu: vàng khi đang hold, xanh lá khi trigger

    // 6. Vẽ finger states
    // "T:✓ I:✗ M:✗ R:✗ P:✗" (Thumb open, rest closed)

    // 7. Vẽ FPS counter góc trên phải

    // 8. Vẽ cooldown bar nếu đang cooldown
  }
}
```

---

## Models

### `hand_gesture.dart`

```dart
enum HandGesture {
  thumbsUp,     // 👍 +1 bên mình
  thumbsDown,   // 👎 +1 bên đối thủ
  openPalm,     // 🖐 Undo
  none,         // Không nhận diện gesture nào
}
```

### `gesture_event.dart`

```dart
class GestureEvent {
  final HandGesture gesture;
  final DateTime timestamp;
  final double confidence;  // % stability khi trigger

  GestureEvent({
    required this.gesture,
    required this.timestamp,
    this.confidence = 0.0,
  });
}

class GestureFrameData {
  final List<Hand> hands;           // Tất cả bàn tay detected
  final HandGesture classifiedGesture;  // Gesture đang classify
  final double stability;           // % stable trong window
  final double holdProgress;        // 0.0 → 1.0 tiến trình hold
  final double fps;                 // FPS hiện tại
  final Map<String, bool> fingerStates;  // {thumb: true, index: false, ...}
}
```

---

## UI Flow

### Button Camera trên màn hình scoring

```
┌──────────────────────────────┐
│  SCORING SCREEN (hiện tại)   │
│                              │
│    12  —  10                 │
│                              │
│  [- ] [Undo] [+ ]           │ ← Manual buttons hiện tại
│  [🎤 Voice]                  │ ← Voice toggle hiện tại
│  [📷 Gesture]                │ ← NÚT MỚI: Toggle gesture detection
│                              │
│  Trạng thái: khi gesture ON  │
│  ● Camera active             │ ← Chấm đỏ nhỏ
│  👍 Hold: 1.2s ████░░ 60%   │ ← Hiển thị khi đang detect gesture
│                              │
└──────────────────────────────┘
```

### Debug Mode (long press nút camera hoặc toggle trong Settings)

```
┌──────────────────────────────┐
│  SCORING SCREEN              │
│    12  —  10                 │
│                              │
│  ┌────────────────────┐      │
│  │ CAMERA PREVIEW     │ FPS:28│
│  │                    │      │
│  │   ●──●──●──●      │      │
│  │  /   |             │      │
│  │ ●    ●──●──●      │      │
│  │  \   |             │      │
│  │   ●──●──●──●      │      │
│  │       |             │      │
│  │       ●──●──●      │      │
│  │                    │      │
│  │ 👍 THUMBS UP  85% │      │
│  │ T:✓ I:✗ M:✗ R:✗ P:✗│     │
│  │ Hold: 1.5s/2.0s   │      │
│  │ ████████████░░ 75% │      │
│  └────────────────────┘      │
│                              │
│  [📷 ON] [🐛 Debug] [📸]    │
│           ↑            ↑     │
│     Toggle mode    Screenshot│
└──────────────────────────────┘
```

---

## Cấu hình / Settings

Thêm vào Settings screen hiện tại:

```dart
/// Gesture Detection Settings
class GestureSettings {
  bool enabled = false;                     // Bật/tắt gesture detection
  bool debugMode = false;                   // Hiển thị camera preview + overlay
  Duration holdDuration = Duration(seconds: 2);       // Thời gian giữ gesture
  Duration undoHoldDuration = Duration(milliseconds: 2500); // Thời gian giữ undo
  Duration cooldownDuration = Duration(seconds: 3);   // Cooldown sau trigger
  double stabilityThreshold = 0.7;          // % frames stable cần thiết
  int smoothingWindowSize = 10;             // Số frames trong sliding window
  CameraLensDirection cameraDirection = CameraLensDirection.back; // Front/back cam

  // Mapping gesture → action (cho phép user customize sau này)
  Map<HandGesture, ScoringAction> gestureMapping = {
    HandGesture.thumbsUp: ScoringAction.scoreLeft,
    HandGesture.thumbsDown: ScoringAction.scoreRight,
    HandGesture.openPalm: ScoringAction.undo,
  };
}
```

---

## Edge Cases & Xử lý lỗi

1. **Không detect được tay:** Sau 5s không thấy tay → hiển thị hint "Giơ tay vào camera"
2. **Tay quá xa / quá nhỏ:** Nếu bounding box < 5% diện tích frame → warning "Tiến lại gần camera"
3. **Nhiều bàn tay:** Luôn chọn bàn tay có bounding box lớn nhất (gần nhất)
4. **2 tay cùng 1 người:** Nếu detect 2 tay, chỉ xét tay đang giữ gesture (tay kia thường ở trạng thái tự nhiên)
5. **Ánh sáng yếu:** MediaPipe sẽ tự handle, nhưng nên warning user nếu FPS drop < 10
6. **Camera bị che / tối:** Nếu 0 hands detected liên tục > 10s → suggest kiểm tra camera
7. **Conflict với voice:** Nếu cả voice và gesture đều enabled, scoring system phải có shared cooldown — 1 lần trigger (bất kể từ voice hay gesture) thì cả 2 input đều cooldown
8. **Pin:** Camera + ML inference tốn pin. Hiển thị warning khi pin < 20% và suggest tắt gesture mode
9. **Background app:** Phải stop camera khi app vào background, resume khi quay lại

---

## Testing Checklist

### Unit tests

- [ ] GestureClassifier: thumbs up detection từ mock landmarks
- [ ] GestureClassifier: thumbs down detection từ mock landmarks
- [ ] GestureClassifier: open palm detection từ mock landmarks
- [ ] GestureClassifier: trả về `none` cho random hand positions
- [ ] GestureSmoother: trigger sau đúng holdDuration
- [ ] GestureSmoother: không trigger khi stability < threshold
- [ ] GestureSmoother: cooldown hoạt động đúng
- [ ] GestureSmoother: reset khi gesture thay đổi giữa chừng
- [ ] Primary hand selection: chọn tay lớn nhất

### Integration tests

- [ ] Gesture trigger → score update đúng bên
- [ ] Gesture undo → undo điểm cuối
- [ ] Shared cooldown giữa voice + gesture
- [ ] Toggle debug mode không crash
- [ ] Camera start/stop không leak resources
- [ ] App background/foreground → camera lifecycle đúng

### Manual tests (tại sân cầu lông)

- [ ] Thumbs up ở khoảng cách 3m — detect được không?
- [ ] Thumbs down ở khoảng cách 3m — phân biệt được với thumbs up?
- [ ] False positive khi đang chơi (tay cầm vợt, vung tay) — có trigger nhầm?
- [ ] Ánh sáng sân trong nhà vs ngoài trời
- [ ] Camera trước vs camera sau
- [ ] Rung tay khi giữ gesture — vẫn trigger được?
- [ ] Nhiều người đi qua phía sau — có ảnh hưởng?
- [ ] FPS trên thiết bị thật (target: > 15 FPS)

---

## Lưu ý cho implementation

1. **Không block UI thread:** Hand detection phải chạy trên isolate/background thread. `hand_landmarker` plugin đã handle native qua JNI, nhưng cần verify không gây jank.

2. **Frame skipping:** Nếu detection chậm hơn camera framerate, skip frames thay vì queue lên. Chỉ process frame mới nhất.

3. **Camera resolution:** Không cần full resolution cho hand detection. Dùng `ResolutionPreset.medium` (720p) hoặc thậm chí `low` (480p) để tiết kiệm tài nguyên. MediaPipe handle tốt ở resolution thấp.

4. **Coordinate transformation:** Landmark coordinates từ `hand_landmarker` là normalized (0.0 → 1.0). Khi vẽ debug overlay lên camera preview, cần transform theo camera preview size và rotation.

5. **Tích hợp scoring:** Gọi **cùng hàm scoring** mà manual tap và voice đang dùng. KHÔNG tạo logic scoring riêng cho gesture. Gesture chỉ là thêm 1 input method, output là cùng scoring action.

6. **Sound/haptic feedback:** Khi gesture trigger thành công, phát sound + haptic giống voice trigger. Thêm sound riêng cho "đang hold" (tick tick) nếu muốn.

7. **Persist settings:** Lưu gesture settings vào SharedPreferences/local storage, bao gồm enabled state, debug mode, và custom thresholds.
