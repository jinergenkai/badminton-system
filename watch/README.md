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

Đẩy RPK sang máy rồi cài qua Notify for Xiaomi:

```bash
adb push bandcounter-watch/dist/com.hung.bandcounter.release.1.0.0.rpk /sdcard/Download/
```

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

### Giả thuyết chính

> `addListener` phía Android thất bại **im lặng**, nên chiều watch → phone chết,
> trong khi `sendMessage` không cần kênh ngược nên phone → watch vẫn chạy.

Vẫn là giả thuyết mạnh nhất, nhưng **không được dùng chấm đỏ làm bằng chứng cho
nó** — xem mục ngay trên.

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
