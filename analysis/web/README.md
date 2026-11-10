# analysis/web — phân tích cầu lông đầy đủ ngay trong trình duyệt

Toàn bộ pipeline của `analysis/` chạy **trên máy người xem** (WebGPU, không có thì CPU/WASM): Vercel chỉ
phục vụ file tĩnh, model tải từ Hugging Face, video không rời khỏi thiết bị.

```
video ─► chấm ≥ 4 điểm sân ─► (Cân bằng / Tối đa) khớp sân vào vạch trắng ─► camera K, R, t
      ─► TrackNetV3 (nền trung vị + 8 frame) ─► ứng viên cầu ─► theo dõi đường bay
      ─► RTMO khung xương (+ lượt phóng to nửa sân xa) ─► người trên sân, 3D, P1–P4 theo màu áo
      ─► cú chạm (cổ tay gần tia nhìn, Viterbi theo luật luân phiên) ─► đường bay 3D vật lý (7 ẩn)
      ─► khôi phục cú sót ─► điểm rơi ─► phân tích (loại cú, tốc độ ± σ, thế đứng…) ─► render + MP4
```

`src/core/` là bản port JS của `analysis/badminton/` (camera, track, players, identity, hits, flight +
optimize, analytics, report, courtfit), `src/app/pipeline.js` nối các bước (chạy trong worker),
`src/ui/render.js` vẽ overlay, sân 3D và các thẻ (ngang hoặc dọc 9:16). Test so với bản Python:
`node --test test/` (fixtures: `python analysis/tools/export_fixtures.py danh-cau-02`) — cùng đầu vào cho
cùng 124/124 cú, 121 trùng cả loại cú.

## Mức phân tích

| Mức | Bắt cầu | Khung xương | Sân | 20 s video, RTX 5060 Ti |
|---|---|---|---|---|
| Nhanh | cửa sổ 8 frame | RTMO-s, mỗi 3 frame + phóng to nửa sân xa | theo điểm chấm | ~22 s |
| Cân bằng | cửa sổ 8 frame | RTMO-m, mỗi 3 frame + lượt phóng to nửa sân xa | khớp vạch trắng | ~30 s |
| Tối đa | cửa sổ chồng nhau (bước 4) | RTMO-l, mọi frame + phóng to nửa sân xa | khớp vạch trắng | ~80 s |

Mức nào cũng đủ tính năng; mức cao hơn bắt người chơi và cú chạm chắc hơn. Lượt **phóng to nửa sân xa**
(cắt vùng nửa sân xa + 2.5 m sau đường cuối, chạy lại RTMO, gộp theo IoU) là cần thiết: trên khung 640 cả
ảnh, người đánh cầu cao từ sau cuối sân xa quá nhỏ và bị bỏ sót, khiến cú đó bị gán cho người phía gần và
đường bay 3D sai (cú 97 của video 02: 64 km/h → 159 km/h sau khi sửa; bản desktop 177 km/h).

Còn khác bản desktop ở đầu vào: khung xương RTMO thay cho YOLOX-x + RTMPose-x (desktop), frame lấy qua
`<video>` + canvas, điểm rơi chỉ tính bằng vật lý. Bắt cầu khớp 99% (371/375 frame), cú chạm trùng frame.

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

Project Vercel riêng **trong cùng repo**: *Add New → Project → chọn repo → Root Directory = `analysis/web`*
(framework Vite, build/output đã có trong `vercel.json`). Không cần file model trong git: trang tải trọng số
từ Hugging Face [`jinergenkai/badminton-analysis-web`](https://huggingface.co/jinergenkai/badminton-analysis-web)
(CORS hợp lệ với COOP/COEP). Lần đầu mở trang tải ~60 MB, sau đó nằm trong Cache Storage của trình duyệt.

Chạy local dùng bản model trên máy: `.env.development` đặt `VITE_MODEL_BASE=/models/`
(`npm run dev` copy từ `../models/web` vào `public/models`).

## Giấy phép

TrackNetV3 (alenzenx): MIT · RTMO / mmpose: Apache-2.0 · onnxruntime-web: MIT.
Trọng số TrackNet được train trên dataset thi đấu: nếu bán thương mại thì cần kiểm tra lại điều khoản của dataset.
