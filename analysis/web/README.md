# analysis/web — phân tích cầu lông ngay trong trình duyệt

Bản "lite" của pipeline `analysis/` chạy **hoàn toàn trên máy người xem** (WebGPU, không có thì CPU/WASM).
Vercel chỉ phục vụ file tĩnh, video không rời khỏi thiết bị và server không tốn GPU.

```
video ─► chọn ≥4 điểm sân (homography) ─► ảnh nền trung vị (25 frame)
      ─► mỗi 8 frame: TrackNetV3 chính thức (nền + 8 frame; worker, WebGPU FP16 / WASM FP32)
                                        └► mỗi N frame: RTMO-s (người + 17 khớp, 1 lượt)
      ─► track.py port sang JS (multi-target, chọn đường bay) ─► cú đánh = đổi hướng 2D gần cổ tay
      ─► vị trí người trên sân (cổ chân → H⁻¹), quãng đường, điểm rơi thô ─► overlay + xuất MP4 (WebCodecs)
```

## Chạy

```bash
cd analysis/web
npm install
npm run dev        # http://localhost:5174 (copy model từ ../models/web vào public/)
npm run build      # dist/ — public/samples bị loại khỏi bản build
```

Model (không nằm trong git, tạo một lần):

| File | Cách tạo |
|---|---|
| `../models/web/out/tracknet3_fp32.onnx`, `tracknet3_fp16.onnx` | export từ `models/tracknetv3_official/ckpts/TrackNet_best.pt` (qua `badminton/shuttle_v3.py`), input động `(1, 27, H, W)`, opset 17; fp16 bằng `onnxconverter_common.float16` (`keep_io_types`) |
| `../models/web/dl/x/rtmo-s/end2end.onnx` | `rtmo-s_8xb32-600e_body7-640x640-dac2bf74_20231211.zip` trên download.openmmlab.com |

`public/samples/demo.mp4` + `demo.json` (nút "Thử với video mẫu") là tuỳ chọn và **chỉ dùng local**.
Video mẫu hiện tại là clip repost từ TikTok, không được đưa lên bản công khai.

## Số đo (2026-11-09, Chromium, clip 20 s 1024×576 30 fps)

TrackNetV3 chính thức (nền + 8 frame), 512×288:

| | Bắt cầu / 8 frame | Khung xương / lần | 20 s video | Frame thấy cầu |
|---|---|---|---|---|
| RTX 5060 Ti, WebGPU FP16 | 90 ms | 31 ms | **17 s** (36 fps, nhanh hơn thời gian thực) | 64% |
| i5-12400F, WASM 8 luồng | 1190 ms | 187 ms | ~2 phút | 66% |
| *Bản cũ (alenzenx, 3 frame), RTX 5060 Ti* | *104 ms / 3 frame* | | *27 s* | *48%* |

28 GFLOP/frame (bản cũ 134). Bảng ước lượng cho laptop và điện thoại: `src/devices.js` (iPhone 15 Pro /
laptop GPU tích hợp ~4 phút cho 1 phút video, Android tầm trung ~11 phút, chỉ CPU 6–24 phút).

**Lỗi onnxruntime-web WebGPU (1.30):** conv có **27 kênh đầu vào** cho kết quả sai (heatmap gần như
trống; WASM thì đúng). Bản export độn lên 32 kênh (5 kênh 0, trọng số 0), và gộp BatchNorm vào conv;
worker gửi tensor 32 kênh. Nếu export lại model, giữ cả hai bước này.

So với bản desktop trên cùng 20 s: bản web không có vật lý 3D, nên cú đánh là ước lượng 2D (đổi hướng
gần cổ tay), điểm rơi lệch ~1–2 m (coi điểm cuối trên ảnh như đã chạm sàn).

## Deploy Vercel

Project riêng, root directory = `analysis/web`. `vercel.json` bật COOP/COEP (cần cho WASM đa luồng) và cache
model 1 năm. Model ~130 MB nằm trong `public/models` nên phải deploy từ máy có model (`vercel deploy --prod`
tại `analysis/web`), hoặc chuyển model sang host khác (Hugging Face, R2) rồi sửa đường dẫn trong `src/worker.js`.

## Giấy phép

TrackNetV3 (alenzenx): MIT · RTMO / mmpose: Apache-2.0 · onnxruntime-web: MIT.
Trọng số TrackNet được train trên dataset thi đấu: nếu bán thương mại thì cần kiểm tra lại điều khoản của dataset.
