// Time to analyse 1 minute of 30 fps video (1800 frames) at 512x288, pose 5x/s.
// tnMs = TrackNet ms per call (official TrackNetV3: 8 frames + background), poseMs = RTMO-s ms per call.
// "measured" rows were timed on real hardware; the rest are scaled from them by compute throughput.
// Measured 2026-11-09 in Chromium, official TrackNetV3 (8 frames per call): RTX 5060 Ti WebGPU FP16 = 90 ms / 31 ms;
// i5-12400F WASM 8 threads = 1190 ms / 187 ms. Other rows are estimates scaled from these by compute throughput
// (WebGPU reaches ~15-25% of a GPU's FP32 peak on this U-Net).
export const DEVICE_TABLE = [
  { name: 'PC RTX 5060 Ti — GPU (WebGPU)', tnMs: 90, poseMs: 31, measured: true },
  { name: 'Laptop RTX 4050/3050 — GPU', tnMs: 175, poseMs: 55 },
  { name: 'MacBook Air M2/M3 — GPU', tnMs: 350, poseMs: 90 },
  { name: 'Laptop Intel Iris Xe / AMD 680M — GPU tích hợp', tnMs: 700, poseMs: 160 },
  { name: 'iPhone 15 Pro/16 (Safari 26) — GPU', tnMs: 700, poseMs: 160 },
  { name: 'Android cao cấp (Snapdragon 8 Gen 2/3) — GPU', tnMs: 780, poseMs: 180 },
  { name: 'PC i5-12400F (6 nhân) — CPU (WASM)', tnMs: 1190, poseMs: 187, measured: true },
  { name: 'Android tầm trung (Adreno 6xx / Mali-G57) — GPU', tnMs: 2150, poseMs: 450 },
  { name: 'Laptop văn phòng 4 nhân — chỉ CPU', tnMs: 2800, poseMs: 450 },
  { name: 'Điện thoại không có WebGPU — chỉ CPU', tnMs: 5000, poseMs: 900 },
];

const SEEK_MS = 12;
export function minutesFor(tnMs, poseMs, frames = 1800, every = 6) {
  return ((frames / 8) * tnMs + (every ? (frames / every) * poseMs : 0) + frames * SEEK_MS) / 60000;
}

const fmt = (m) => (m < 1 ? `${Math.round(m * 60)} giây` : m < 90 ? `${m.toFixed(m < 10 ? 1 : 0)} phút` : `${(m / 60).toFixed(1)} giờ`);

export function renderDeviceTable(table, mine) {
  const rows = DEVICE_TABLE.map((d) => ({ ...d }));
  if (mine) rows.unshift({ name: mine.label, poseMs: mine.poseMs, mine: true, raw: mine });
  table.innerHTML = `<thead><tr><th>Thiết bị</th><th>Chuẩn 512×288</th><th>Nhanh 384×216</th><th>Siêu nhanh 256×144</th><th>Loại số</th></tr></thead><tbody>` +
    rows.map((d) => {
      // cost scales ~linearly with pixels: 384x216 = 0.56x, 256x144 = 0.25x
      const tn = d.mine ? d.raw.tracknetMs * ((288 * 512) / (d.raw.w * d.raw.h)) : d.tnMs;
      const cell = (k) => `<td class="num">${fmt(minutesFor(tn * k, d.poseMs))}</td>`;
      return `<tr class="${d.mine ? 'measured' : ''}"><td>${d.name}</td>${cell(1)}${cell(0.5625)}${cell(0.25)}<td>${d.mine ? 'máy bạn vừa đo' : d.measured ? 'đo thật' : 'ước lượng'}</td></tr>`;
    }).join('') + '</tbody>';
}
