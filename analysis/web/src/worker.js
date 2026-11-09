// Inference worker: TrackNetV3 (shuttle) + RTMO-s (players' pose) via onnxruntime-web.
// Everything runs on the visitor's own GPU (WebGPU) or CPU (WASM) — the video never leaves the device.
import * as ort from 'onnxruntime-web/webgpu';

ort.env.wasm.wasmPaths = new URL('/ort/', self.location.origin).href;
ort.env.wasm.numThreads = self.crossOriginIsolated ? Math.min(8, navigator.hardwareConcurrency || 4) : 1;
ort.env.logLevel = 'error';

const MODEL_CACHE = 'badminton-models-v1';
let tracknet = null;
let rtmo = null;
let backend = 'wasm';

const post = (type, data = {}, transfer = []) => self.postMessage({ type, ...data }, transfer);

async function fetchModel(url, label) {
  let cache = null;
  try { cache = await caches.open(MODEL_CACHE); } catch { /* no Cache API (private mode) */ }
  const hit = cache && (await cache.match(url));
  if (hit) {
    post('progress', { label: `${label}: lấy từ bộ nhớ đệm`, frac: 1 });
    return new Uint8Array(await hit.arrayBuffer());
  }
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Không tải được ${url} (${res.status})`);
  const total = Number(res.headers.get('content-length')) || 0;
  const reader = res.body.getReader();
  const chunks = [];
  let got = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    got += value.length;
    post('progress', { label: `Tải ${label} ${(got / 1e6).toFixed(1)}${total ? ' / ' + (total / 1e6).toFixed(1) : ''} MB`, frac: total ? got / total : 0 });
  }
  const buf = new Uint8Array(got);
  let o = 0;
  for (const c of chunks) { buf.set(c, o); o += c.length; }
  try { cache && (await cache.put(url, new Response(buf.slice()))); } catch { /* quota */ }
  return buf;
}

async function gpuInfo() {
  if (!self.navigator.gpu) return null;
  try {
    const a = await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' });
    if (!a) return null;
    const info = a.info || {};
    return { f16: a.features.has('shader-f16'), vendor: info.vendor || '', arch: info.architecture || '', desc: info.description || '' };
  } catch { return null; }
}

async function init({ want, pose }) {
  const gpu = await gpuInfo();
  backend = want === 'wasm' || !gpu ? 'wasm' : 'webgpu';
  const ep = backend === 'webgpu' ? ['webgpu', 'wasm'] : ['wasm'];
  // fp16 halves the download and doubles GPU speed; CPU kernels are fp32 only
  const tnFile = backend === 'webgpu' && gpu.f16 ? 'tracknet_fp16.onnx' : 'tracknet_fp32.onnx';
  const opts = { executionProviders: ep, graphOptimizationLevel: 'all' };
  tracknet?.release?.();
  rtmo?.release?.();
  tracknet = await ort.InferenceSession.create(await fetchModel(`/models/${tnFile}`, 'TrackNetV3'), opts);
  rtmo = pose ? await ort.InferenceSession.create(await fetchModel('/models/rtmo_s.onnx', 'RTMO-s'), opts) : null;
  post('ready', { backend, model: tnFile, gpu, threads: ort.env.wasm.numThreads, isolated: self.crossOriginIsolated });
}

// ---------- TrackNet ----------

// 3 RGBA frames (w*h*4) -> (1, 9, h, w) float, BGR order /255 (the weights were trained on cv2 frames)
function tracknetInput(frames, w, h) {
  const n = w * h;
  const x = new Float32Array(9 * n);
  for (let k = 0; k < 3; k++) {
    const f = frames[k];
    const b = x.subarray((k * 3) * n), g = x.subarray((k * 3 + 1) * n), r = x.subarray((k * 3 + 2) * n);
    for (let i = 0, j = 0; i < n; i++, j += 4) {
      r[i] = f[j] / 255; g[i] = f[j + 1] / 255; b[i] = f[j + 2] / 255;
    }
  }
  return new ort.Tensor('float32', x, [1, 9, h, w]);
}

// every blob > thr (8-connected), like the desktop pipeline: the tracker decides which one is ours
function blobs(heat, w, h, thr = 0.5) {
  const seen = new Uint8Array(w * h);
  const out = [];
  const stack = [];
  for (let s = 0; s < w * h; s++) {
    if (seen[s] || heat[s] <= thr) continue;
    let sx = 0, sy = 0, area = 0, peak = 0;
    stack.push(s); seen[s] = 1;
    while (stack.length) {
      const p = stack.pop();
      const px = p % w, py = (p - px) / w;
      sx += px; sy += py; area++; if (heat[p] > peak) peak = heat[p];
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        const qx = px + dx, qy = py + dy;
        if (qx < 0 || qy < 0 || qx >= w || qy >= h) continue;
        const q = qy * w + qx;
        if (!seen[q] && heat[q] > thr) { seen[q] = 1; stack.push(q); }
      }
    }
    out.push({ x: (sx / area + 0.5) / w, y: (sy / area + 0.5) / h, area, score: peak });
  }
  return out;
}

async function runTracknet({ frames, w, h }) {
  const t0 = performance.now();
  const out = await tracknet.run({ [tracknet.inputNames[0]]: tracknetInput(frames, w, h) });
  const heat = out[tracknet.outputNames[0]].data;
  const n = w * h;
  const res = [0, 1, 2].map((k) => blobs(heat.subarray(k * n, (k + 1) * n), w, h));
  return { cands: res, ms: performance.now() - t0 };
}

// ---------- RTMO ----------

function iou(a, b) {
  const x1 = Math.max(a[0], b[0]), y1 = Math.max(a[1], b[1]), x2 = Math.min(a[2], b[2]), y2 = Math.min(a[3], b[3]);
  const inter = Math.max(0, x2 - x1) * Math.max(0, y2 - y1);
  return inter / ((a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter + 1e-9);
}

async function runPose({ image }) {
  const t0 = performance.now();
  const S = 640, n = S * S;
  const x = new Float32Array(3 * n);           // BGR 0..255, letterboxed by the main thread
  for (let i = 0, j = 0; i < n; i++, j += 4) { x[i] = image[j + 2]; x[n + i] = image[j + 1]; x[2 * n + i] = image[j]; }
  const out = await rtmo.run({ [rtmo.inputNames[0]]: new ort.Tensor('float32', x, [1, 3, S, S]) });
  const dets = out.dets, kps = out.keypoints;
  const N = dets.dims[1];
  const cand = [];
  for (let i = 0; i < N; i++) {
    const d = dets.data.subarray(i * 5, i * 5 + 5);
    if (d[4] < 0.35) continue;      // far-court players are small and score lower
    cand.push({ box: Array.from(d.subarray(0, 4)), score: d[4], i });
  }
  cand.sort((a, b) => b.score - a.score);
  const keep = [];
  for (const c of cand) if (keep.every((k) => iou(k.box, c.box) < 0.45)) keep.push(c);
  const people = keep.map((c) => ({
    box: c.box, score: c.score,
    kp: Array.from(kps.data.subarray(c.i * 51, c.i * 51 + 51)),   // 17 × (x, y, score) in 640 space
  }));
  return { people, ms: performance.now() - t0 };
}

async function bench({ w, h, pose }) {
  const frames = [0, 1, 2].map(() => new Uint8ClampedArray(w * h * 4).map((_, i) => (i * 37) & 255));
  const img = new Uint8ClampedArray(640 * 640 * 4).fill(114);
  const time = async (fn, n) => {
    await fn();                                  // warm-up: shader compilation / allocation
    const t0 = performance.now();
    for (let i = 0; i < n; i++) await fn();
    return (performance.now() - t0) / n;
  };
  const tn = await time(() => runTracknet({ frames, w, h }), 3);
  const ps = pose && rtmo ? await time(() => runPose({ image: img }), 3) : 0;
  return { tracknetMs: tn, poseMs: ps };
}

// onnxruntime-web must not run two inferences at once (WASM heap / WebGPU state are shared):
// handle messages strictly one after another.
let queue = Promise.resolve();
self.onmessage = ({ data }) => {
  queue = queue.then(async () => {
    try {
      if (data.type === 'init') await init(data);
      else if (data.type === 'bench') post('bench', await bench(data));
      else if (data.type === 'tracknet') post('tracknet', { id: data.id, ...(await runTracknet(data)) });
      else if (data.type === 'pose') post('pose', { id: data.id, ...(await runPose(data)) });
    } catch (e) {
      post('error', { id: data.id, message: String(e?.message || e) });
    }
  });
};
