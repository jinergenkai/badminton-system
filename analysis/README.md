# Badminton video analysis

Phân tích video cầu lông quay bằng 1 camera cố định (tripod): vẽ sân chuẩn BWF lên video,
theo dõi quả cầu bằng TrackNetV3, tìm điểm cầu rơi, và render thêm một màn hình 3D riêng.

## Cài đặt

```bash
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements.txt
git clone https://github.com/alenzenx/TrackNetV3.git third_party/TrackNetV3
git -C third_party/TrackNetV3 checkout d1d96f39d275970d3597a45926f4f46e6ee85e2c
```

Trọng số TrackNetV3 (`model_best.pt`, link Google Drive trong README của repo trên) đặt ở
`models/tracknet_v3.pt`. Pose: `models/pose/yolox_x_humanart.onnx` và
`models/pose/rtmpose_x_body7_384x288.onnx` (bản `performance` của rtmlib, tải từ download.openmmlab.com). Cần `ffmpeg` trong PATH để xuất H.264 có âm thanh (không có thì vẫn
ra file mp4v không tiếng).

Video đặt ở `data/videos/` (không commit). `data/`, `models/`, `outputs/` đều nằm ngoài git.

## Chạy

```bash
.venv/Scripts/python -m badminton configs/danh-cau-02.json
```

Mỗi bước lưu kết quả vào `outputs/<tên config>/` và được bỏ qua ở lần chạy sau.
`--force <bước...>` để tính lại, `--only <bước...>` để chỉ chạy vài bước.

| Bước | Làm gì | File ra |
|---|---|---|
| `background` | Trung vị 60 frame rải đều video → sân trống, xoá người | `background.png` |
| `calibrate` | Khớp mô hình sân chuẩn với vạch trắng, suy ra tiêu cự + vị trí camera | `calib.json`, `court_overlay.png` |
| `detect` | TrackNetV3, giữ **mọi** ứng viên mỗi frame (bản gốc chỉ giữ 1) | `candidates.csv` |
| `track` | Multi-target tracking, bỏ đường bay ngắn/đứng yên, chọn 1 đường bay mỗi frame, nội suy chỗ mất dấu ≤ 5 frame | `shuttle.csv`, `court_volume.png` |
| `pose` | YOLOX-x + RTMPose-x (rtmlib, ONNX GPU) mọi frame — chậm (~10 fps), có cache | `pose.npz` |
| `players` | Giữ người đứng trên sân mình, gán ID theo vị trí sàn, nâng khung xương lên 3D (mặt phẳng đứng qua chân) | `players.csv`, `players_k3d.npy` |
| `hits` | Cầu bắt đầu bay / đổi hướng gấp + tia nhìn tới cầu đi sát cổ tay ai đó (< 1 m, 3D) → cú chạm, điểm chạm, độ cao | `hits.json` |
| `flight` | Khớp đường bay 3D theo vật lý (lực cản bậc 2, V∞ 6.7 m/s) cho từng cú; cắt khi cầu rời đường dự đoán; khôi phục cú đánh bị sót | `flights.json` |
| `landing` | Điểm rơi: ngoại suy vật lý của cú cuối mỗi pha + vật trắng nhỏ nằm yên trên sàn | `landings.json` |
| `render` | Video gốc (sân, vệt cầu, điểm rơi) + màn hình 3D | `<tên>_3d.mp4` |

## Thêm video mới

Tạo `configs/<tên>.json`:

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

- `seeds`: ≥ 4 cặp `[toạ độ sân (m), pixel]`, ước lượng thô là đủ (bước calibrate tự tinh chỉnh).
  Pixel được phép nằm ngoài khung hình (giao điểm suy ra từ vạch nhìn thấy). Tránh để các điểm
  dồn sát nhau trên cùng một vạch.
- Toạ độ sân: X ngang sân (0 = biên đôi trái, 6.1 = phải), Y dọc sân (0 = lưới, âm = nửa sân
  phía camera, ±1.98 giao cầu ngắn, ±5.94 giao cầu dài đôi, ±6.7 cuối sân).
- `floor_top`: hàng pixel phía trên đó không có sàn. `ignore`: các hình chữ nhật bỏ qua (logo, watermark).
- Kiểm tra `court_overlay.png` sau bước calibrate: vạch vàng phải nằm trên vạch trắng.
  Mỗi lần dời tripod là một config mới.

## Giới hạn hiện tại

- 1 camera không biết độ cao của cầu, nên không phân biệt được cầu sân mình với cầu sân bên
  cạnh nằm trên cùng tia nhìn. Bộ lọc "khối không gian sân" chỉ có tác dụng khi camera đặt xa sân.
- Điểm rơi ưu tiên chính xác hơn đầy đủ: bỏ sót khi cầu bị che, bị nhặt ngay, hoặc người đang
  cúi ngay trên quả cầu.
- TrackNetV3 được train trên video góc truyền hình; video góc thấp, nhiều sân sẽ nhiễu hơn.

## Triển khai: GPU ở xa, qua internet

Pipeline chạy headless (không GUI), đầu vào là file + config, nên chạy trên máy GPU từ xa được:

```
điện thoại (tripod) ──upload video──▶ máy GPU (cloud / PC ở nhà) ──▶ outputs/ ──▶ xem trên điện thoại
```

- **Sau trận (dễ nhất):** quay xong upload file → chạy pipeline → tải video kết quả.
  Video 2–2.5 phút xử lý ~3–4 phút trên RTX 5060 Ti (detect ~75–80 fps).
- **Gần realtime:** điện thoại phát stream (RTMP/SRT/WebRTC) lên máy GPU, xử lý từng đoạn vài giây.
  Upload 4G/5G cần ~3–6 Mbps cho 720p30 / ~8–15 Mbps cho 1080p60 mỗi camera; độ trễ thực tế ~1–3 s,
  đủ để báo IN/OUT sau mỗi pha. Calibration chỉ làm 1 lần mỗi lần đặt tripod.
