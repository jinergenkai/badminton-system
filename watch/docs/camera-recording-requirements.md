# Quay video trận đấu: requirements sơ bộ

Trạng thái: giai đoạn 1 đã code, 2026-10-03 (`lib/features/camera/`, `CameraRecorder.kt`).
Đã thử trên Redmi 13C thật: quay, tách file, JSON, đồng bộ giờ. Chưa thử trận thật với band + hotspot.

### Khác với bản nháp (và lý do)
- **Thư mục: `Download/Godminton/YYYY-MM-DD/`**, không phải `Movies/`. MediaStore chỉ
  nhận file video trong `Movies/`, không cho đặt `.json` cạnh `.mp4`. `Download/` nhận cả hai.
- **Điện thoại ping tablet**, không phải ngược lại: phép đổi giờ nằm trọn ở máy ghi JSON.
  Lệch = giờ tablet − giờ điện thoại, trung vị 5 lần ping. Lần đo đầu: 39 giây.
- **Mỗi sự kiện được ack.** Tablet giữ trong hàng đợi đến khi có ack, nối lại thì gửi lại.
  Điện thoại bỏ bản trùng theo `cid:seq`.
- **Mốc bắt đầu trận = lúc bấm start trên band** (màn hình bắt đầu mới), không phải điểm đầu.
- **Chưa có MP4 phân mảnh.** CameraX không tự đóng file khi app bị kill, nên mất tối đa
  file đang quay (≤ 1 set, ≤ 40 phút).
- **Chưa khóa lấy nét / phơi sáng.**
- `match_end` cho set kết thúc bằng End set đến từ bản ghi `match_record` (status `stopped`).
- JSON có thêm: `startWallEstimated`, `continuedFrom` (`joined` / `split` / `reopened`),
  `ralT`, `bandStartedAt`, `bandEndedAt`, `recorderError`, `lens`.

### Thêm sau lượt đầu (2026-10-03)
- **Chế độ máy.** Utility → *Use this device as the corner camera*: app khởi động lại và chỉ
  mở camera. Không chạy database, band, TTS, nhạc hay thư viện âm thanh. Nút *Board mode*
  trên màn camera để chuyển lại. Đo RAM ở chế độ camera: khoảng 214 MB PSS, đã gồm bộ đệm camera.
- **Tự tìm camera.** Điện thoại phát UDP 8766 mỗi 2 giây, tablet nối vào máy vừa phát.
  Chạy được cả qua hotspot lẫn khi chung Wi-Fi; nếu không thấy tín hiệu thì dùng gateway
  (trường hợp hotspot). Ô địa chỉ chỉ dùng khi Wi-Fi chặn broadcast; màn camera có hiện IP.
- **Camera bắt đầu quay giữa set:** gửi `resync`, bảng điểm báo lại set đang chơi
  (`joined`, kèm tỉ số).
- **Tỉ số chèn thẳng vào video** (CameraX `OverlayEffect`): ô đỏ/xanh và giờ ở góc trên trái,
  chỉ vẽ trong dải 16:9 của khung cảm biến 4:3. Điện thoại camera: mặc định bật. Tablet:
  mặc định tắt (+22% CPU).
- **Tablet tự quay** (giai đoạn 2): Utility → *Record on this device too*. Không có preview,
  sự kiện lấy thẳng trong app (không cần đổi giờ), `role: "front"`. Đo trên tablet sân,
  khi đang quay 1080p30: app khoảng 29% một nhân (51% nếu bật tỉ số), dịch vụ camera
  khoảng 30%, bộ mã hóa khoảng 6%.
- **Camera trước hoặc sau** chọn riêng cho từng máy.
- **Đổi chỗ cắt file (thay §3.3):** cắt khi **bắt đầu set** (New game / Same 4 / chọn xong
  người trên band), không cắt 5 giây sau khi kết thúc. Mỗi file bắt đầu đúng lúc bấm start,
  chứa set đó và đoạn nghỉ phía sau (đuôi dễ cắt bỏ). Done, Resume, End set, thoát app: không
  cắt. Nhảy vào giữa set (`joined`) chỉ cắt nếu file đang chứa một set khác. File dưới 3 giây
  thì không cắt. Chuyển file mất khoảng 0,5–1 giây, nên `startS` hơi âm (ví dụ −0,8): lúc bấm
  start nằm ở cuối file trước, còn cú giao cầu đầu tiên đến sau đó vài giây.
- **Khóa lấy nét / độ sáng** (3A lock của Camera2): sau khi bấm Start 2 giây thì lấy nét
  giữa khung một lần rồi giữ, khóa độ sáng (AE) và cân bằng trắng (AWB); Stop thì mở. Có
  công tắc, mặc định bật. Ống kính không lấy nét được (đa số camera trước) chỉ khóa độ sáng.
- **Gallery:** liệt kê `Download/Godminton` của máy, nhóm theo ngày, có ảnh thu nhỏ, thời
  lượng và tỉ số; bấm để xem bằng trình phát của máy; nhấn giữ để chọn nhiều và xóa (xóa
  kèm `.json`).

## 1. Mục tiêu

Mỗi trận đấu có một file video riêng kèm file JSON ghi điểm số và thời điểm từng điểm. Người dùng không phải bấm quay hay cắt tay.

Các file này là đầu vào cho pipeline phân tích video trên PC (`badminton-analysis`: hiệu chỉnh sân, TrackNet, pose, đường bay 3D).

Ngoài phạm vi (giai đoạn này):
- Upload lên mạng.
- Phân tích video ngay trên máy.
- Tự cắt bớt đoạn nghỉ đầu file (việc này làm trên PC, dựa vào JSON).
- Tự chuyển file về PC. Người dùng tự copy.

## 2. Thiết bị và vai trò

Hai máy cài **cùng một app** (`bandcounter-flutter`). Vai trò chọn theo màn hình đang mở.

| Máy | Vai trò | Việc làm |
|---|---|---|
| Tablet, đặt giữa sân | **Bảng điểm** (như hiện tại) | Kết nối band, hiện điểm, đọc điểm. Gửi sự kiện trận sang máy camera. Giai đoạn 2: tự quay bằng camera trước. |
| Redmi 13C, đặt ở góc sân | **Camera góc** | Phát hotspot, chạy WebSocket server, quay video, tách file khi hết trận. |

Ghi chú:
- Tablet không có SIM. Điện thoại phát hotspot, không cần data hay internet.
- Điểm bấm từ band. Tablet chỉ xem, không ai chạm vào trong lúc chơi.

## 3. Màn hình "Camera góc" (máy điện thoại)

Đây là màn hình riêng, mở bằng nút **Utility** (ô lưới) trên bảng điểm → *Use this phone as the corner camera*.

### 3.1 Giao diện
- **Ô xem trước camera.** Có nút ẩn/hiện; ẩn để đỡ nóng máy.
- **Trạng thái:**
  - Đang quay: chấm đỏ kèm thời lượng file hiện tại.
  - Kết nối với tablet: đã nối / mất kết nối, và độ lệch đồng hồ.
  - Trận hiện tại: tỉ số.
  - Máy: dung lượng trống, pin, nhiệt độ.
- **Nút:**
  - Bắt đầu / Dừng phiên quay.
  - **Tách file ngay**: dùng khi mất kết nối với tablet.
  - Mở cài đặt hotspot.
- Giữ màn hình luôn sáng (`wakelock_plus`, đã có trong app). Hạ độ sáng màn hình xuống thấp nhất trong lúc quay.
- Khóa màn hình ở chiều ngang.

### 3.2 Hotspot
- Android không cho app tự bật hotspot của hệ thống. Người dùng bật tay, app chỉ có nút mở trang cài đặt.
- **Tên mạng và mật khẩu cố định**, để tablet tự kết nối lại như một Wi-Fi đã lưu.
- **Ưu tiên băng tần 5GHz** nếu tablet hỗ trợ. Wi-Fi 2.4GHz dùng chung sóng với Bluetooth và có thể làm đứt kết nối BLE với band.
- Không dùng `LocalOnlyHotspot`: API này đổi tên mạng và mật khẩu mỗi lần bật.

### 3.3 Cách quay: quay liên tục, tách file khi hết trận
Lý do: rally đầu tiên bắt đầu *trước* khi có điểm đầu tiên. Nếu đợi sự kiện "bắt đầu trận" mới quay thì sẽ mất rally đó.

- Bấm **Bắt đầu** thì quay liên tục.
- Khi nhận `match_end`:
  - Quay thêm **5 giây**, rồi dừng file hiện tại.
  - Mở ngay file mới. Khoảng hở khi chuyển file chừng 1 giây, rơi vào lúc nghỉ giữa trận.
- Mỗi file vì thế chứa: thời gian nghỉ trước trận, trận đấu, và 5 giây sau trận. File JSON đi kèm ghi lúc trận bắt đầu, để PC cắt bỏ đoạn nghỉ.
- **Giới hạn an toàn:** một file dài quá 40 phút (quên kết thúc trận) thì tự tách file.
- **Hết chỗ:** dung lượng trống dưới 2GB thì dừng quay và báo trên màn hình.
- **Giữ file dở:** app bị tắt giữa chừng thì file đang quay vẫn phải xem được. Dùng MP4 phân mảnh, hoặc CameraX tự đóng file.

### 3.4 Thông số camera
Các thông số này ảnh hưởng trực tiếp tới chất lượng phân tích, nên phải **cố định và giống nhau giữa các buổi**.

| Thông số | Giá trị | Lý do |
|---|---|---|
| Độ phân giải | 1920×1080 | Đủ để thấy quả cầu |
| FPS | 30 (máy chỉ hỗ trợ tối đa 30) | — |
| **Chống rung** | **TẮT** | Chống rung cắt và bẻ cong khung hình theo từng frame, làm hỏng hiệu chỉnh sân |
| Zoom | 1x, camera chính | Giữ hiệu chỉnh và tiêu cự ổn định |
| HDR, làm đẹp, AI cảnh | Tắt | — |
| Lấy nét / phơi sáng | Khóa sau khi bắt đầu (nếu API cho phép) | Tránh nhảy sáng khi có người đi qua |
| Âm thanh | **Bật** | Tiếng vợt chạm cầu giúp phát hiện cú đánh |
| Bitrate | ~12 Mbps (khoảng 5.4GB/giờ) | 31GB trống đủ chừng 5 giờ |

**Gợi ý triển khai:** Kotlin dùng CameraX `VideoCapture` + `Recorder`, gọi qua MethodChannel. Plugin `camera` của Flutter không chỉnh được chống rung và bitrate.

### 3.5 Lưu file
- Thư mục: `Movies/Godminton/YYYY-MM-DD/`, ghi qua MediaStore để thấy được khi cắm cáp vào PC.
- Tên file: `YYYY-MM-DD_HHMMSS_<matchId 6 ký tự>_<A>-<B>.mp4` và một file `.json` cùng tên.
- File quay chưa gắn với trận nào: `..._nomatch.mp4`. Đây là đoạn từ lúc bấm Dừng sau trận cuối.

## 4. Kết nối tablet ↔ điện thoại

- Điện thoại là **server**: WebSocket ở cổng `8765`, dùng `dart:io` `HttpServer` + `WebSocketTransformer`, không cần thêm package.
- Tablet là **client**:
  - Không phải nhập IP. Trong mạng hotspot, gateway chính là điện thoại, nên lấy `WifiGatewayIP` (qua `network_info_plus`).
  - Tự kết nối lại sau mỗi 2 giây khi mất kết nối.
- **Tablet không được phụ thuộc vào camera.** Mất kết nối không được làm chậm hay chặn luồng band → bảng điểm.
- Sự kiện chưa gửi được thì xếp vào hàng đợi, có kết nối lại thì gửi bù. Mỗi sự kiện có `seq` để bên nhận bỏ bản trùng.

### 4.1 Tin nhắn (JSON)
Tablet gửi sang điện thoại:

| type | Khi nào | Trường |
|---|---|---|
| `hello` | Vừa kết nối | `device`, `appVersion` |
| `ping` | Mỗi 10 giây | `t0` (đồng hồ tablet, ms) |
| `match_start` | Band báo trận mới (`matchId` mới, status `active`) | `matchId`, `t`, `lineup` |
| `point` | Mỗi điểm | `matchId`, `team` (A/B), `scoreA`, `scoreB`, `rev`, `t` |
| `undo` | Hoàn tác | `matchId`, `scoreA`, `scoreB`, `rev`, `t` |
| `match_end` | Trận xong: `completed` hoặc `stopped` | `matchId`, `status`, `scoreA`, `scoreB`, `startedAt`, `endedAt`, `rallies`, `ralT`, `lineup`, `server0`, `receiver0` |
| `match_reopen` | Hoàn tác sau khi đã thắng | `matchId`, `t` |

Điện thoại gửi sang tablet:
- `pong`: gồm `t0`, `t1` (lúc nhận), `t2` (lúc gửi).
- `status` (mỗi 5 giây): `recording`, `file`, `freeGB`, `battery`, `tempC`. Tablet hiện một chấm REC nhỏ ở góc bảng điểm.

**Đồng bộ đồng hồ** (kiểu NTP):
- Độ lệch = ((t1 − t0) + (t2 − t3)) / 2. Lấy trung vị của 5 lần ping gần nhất.
- Điện thoại đổi mọi `t` của tablet sang đồng hồ của mình, rồi sang **giây tính từ đầu file video**.
- Nên đạt sai số dưới 50ms.

**Chỗ móc vào code hiện có:**
- `match_end`: trong `ScoreController._persistBandTerminalMatch` (lúc band đã sẵn sàng), hoặc `_checkGameEnd` (khi không có band).
- `point`: các nhánh `incrementTeamA` / `incrementTeamB` và luồng trạng thái từ band.
- `match_reopen`: nhánh `status == 'active' && isGameEnded` trong `_handleWatchCommand`.

### 4.2 Hoàn tác sau khi thắng
File đã tách thì để nguyên. Điện thoại ghi `reopened: true` vào JSON của file đó. File kế tiếp nhận các điểm còn lại và `match_end` mới. PC sẽ ghép hai file theo `matchId`.

## 5. JSON đi kèm video
Đây là hợp đồng với pipeline phân tích. Mọi mốc thời gian quy về **giây tính từ frame đầu tiên của file**.

```json
{
  "schema": 1,
  "video": "2026-10-03_191502_a1b2c3_21-18.mp4",
  "role": "corner",
  "device": "Redmi 13C",
  "width": 1920, "height": 1080, "fps": 30,
  "stabilization": false,
  "recordStartWall": "2026-10-03T19:15:02.120+07:00",
  "clockOffsetMs": -132, "clockSyncSamples": 5, "clockRttMs": 18,
  "match": {
    "matchId": "a1b2c3d4-...",
    "status": "completed",
    "scoreA": 21, "scoreB": 18, "winner": "A",
    "startS": 74.3,
    "endS": 1012.8,
    "reopened": false,
    "lineup": { "red": ["p1", "p2"], "blue": ["p3", "p4"], "names": {"p1": "Hùng"}, "server0": "p1", "receiver0": "p3" },
    "rallies": "AABAB..."
  },
  "events": [
    { "type": "match_start", "s": 74.3 },
    { "type": "point", "team": "A", "scoreA": 1, "scoreB": 0, "s": 92.6 },
    { "type": "undo",  "scoreA": 0, "scoreB": 0, "s": 95.1 },
    { "type": "match_end", "s": 1012.8 }
  ],
  "gaps": [ { "fromS": 300.0, "toS": 312.5, "reason": "ws_disconnected" } ]
}
```

Giải thích:
- `point.s` là lúc điểm được *bấm trên band*, thường chậm 1–3 giây sau khi cầu chạm sàn. PC sẽ dùng mốc này để tìm điểm cầu rơi gần nhất phía trước nó.
- `gaps`: các khoảng mất kết nối. Thời điểm của sự kiện gửi bù trong khoảng này lấy theo `t` gốc, nên vẫn đúng.

## 6. Giai đoạn 2: tablet tự quay bằng camera trước
- Dùng chung module quay của mục 3.3–3.5, với `role: "front"`, camera trước. Tablet tự kích hoạt luôn, không cần WebSocket.
- Không hiện ô xem trước. Bảng điểm vẫn chiếm toàn màn hình. Nếu thiết bị bắt buộc phải có surface xem trước thì dùng một surface 1×1 px.
- **Điều kiện bắt buộc:** không làm hỏng BLE với band, giọng đọc điểm hay nhạc.
  - Phải đo trước và sau: tỉ lệ rớt kết nối band, độ trễ đọc điểm, nhiệt độ.
  - Có công tắc bật/tắt trong Cài đặt, mặc định tắt.
- Hai video (góc sân + giữa sân) cùng `matchId`, cùng mốc thời gian đã đồng bộ. PC có thể dùng cặp này để triangulation. Góc nhìn cách nhau khoảng 60–90° là tốt.

## 7. Tiêu chí nghiệm thu
1. Một buổi 3 trận: điện thoại có 3 cặp `.mp4` + `.json` và một file `_nomatch`. Không ai chạm vào điện thoại giữa các trận.
2. Mỗi file chứa trọn trận, từ trước rally đầu tiên tới 5 giây sau điểm cuối.
3. Tắt hotspot 30 giây giữa trận rồi bật lại: video không đứt. Các sự kiện được gửi bù và đúng thời gian, có ghi trong `gaps`.
4. Sai số `point.s` so với video dưới 0.2 giây. Kiểm tra bằng cách bấm điểm trên band ngay trước camera, rồi so frame có ngón tay bấm.
5. Quay liên tục 60 phút: không mất frame (kiểm tra bằng `ffprobe`), nhiệt độ dưới 45°C, file luôn mở được.
6. Mở màn hình Camera góc không làm tăng tỉ lệ rớt BLE giữa tablet và band.

## 8. Câu hỏi còn mở
- Tablet có hỗ trợ 5GHz không? Nếu không, phải thử độ nhiễu với BLE ở 2.4GHz.
- Có cần giữ đoạn nghỉ giữa trận không? Hiện tại có giữ, PC sẽ cắt.
- Pin: điện thoại có cắm sạc khi quay không? Nếu không, 1 giờ quay ước tính tốn 25–35% pin.
