# analysis/web — phân tích cầu lông ngay trong trình duyệt

Bản "lite" của pipeline `analysis/` chạy **hoàn toàn trên máy người xem** (WebGPU, không có thì CPU/WASM).
Vercel chỉ phục vụ file tĩnh, video không rời khỏi thiết bị và server không tốn GPU.

```
video ─► chọn ≥4 điểm sân (homography) ─► mỗi 3 frame: TrackNetV3 (worker, WebGPU FP16 / WASM FP32)
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
| `../models/web/out/tracknet_fp32.onnx`, `tracknet_fp16.onnx` | export từ `models/tracknet_v3.pt`, input động `(1, 9, H, W)`, opset 17; fp16 bằng `onnxconverter_common.float16` (`keep_io_types`) |
| `../models/web/dl/x/rtmo-s/end2end.onnx` | `rtmo-s_8xb32-600e_body7-640x640-dac2bf74_20231211.zip` trên download.openmmlab.com |

`public/samples/demo.mp4` + `demo.json` (nút "Thử với video mẫu") là tuỳ chọn và **chỉ dùng local**.
Video mẫu hiện tại là clip repost từ TikTok, không được đưa lên bản công khai.

## Số đo (2026-11-09, Chromium, clip 20 s 1024×576 30 fps)

| | Bắt cầu / 3 frame | Khung xương / lần | 20 s video |
|---|---|---|---|
| RTX 5060 Ti, WebGPU FP16, 512×288 | 104 ms | 31 ms | **27 s** (22 fps) |
| RTX 5060 Ti, WebGPU, 384×216 / 256×144 | 55 / 29 ms | | |
| i5-12400F, WASM 8 luồng, 512×288 | 2131 ms | 185 ms | ~7.5 phút |
| i5-12400F, WASM, 384×216 / 256×144 | 1233 / 568 ms | | |
| *Desktop Python (`analysis/`), RTX 5060 Ti* | *~39 ms (PyTorch FP16)* | *YOLOX-x + RTMPose-x ~86 ms/frame* | *150 s video: 9.9 phút* |

Thời gian tỉ lệ gần đúng theo số pixel đầu vào của TrackNet (~134 GFLOP/frame ở 512×288).
Độ phân giải thấp làm mất cầu: trên 322 frame mà bản desktop thấy cầu, 512×288 bắt lại được 100%,
384×216 được 90%, 256×144 được 77% (cùng model, ngưỡng 0.5, lệch ≤ 20 px).
Bảng ước lượng cho laptop và điện thoại nằm trong `src/devices.js`.

So với bản desktop trên cùng 20 s: tỉ lệ frame thấy cầu là 48% (desktop 54%), 14 cú đánh ước tính (desktop 14),
1 điểm rơi IN (desktop 1). Điểm rơi bản web lệch ~1–2 m vì lấy điểm cuối của cầu trên ảnh và coi như cầu đã
chạm sàn, không có vật lý 3D.

## Deploy Vercel

Project riêng, root directory = `analysis/web`. `vercel.json` bật COOP/COEP (cần cho WASM đa luồng) và cache
model 1 năm. Model ~130 MB nằm trong `public/models` nên phải deploy từ máy có model (`vercel deploy --prod`
tại `analysis/web`), hoặc chuyển model sang host khác (Hugging Face, R2) rồi sửa đường dẫn trong `src/worker.js`.

## Giấy phép

TrackNetV3 (alenzenx): MIT · RTMO / mmpose: Apache-2.0 · onnxruntime-web: MIT.
Trọng số TrackNet được train trên dataset thi đấu: nếu bán thương mại thì cần kiểm tra lại điều khoản của dataset.
