# badminton-analysis

Phân tích video cầu lông quay bằng **một điện thoại đặt trên tripod**: dựng lại sân chuẩn BWF trong
video, theo dõi quả cầu, nhận diện người chơi và cú chạm vợt, rồi **khôi phục đường bay 3D của cầu
bằng vật lý** — tất cả từ một camera duy nhất.

![demo](docs/demo.gif)

▶ Bản nét hơn: [docs/demo.mp4](docs/demo.mp4) (0–22 s của `danh-cau`).
Trái: video gốc với sân, khung xương, vệt cầu (đỏ), đường bay 3D chiếu ngược vào ảnh (xanh, nét liền
= có dữ liệu, chấm = ngoại suy) và cú chạm vợt (`HIT`, `HIT*` = cú bị bỏ sót đã khôi phục).
Phải: cảnh 3D — sân, lưới, camera thật, người chơi 3D, đường bay 3D kèm độ cao, điểm chạm, điểm rơi.

---

## Mục lục

1. [Cài đặt và chạy](#1-cài-đặt-và-chạy)
2. [Tổng quan pipeline](#2-tổng-quan-pipeline)
3. [Thuật toán chi tiết](#3-thuật-toán-chi-tiết)
   - [3.1 Hệ toạ độ sân](#31-hệ-toạ-độ-sân)
   - [3.2 Nền sân trống bằng trung vị](#32-nền-sân-trống-bằng-trung-vị-background)
   - [3.3 Calibration camera từ vạch sân](#33-calibration-camera-từ-vạch-sân-calibrate)
   - [3.4 Phát hiện cầu bằng TrackNetV3](#34-phát-hiện-cầu-bằng-tracknetv3-detect)
   - [3.5 Theo dõi đường bay trên ảnh](#35-theo-dõi-đường-bay-trên-ảnh-track)
   - [3.6 Người chơi: pose và nâng lên 3D](#36-người-chơi-pose-và-nâng-lên-3d-pose-players)
   - [3.7 Cú chạm vợt](#37-cú-chạm-vợt-hits)
   - [3.8 Đường bay 3D bằng vật lý](#38-đường-bay-3d-bằng-vật-lý-flight)
   - [3.9 Điểm rơi](#39-điểm-rơi-landing)
   - [3.10 Render](#310-render-render)
4. [Kết quả và độ tin cậy](#4-kết-quả-và-độ-tin-cậy)
5. [Giới hạn và hướng tiếp theo](#5-giới-hạn-và-hướng-tiếp-theo)
6. [Tham khảo](#6-tham-khảo)

---

## 1. Cài đặt và chạy

```bash
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements.txt
.venv/Scripts/python -m pip uninstall -y onnxruntime          # rtmlib kéo bản CPU vào, làm hỏng GPU
.venv/Scripts/python -m pip install --no-deps onnxruntime-gpu==1.23.2
git clone https://github.com/alenzenx/TrackNetV3.git third_party/TrackNetV3
git -C third_party/TrackNetV3 checkout d1d96f39d275970d3597a45926f4f46e6ee85e2c
```

Những thứ không nằm trong git (`data/`, `models/`, `outputs/`):

| File | Nguồn |
|---|---|
| `models/tracknet_v3.pt` | `model_best.pt` — link Google Drive trong README của `alenzenx/TrackNetV3` |
| `models/pose/yolox_x_humanart.onnx` | `yolox_x_8xb8-300e_humanart-a39d44ed.zip` trên download.openmmlab.com (rtmlib, mode `performance`) |
| `models/pose/rtmpose_x_body7_384x288.onnx` | `rtmpose-x_simcc-body7_pt-body7_700e-384x288-71d7b7e9_20230629.zip` (cùng nguồn) |
| `data/videos/<tên>.mp4` | video của bạn |

Chạy toàn bộ:

```bash
.venv/Scripts/python -m badminton configs/danh-cau-02.json
```

Mỗi bước ghi kết quả vào `outputs/<tên config>/` và được **cache**: lần sau bỏ qua.
`--force <bước...>` để tính lại, `--only <bước...>` để chỉ chạy vài bước. Cần `ffmpeg` trong PATH
để xuất H.264 có âm thanh. Pipeline chạy headless nên đặt được trên máy GPU từ xa
(điện thoại upload video → máy GPU xử lý → tải kết quả).

### Thêm video mới

```json
{
  "video": "data/videos/<tên>.mp4",
  "floor_top": 300,
  "ignore": [[850, 480, 1024, 576]],
  "seeds": [
    [[0, -1.98], [88, 408]],
    [[3.05, -1.98], [430, 373]],
    [[3.05, -6.7], [930, 479]],
    [[0, -6.7], [524, 780]]
  ]
}
```

- `seeds`: ≥ 4 cặp `[toạ độ sân (m), pixel]`, ước lượng thô là đủ. Pixel **được phép nằm ngoài khung
  hình** (giao điểm suy từ phương trình 2 vạch nhìn thấy). Tránh dồn các điểm sát nhau trên một vạch.
- `floor_top`: phía trên hàng pixel này không có sàn. `ignore`: hình chữ nhật bỏ qua (logo, watermark).
- Sau bước `calibrate`, mở `court_overlay.png`: vạch vàng phải nằm trên vạch trắng. Dời tripod = config mới.

---

## 2. Tổng quan pipeline

```
video ──► background ──► calibrate ─────────────────────────────┐
  │        (trung vị)     (sân chuẩn ↔ vạch trắng → K, R, t)      │
  │                                                              ▼
  ├────► detect ──► track ──────────────► hits ──► flight ──► landing ──► render
  │      TrackNetV3  multi-target          ▲       vật lý 3D    vật lý +    video +
  │      mọi ứng viên  + chọn đường bay    │       + khôi phục  vật trắng   cảnh 3D
  │                                        │       cú bị sót    nằm yên
  └────► pose ──► players ─────────────────┘
         YOLOX-x   chân → sàn (homography),
         RTMPose-x khớp → 3D, ID người
```

| Bước | Đầu ra | Thời gian* |
|---|---|---|
| `background` | `background.png` | ~4 s |
| `calibrate` | `calib.json`, `court_overlay.png` | < 1 s |
| `detect` | `candidates.csv` | ~75–80 fps |
| `track` | `shuttle.csv`, `court_volume.png` | < 1 s |
| `pose` | `pose.npz` | ~10 fps (chậm nhất) |
| `players` | `players.csv`, `players_k3d.npy` | ~5 s |
| `hits` | `hits.json` | < 1 s |
| `flight` | `flights.json` | ~1 phút |
| `landing` | `landings.json` | ~40 s |
| `render` | `<tên>_3d.mp4` | ~1 phút |

\* RTX 5060 Ti 16 GB, video 1024×576–1280×720, 30 fps, 2–2.5 phút.

Mã nguồn: `badminton/` — `court.py` (hình học sân), `background.py`, `calibrate.py`, `shuttle.py`,
`track.py`, `players.py`, `hits.py`, `flight.py`, `landing.py`, `render.py`, `__main__.py` (pipeline).

---

## 3. Thuật toán chi tiết

### 3.1 Hệ toạ độ sân

Đơn vị mét, sân đôi BWF 13.4 × 6.1 m:

- **X** ngang sân: 0 = biên đôi trái, 6.1 = biên đôi phải (biên đơn ở 0.46 và 5.64).
- **Y** dọc sân: 0 = lưới, âm = nửa sân phía camera, dương = nửa bên kia.
  Giao cầu ngắn ±1.98, giao cầu dài (đôi) ±5.94, đường cuối ±6.7.
- **Z** hướng lên từ mặt sàn. Lưới cao 1.55 m ở cột, 1.524 m ở giữa, mép dưới 0.79 m.

### 3.2 Nền sân trống bằng trung vị (`background`)

Camera đứng yên nên mỗi pixel phần lớn thời gian nhìn thấy sàn; người chơi thì luôn di chuyển.
Lấy 60 frame **rải đều cả video** và tính trung vị theo thời gian cho từng pixel, từng kênh màu:

```python
frames = [read(i) for i in np.linspace(0, n - 1, 60).astype(int)]   # (60, H, W, 3)
bg = np.median(np.stack(frames), axis=0)
```

- Trung vị chứ không phải trung bình: trung bình để lại "bóng ma" mờ của người, trung vị thì không
  miễn là mỗi pixel bị che **dưới một nửa** số frame.
- Rải đều chứ không lấy frame liên tiếp: trong vài giây liên tiếp người gần như đứng yên.
- Giới hạn: ai đứng một chỗ quá nửa thời gian vẫn để lại bóng mờ.

Nền này được dùng cho calibration (vạch không bị người che) và cho bước tìm vật trắng nằm yên.

### 3.3 Calibration camera từ vạch sân (`calibrate`)

Mục tiêu: tìm phép chiếu từ toạ độ sân (mét) sang pixel, rồi suy ra **tiêu cự** và **vị trí/hướng
camera** — không cần bảng caro hay thông số điện thoại.

1. **Mặt nạ vạch trắng:** HSV với độ bão hoà < 60 và độ sáng > 170. Sàn bóng phản chiếu đèn thành
   những mảng sáng to; giữ lại **nét mảnh** bằng *white top-hat*: `mask − open(mask, 11×11)`.
2. **Bản đồ khoảng cách:** `distanceTransform` — mỗi pixel biết khoảng cách tới vạch trắng gần nhất.
3. **Homography khởi đầu** từ các điểm `seeds` (≥ 4, bình phương tối thiểu `findHomography`).
4. **Tinh chỉnh (chamfer matching):** lấy mẫu 120 điểm trên mỗi vạch của mô hình sân chuẩn, chiếu bằng
   H, đo khoảng cách tới vạch trắng thật (cắt ngưỡng 12 px). Tối ưu 8 tham số của H bằng Powell:

   ```
   cost(H) = mean(min(dist(H·p), 12))  +  0.05 · Σ max(‖H·seed − seed_px‖ − 25, 0)
   ```

   - Điểm nằm **sau camera** (toạ độ thuần nhất w ≤ 0) bị bỏ, nếu không phép chiếu bị lật.
   - Số hạng thứ hai **neo** nghiệm gần các seed: không có nó, bộ tối ưu có thể co cả sân lại đè lên
     một vạch duy nhất (cost ≈ 0 nhưng vô nghĩa — đã gặp thật ở video 02).
5. **Tiêu cự từ homography của mặt sàn.** Với điểm chính ở tâm ảnh và pixel vuông,
   `A = T·H` (T dời gốc về tâm ảnh), hai cột đầu h₁, h₂ của A tỉ lệ với hai trục xoay r₁, r₂ (vuông góc):

   ```
   f² = −(h₁ₓ·h₂ₓ + h₁ᵧ·h₂ᵧ) / (h₁𝓏·h₂𝓏)
   ```

6. **Tư thế camera:** `solvePnP` với K vừa tìm và lưới điểm trên sàn → R, t; vị trí camera `C = −Rᵀt`.

**Kiểm chứng:** camera ra cao 1.32 m và 1.12 m (đúng tầm tripod), đứng sau đường cuối sân lệch ra
ngoài biên ~1 m; chiều cao người chơi tính ra 1.4–1.75 m (mục 3.6) — một phép kiểm tra độc lập.

### 3.4 Phát hiện cầu bằng TrackNetV3 (`detect`)

TrackNet là mạng encoder–decoder (dạng U-Net, bản V3 có thêm attention) nhận **3 frame liên tiếp**
(9 kênh, 512×288) và xuất 3 **bản đồ nhiệt** (heatmap) vị trí cầu. Vì thấy chuyển động, nó học
"vật nhỏ, sáng, bay nhanh" chứ không chỉ hình dạng. Trọng số train trên video thi đấu góc truyền hình.

Khác bản gốc: `predict.py` gốc chỉ lấy **vùng sáng lớn nhất** của mỗi heatmap, nên khi cầu sân bên
cạnh cũng hiện ra, nó có thể thắng. Ở đây giữ **mọi** vùng > 0.5 (toạ độ, diện tích, điểm cao nhất)
và để bộ theo dõi quyết định. Chạy FP16 và không ghi video trung gian: ~75–80 fps (gấp đôi bản gốc).

### 3.5 Theo dõi đường bay trên ảnh (`track`)

1. **Khối không gian sân:** chiếu hộp `[−1.5, 7.6] × [−8.2, 8.2] × [0, 10] m` vào ảnh (bỏ điểm sau
   camera, lấy bao lồi); ứng viên ngoài vùng này bị loại. *Ghi chú:* khi camera đứng sát mép sân,
   vùng này phủ kín khung hình nên không loại được gì — nó chỉ có ích khi camera đặt xa sân.
2. **Multi-target tracking:** mỗi đường bay đang sống dự đoán vị trí kế tiếp
   `p̂ = p_last + v·gap`; gán ứng viên gần nhất trong cổng `30 + 18·gap` px (tham lam, cặp gần nhất
   trước). Vận tốc làm mượt `v ← ½v + ½v_new`. Ứng viên không khớp mở đường bay mới — nhờ vậy cầu sân
   bên có đường bay **riêng** thay vì cướp đường bay của ta. Mất dấu quá 5 frame thì đóng.
3. **Lọc:** bỏ đường bay < 8 điểm hoặc di chuyển < 40 px (đèn trần, khung cửa, giày trắng).
4. **Chọn:** mỗi frame giữ một đường bay có điểm `mật độ × độ dài` cao nhất; lấp chỗ mất dấu ≤ 5 frame
   bằng nội suy tuyến tính.

### 3.6 Người chơi: pose và nâng lên 3D (`pose`, `players`)

- **Pose 2D:** YOLOX-x (tìm người) + RTMPose-x 384×288 (17 khớp COCO) qua `rtmlib`/ONNX Runtime GPU.
  Chọn bản lớn nhất vì ưu tiên độ chính xác (~10 fps).
- **Vị trí trên sân:** chân chạm sàn ⇒ trung điểm hai cổ chân (+4 px tới đế giày) qua `H⁻¹` cho ra
  (X, Y) **chính xác**. Chỉ giữ người đứng trong sân ± 1.2 m.
- **Nâng các khớp lên 3D:** giả sử thân người nằm trên **mặt phẳng đứng đi qua chân, quay về phía
  camera** (pháp tuyến n = hướng ngang từ camera tới chân). Tia nhìn qua pixel của khớp
  `P(t) = C + t·d` cắt mặt phẳng tại

  ```
  t = n·(F − C) / (n·d)
  ```

  Cho độ cao đầu, cổ tay… theo mét. Kém chính xác khi tay vươn thẳng về phía/ra xa camera.
- **ID người:** ghép giữa các frame bằng thuật toán Hungarian trên khoảng cách vị trí sàn
  (ngưỡng 1.2 m, nới theo số frame mất dấu).
- **Kiểm tra:** chiều cao (đầu + 0.12 m) ra 1.53–1.75 m ở video 02 — khớp người thật.

### 3.7 Cú chạm vợt (`hits`)

1. **Thời điểm ứng viên:** đầu mỗi đường bay, và các điểm mà hướng bay trên ảnh **đổi > 50°** hoặc tốc
   độ **tăng > 2.5×** (so 3 frame trước/sau).
2. **Kiểm tra 3D:** tia nhìn tới cầu `C + t·d` phải đi **gần cổ tay** của ai đó (±3 frame). Khoảng
   cách điểm–tia: `‖(W − C) − ((W − C)·d)·d‖ < 1.0 m` (đầu vợt cách cổ tay ~0.6 m).
3. **Điểm chạm** = điểm trên tia gần cổ tay nhất ⇒ **độ cao điểm chạm từ một camera**.
4. **Luật chơi:** gộp ứng viên trong 8 frame; một bên không đánh hai lần liên tiếp (< 20 frame);
   "chạm" dưới 0.25 m là nhặt cầu, bị bỏ.

Âm thanh (tiếng vợt) đã thử nhưng không dùng: cả hai video đều lẫn nhạc nền/tiếng sân khác
(~3 "tiếng tách" mỗi giây).

### 3.8 Đường bay 3D bằng vật lý (`flight`)

**Mô hình cầu lông** — lực cản bậc hai (Cohen et al., 2015):

```
dv/dt = g − (g / V∞²) · |v| · v,     V∞ ≈ 6.7 m/s (vận tốc rơi giới hạn)
```

Đường bay **không phải parabol**: rời vợt gần như thẳng, phanh rất gắt, rồi rơi gần như thẳng đứng.
Tích phân RK4, 4 bước con mỗi frame (viết bằng số thực thuần Python — nhanh hơn numpy 5–10× cho
vector 3 chiều, vì bộ tối ưu gọi hàng chục nghìn lần). Kiểm tra: thả rơi 3 s → 6.70 m/s.

**Vì sao một camera đủ:** mỗi cú có **6 ẩn** (vị trí + vận tốc lúc chạm), mỗi frame cho **2 phương
trình** (pixel x, y) ⇒ 10–30 frame là thừa dữ kiện. Trọng lực đã biết cho **thước đo tỉ lệ thật** mà
một camera thuần tuý không có.

**Bài toán tối ưu** cho mỗi cú (từ cú chạm này tới cú chạm sau):

| Số hạng | Ý nghĩa |
|---|---|
| `π(P(tᵢ)) − pxᵢ` | sai số chiếu lại (pixel) mọi quan sát TrackNet |
| `(p₀ − contact) / 0.25 m` | bắt đầu ở điểm chạm vợt (mục 3.7) |
| `(P(t_next) − contact_next) / 0.4 m` | tới được vợt của cú sau (nếu có) |
| `min(Z, 0) / 0.05` | không chui xuống sàn |
| `max(1.524 − Z_lưới, 0) / 0.05` | qua lưới nếu cú đổi bên |

- Hàm mất mát **soft-L1** (f_scale 6 px) để điểm nhiễu không kéo lệch.
- **Giới hạn cứng:** điểm chạm cao 0.3–3.5 m, vận tốc ≤ 120 m/s.
- **Khởi tạo đa điểm:** lưới 3 hướng × 5 góc nâng × 4 tốc độ (6–40 m/s); chọn 4 điểm đầu tốt nhất để
  tối ưu (`least_squares`, trust-region) — tránh cực tiểu địa phương.
- **Cổng chất lượng ("good"):** trung vị chiếu lại < 6 px, > 70% điểm trong 8 px, ≥ 8 quan sát,
  điểm đầu lệch neo < 1.5 m, tốc độ < 360 km/h.
- **Hai cú dính nhau** (một cú chạm bị sót ở giữa): nếu chỉ phần đầu khớp, cắt ở chỗ 3 điểm liên tiếp
  lệch > 8 px và khớp lại phần đầu.
- **Kiểm tra phần ngoại suy:** sau điểm quan sát cuối, nếu cầu thật lệch > 25 px khỏi đường dự đoán
  2 frame liên tiếp ⇒ cầu đã bị đánh ⇒ **cắt đường bay** ở đó và bỏ điểm rơi ngoại suy.
- **Khôi phục cú bị sót:** các đoạn quan sát chưa được cú nào giải thích ("mồ côi") được cắt tại các
  điểm đổi hướng gấp; mỗi mảnh nhận một cú chạm suy luận — hoặc **vị trí 3D dự đoán ở cuối cú trước**
  (nếu cú trước vừa bị cắt), hoặc cổ tay gần tia nhìn nhất với cổng nới 1.6 m — rồi khớp, lặp lại.
  Đã thử neo "lỏng" vào người gần nhất khi không có cổ tay nào gần: khớp pixel rất đẹp nhưng **sai**
  (điểm chạm dính trần 3.5 m, tốc độ ~13 km/h — nghiệm trượt dọc tia nhìn) ⇒ đã bỏ.

### 3.9 Điểm rơi (`landing`)

Hai nguồn độc lập:

1. **Vật lý:** cú cuối của mỗi pha (không có cú chạm sau) được tích phân tới Z = 0. Ghi lại số giây
   ngoại suy sau lần cuối thấy cầu; > 0.5 s hiển thị dấu `?`.
2. **Vật trắng nằm yên:** TrackNet không thấy cầu đứng yên, nên tìm vật trắng nhỏ **mới xuất hiện** so
   với nền, nằm yên ≥ 0.5 s, cách điểm cuối một đường bay đang rơi ≤ 45 px, xuất hiện trong ~0.7 s sau
   đó. Phân biệt với giày/băng gối trắng: **phía trên quả cầu là sàn trống** (cột ngay trên blob có
   < 25% pixel khác nền), còn trên giày luôn là chân người; nhiều ứng viên thì chọn **nhỏ nhất**
   (cầu ~7 cm, giày ~28 cm ở cùng độ sâu). Ưu tiên chính xác hơn đầy đủ.

### 3.10 Render (`render`)

- **Video:** sân + lưới 3D chiếu vào ảnh, khung xương (xanh = phía camera, hồng = phía xa), vệt cầu,
  đường bay 3D chiếu ngược (đối chiếu trực quan với vệt đỏ), cú chạm, điểm rơi.
- **Cảnh 3D:** camera ảo quay chậm quanh sân (phía camera thật), sân, lưới trong suốt, frustum camera
  thật, người que 3D, đường bay (nét liền đã bay / chấm ngoại suy), quả cầu kèm độ cao và bóng chiếu
  xuống sàn, tia nhìn khi chưa có đường bay khớp.
- Xuất H.264 + âm thanh gốc qua ffmpeg.

---

## 4. Kết quả và độ tin cậy

### Thử với dữ liệu giả có đáp án (camera thật của video 02, nhiễu 3 px, điểm chạm lệch 0.2 m)

| Cú | Sai số 3D | Tốc độ thật / ước tính | Sai số điểm rơi |
|---|---|---|---|
| Phông cao | 7 cm | 71 / 72 km/h | 8 cm |
| Đập | 21 cm | 203 / 209 km/h | 24 cm |
| Lốp | 8 cm | 56 / 53 km/h | 12 cm |
| Bỏ nhỏ | 6 cm | 33 / 32 km/h | 7 cm |
| **Tạt ngang** | **58 cm** | 80 / 91 km/h | 64 cm |

Tạt ngang yếu nhất: đi thẳng, ít cong nên vật lý ít ràng buộc chiều sâu.

### Dữ liệu thật

| | `danh-cau` (1280×720, nhiều sân) | `danh-cau-02` (1024×576, 1 sân) |
|---|---|---|
| Camera | X −0.77, Y −6.35, cao 1.32 m | X −0.97, Y −7.64, cao 1.12 m |
| Cú chạm phát hiện | 56 | 98 |
| Cú bay 3D đạt chuẩn | 39 (18 trực tiếp + 21 khôi phục) | 88 (68 + 20) |
| Sai số chiếu lại (trung vị) | 1.9 px | 1.5 px |
| Điểm TrackNet lệch > 25 px khỏi đường 3D | 3.0% | 2.7% |
| Điểm TrackNet được đường 3D giải thích | 32% | 65% |
| Tốc độ cú đánh (trung vị / max) | 49 / 216 km/h | 55 / 252 km/h |
| Điểm rơi | 8 | 6 |

**Đối chiếu độc lập:** pha 51.3 s của `danh-cau` — vật lý dự đoán rơi ở (1.74, 2.15); quả cầu thật
xác nhận bằng mắt trên sàn ở khoảng (1.5–1.7, 1.7–2.6) ⇒ lệch ~0.3–0.5 m.

Các con số trên là **"khớp nhất quán"**, chưa phải **"đúng đã kiểm chứng"** — chưa có số đo thật.

---

## 5. Giới hạn và hướng tiếp theo

- **Một camera không phân biệt được cầu sân mình với cầu sân bên** nằm trên cùng tia nhìn
  (`danh-cau`: hai điểm OUT lệch 1.5–2.5 m sang sân phải nhiều khả năng là cầu sân bên).
- **ID người bị vỡ** (video 02: 96 ID cho 4 người) — chưa ảnh hưởng cú chạm, cần cho thống kê từng người.
- **Pose chậm** (~10 fps): gộp lô pose theo frame, chạy detector mỗi 3–5 frame, TensorRT FP16
  → dự kiến 30–50 fps mà không giảm chất lượng.
- **30 fps** và nhạc nền làm thời điểm chạm cầu lệch vài frame.

**Bước tiếp theo: 2 camera để có đáp án thật.** Hai tia nhìn nên gần **vuông góc** (60–120°):

```
            sân đối thủ
   ┌──────────────────────┐
   │                      │
 ──┼──────── lưới ────────┼──   ◀── Máy B: ngang lưới, cách biên 3–5 m, cao nhất có thể
   │                      │
   └──────────────────────┘
              ▲
     Máy A: sau đường cuối sân, cao 1.5–2 m+
```

Không đặt hai máy ở **hai góc chéo đối diện**: chúng nhìn dọc cùng một đường chéo từ hai phía, tia nhìn
gần như trùng phương ⇒ triangulation kém. Quay 60 fps, khoá lấy nét/phơi sáng, ống 1x, vỗ tay hoặc
nháy flash trước mỗi lần quay để đồng bộ, không chèn nhạc. Từ đó: triangulation → đáp án 3D thật →
đo sai số của phương pháp một camera ở trên.

---

## 6. Tham khảo

- C. Cohen, B. Darbois Texier, D. Quéré, C. Clanet — *The physics of badminton*, New Journal of Physics 17 (2015).
- P. Liu, J.-H. Wang — *MonoTrack: Shuttle trajectory reconstruction from monocular badminton video*, CVPR Workshops 2022.
- Y.-C. Huang et al. — *TrackNet: A deep learning network for tracking high-speed and tiny objects in sports applications*, AVSS 2019.
- TrackNetV3 (bản dùng ở đây): https://github.com/alenzenx/TrackNetV3
- T. Jiang et al. — *RTMPose: Real-time multi-person pose estimation based on MMPose*, 2023; rtmlib: https://github.com/Tau-J/rtmlib
- Z. Ge et al. — *YOLOX: Exceeding YOLO series in 2021*, 2021.
