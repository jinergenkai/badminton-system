# Godminton — Mi Band 10 score counter

App đếm điểm cầu lông chạy trên Mi Band 10 (Vela QuickApp), ghép đôi với một app
Flutter trên Android làm bảng điểm + loa.

---

## 1. Repo có gì

| Thư mục | Vai trò |
|---|---|
| `bandcounter-watch/` | **Source of truth.** QuickApp `.ux` chạy trên band. Build bằng `aiot-toolkit`. |
| `bandcounter-flutter/` | **Source of truth.** App phone (GetX). Native bridge ở `android/app/src/main/kotlin/com/hung/bandcounter/MainActivity.kt`. |
| `bandcounter-android/` | Đồ cũ — bản Kotlin/Compose thuần trước khi chuyển sang Flutter. Chỉ để tham khảo. |
| `com.bandbbs.ebook/`, `com.bandbbs.ebook-android/` | Repo mẫu của người khác, dùng để học cơ chế interconnect. |
| `counter_demo/`, `interconnect_dev_test_demo/` | Demo tối giản hồi đầu. |
| `docs/` | Ghi chú research cũ + code Kotlin cũ dán vào file `.md`. |

> 📌 **[docs/watch-ui-gotchas.md](docs/watch-ui-gotchas.md) — đọc trước khi làm UI
> cho band.** Những bẫy đã tốn hàng giờ debug: `<list-item>` không có `height`
> thì không vẽ gì (đây là lý do list nhạc chưa bao giờ hiện được), 4 góc bo tròn
> không đặt nút được, `right:` bị bỏ qua trong `<stack>`, toast hệ thống không
> đổi được vị trí.

> `bandcounter-flutter/` có `.git` riêng bên trong → nó là repo lồng. Đừng
> `git add` nó vào repo cha, sẽ tạo gitlink rỗng chứ không commit code. Commit
> riêng trong thư mục đó.

---

## 2. Phần mềm cần cài trên điện thoại

Đây là phần không có trong tài liệu nào, phải tự mò ra:

| App | Bản | Để làm gì |
|---|---|---|
| **Mi Fitness (mod)** | `mifitness_3.33.6i_m0tral_v141` | Bản mod của m0tral. Build cũ nên cho can thiệp sâu vào band, và **cho phép cài custom app**. Bản Mi Fitness chính chủ trên Play Store **không cài được** RPK bên thứ ba. |
| **Notify for Xiaomi** | — | Dùng để đẩy file `.rpk` vào band (mục cài app firmware / app bên thứ ba). |

Cả hai đều yêu cầu **đăng nhập tài khoản Xiaomi** (SDK gắn với hệ sinh thái sức
khoẻ của Xiaomi).

⚠️ Notify for Xiaomi và Mi Fitness **giành nhau kết nối BLE**. Muốn Notify sync
được thì phải **tắt chạy ngầm của Mi Fitness**. Nhưng lúc chơi thì Mi Fitness lại
chính là đường truyền — xem phần 5.

---

## 3. Ràng buộc ký số (bắt buộc, sai là không chạy)

Watch app và Android app **phải cùng package name và cùng chữ ký**:

- package QuickApp (`bandcounter-watch/src/manifest.json` → `package`)
  == `applicationId` của Android (`android/app/build.gradle.kts`)
  == `com.hung.bandcounter`
- RPK ký bằng cặp `.pem` trong `bandcounter-watch/sign/{debug,release}/`
- APK ký bằng `bandcounter.jks`
- Cặp `.pem` phải được **trích ra từ chính `bandcounter.jks`** (quy trình ở
  `docs/gen-key.txt` và `docs/SETUP_GUIDE.md`)

**Trạng thái hiện tại: đã kiểm chứng là khớp.** SHA-256 fingerprint của cả
`sign/debug/certificate.pem`, `sign/release/certificate.pem`, `bandcounter.jks`
(cả 3 bản sao trong repo) đều là:

```
80:46:2E:57:5A:4E:E5:A3:77:EA:6D:87:E7:91:52:4F:E4:04:58:2C:86:1D:D8:D6:02:AB:C8:F4:9B:7C:B2:68
```

Kiểm tra lại khi nghi ngờ:

```bash
openssl x509 -in bandcounter-watch/sign/release/certificate.pem -noout -fingerprint -sha256
```

```bash
keytool -list -v -keystore bandcounter.jks -storepass yourpassword | grep SHA256
```

Bản debug và bản release của RPK dùng **cùng một cert**, nên `npm run build`
(debug) và `npm run release` không khác nhau về mặt chữ ký.

Phía Android, `build.gradle.kts` cố tình ép **cả bản debug cũng ký bằng
`bandcounter.jks`**, để `flutter run` không sinh ra APK ký bằng debug keystore
mặc định. Đường dẫn keystore lấy từ `android/gradle.properties` →
`KEYSTORE_PATH=../../bandcounter.jks`.

> 🔴 **Bẫy:** nếu `KEYSTORE_PATH` trỏ sai hoặc file không tồn tại, gradle
> **im lặng** rơi về debug keystore mặc định (`if (keystoreFile.exists())`),
> APK sẽ sai chữ ký mà không có cảnh báo nào.

---

## 4. Build

```bash
cd bandcounter-watch && npm run release
```

Sinh ra `dist/com.hung.bandcounter.release.1.0.0.rpk`. Lưu ý `npm run build` chỉ
ra bản `.debug.` — mà `deploy.ps1` thì push file `.release.`, nên build xong bằng
`npm run build` rồi chạy `deploy.ps1` sẽ đẩy nhầm file cũ.

```bash
cd bandcounter-flutter && flutter run --release
```

### Quy trình dev: đưa bản build mới lên band

**Thứ tự này là bắt buộc.** Notify chỉ cài được khi nó đang giữ kết nối band.
Nó chỉ lấy được kết nối sau khi Mi Fitness đã sync (tạo auth), và chỉ giữ
được kết nối khi Mi Fitness đã bị dừng.

1. **Build** band app bản release (`npm run release`).
2. **Push** file `.rpk` vào `/sdcard/Download/` trên phone.
3. **Clean**: kill toàn bộ app trên phone.
4. Mở **Mi Fitness** → **Sync** band cho tới khi kết nối xong.
5. **Giữ Mi Fitness mở**, mở tiếp **Notify for Xiaomi**, đợi nó nối band.
6. **Kill Mi Fitness**, rồi trong Notify: cài firmware / app → app bên thứ
   ba → chọn `Download/com.hung.bandcounter.release.1.0.0.rpk`.

Sau khi cài xong, làm lại nghi thức bắt tay ở §5 trước khi chơi.

Cả 6 bước chạy bằng một lệnh. Script tự làm bước 1–3 và 6; ở bước 4–5 nó tự
mở app rồi dừng lại chờ bạn bấm Enter:

```bash
.\deploy.ps1 -Dev
```

Tên gói trên máy dev: Mi Fitness bản mod là `com.xiaomi.wearable`, Notify là
`com.mc.xiaomi1`. Máy khác mà khác tên gói thì sửa ở đầu `deploy.ps1`.

Các lệnh lẻ khác của `deploy.ps1`:

| Lệnh | Làm gì |
|---|---|
| `.\deploy.ps1` | chỉ push `.rpk` |
| `-Clean` | kill mọi app trên phone (khi máy lag) |
| `-StopMiFitness` | chỉ dừng Mi Fitness |
| `-Mem` | xem RAM và tiến trình ăn RAM nhiều nhất |
| `-Slim` / `-Unslim` | tắt / bật lại Google bloat, giới hạn chạy nền (lâu dài) |

### Âm thanh: Sound Library

Mọi câu hype nằm trong **một** file: `bandcounter-flutter/assets/config/sound_library.json`
(câu nói, chữ hiện trên màn, màu, nằm trong trigger nào). *Khi nào* một trigger
bắn là code (`HypeVoiceController._triggerMatches`); *phát câu gì* là dữ liệu.

Một câu phát từ nguồn đầu tiên có được:

1. MP3 thả vào phone: `/sdcard/Android/data/com.hung.bandcounter/files/sounds/<id>.mp3`
2. MP3 đóng trong app: `assets/audio/hype/<id>.mp3`
3. TTS đã render sẵn (cache lâu dài, không mất khi thoát app)
4. TTS đọc trực tiếp, đồng thời render để lần sau dùng cache

Trên phone, màn **Sound Library** (icon 🎵 cạnh History) cho thêm câu TTS mới, sửa chữ,
chuyển câu giữa các trigger, tắt câu. Mọi chỉnh sửa lưu vào `library_user.json` trong
cùng thư mục `sounds/`, không cần build lại app.

Muốn chỉnh sửa trên phone thành mặc định trong code:

```bash
cd bandcounter-flutter && python tools/pull_sound_library.py --dry-run
```

Bỏ `--dry-run` để ghi thật. MP3 kéo về nằm ở `audio_src/hype/`. Lần build Android
kế tiếp tự chuẩn hóa độ to cho file mới hoặc file đã đổi
(`normalize_voice.py --changed`, gọi từ Gradle; máy không có python/ffmpeg thì chỉ cảnh
báo). Build và cài bản mới xong thì chạy thêm `--clear-device` để phone không giữ bản
sao cũ.

Cắt một câu từ file MP3 dài (nguồn nằm ở `audio_src/pack/`):

```bash
ffmpeg -i audio_src/pack/pack7_viet_hai.mp3 -ss 12.3 -to 14.1 audio_src/hype/u_ba_khi.mp3
```

Sau đó thêm một mục `u_ba_khi` vào `sound_library.json`. Việc chuẩn hóa độ to diễn ra
khi build.

Voice (all) và Hype chỉnh được tới 300%. Trên 100%, app không tăng âm lượng phát mà làm
to chính file: giải mã sang PCM một lần (MediaCodec), nhân lên, rồi cache theo mức.

---

## 5. Nghi thức bắt tay (thứ tự bắt buộc)

Mỗi buổi chơi phải làm đúng thứ tự này, sai là không kết nối được:

0. Tắt sạch app / khởi động lại Android. Bật lại Bluetooth (gần như chắc ăn nếu
   vừa restart máy hoặc vừa bật lại BLE).
1. Mở **Mi Fitness** → bấm **Sync** → chờ nó tạo phiên auth với đồng hồ.
2. Mở **band app** trên đồng hồ.
3. Mở **app Flutter** trên Android và **đợi**.

Nếu ăn: chấm trạng thái trên band app sáng **xanh**, status trên app Flutter báo
connected, hai chiều chạy bình thường.

---

## 6. 🐛 Bug đang mở: kết nối một chiều

### Triệu chứng

Khi chấm trạng thái trên band app **đỏ** (không "connected"):

- **Phone → watch: vẫn chạy bình thường.** Vẫn popup sync, vẫn đẩy điểm sang đồng hồ.
- **Watch → phone: không bao giờ nhận được.** Bấm điểm trên đồng hồ, phone im.

Nó **bất đối xứng**, và đó chính là đầu mối. Một kết nối BLE đứt thì phải chết cả
hai chiều. Chết đúng một chiều nghĩa là đường truyền vẫn sống, chỉ có **phần đăng
ký nhận ở phía Android là hỏng**.

### Đã kiểm chứng (không phải suy đoán)

Đọc bytecode `xms-wearable-lib_1.4_release.aar` và code hiện tại:

1. **Chữ ký khớp.** Đã loại giả thuyết sai key (xem phần 3).
2. `Task` của SDK **chỉ có** `addOnSuccessListener` / `addOnFailureListener`,
   **không có** `addOnCompleteListener`.
3. Trong `MainActivity.initWearableConnect()`:
   ```kotlin
   messageApi.removeListener(node.id)          // Task bất đồng bộ, thả trôi
   messageApi.addListener(node.id, listener)   // Task bất đồng bộ, thả trôi
   result.success(true)                        // báo thành công vô điều kiện
   ```
   Hai lệnh này là **Task bất đồng bộ không được xâu chuỗi**. Không có gì đảm bảo
   `removeListener` xong trước. Nếu nó về sau, **nó gỡ đúng cái listener vừa đăng ký**.
4. **Kết quả của `addListener` không hề được kiểm tra.** Thất bại là im lặng
   tuyệt đối, mà `result.success(true)` vẫn trả về true → Dart tưởng đã kết nối.
5. `requestPermission()` trả về `Task<Permission[]>` — mảng quyền **thực sự được
   cấp**. Code hiện tại **vứt mảng này đi**, chỉ cần callback success là chạy tiếp.
   Success không có nghĩa là DEVICE_MANAGER đã được cấp.
6. SDK có sẵn mã lỗi cho đúng những tình huống này, và ta **đang vứt hết**:
   `RESULT_PERMISSION_DENIED`, `RESULT_SIGNATURE_VERIFY_FAILED`,
   `RESULT_APP_NOT_INSTALLED`, `RESULT_PACKAGE_NOT_INSTALLED`,
   `RESULT_DISCONNECTED` — truy được qua `Status.getCode()`, và có cả
   `exception/PermissionDeniedException`.
7. Phía watch, **không một lệnh `connect.send()` nào có callback `fail`**. Nên
   hiện tại **không phân biệt được** "watch gửi thất bại" với "phone không nhận".
8. Hai API chưa bao giờ dùng, mà lại đúng là thứ cần để chẩn đoán:
   `nodeApi.isWearAppInstalled(pkg)` và `nodeApi.launchWearApp(nodeId, pkg)`.
9. SDK bind vào service `com.xiaomi.wearable.XMS` thuộc package
   `com.xiaomi.wearable` **hoặc** `com.mi.health`.

### Ai là người chủ động dò trạng thái? — **Không ai cả**

Đây là chỗ dễ hiểu nhầm nhất, nên nói rõ. Không bên nào *poll* trạng thái thật:

**Phía band app** (`index.ux`), biến `connected` (chấm xanh/đỏ) chỉ được ghi ở
đúng 3 chỗ:
- `connect.onopen` → true
- `connect.onclose` → false
- **một lần duy nhất** `getReadyState()` gọi trong `setupConnect()` lúc `onShow`

Không có timer, không lặp lại. Chấm đỏ/xanh = **một tấm ảnh chụp lúc mở page,
cộng với các sự kiện cạnh (edge) sau đó**. `requestSync()` cũng chỉ bắn khi
`onopen` hoặc khi `getReadyState` trả về ready — không định kỳ.

**Phía Android**, `_watchConnectionPoll` chạy 5 giây một lần gọi
`isWatchConnected()` → xuống Kotlin trả về `watchNodeId != null`. Hàm này
**không hề chạm vào SDK**. `watchNodeId` được gán một lần trong
`initWearableConnect()` và **không bao giờ được gán lại null** (kể cả `onDestroy`).
Nghĩa là timer 5 giây đang poll một hằng số: **đã xanh thì xanh vĩnh viễn.**

> **Kết luận: cả hai đèn báo đều không đáng tin, vì hai lý do khác nhau.** Đèn
> phía phone là một cái chốt một chiều. Đèn phía watch thì đúng lúc chụp, sau đó
> chỉ đổi nếu bắt được đúng sự kiện cạnh.

### Vì sao chấm đỏ mà phone → watch vẫn chạy

Ghép cái trên với nghi thức ở phần 5 thì ra một lời giải rất đời thường:

Bước 2 là **mở band app**, bước 3 mới là **mở app Flutter**. Lúc band app chạy
`onShow` → `getReadyState()`, app phone **chưa hề chạy**. Nên câu trả lời là
"chưa ready" → **chấm đỏ**. Sau đó phone kết nối. Nếu sự kiện `onopen` bắt được
thì chấm chuyển xanh; nếu cạnh `onopen` xảy ra **trước khi** page kịp gán
`this.connect.onopen = ...` (trong `setupConnect()` việc gán `onopen` diễn ra
*trước* lời gọi `getReadyState`, nhưng cả hai đều sau khi kênh có thể đã mở), thì
sự kiện đó bay vào hư không và **không còn gì kiểm tra lại nữa** → đỏ vĩnh viễn,
dù kênh hoàn toàn khoẻ.

Điều này có nghĩa: **chấm đỏ KHÔNG chứng minh được listener phía Android đã
chết.** Nó có thể chỉ là một cạnh bị bỏ lỡ. Đây là lý do bước 0 (log) phải làm
trước — hiện tại ta không phân biệt được hai khả năng.

### ✅ KẾT QUẢ ĐO THẬT (2026-08-23) — giả thuyết chính đã SAI

Chạy bản Bước 0 trên thiết bị thật. Kết quả lật ngược mọi phán đoán trước đó.

**Phía Android — mọi bước đều THÀNH CÔNG:**

```
BandDiag: ======== initialize() ========
BandDiag: getConnectedNodes -> 1 node(s)
BandDiag:     node[0] id=2127934474 name=Xiaomi Smart Band 10
BandDiag: requestPermission -> granted=[data_manager]  hasDeviceManager=true
BandDiag: isWearAppInstalled -> true
BandDiag: removeListener settled: IllegalStateException: you have not registered
BandDiag: >>> addListener OK — watch -> phone SHOULD work now
BandDiag: >>> SEND ok: score_A (42 bytes)
BandDiag: >>> SEND FAILED: score_B (42 bytes) Exception: sendMessage failed
```

**Phía watch — trang DIAG:** `ready=2  open=0  close=1  sendFail=5`

Đọc ra:

| Bằng chứng | Kết luận |
|---|---|
| `addListener OK` | **Giả thuyết chính SAI.** Listener đăng ký thành công. Đây chưa bao giờ là lỗi phía Android. |
| `granted=[data_manager] hasDeviceManager=true` | Loại giả thuyết (b) — quyền đầy đủ. |
| `isWearAppInstalled -> true` | Đóng đinh việc loại giả thuyết (c). |
| **`open=0`** | `onopen` **chưa từng nổ một lần nào**. |
| **`sendFail=5`** | 5 lần bấm điểm trên band → **callback `fail` của chính watch nổ**. Message chưa bao giờ rời khỏi đồng hồ. |
| Log Android **không có một dòng `<<< RECV`** nào | Khớp: phone không nhận vì watch không hề gửi được. |
| `ready=2`, `close=1` | Kênh ở trạng thái 2, không phải 1. |

> ### 🎯 Kết luận đã kiểm chứng
>
> Đây **không** phải lỗi nhận ở Android. **Kênh gửi ra của watch không bao giờ
> mở**, nên `send()` fail ngay tại chỗ, trước khi chạm tới đường truyền.
>
> Chiều phone → watch vẫn chạy vì message đến được xử lý bởi nền tảng, không
> phụ thuộc kênh gửi ra của chính app watch.

### Giả thuyết mới

`getReadyState` trả **2**. API này mô phỏng WebSocket (`instance` / `onopen` /
`onmessage` / `onclose` / `send` / `getReadyState`), mà WebSocket readyState là
`0=CONNECTING 1=OPEN 2=CLOSING 3=CLOSED`. Ghép với `open=0`: kênh **chưa bao giờ
đạt OPEN** — hoặc đang kẹt ở một trạng thái trung gian, hoặc đã đóng.

Và điểm mấu chốt: **không có dòng code nào trong cả hai app yêu cầu mở kênh này.**
Watch chỉ gọi `instance()` rồi `send()` luôn.

- **(f) Kênh thuộc về một phiên do *phone* khởi tạo**, chứ không phải do người
  dùng bấm mở app trên đồng hồ. `nodeApi.launchWearApp(nodeId, pkg)` là API cho
  việc đó, và ta **chưa bao giờ gọi**. Giải thích được cả việc chiều vào vẫn chạy,
  lẫn việc "khởi động lại Bluetooth thì ăn" (phiên được tạo lại).
- **(g) Có một `connect()` / `open()` trên instance mà ta chưa gọi.** Chưa xác
  minh được từ tài liệu — simulator không implement interconnect, binary không
  chứa API này.

### ✅ KẾT QUẢ PROBE API (2026-08-24)

Nút LIST API trên đồng hồ trả về:

```
instance own   = package, send, onmessage, onopen, onclose, onerror,
                 getApkStatus, getReadyState, stored_onopen, stored_onclose,
                 stored_onmessage
instance proto = RECV_DATA, CONNECTED, DISCONNECTED, CONNECT_ERROR,
                 create, connect, init, uninit, send, close, listen, getApkStatus
```

Và lỗi send nói thẳng: `{"data":"not connected","code":1006}`.

**`connect()` có tồn tại** → giả thuyết (g) đúng về mặt tồn tại. Nhưng gọi
`conn.connect({success, fail})` thì ném **`miwear object expected`**.

Để ý: `send` và `getApkStatus` nằm ở **cả `own` lẫn `proto`** — framework có bọc
wrapper JS. `connect` **chỉ có ở `proto`** → nó là hàm native thô, sai receiver
hoặc sai kiểu tham số. Chữ ký đúng **vẫn chưa tìm ra**.

### 🔧 Cách đã xử lý (không cần biết chữ ký `connect()`)

Manh mối quyết định đến từ người dùng: **có một thứ tự khiến nó xanh ngay** —
Mi Fitness → band app → Flutter app. Nghĩa là **kênh vẫn tự mở được**, chỉ là
đồng hồ phải đang nhìn đúng lúc.

Lý do: `getReadyState` chỉ được lấy mẫu **đúng một lần** lúc `onShow`, còn cạnh
`onopen` thì đã nổ trước đó và không ai nghe. Mở band app trước thì kịp bắt; mở
ngược lại thì hụt, và **không bao giờ có lần kiểm tra thứ hai**.

Nên thay vì đoán chữ ký, ta bỏ luôn sự phụ thuộc vào thứ tự:

- **Poll `getReadyState` mỗi 3s** khi trang đang hiển thị, xử lý lúc chuyển
  trạng thái → phone bật lúc nào, đồng hồ nhận ra trong vài giây.
- **Hàng đợi gửi** trên app object (đổi trang không mất), tối đa 20, phát lại
  cách nhau 300ms khi kênh lên. Điểm bấm lúc mất kết nối không còn biến mất.

### Còn tồn đọng

- Chữ ký `connect()` — nếu tìm ra thì đồng hồ chủ động mở kênh được, không phải
  chờ phone. Nút **2 · CONNECT TRY** trên trang DIAG thử 8 dạng gọi và log lỗi
  từng cái.
- `launchWearApp()` trả OK nhưng **chưa xác minh được nó có thật sự bật app trên
  đồng hồ hay không** — `open` vẫn 0 sau lệnh đó.
- **Vẫn phải vào Mi Fitness sync để lấy auth khi mất.** Nằm ngoài tầm ta: SDK
  bind vào service XMS trong Mi Fitness.

### 🐛 Bug list nhạc: tìm ra một nguyên nhân độc lập

`<list-item>` **không có `height` thì tính ra 0px và không vẽ gì**, kéo theo cả
con của nó:

| Trang | style list-item | Kết quả |
|---|---|---|
| `settings` | `height: 100px` | ✅ hiện |
| `media_list` | *không có* | ❌ trắng |
| `diag` | *không có* | ❌ trắng |

Nghĩa là **kể cả những lần payload về tới nơi, danh sách nhạc cũng không thể hiện
ra được**. Đã cho height cả 4 loại item. Phần truyền dữ liệu có hỏng nữa hay
không thì log `recv action=media_list` sẽ trả lời.

Hai cơ chế khả dĩ khiến `addListener` chết, cả hai đều đang hiện diện trong code:

- **(a) Race remove/add** — mục 3 ở trên. Giải thích được cả tính "lúc được lúc không".
- **(b) Chưa thực sự có quyền DEVICE_MANAGER** — mục 5. Khớp với lỗi phân quyền
  bạn từng gặp khi debug.

### Giả thuyết phụ, chưa loại được

- ~~**(c) Mi Fitness không biết band app tồn tại**, vì RPK cài bằng *Notify for
  Xiaomi* chứ không phải bằng Mi Fitness.~~ **ĐÃ LOẠI.** Notify chỉ tham gia lúc
  *cài đặt*, hoàn toàn không có mặt lúc chạy — thực tế nó còn phải nhường
  đường, vì muốn Notify kết nối được thì phải tắt chạy ngầm của Mi Fitness. Quan
  trọng hơn: giả thuyết này dự đoán **hỏng 100%**, trong khi thực tế **lúc được
  lúc không**. Một dự đoán sai bản chất, không phải sai chi tiết.
- **(c′) Nhiều page cùng giành một kênh interconnect.** Xem mục riêng bên dưới —
  đây là ứng viên số một cho bug list nhạc.
- **(d) Mod Mi Fitness 3.33.6 quá cũ** so với `xms-wearable-lib 1.4`, hoặc phần
  vá của mod làm hỏng bước xác thực chữ ký ở chiều nhận.
- **(e) Vòng đời Activity.** Dart có cờ `_isInitialized` chặn mọi lần
  `initialize()` sau lần đầu; `onDestroy` thì gọi `removeListener`. Activity bị
  huỷ/tạo lại là listener mất mà không ai đăng ký lại.

### 🐛 Bug list nhạc: nhiều page giành một kênh

Page cũ **không bị huỷ** khi mở page mới. QuickApp có `onHide` và `onDestroy` là
hai hook riêng biệt, và runtime có hẳn `destroyPage` — `router.push` chỉ đẩy page
cũ xuống `onHide` và **giữ nguyên instance JS cùng toàn bộ closure của nó**;
`onDestroy` chỉ chạy khi page bị pop khỏi stack. Nên đúng như nghi ngờ: các page
**chồng lên nhau và cùng sống**.

Vấn đề nằm ở chỗ này:

```js
this.connect.onmessage = (data) => { ... }
```

`onmessage` là **một ô property duy nhất**, không phải danh sách listener như
`addEventListener`. Ba page (`index`, `settings`, `media_list`) đều lấy kênh qua
`interconnect.instance()`, và **hai trong ba** ghi đè cái ô đó. Tệ hơn:
`index.ux` trong `onHide` **gán nó bằng `null`**.

Kịch bản khớp chính xác với triệu chứng:

1. `index` → `settings` → `media_list`
2. `media_list.onShow` gán `onmessage` của nó rồi bắn `request_media_list`
3. nếu `index.onHide` chạy **sau** `media_list.onShow` (thứ tự này chưa kiểm
   chứng được — runtime là binary, không có source để đọc), nó **xoá đúng cái
   handler mà `media_list` vừa gán**
4. phone trả list về → rơi vào `onmessage === null` → **mất trắng, không lỗi, không log**

Ngoài ra `settings.ux` **không gán handler nào cả**, nên suốt thời gian màn hình
settings hiển thị, kênh nhận của cả app là `null`. Mọi phản hồi từ phone trong
khoảng đó đều rơi vào hư không — kể cả phản hồi cho chính những lệnh mà
`settings.ux` vừa `send()` xong trước khi `router.back()`.

**Điểm mấu chốt:** dù thứ tự `onShow`/`onHide` thực tế là gì, thiết kế hiện tại
vẫn sai. Cách sửa đúng là **bỏ hẳn sự phụ thuộc vào thứ tự**: một chủ sở hữu kênh
duy nhất ở `app.ux`, giữ một danh sách subscriber, page chỉ đăng ký/huỷ đăng ký
phần của mình, và **không page nào được phép gán `onmessage = null`**.

### Việc cần làm — theo thứ tự

**Bước 0 — mở mắt trước đã. Đừng sửa mù.**

1. Watch: thêm callback `fail` vào **mọi** `connect.send()`, log `code`.
2. Watch: log thẳng `getReadyState()` ra số `status`, đừng ép về boolean.
3. Android: bọc `addListener` bằng `addOnSuccessListener` / `addOnFailureListener`,
   log `Status.getCode()` và tên exception. Chỉ `result.success(true)` **sau khi**
   `addListener` báo thành công.
4. Android: log mảng `Permission[]` mà `requestPermission` trả về.
5. Watch: log `onopen` / `onclose` kèm timestamp, để biết cạnh có bị bỏ lỡ không.
6. Watch: log `onInit` / `onShow` / `onHide` / `onDestroy` của **cả ba page** kèm
   timestamp → xác định dứt điểm thứ tự lifecycle, thứ mà không đọc được từ source.

Chạy một lần, đọc log, lúc đó mới biết đang sửa cái gì.

**Bước 1 — sửa những lỗi đã chắc chắn:**

7. Xâu chuỗi `removeListener` → `addListener` (gắn cả success lẫn failure vào
   `removeListener`, vì nó fail khi chưa có listener nào).
8. Kiểm tra `Permission[]` có thật sự chứa `DEVICE_MANAGER` rồi mới `addListener`.
9. Watch: một chủ sở hữu kênh duy nhất ở `app.ux` + danh sách subscriber; không
   page nào được gán `onmessage = null`.
10. Watch: `getReadyState()` phải được gọi lại định kỳ (hoặc ít nhất mỗi lần
    `onShow` + một timer), thay vì chụp đúng một lần rồi tin mãi mãi.

**Bước 2 — làm cho nó tự lành:**

11. Retry `addListener` có backoff.
12. `WidgetsBindingObserver` phía Dart → re-init khi app resume; bỏ cờ
   `_isInitialized` đang chặn retry.
13. `isWatchConnected` phải gọi `getConnectedNodes()` thật, không phải trả về
    `watchNodeId != null` (hiện tại set một lần là xanh vĩnh viễn).
14. Dùng `launchWearApp()` → nút "Mở app trên đồng hồ", bỏ được bước 2 của nghi thức.
15. Heartbeat ping/pong ~10s để phát hiện kênh chết mà vẫn báo mở.

---

## 7. Câu hỏi còn mở (dành cho vòng research tiếp theo)

Tài liệu Xiaomi Vela chủ yếu là tiếng Trung. Những câu hỏi cần tìm lời đáp:

1. `getReadyState().status` trong `@system.interconnect` **chính xác** phản ánh
   cái gì? Kênh BLE, hay việc app phone cùng package đã bind? Bảng giá trị đầy đủ?
2. `MessageApi.sendMessage` giới hạn **bao nhiêu byte** một lần? (Liên quan trực
   tiếp tới bug list nhạc ~2KB không sang được — xem `docs/`.)
3. `addListener` có yêu cầu band app đang **chạy foreground** không?
4. Band app cài bằng đường bên thứ ba (Notify for Xiaomi) có được service XMS của
   Mi Fitness ghi nhận như app cài chính thống không?
5. `requestPermission` trả mảng rỗng trong trường hợp nào, và có cần user thao tác
   tay trong Mi Fitness không?
6. Bản Mi Fitness tối thiểu nào tương thích `xms-wearable-lib 1.4`?

Tài liệu tham khảo đã có: `docs/SETUP_GUIDE.md`, `docs/fix_connect.md`,
`docs/wear_api.md`, `docs/old_logic.md`, `docs/conversation_01.json`.
