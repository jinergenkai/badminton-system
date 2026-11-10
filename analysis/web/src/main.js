import { Muxer, ArrayBufferTarget } from 'mp4-muxer';
import { apply, COURT_LINES, COURT_W, HALF_L, homography, invert3, NET, projectSegment } from './geom.js';
import { renderDeviceTable } from './devices.js';
import { calibrateFromHomography } from './core/camera.js';
import { fitCourt } from './core/courtfit.js';
import { reportHtml } from './core/report.js';
import { buildPoses, createRenderer } from './ui/render.js';

const SEQ = 8;   // TrackNetV3: frames per inference

const $ = (s) => document.querySelector(s);
const show = (el, on = true) => { el.hidden = !on; };
const fmtTime = (s) => (s < 60 ? `${Math.round(s)} giây` : s < 3600 ? `${Math.floor(s / 60)} phút ${Math.round(s % 60)} giây` : `${(s / 3600).toFixed(1)} giờ`);

const state = {
  file: null, url: null, W: 0, VH: 0, fps: 30, duration: 0,   // video size W × VH
  pairs: [],            // {court:[X,Y], px:[x,y]}
  pick: null,           // court point selected on the mini court
  Hc: null, Hinv: null, // homography court -> image, image -> court
  bench: null, ready: null,
  result: null,
};

// ---------- worker plumbing ----------
const worker = new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
let reqId = 0;
const waiting = new Map();
let onReady = null, onBench = null;
worker.onmessage = ({ data }) => {
  if (data.type === 'progress') setProgress(data.frac, data.label);
  else if (data.type === 'ready') { state.ready = data; onReady?.(data); }
  else if (data.type === 'bench') onBench?.(data);
  else if (data.type === 'error') {
    const w = waiting.get(data.id);
    if (w) { waiting.delete(data.id); w.reject(new Error(data.message)); } else alert('Lỗi: ' + data.message);
  } else {
    const w = waiting.get(data.id);
    if (w) { waiting.delete(data.id); w.resolve(data); }
  }
};
const call = (msg, transfer) => new Promise((resolve, reject) => {
  const id = ++reqId;
  waiting.set(id, { resolve, reject });
  worker.postMessage({ ...msg, id }, transfer);
});
let readyKey = '';
async function ensureModels() {
  const key = `${$('#opt-backend').value}|${preset().pose}`;
  if (readyKey === key && state.ready) return state.ready;
  state.ready = null;
  const p = new Promise((res) => { onReady = res; });
  worker.postMessage({ type: 'init', want: $('#opt-backend').value, pose: preset().pose,
                       fp32: new URLSearchParams(location.search).has('fp32') });
  const r = await p;
  readyKey = key;
  describeDevice(r);
  return r;
}

function describeDevice(r) {
  const el = $('#device');
  const gpu = r.gpu ? `${r.gpu.vendor} ${r.gpu.arch} ${r.gpu.desc}`.trim() || 'có WebGPU' : 'không có WebGPU';
  el.innerHTML = `Đang chạy bằng <b>${r.backend === 'webgpu' ? 'GPU (WebGPU)' : 'CPU (WASM)'}</b> · GPU: ${gpu}` +
    ` · CPU: ${navigator.hardwareConcurrency || '?'} luồng (dùng ${r.threads}${r.isolated ? '' : ', thiếu cross-origin isolation'})` +
    ` · mô hình ${r.model.includes('fp16') ? 'FP16' : 'FP32'}, khung xương ${r.poseModel || '—'}`;
  show(el);
}

// ---------- step 1: video ----------
const proc = $('#proc');
const player = $('#player');

function waitEvent(el, ev) { return new Promise((res, rej) => { el.addEventListener(ev, res, { once: true }); el.addEventListener('error', rej, { once: true }); }); }

async function estimateFps(v) {
  if (!('requestVideoFrameCallback' in HTMLVideoElement.prototype)) return 30;
  const times = [];
  await new Promise((resolve) => {
    const cb = (_, m) => {
      times.push(m.mediaTime);
      if (times.length < 25) v.requestVideoFrameCallback(cb); else resolve();
    };
    v.requestVideoFrameCallback(cb);
    v.play().catch(resolve);
    setTimeout(resolve, 3000);
  });
  v.pause();
  const d = times.slice(1).map((t, i) => t - times[i]).filter((x) => x > 0.004).sort((a, b) => a - b);
  if (!d.length) return 30;
  const fps = 1 / d[0];          // smallest gap = one frame (playback may drop frames, never adds)
  const common = [24, 25, 30, 48, 50, 60, 90, 120, 240].reduce((a, b) => (Math.abs(b - fps) < Math.abs(a - fps) ? b : a));
  return Math.abs(common - fps) / fps < 0.08 ? common : Math.round(fps);
}

fetch('/samples/demo.json').then((r) => (r.ok ? r.json() : null)).then((demo) => {
  if (!demo) return;
  show($('#demo-row'));
  $('#btn-demo').onclick = async () => {
    const btn = $('#btn-demo');
    btn.disabled = true;
    try {
      const blob = await (await fetch(demo.video)).blob();
      await loadFile(new File([blob], demo.video.split('/').pop(), { type: 'video/mp4' }), demo.fps);
      state.pairs = demo.pairs.map((p) => ({ court: p.court, px: p.px }));
      state.pick = nextDefaultPick();
      updateH(); drawCalib();
    } finally { btn.disabled = false; }
  };
}).catch(() => {});

async function loadFile(file, knownFps) {
  if (state.url) URL.revokeObjectURL(state.url);
  state.file = file;
  state.url = URL.createObjectURL(file);
  proc.src = state.url;
  player.src = state.url;
  await waitEvent(proc, 'loadedmetadata');
  state.W = proc.videoWidth; state.VH = proc.videoHeight; state.duration = proc.duration;
  state.fps = knownFps || (await estimateFps(proc));
  await seek(proc, Math.min(1, state.duration / 2));
  const info = $('#video-info');
  info.innerHTML = `<b>${file.name}</b> · ${state.W}×${state.VH} · ${state.fps} fps · ${fmtTime(state.duration)} · ${(file.size / 1e6).toFixed(1)} MB`;
  show(info);
  state.pairs = []; state.pick = null; state.Hc = state.Hinv = null; state.result = null;
  show($('#step-court')); show($('#step-run'), false); show($('#step-result'), false);
  $('#calib-time').value = Math.min(0.1, 3 / state.duration).toString();
  setupCalib();
  $('#step-court').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

$('#file').addEventListener('change', (e) => e.target.files[0] && loadFile(e.target.files[0]));
const drop = $('#drop');
drop.addEventListener('dragover', (e) => { e.preventDefault(); drop.classList.add('over'); });
drop.addEventListener('dragleave', () => drop.classList.remove('over'));
drop.addEventListener('drop', (e) => { e.preventDefault(); drop.classList.remove('over'); e.dataTransfer.files[0] && loadFile(e.dataTransfer.files[0]); });

function seek(v, t) {
  return new Promise((resolve) => {
    if (Math.abs(v.currentTime - t) < 1e-6 && v.readyState >= 2) return resolve();
    v.addEventListener('seeked', resolve, { once: true });
    v.currentTime = t;
  });
}

// ---------- step 2: court ----------
const cc = $('#calib-canvas');
const pc = $('#pick-canvas');
const MARGIN = 0.18;   // dark border around the frame so off-screen points can be placed
let frameBitmap = null;

// court points the user can pick: every line intersection
const PICKS = (() => {
  const xs = [0, 0.46, 3.05, 5.64, COURT_W], ys = [-HALF_L, -5.94, -1.98, 1.98, 5.94, HALF_L];
  const out = [];
  for (const y of ys) for (const x of xs) {
    if (x === 3.05 && Math.abs(y) === 5.94) continue;
    out.push([x, y]);
  }
  return out;
})();
const DEFAULT_ORDER = [[0, -1.98], [COURT_W, -1.98], [COURT_W, HALF_L], [0, HALF_L], [0, -HALF_L], [COURT_W, -HALF_L]];

function miniLayout(canvas, pad = 22) {
  const s = Math.min((canvas.width - 2 * pad) / COURT_W, (canvas.height - 2 * pad) / (2 * HALF_L));
  const ox = (canvas.width - COURT_W * s) / 2, oy = canvas.height / 2;
  return { s, toPx: ([X, Y]) => [ox + X * s, oy - Y * s], toCourt: ([x, y]) => [(x - ox) / s, (oy - y) / s] };
}

function drawMiniCourt(ctx, L) {
  const c = ctx.canvas;
  ctx.fillStyle = getComputedStyle(document.documentElement).getPropertyValue('--court');
  ctx.fillRect(0, 0, c.width, c.height);
  ctx.strokeStyle = 'rgba(255,255,255,.85)'; ctx.lineWidth = 1.5;
  for (const [p, q] of COURT_LINES) { ctx.beginPath(); ctx.moveTo(...L.toPx(p)); ctx.lineTo(...L.toPx(q)); ctx.stroke(); }
  ctx.strokeStyle = 'rgba(255,255,255,.5)'; ctx.setLineDash([4, 3]); ctx.lineWidth = 3;
  ctx.beginPath(); ctx.moveTo(...L.toPx(NET[0])); ctx.lineTo(...L.toPx(NET[1])); ctx.stroke(); ctx.setLineDash([]);
  ctx.fillStyle = 'rgba(255,255,255,.55)'; ctx.font = '11px system-ui';
  ctx.fillText('phía xa', 6, 14); ctx.fillText('phía camera', 6, c.height - 6);
}

function nextDefaultPick() {
  return DEFAULT_ORDER.find((p) => !state.pairs.some((q) => q.court[0] === p[0] && q.court[1] === p[1])) || null;
}

function setupCalib() {
  state.pick = nextDefaultPick();
  refreshFrame();
}

async function refreshFrame() {
  await seek(proc, Number($('#calib-time').value) * state.duration);
  frameBitmap = await createImageBitmap(proc);
  cc.width = Math.round(state.W * (1 + 2 * MARGIN));
  cc.height = Math.round(state.VH * (1 + 2 * MARGIN));
  drawCalib();
}
$('#calib-time').addEventListener('input', () => refreshFrame());

const calibToVideo = ([x, y]) => [x - state.W * MARGIN, y - state.VH * MARGIN];
const videoToCalib = ([x, y]) => [x + state.W * MARGIN, y + state.VH * MARGIN];

function updateH() {
  state.Hc = state.pairs.length >= 4 ? homography(state.pairs.map((p) => p.court), state.pairs.map((p) => p.px)) : null;
  state.Hinv = state.Hc ? invert3(state.Hc) : null;
}

function drawCalib() {
  const ctx = cc.getContext('2d');
  ctx.fillStyle = '#111'; ctx.fillRect(0, 0, cc.width, cc.height);
  if (frameBitmap) ctx.drawImage(frameBitmap, state.W * MARGIN, state.VH * MARGIN, state.W, state.VH);
  const k = state.W / 1280;
  if (state.Hc) {
    ctx.strokeStyle = '#ffd400'; ctx.lineWidth = 2 * Math.max(1, k);
    for (const [p, q] of COURT_LINES) {
      const pts = projectSegment(state.Hc, p, q);
      if (pts.length < 2) continue;
      ctx.beginPath();
      pts.forEach((r, i) => ctx[i ? 'lineTo' : 'moveTo'](...videoToCalib(r)));
      ctx.stroke();
    }
  }
  state.pairs.forEach((p, i) => {
    const [x, y] = videoToCalib(p.px);
    ctx.fillStyle = '#d9ff3f'; ctx.strokeStyle = '#000'; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.arc(x, y, 9 * Math.max(1, k), 0, 7); ctx.fill(); ctx.stroke();
    ctx.fillStyle = '#000'; ctx.font = `bold ${12 * Math.max(1, k)}px system-ui`; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(String(i + 1), x, y + 1);
  });
  // pick court
  const pctx = pc.getContext('2d');
  const L = miniLayout(pc);
  drawMiniCourt(pctx, L);
  for (const p of PICKS) {
    const [x, y] = L.toPx(p);
    const used = state.pairs.findIndex((q) => q.court[0] === p[0] && q.court[1] === p[1]);
    const sel = state.pick && state.pick[0] === p[0] && state.pick[1] === p[1];
    pctx.beginPath(); pctx.arc(x, y, sel ? 8 : 5, 0, 7);
    pctx.fillStyle = sel ? '#ffd400' : used >= 0 ? '#d9ff3f' : 'rgba(255,255,255,.35)';
    pctx.fill();
    if (used >= 0) { pctx.fillStyle = '#000'; pctx.font = 'bold 9px system-ui'; pctx.textAlign = 'center'; pctx.textBaseline = 'middle'; pctx.fillText(String(used + 1), x, y + 0.5); }
  }
  const n = state.pairs.length;
  $('#calib-status').innerHTML = state.pick
    ? `Bấm vào video tại điểm <b style="color:#ffd400">vàng</b> trên sơ đồ.<br>Đã có ${n} điểm${n < 4 ? `, cần thêm ${4 - n}` : ''}.`
    : `Đã có ${n} điểm. Chọn thêm điểm trên sơ đồ nếu cần.`;
  $('#calib-ok').disabled = !state.Hc;
}

function evtPos(canvas, e) {
  const r = canvas.getBoundingClientRect();
  return [((e.clientX - r.left) / r.width) * canvas.width, ((e.clientY - r.top) / r.height) * canvas.height];
}

let drag = -1;
cc.addEventListener('pointerdown', (e) => {
  const p = evtPos(cc, e);
  const tol = 22 * Math.max(1, state.W / 1280) * (cc.width / cc.getBoundingClientRect().width) / 2;
  drag = state.pairs.findIndex((q) => Math.hypot(...videoToCalib(q.px).map((v, i) => v - p[i])) < tol);
  if (drag < 0 && state.pick) {
    state.pairs.push({ court: state.pick, px: calibToVideo(p) });
    drag = state.pairs.length - 1;
    state.pick = nextDefaultPick();
    updateH();
  }
  cc.setPointerCapture(e.pointerId);
  drawCalib();
});
cc.addEventListener('pointermove', (e) => {
  if (drag < 0) return;
  state.pairs[drag].px = calibToVideo(evtPos(cc, e));
  updateH(); drawCalib();
});
cc.addEventListener('pointerup', () => { drag = -1; });
pc.addEventListener('click', (e) => {
  const L = miniLayout(pc);
  const p = evtPos(pc, e);
  let best = null, bd = 1e9;
  for (const q of PICKS) { const d = Math.hypot(...L.toPx(q).map((v, i) => v - p[i])); if (d < bd) { bd = d; best = q; } }
  if (bd < 18) {
    const used = state.pairs.findIndex((q) => q.court[0] === best[0] && q.court[1] === best[1]);
    if (used >= 0) state.pairs.splice(used, 1);
    state.pick = best; updateH(); drawCalib();
  }
});
$('#calib-undo').onclick = () => { state.pairs.pop(); state.pick = nextDefaultPick(); updateH(); drawCalib(); };
$('#calib-reset').onclick = () => { state.pairs = []; state.pick = nextDefaultPick(); updateH(); drawCalib(); };
$('#calib-ok').onclick = () => { show($('#step-run')); $('#step-run').scrollIntoView({ behavior: 'smooth' }); };

// ---------- step 3: presets, bench, run ----------
// Every level runs the full analysis; higher levels detect more carefully and use a better pose model.
const PRESETS = {
  fast:     { label: 'Nhanh',     stride: 8, pose: 's', poseEvery: 6, farZoom: false, courtFit: false, starts: 2, maxNfev: 200 },
  balanced: { label: 'Cân bằng',  stride: 8, pose: 'm', poseEvery: 3, farZoom: true,  courtFit: true,  starts: 4, maxNfev: 300 },
  max:      { label: 'Tối đa',    stride: 4, pose: 'l', poseEvery: 1, farZoom: true,  courtFit: true,  starts: 4, maxNfev: 300 },
};
const preset = () => PRESETS[document.querySelector('input[name=preset]:checked')?.value || 'balanced'];
const TW = 512, TH = 288;
function rangeFrames() {
  const lim = Number($('#opt-range').value);
  const sec = lim ? Math.min(lim, state.duration) : state.duration;
  return Math.max(SEQ, Math.floor(sec * state.fps));
}

function setProgress(frac, label) {
  const el = $('#progress');
  show(el);
  el.querySelector('i').style.width = `${Math.round((frac || 0) * 100)}%`;
  el.querySelector('span').textContent = label || '';
}

const SEEK_MS = 12;   // frame grab cost (seek + draw + readback) per frame
// CPU analysis after inference, measured: ~5 s for 150 s of video on a desktop CPU (~0.035 s per video second)
function estimateSeconds(b, frames, p) {
  const calls = Math.ceil(frames / p.stride);
  return (calls * b.tracknetMs + (frames / p.poseEvery) * b.poseMs + frames * SEEK_MS) / 1000 + (frames / state.fps) * 0.05;
}

$('#btn-bench').onclick = async () => {
  const btn = $('#btn-bench');
  btn.disabled = true;
  try {
    await ensureModels();
    setProgress(0, 'Đang đo tốc độ… (lần đầu GPU phải biên dịch shader, có thể mất 10–30 giây)');
    const b = await new Promise((res) => { onBench = res; worker.postMessage({ type: 'bench', w: TW, h: TH, pose: true }); });
    state.bench = { ...b, backend: state.ready.backend, pose: preset().pose };
    show($('#progress'), false);
    renderEstimate();
  } catch (e) { alert(e.message); } finally { btn.disabled = false; }
};

function renderEstimate() {
  const b = state.bench;
  if (!b) return;
  const p = preset();
  const frames = rangeFrames();
  const el = $('#estimate');
  el.innerHTML = `
    <div class="kpi"><b>${b.tracknetMs.toFixed(0)} ms</b><span>bắt cầu / 8 frame</span></div>
    <div class="kpi"><b>${b.poseMs.toFixed(0)} ms</b><span>khung xương RTMO-${b.pose} / lần</span></div>
    <div class="kpi"><b>${fmtTime(estimateSeconds(b, frames, p))}</b><span>mức ${p.label}, đoạn đã chọn (${fmtTime(frames / state.fps)})</span></div>
    <div class="kpi"><b>${fmtTime(estimateSeconds(b, 1800, p))}</b><span>mức ${p.label}, 1 phút video 30 fps</span></div>`;
  show(el);
  renderDeviceTable($('#device-table'), { ...b, every: p.poseEvery, w: TW, h: TH,
    label: `Máy này (${b.backend === 'webgpu' ? 'GPU' : 'CPU'})` });
}
['#opt-range'].forEach((s) => $(s).addEventListener('change', renderEstimate));
document.querySelectorAll('input[name=preset]').forEach((r) => r.addEventListener('change', () => {
  if (state.bench && state.bench.pose !== preset().pose) state.bench = null, show($('#estimate'), false);
  else renderEstimate();
}));

let cancelled = false;
$('#btn-cancel').onclick = () => { cancelled = true; };

$('#btn-run').onclick = async () => {
  const run = $('#btn-run');
  run.disabled = true; $('#btn-bench').disabled = true; show($('#btn-cancel'));
  cancelled = false;
  try {
    await ensureModels();
    const t0 = performance.now();
    const input = await infer();
    if (!input) return;
    const out = await analysePipeline(input);
    state.result = { ...out, input, seconds: (performance.now() - t0) / 1000, preset: preset().label };
    showResult();
  } catch (e) {
    console.error(e); alert('Lỗi khi phân tích: ' + e.message);
  } finally {
    run.disabled = false; $('#btn-bench').disabled = false; show($('#btn-cancel'), false);
  }
};

// median of K frames spread over [0, sec] at w x h (RGBA)
async function medianFrame(sec, w, h, K, label) {
  const ctx = new OffscreenCanvas(w, h).getContext('2d', { willReadFrequently: true });
  const samples = [];
  for (let i = 0; i < K; i++) {
    await seek(proc, ((i + 0.5) / K) * sec);
    ctx.drawImage(proc, 0, 0, w, h);
    samples.push(ctx.getImageData(0, 0, w, h).data);
    setProgress(0, `${label} ${i + 1}/${K}`);
  }
  const bg = new Uint8ClampedArray(w * h * 4);
  const col = new Uint8Array(K);
  for (let q = 0; q < w * h * 4; q++) {
    if ((q & 3) === 3) { bg[q] = 255; continue; }
    for (let i = 0; i < K; i++) col[i] = samples[i][q];
    col.sort();
    bg[q] = col[K >> 1];
  }
  return bg;
}

/** Runs the models over the video: shuttle candidates, poses + appearance; snaps the court if asked. */
async function infer() {
  const p = preset();
  const N = rangeFrames();
  const tn = new OffscreenCanvas(TW, TH).getContext('2d', { willReadFrequently: true });
  const S = 640, ratio = Math.min(S / state.W, S / state.VH);
  const pz = new OffscreenCanvas(S, S).getContext('2d', { willReadFrequently: true });
  const cands = [];
  const poses = { frame: [], kpts: [], scores: [] }, feats = [];
  const inflight = [];
  let failure = null;
  const track = (pr) => inflight.push(pr.catch((e) => { failure = failure || e; }));
  proc.pause();

  // court: the clicked points, optionally snapped onto the white lines of the empty court
  // geom.js gives a flat 9-vector; the core works with 3x3
  let H = state.Hc ? [state.Hc.slice(0, 3), state.Hc.slice(3, 6), state.Hc.slice(6, 9)] : null;
  if (!H) throw new Error('Cần đánh dấu sân (ít nhất 4 điểm) để dựng camera 3D.');
  if (H && p.courtFit && state.pairs.length >= 4) {
    const cw = Math.min(state.W, 1280), ch = Math.round(state.VH * cw / state.W), k = cw / state.W;
    const bgFull = await medianFrame(N / state.fps, cw, ch, 25, 'Ảnh nền sân trống (khớp sân)');
    const fit = fitCourt(bgFull, cw, ch, state.pairs.map((q) => [q.court, [q.px[0] * k, q.px[1] * k]]));
    if (fit.cost < fit.seedCost) {
      // back to full resolution: scale the image side of the homography
      H = fit.H.map((row, i) => (i < 2 ? row.map((v) => v / k) : row));
      state.courtFit = fit;
    }
  }

  const bg = await medianFrame(N / state.fps, TW, TH, 25, 'Ảnh nền cho bắt cầu');
  worker.postMessage({ type: 'background', image: bg }, [bg.buffer]);

  const t0 = performance.now();
  let tnMs = 0, poseMs = 0, done = 0;
  const cache = new Map();            // frame -> TW x TH RGBA (overlapping windows reuse frames)
  // far-half zoom (SAHI-style second pose pass): far players are small, and a one-stage pose model on the
  // whole frame letterboxed to 640 misses them (e.g. a deep clear hit 2 m behind the far baseline)
  let roi = null;
  if (p.farZoom) {
    const cam = calibrateFromHomography(H, state.W, state.VH);
    const pts = [];
    for (const X of [-1.5, 3.05, 7.6]) for (const Y of [0, 4.5, 9.2]) for (const Z of [0, 2.3])
      if (cam.depth([X, Y, Z]) > 0.5) pts.push(cam.project([[X, Y, Z]])[0]);
    if (pts.length >= 4) {
      const xs = pts.map((q) => q[0]), ys = pts.map((q) => q[1]);
      const x0 = Math.max(0, Math.min(...xs) - 20), x1 = Math.min(state.W, Math.max(...xs) + 20);
      const y0 = Math.max(0, Math.min(...ys) - 30), y1 = Math.min(state.VH, Math.max(...ys) + 20);
      const r2 = Math.min(S / (x1 - x0), S / (y1 - y0));
      if (x1 - x0 > 50 && y1 - y0 > 50 && r2 > ratio * 1.25) roi = { x0, y0, w: x1 - x0, h: y1 - y0, r: r2 };
    }
  }
  const people = new Map();           // frame -> [{k2, sc, feat, box}] from both passes, deduplicated at the end
  const addPeople = (f, list, sx, sy, sc) => {
    const arr = people.get(f) || [];
    for (const person of list) {
      const k2 = [], s2 = [];
      for (let j = 0; j < 17; j++) { k2.push([sx + person.kp[j * 3] / sc, sy + person.kp[j * 3 + 1] / sc]); s2.push(person.kp[j * 3 + 2]); }
      const vis = k2.filter((_, j) => s2[j] > 0.3);
      if (!vis.length) continue;
      const box = [Math.min(...vis.map((q) => q[0])), Math.min(...vis.map((q) => q[1])), Math.max(...vis.map((q) => q[0])), Math.max(...vis.map((q) => q[1]))];
      arr.push({ k2, sc: s2, feat: person.feat, box, conf: s2.reduce((a, b) => a + b, 0) / 17 });
    }
    people.set(f, arr);
  };
  const runPose = (f, ctx, sx, sy, sc, draw) => {
    ctx.fillStyle = 'rgb(114,114,114)'; ctx.fillRect(0, 0, S, S);
    draw();
    const im = ctx.getImageData(0, 0, S, S).data;
    track(call({ type: 'pose', image: im }, [im.buffer]).then((r) => { poseMs += r.ms; addPeople(f, r.people, sx, sy, sc); }));
  };
  const grab = async (f) => {
    if (cache.has(f)) return cache.get(f);
    await seek(proc, (f + 0.5) / state.fps);
    tn.drawImage(proc, 0, 0, TW, TH);
    const img = tn.getImageData(0, 0, TW, TH).data;
    cache.set(f, img);
    if (f % p.poseEvery === 0) {
      runPose(f, pz, 0, 0, ratio, () => pz.drawImage(proc, 0, 0, state.W * ratio, state.VH * ratio));
      if (roi) runPose(f, pz, roi.x0, roi.y0, roi.r,
        () => pz.drawImage(proc, roi.x0, roi.y0, roi.w, roi.h, 0, 0, roi.w * roi.r, roi.h * roi.r));
    }
    return img;
  };

  for (let g = 0; g < N; g += p.stride) {
    if (cancelled) { setProgress(g / N, 'Đã dừng.'); return null; }
    if (failure) throw failure;
    const frames = [];
    for (let k = 0; k < SEQ; k++) frames.push((await grab(Math.min(g + k, N - 1))).slice());
    for (const f of [...cache.keys()]) if (f < g + p.stride) cache.delete(f);
    const last = g + p.stride >= N;
    track(call({ type: 'tracknet', frames, w: TW, h: TH, start: g, stride: p.stride, last }, frames.map((x) => x.buffer)).then((r) => {
      tnMs += r.ms;
      for (const [f, list] of Object.entries(r.cands)) {
        if (+f >= N) continue;
        for (const c of list) cands.push({ frame: +f, x: c.x * state.W, y: c.y * state.VH, area: c.area, score: c.score });
      }
    }));
    while (inflight.length > 6) await inflight.shift();
    done = Math.min(N, g + p.stride);
    const el = (performance.now() - t0) / 1000;
    setProgress(0.85 * done / N, `Mức ${p.label} · frame ${done}/${N} · ${(done / el).toFixed(1)} fps · còn ~${fmtTime((el / done) * (N - done))}`);
  }
  await Promise.all(inflight);
  if (failure) throw failure;
  cands.sort((a, b) => a.frame - b.frame);
  // merge the two pose passes: the same person found twice -> keep the more confident skeleton
  const iou = (a, b) => {
    const w = Math.max(0, Math.min(a[2], b[2]) - Math.max(a[0], b[0])), h = Math.max(0, Math.min(a[3], b[3]) - Math.max(a[1], b[1]));
    const u = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - w * h;
    return u > 0 ? (w * h) / u : 0;
  };
  for (const f of [...people.keys()].sort((a, b) => a - b)) {
    const kept = [];
    for (const q of people.get(f).sort((a, b) => b.conf - a.conf)) if (kept.every((k) => iou(k.box, q.box) < 0.45)) kept.push(q);
    for (const q of kept) { poses.frame.push(f); poses.kpts.push(q.k2); poses.scores.push(q.sc); feats.push(q.feat); }
  }
  const order = poses.frame.map((_, i) => i);
  return {
    fps: state.fps, width: state.W, height: state.VH, H, N, cands,
    poses: { frame: order.map((i) => poses.frame[i]), kpts: order.map((i) => poses.kpts[i]), scores: order.map((i) => poses.scores[i]) },
    feats: order.map((i) => feats[i]),
    inferenceSeconds: (performance.now() - t0) / 1000,
    timings: { tracknetMs: tnMs, poseMs },
  };
}

function analysePipeline(input) {
  const p = preset();
  return new Promise((resolve, reject) => {
    const w = new Worker(new URL('./app/pipeline.worker.js', import.meta.url), { type: 'module' });
    w.onmessage = ({ data }) => {
      if (data.type === 'progress') setProgress(0.85 + 0.15 * data.frac, `Phân tích: ${data.label}…`);
      else if (data.type === 'done') { w.terminate(); resolve(data.result); }
      else if (data.type === 'error') { w.terminate(); reject(new Error(data.message)); }
    };
    w.postMessage({ input, opts: { poseEvery: p.poseEvery, starts: p.starts, maxNfev: p.maxNfev } });
  });
}

// ---------- step 4: result ----------
const ov = $('#overlay');
const panelCanvas = $('#panel');
let renderer = null, poseCache = null;

function makeRenderer(layout, panelPosition = 'below') {
  const r = state.result, inp = r.input;
  const cam = calibrateFromHomography(inp.H, inp.width, inp.height);
  poseCache = poseCache || buildPoses(r.players, inp.poses.kpts, inp.poses.scores, r.k3d);
  return createRenderer({
    cam, fps: inp.fps, width: inp.width, height: inp.height,
    shots: r.shots.filter((s) => s.good), report: r.report, landings: r.landings,
    shuttleRows: r.shuttle, poses: poseCache, players: r.players, layout, panelPosition,
  });
}

function showResult() {
  const r = state.result;
  window.__result = r;   // for devtools
  poseCache = null;
  renderer = makeRenderer('horizontal');
  show($('#step-result'));
  ov.width = r.input.width; ov.height = r.input.height;
  panelCanvas.width = renderer.panelWidth; panelCanvas.height = renderer.panelHeight;
  const rep = r.report.summary;
  setProgress(1, `Xong trong ${fmtTime(r.seconds)} (mức ${r.preset}, ${state.ready.backend === 'webgpu' ? 'GPU' : 'CPU'}) · ` +
    `${rep.shots} cú có đường bay 3D, ${rep.rallies} pha, ${rep.players} người chơi` +
    (state.courtFit ? ` · sân khớp vạch trắng ${state.courtFit.seedCost.toFixed(1)} → ${state.courtFit.cost.toFixed(1)} px` : ''));
  $('#report').innerHTML = reportHtml(r.report, state.file?.name || '');
  player.currentTime = 0;
  drawFrame(0);
  if ('requestVideoFrameCallback' in HTMLVideoElement.prototype) {
    const loop = (_, m) => { drawFrame(Math.floor(m.mediaTime * r.input.fps + 1e-3)); player.requestVideoFrameCallback(loop); };
    player.requestVideoFrameCallback(loop);
  } else {
    player.addEventListener('timeupdate', () => drawFrame(Math.floor(player.currentTime * r.input.fps)));
  }
  player.addEventListener('seeked', () => drawFrame(Math.floor(player.currentTime * r.input.fps + 1e-3)));
  $('#step-result').scrollIntoView({ behavior: 'smooth' });
}

function drawFrame(f) {
  if (!renderer) return;
  const c = ov.getContext('2d');
  c.clearRect(0, 0, ov.width, ov.height);
  renderer.drawOverlay(c, f);
  renderer.drawPanel(panelCanvas.getContext('2d'), f);
}

// clicking a shot in the report jumps the video there
$('#report').addEventListener('click', (e) => {
  const tr = e.target.closest('tr[data-frame]');
  if (tr && state.result) { player.currentTime = (+tr.dataset.frame + 0.5) / state.result.input.fps - 0.5; player.play(); }
});

$('#btn-json').onclick = () => {
  const r = state.result;
  const data = {
    video: state.file?.name, preset: r.preset, fps: r.input.fps, size: [r.input.width, r.input.height],
    court_to_image: r.input.H, camera: r.camera, report: r.report, flights: r.shots, hits: r.hits, landings: r.landings,
  };
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([JSON.stringify(data)], { type: 'application/json' }));
  a.download = (state.file?.name || 'video').replace(/\.\w+$/, '') + '_analysis.json';
  a.click();
};

$('#btn-export').onclick = async () => {
  const r = state.result;
  const st = $('#export-status');
  if (!('VideoEncoder' in window)) { st.textContent = 'Trình duyệt này chưa hỗ trợ WebCodecs — hãy dùng Chrome/Edge/Safari mới.'; return; }
  const btn = $('#btn-export');
  btn.disabled = true;
  try {
    const choice = $('#opt-layout').value;
    const R = choice === 'horizontal' ? makeRenderer('horizontal')
      : makeRenderer('vertical', choice === 'vertical-above' ? 'above' : 'below');
    const W = Math.round(R.compositeWidth / 2) * 2, H = Math.round(R.compositeHeight / 2) * 2;
    let codec = null;
    for (const c of ['avc1.640034', 'avc1.640033', 'avc1.640028', 'avc1.4d0028']) {
      const s = await VideoEncoder.isConfigSupported({ codec: c, width: W, height: H, bitrate: 10e6, framerate: r.input.fps });
      if (s.supported) { codec = c; break; }
    }
    if (!codec) throw new Error('không mã hoá được H.264 ở ' + W + '×' + H);
    const muxer = new Muxer({ target: new ArrayBufferTarget(), video: { codec: 'avc', width: W, height: H }, fastStart: 'in-memory' });
    let encErr = null;
    const enc = new VideoEncoder({ output: (chunk, meta) => muxer.addVideoChunk(chunk, meta), error: (e) => { encErr = e; } });
    enc.configure({ codec, width: W, height: H, bitrate: 10e6, framerate: r.input.fps });
    const canvas = new OffscreenCanvas(W, H);
    const ctx = canvas.getContext('2d');
    const t0 = performance.now();
    const N = r.input.N;
    for (let f = 0; f < N; f++) {
      if (encErr) throw encErr;
      await seek(proc, (f + 0.5) / r.input.fps);
      ctx.fillStyle = '#0D1117'; ctx.fillRect(0, 0, W, H);
      R.drawComposite(ctx, f, proc);
      const vf = new VideoFrame(canvas, { timestamp: Math.round((f * 1e6) / r.input.fps), duration: Math.round(1e6 / r.input.fps) });
      enc.encode(vf, { keyFrame: f % Math.round(r.input.fps * 2) === 0 });
      vf.close();
      while (enc.encodeQueueSize > 8) await new Promise((res) => setTimeout(res, 1));
      if (f % 15 === 0) st.textContent = `Đang xuất ${Math.round((100 * f) / N)}% · ${(f / ((performance.now() - t0) / 1000)).toFixed(0)} fps`;
    }
    await enc.flush();
    muxer.finalize();
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([muxer.target.buffer], { type: 'video/mp4' }));
    a.download = (state.file?.name || 'video').replace(/\.\w+$/, '') + (choice === 'horizontal' ? '_analysis.mp4' : '_analysis_9x16.mp4');
    a.click();
    st.textContent = `Xong (${fmtTime((performance.now() - t0) / 1000)}, ${W}×${H}). Video xuất không có tiếng.`;
  } catch (e) {
    st.textContent = 'Lỗi xuất video: ' + e.message;
  } finally { btn.disabled = false; }
};

renderDeviceTable($('#device-table'), null);
