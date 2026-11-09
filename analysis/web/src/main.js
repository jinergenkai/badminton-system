import { Muxer, ArrayBufferTarget } from 'mp4-muxer';
import { apply, COURT_LINES, COURT_W, HALF_L, homography, invert3, NET, projectSegment } from './geom.js';
import { buildTracks, playerStats, rallies, selectTracks, shuttleGate, trackPlayers } from './analysis.js';
import { DEVICE_TABLE, renderDeviceTable } from './devices.js';

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
  const key = `${$('#opt-backend').value}|${$('#opt-pose').value !== '0'}`;
  if (readyKey === key && state.ready) return state.ready;
  state.ready = null;
  const p = new Promise((res) => { onReady = res; });
  worker.postMessage({ type: 'init', want: $('#opt-backend').value, pose: $('#opt-pose').value !== '0' });
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
    ` · mô hình ${r.model.includes('fp16') ? 'FP16' : 'FP32'}`;
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
$('#calib-skip').onclick = () => { state.pairs = []; updateH(); drawCalib(); show($('#step-run')); $('#step-run').scrollIntoView({ behavior: 'smooth' }); };

// ---------- step 3: bench + run ----------
const resWH = () => $('#opt-res').value.split('x').map(Number);
const poseEvery = () => Number($('#opt-pose').value);
function rangeFrames() {
  const lim = Number($('#opt-range').value);
  const sec = lim ? Math.min(lim, state.duration) : state.duration;
  return Math.max(3, Math.floor((sec * state.fps) / 3) * 3);
}

function setProgress(frac, label) {
  const el = $('#progress');
  show(el);
  el.querySelector('i').style.width = `${Math.round((frac || 0) * 100)}%`;
  el.querySelector('span').textContent = label || '';
}

const SEEK_MS = 12;   // measured frame grab cost (seek + draw + readback) per frame, refined while running
function estimateSeconds(b, frames, every) {
  return (frames / 3) * b.tracknetMs / 1000 + (every ? (frames / every) * b.poseMs / 1000 : 0) + frames * SEEK_MS / 1000;
}

$('#btn-bench').onclick = async () => {
  const btn = $('#btn-bench');
  btn.disabled = true;
  try {
    await ensureModels();
    setProgress(0, 'Đang đo tốc độ… (lần đầu GPU phải biên dịch shader, có thể mất 10–30 giây)');
    const [w, h] = resWH();
    const b = await new Promise((res) => { onBench = res; worker.postMessage({ type: 'bench', w, h, pose: poseEvery() > 0 }); });
    state.bench = { ...b, w, h, backend: state.ready.backend };
    show($('#progress'), false);
    renderEstimate();
  } catch (e) { alert(e.message); } finally { btn.disabled = false; }
};

function renderEstimate() {
  const b = state.bench;
  const frames = rangeFrames();
  const every = poseEvery();
  const tFrame = (b.tracknetMs / 3 + (every ? b.poseMs / every : 0) + SEEK_MS) / 1000;
  const el = $('#estimate');
  el.innerHTML = `
    <div class="kpi"><b>${b.tracknetMs.toFixed(0)} ms</b><span>bắt cầu / 3 frame (${b.w}×${b.h})</span></div>
    <div class="kpi"><b>${every ? b.poseMs.toFixed(0) + ' ms' : '—'}</b><span>khung xương / lần</span></div>
    <div class="kpi"><b>${(1 / tFrame).toFixed(1)} fps</b><span>tốc độ xử lý ≈ ${(1 / tFrame / state.fps).toFixed(2)}× thời gian thực</span></div>
    <div class="kpi"><b>${fmtTime(estimateSeconds(b, frames, every))}</b><span>cho đoạn đã chọn (${fmtTime(frames / state.fps)})</span></div>
    <div class="kpi"><b>${fmtTime(estimateSeconds(b, state.duration * state.fps, every))}</b><span>cho cả video (${fmtTime(state.duration)})</span></div>
    <div class="kpi"><b>${fmtTime(estimateSeconds(b, 1800, every))}</b><span>cho 1 phút video 30 fps</span></div>`;
  show(el);
  renderDeviceTable($('#device-table'), { ...b, every, label: `Máy này (${b.backend === 'webgpu' ? 'GPU' : 'CPU'}, ${b.w}×${b.h})` });
}
['#opt-res', '#opt-pose', '#opt-range'].forEach((s) => $(s).addEventListener('change', () => state.bench && renderEstimate()));

let cancelled = false;
$('#btn-cancel').onclick = () => { cancelled = true; };

$('#btn-run').onclick = async () => {
  const run = $('#btn-run');
  run.disabled = true; $('#btn-bench').disabled = true; show($('#btn-cancel'));
  cancelled = false;
  try {
    await ensureModels();
    state.result = await analyse();
    if (state.result) showResult();
  } catch (e) {
    console.error(e); alert('Lỗi khi phân tích: ' + e.message);
  } finally {
    run.disabled = false; $('#btn-bench').disabled = false; show($('#btn-cancel'), false);
  }
};

async function analyse() {
  const [tw, th] = resWH();
  const every = poseEvery();
  const N = rangeFrames();
  const tn = new OffscreenCanvas(tw, th).getContext('2d', { willReadFrequently: true });
  const S = 640, ratio = Math.min(S / state.W, S / state.VH);
  const pz = new OffscreenCanvas(S, S).getContext('2d', { willReadFrequently: true });
  const cands = new Array(N);
  const poses = new Map();
  const inflight = [];
  let failure = null;
  const track = (p) => inflight.push(p.catch((e) => { failure = failure || e; }));
  const t0 = performance.now();
  let tnMs = 0, poseMs = 0;
  proc.pause();

  for (let g = 0; g < N; g += 3) {
    if (cancelled) { setProgress(g / N, 'Đã dừng.'); return null; }
    if (failure) throw failure;
    const frames = [];
    for (let k = 0; k < 3; k++) {
      const f = g + k;
      await seek(proc, (f + 0.5) / state.fps);
      tn.drawImage(proc, 0, 0, tw, th);
      frames.push(tn.getImageData(0, 0, tw, th).data);
      if (every && f % every === 0) {
        pz.fillStyle = 'rgb(114,114,114)'; pz.fillRect(0, 0, S, S);
        pz.drawImage(proc, 0, 0, state.W * ratio, state.VH * ratio);
        const img = pz.getImageData(0, 0, S, S).data;
        track(call({ type: 'pose', image: img }, [img.buffer]).then((r) => {
          poseMs += r.ms;
          poses.set(f, r.people.map((p) => ({ score: p.score, box: p.box.map((v) => v / ratio), kp: p.kp.map((v, i) => (i % 3 === 2 ? v : v / ratio)) })));
        }));
      }
    }
    track(call({ type: 'tracknet', frames, w: tw, h: th }, frames.map((f) => f.buffer)).then((r) => {
      tnMs += r.ms;
      r.cands.forEach((list, k) => { cands[g + k] = list.map((c) => ({ ...c, x: c.x * state.W, y: c.y * state.VH })); });
    }));
    // keep at most ~2 groups queued so grabbing overlaps with inference without piling up memory
    while (inflight.length > 4) await inflight.shift();
    const done = g + 3, el = (performance.now() - t0) / 1000;
    setProgress(done / N, `Frame ${done}/${N} · ${(done / el).toFixed(1)} fps · còn ~${fmtTime((el / done) * (N - done))} · bắt cầu ${(tnMs / Math.max(1, Math.ceil(done / 3))).toFixed(0)} ms/lần`);
  }
  await Promise.all(inflight);
  if (failure) throw failure;
  const total = (performance.now() - t0) / 1000;

  // post-processing (fast)
  const gate = shuttleGate(state.Hc, state.W, state.VH);
  const shuttle = selectTracks(buildTracks(cands, gate));
  const byFrame = new Map(shuttle.map((r) => [r.frame, r]));
  const players = trackPlayers(poses, state.Hinv, state.VH / 720).map((s) => ({ ...s, stats: playerStats(s, state.fps) }));
  const ral = rallies(shuttle, state.fps, state.Hinv, poses, every);
  window.__result = { shuttle, ral };   // handy for debugging in devtools
  setProgress(1, `Xong ${N} frame trong ${fmtTime(total)} (${(N / total).toFixed(1)} fps) bằng ${state.ready.backend === 'webgpu' ? 'GPU' : 'CPU'}.`);
  return {
    N, fps: state.fps, W: state.W, H: state.VH, every, total, backend: state.ready.backend, res: [tw, th],
    cands, shuttle, byFrame, poses, players, rallies: ral,
    hitFrames: ral.flatMap((r) => r.hits.map((h) => h.frame)),
    timings: { tracknetMs: tnMs / Math.ceil(N / 3), poseMs: every ? poseMs / Math.ceil(N / every) : 0 },
  };
}

// ---------- step 4: result ----------
const SKELETON = [[5, 7], [7, 9], [6, 8], [8, 10], [5, 6], [5, 11], [6, 12], [11, 12], [11, 13], [13, 15], [12, 14], [14, 16], [0, 5], [0, 6]];
const ov = $('#overlay');
const mm = $('#minimap');
const PLAYER_COLORS = ['#4fc3f7', '#ffb74d', '#ff6fb5', '#b388ff', '#81c784', '#fff176'];

function showResult() {
  const r = state.result;
  show($('#step-result'));
  ov.width = r.W; ov.height = r.H;
  player.currentTime = 0;
  renderStats();
  drawFrame(0);
  if ('requestVideoFrameCallback' in HTMLVideoElement.prototype) {
    const loop = (_, m) => { drawFrame(Math.floor(m.mediaTime * r.fps + 1e-3)); player.requestVideoFrameCallback(loop); };
    player.requestVideoFrameCallback(loop);
  } else {
    player.addEventListener('timeupdate', () => drawFrame(Math.floor(player.currentTime * r.fps)));
  }
  player.addEventListener('seeked', () => drawFrame(Math.floor(player.currentTime * r.fps + 1e-3)));
  $('#step-result').scrollIntoView({ behavior: 'smooth' });
}
$('#opt-heat').addEventListener('change', () => state.result && drawFrame(Math.floor(player.currentTime * state.result.fps)));

function poseAt(r, f) {
  if (!r.every) return null;
  const k = Math.floor(f / r.every) * r.every;
  return r.poses.get(k) || null;
}

function drawOverlay(ctx, r, f) {
  const k = r.W / 1280;
  ctx.lineCap = 'round';
  if (state.Hc) {
    ctx.strokeStyle = 'rgba(255,212,0,.75)'; ctx.lineWidth = 1.6 * Math.max(1, k);
    for (const [p, q] of COURT_LINES) {
      const pts = projectSegment(state.Hc, p, q);
      if (pts.length < 2) continue;
      ctx.beginPath(); pts.forEach((s, i) => ctx[i ? 'lineTo' : 'moveTo'](s[0], s[1])); ctx.stroke();
    }
  }
  const people = f < r.N ? poseAt(r, f) : null;
  for (const p of people || []) {
    const col = p.player !== undefined ? PLAYER_COLORS[p.player % PLAYER_COLORS.length] : 'rgba(255,255,255,.6)';
    ctx.strokeStyle = col; ctx.lineWidth = 3 * Math.max(1, k);
    for (const [a, b] of SKELETON) {
      if (p.kp[a * 3 + 2] < 0.3 || p.kp[b * 3 + 2] < 0.3) continue;
      ctx.beginPath(); ctx.moveTo(p.kp[a * 3], p.kp[a * 3 + 1]); ctx.lineTo(p.kp[b * 3], p.kp[b * 3 + 1]); ctx.stroke();
    }
    if (p.player !== undefined && p.kp[2] > 0.3) {
      ctx.fillStyle = col; ctx.font = `bold ${16 * Math.max(1, k)}px system-ui`; ctx.textAlign = 'center';
      ctx.fillText(`P${p.player + 1}`, p.kp[0], p.kp[1] - 22 * Math.max(1, k));
    }
  }
  // shuttle trail
  const trail = [];
  for (let i = f - 12; i <= f; i++) { const s = r.byFrame.get(i); if (s) trail.push(s); }
  for (let i = 1; i < trail.length; i++) {
    if (trail[i].frame - trail[i - 1].frame > 2) continue;
    ctx.strokeStyle = `rgba(255,77,77,${0.25 + 0.75 * (i / trail.length)})`; ctx.lineWidth = 4 * Math.max(1, k);
    ctx.beginPath(); ctx.moveTo(trail[i - 1].x, trail[i - 1].y); ctx.lineTo(trail[i].x, trail[i].y); ctx.stroke();
  }
  const cur = r.byFrame.get(f);
  if (cur) {
    ctx.fillStyle = cur.detected ? '#ff4d4d' : 'rgba(255,77,77,.5)';
    ctx.beginPath(); ctx.arc(cur.x, cur.y, 6 * Math.max(1, k), 0, 7); ctx.fill();
    ctx.strokeStyle = '#fff'; ctx.lineWidth = 1.5; ctx.stroke();
  }
  for (const h of r.hitFrames) {
    if (f >= h && f < h + r.fps * 0.4) {
      const s = r.byFrame.get(h);
      if (!s) continue;
      ctx.fillStyle = '#d9ff3f'; ctx.font = `800 ${18 * Math.max(1, k)}px system-ui`; ctx.textAlign = 'center';
      ctx.fillText('HIT', s.x, s.y - 14 * Math.max(1, k));
    }
  }
  for (const ra of r.rallies) {
    const L = ra.landing;
    if (!L || f < L.frame || f > L.frame + r.fps * 1.5 || !state.Hc) continue;
    const [x, y] = apply(state.Hc, [L.X, L.Y]);
    ctx.strokeStyle = L.inDoubles ? '#57d68d' : '#ff6b6b'; ctx.lineWidth = 3 * Math.max(1, k);
    ctx.beginPath(); ctx.ellipse(x, y, 18 * Math.max(1, k), 7 * Math.max(1, k), 0, 0, 7); ctx.stroke();
    ctx.fillStyle = ctx.strokeStyle; ctx.font = `800 ${16 * Math.max(1, k)}px system-ui`; ctx.textAlign = 'center';
    ctx.fillText(L.inDoubles ? 'IN' : 'OUT', x, y + 26 * Math.max(1, k));
  }
  // corner badge
  ctx.fillStyle = 'rgba(0,0,0,.55)'; ctx.fillRect(10 * k, 10 * k, 250 * Math.max(1, k), 30 * Math.max(1, k));
  ctx.fillStyle = '#d9ff3f'; ctx.font = `700 ${14 * Math.max(1, k)}px system-ui`; ctx.textAlign = 'left';
  ctx.fillText(`Pha ${r.rallies.filter((ra) => ra.start <= f).length}/${r.rallies.length} · t=${(f / r.fps).toFixed(1)}s`, 20 * k, 30 * Math.max(1, k));
}

function drawMinimap(ctx, r, f, heat) {
  const L = miniLayout(ctx.canvas, 18);
  drawMiniCourt(ctx, L);
  if (heat) {
    for (const p of r.players) for (const q of p.stats.smooth) {
      const [x, y] = L.toPx([q.X, q.Y]);
      const g = ctx.createRadialGradient(x, y, 0, x, y, 14);
      g.addColorStop(0, 'rgba(255,90,40,.10)'); g.addColorStop(1, 'rgba(255,90,40,0)');
      ctx.fillStyle = g; ctx.fillRect(x - 14, y - 14, 28, 28);
    }
  }
  for (const p of r.players) {
    const col = PLAYER_COLORS[p.id % PLAYER_COLORS.length];
    const recent = p.stats.smooth.filter((q) => q.f <= f && q.f > f - r.fps * 2);
    ctx.strokeStyle = col; ctx.globalAlpha = 0.6; ctx.lineWidth = 2;
    ctx.beginPath(); recent.forEach((q, i) => ctx[i ? 'lineTo' : 'moveTo'](...L.toPx([q.X, q.Y]))); ctx.stroke();
    ctx.globalAlpha = 1;
    const now = recent.at(-1);
    if (now && f - now.f < r.fps) {
      const [x, y] = L.toPx([now.X, now.Y]);
      ctx.fillStyle = col; ctx.beginPath(); ctx.arc(x, y, 6, 0, 7); ctx.fill();
      ctx.fillStyle = '#000'; ctx.font = 'bold 9px system-ui'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(String(p.id + 1), x, y + 0.5); ctx.textBaseline = 'alphabetic';
    }
  }
  for (const ra of r.rallies) {
    if (!ra.landing || ra.landing.frame > f) continue;
    const [x, y] = L.toPx([ra.landing.X, ra.landing.Y]);
    ctx.strokeStyle = ra.landing.inDoubles ? '#57d68d' : '#ff6b6b'; ctx.lineWidth = 2.5;
    ctx.beginPath(); ctx.moveTo(x - 5, y - 5); ctx.lineTo(x + 5, y + 5); ctx.moveTo(x + 5, y - 5); ctx.lineTo(x - 5, y + 5); ctx.stroke();
  }
}

function drawFrame(f) {
  const r = state.result;
  if (!r) return;
  const ctx = ov.getContext('2d');
  ctx.clearRect(0, 0, ov.width, ov.height);
  drawOverlay(ctx, r, f);
  drawMinimap(mm.getContext('2d'), r, f, $('#opt-heat').checked);
}

function renderStats() {
  const r = state.result;
  const shots = r.rallies.reduce((s, ra) => s + ra.shots, 0);
  const longest = r.rallies.reduce((m, ra) => Math.max(m, (ra.end - ra.start) / r.fps), 0);
  const lands = r.rallies.filter((ra) => ra.landing);
  const detected = r.shuttle.filter((s) => s.detected).length;
  const kpi = (v, l) => `<div class="kpi"><b>${v}</b><span>${l}</span></div>`;
  let html = kpi(r.rallies.length, 'pha cầu') + kpi(shots, 'cú đánh (ước tính 2D)') + kpi(`${longest.toFixed(1)} s`, 'pha dài nhất') +
    kpi(`${Math.round((100 * detected) / r.N)}%`, 'frame thấy cầu') +
    kpi(`${lands.filter((l) => l.landing.inDoubles).length} / ${lands.filter((l) => !l.landing.inDoubles).length}`, 'điểm rơi IN / OUT (thô, ±1–2 m)') +
    kpi(`${(r.N / r.total).toFixed(1)} fps`, `tốc độ máy bạn (${r.backend === 'webgpu' ? 'GPU' : 'CPU'})`);
  for (const p of r.players.slice().sort((a, b) => b.pts.length - a.pts.length).slice(0, 4)) {
    html += kpi(`${p.stats.distance.toFixed(0)} m`, `<span style="color:${PLAYER_COLORS[p.id % PLAYER_COLORS.length]}">P${p.id + 1}</span> chạy (${p.side < 0 ? 'phía camera' : 'phía xa'})`);
  }
  $('#stats').innerHTML = html;
}

$('#btn-json').onclick = () => {
  const r = state.result;
  const data = {
    video: state.file?.name, fps: r.fps, size: [r.W, r.H], frames: r.N, backend: r.backend, seconds: r.total,
    court_to_image: state.Hc, court_points: state.pairs,
    shuttle: r.shuttle, rallies: r.rallies,
    players: r.players.map((p) => ({ id: p.id + 1, side: p.side < 0 ? 'near' : 'far', distance_m: p.stats.distance, positions: p.pts })),
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
    const mmW = Math.round((r.H * 240) / 480 / 2) * 2;
    const W = Math.round((r.W + mmW) / 2) * 2, H = Math.round(r.H / 2) * 2;
    let codec = null;
    for (const c of ['avc1.640033', 'avc1.640028', 'avc1.4d0028', 'avc1.42E01F']) {
      const s = await VideoEncoder.isConfigSupported({ codec: c, width: W, height: H, bitrate: 8e6, framerate: r.fps });
      if (s.supported) { codec = c; break; }
    }
    if (!codec) throw new Error('không mã hoá được H.264 ở ' + W + '×' + H);
    const muxer = new Muxer({ target: new ArrayBufferTarget(), video: { codec: 'avc', width: W, height: H }, fastStart: 'in-memory' });
    let encErr = null;
    const enc = new VideoEncoder({ output: (chunk, meta) => muxer.addVideoChunk(chunk, meta), error: (e) => { encErr = e; } });
    enc.configure({ codec, width: W, height: H, bitrate: 8e6, framerate: r.fps });
    const canvas = new OffscreenCanvas(W, H);
    const ctx = canvas.getContext('2d');
    const mini = new OffscreenCanvas(240, 480);
    const t0 = performance.now();
    for (let f = 0; f < r.N; f++) {
      if (encErr) throw encErr;
      await seek(proc, (f + 0.5) / r.fps);
      ctx.fillStyle = '#0f1412'; ctx.fillRect(0, 0, W, H);
      ctx.drawImage(proc, 0, 0, r.W, r.H);
      drawOverlay(ctx, r, f);
      drawMinimap(mini.getContext('2d'), r, f, false);
      ctx.drawImage(mini, r.W, 0, mmW, r.H);
      const vf = new VideoFrame(canvas, { timestamp: Math.round((f * 1e6) / r.fps), duration: Math.round(1e6 / r.fps) });
      enc.encode(vf, { keyFrame: f % (r.fps * 2) === 0 });
      vf.close();
      while (enc.encodeQueueSize > 8) await new Promise((res) => setTimeout(res, 1));
      if (f % 15 === 0) st.textContent = `Đang xuất ${Math.round((100 * f) / r.N)}% · ${(f / ((performance.now() - t0) / 1000)).toFixed(0)} fps`;
    }
    await enc.flush();
    muxer.finalize();
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([muxer.target.buffer], { type: 'video/mp4' }));
    a.download = (state.file?.name || 'video').replace(/\.\w+$/, '') + '_analysis.mp4';
    a.click();
    st.textContent = `Xong (${fmtTime((performance.now() - t0) / 1000)}). Video xuất không có tiếng.`;
  } catch (e) {
    st.textContent = 'Lỗi xuất video: ' + e.message;
  } finally { btn.disabled = false; }
};

renderDeviceTable($('#device-table'), null);
export { DEVICE_TABLE };
