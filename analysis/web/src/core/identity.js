// Stable player identities ("P1".."P4") over the whole video. Port of analysis/badminton/identity.py.
// 1. appearance: HSV histograms of shirt and shorts from the pose keypoints (+ texture), Hellinger-normalised
// 2. players per side = most common head count on each half; k-means over all confident detections
// 3. per frame, Hungarian assignment of detections to players (appearance + floor jump cost)
import { W, HALF } from './camera.js';
import { linearSumAssignment } from './assign.js';
import { L_SH, R_SH, L_HIP, R_HIP, L_KNEE, R_KNEE } from './players.js';

export const H_BINS = 16, S_BINS = 4, V_BINS = 6;
export const FEAT_DIM = 2 * (H_BINS * S_BINS + V_BINS + 2);

// ---- OpenCV 8-bit BGR->HSV (cv::cvtColor COLOR_BGR2HSV, integer path, H in 0..179) ----
const HSV_SHIFT = 12;
const SDIV = new Int32Array(256), HDIV = new Int32Array(256);
for (let i = 1; i < 256; i++) {
  // saturate_cast<int>(double) rounds to nearest even; no table entry is an exact .5, so Math.round is the same
  SDIV[i] = Math.round((255 << HSV_SHIFT) / i);
  HDIV[i] = Math.round((180 << HSV_SHIFT) / (6 * i));
}

/** [h, s, v] of one 8-bit pixel, bit-exact with cv2.cvtColor(BGR2HSV). */
export function rgbToHsv8(r, g, b) {
  const v = Math.max(r, g, b), vmin = Math.min(r, g, b);
  const diff = v - vmin;
  const vr = v === r ? -1 : 0, vg = v === g ? -1 : 0;
  const s = (diff * SDIV[v] + (1 << (HSV_SHIFT - 1))) >> HSV_SHIFT;
  let h = (vr & (g - b)) + (~vr & ((vg & (b - r + 2 * diff)) + (~vg & (r - g + 4 * diff))));
  h = (h * HDIV[diff] + (1 << (HSV_SHIFT - 1))) >> HSV_SHIFT;
  if (h < 0) h += 180;
  return [h, s, v];
}

// cv2.calcHist uniform-bin lookup for 8-bit input: bin = floor(x * bins / (high - low) - low * a), -1 = out of range
function histLut(bins, low, high) {
  const a = bins / (high - low), b = -a * low, lut = new Int8Array(256);
  for (let x = 0; x < 256; x++) { const i = Math.floor(x * a + b); lut[x] = i >= 0 && i < bins ? i : -1; }
  return lut;
}
const LUT_H = histLut(H_BINS, 0, 180), LUT_S = histLut(S_BINS, 0, 256), LUT_V = histLut(V_BINS, 0, 256);

/** Shirt (shoulders-hips) and shorts (hips-knees) boxes [x0, y0, x1, y1] (or null) from the keypoints. */
export function bodyBoxes(k, s, thr = 0.3) {
  const out = [];
  for (const [top, bottom] of [[[L_SH, R_SH], [L_HIP, R_HIP]], [[L_HIP, R_HIP], [L_KNEE, R_KNEE]]]) {
    const idx = [...top, ...bottom].filter((j) => s[j] > thr);
    if (idx.length < 3) { out.push(null); continue; }
    const xs = idx.map((j) => k[j][0]), ys = idx.map((j) => k[j][1]);
    const x0 = Math.min(...xs), y0 = Math.min(...ys), x1 = Math.max(...xs), y1 = Math.max(...ys);
    const mx = 0.15 * (x1 - x0), my = 0.1 * (y1 - y0);
    out.push([x0 + mx, y0 + my, x1 - mx, y1 - my].map(Math.trunc));   // Python int(): towards zero
  }
  return out;
}

// reflect-101 border index (cv::BORDER_REFLECT_101; a length-1 axis maps to 0)
const refl = (i, n) => (n === 1 ? 0 : i < 0 ? -i : i >= n ? 2 * n - 2 - i : i);

/** Feature of one box on an RGBA frame (identity._hist), or null if the box has < 10 pixels. */
function boxFeature(rgba, width, height, box) {
  const x0 = Math.max(0, box[0]), y0 = Math.max(0, box[1]);
  const x1 = Math.min(width, Math.max(0, box[2])), y1 = Math.min(height, Math.max(0, box[3]));
  const w = Math.max(0, x1 - x0), h = Math.max(0, y1 - y0);
  if (w * h * 3 < 30) return null;                 // numpy roi.size counts the 3 channels
  const hs = new Float64Array(H_BINS * S_BINS), vh = new Float64Array(V_BINS);
  const val = new Float32Array(w * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const o = ((y0 + y) * width + x0 + x) * 4;
    const [H, S, V] = rgbToHsv8(rgba[o], rgba[o + 1], rgba[o + 2]);
    const bh = LUT_H[H], bs = LUT_S[S], bv = LUT_V[V];
    if (bh >= 0 && bs >= 0) hs[bh * S_BINS + bs]++;
    if (bv >= 0) vh[bv]++;
    val[y * w + x] = V;
  }
  const f = [...hs, ...[...vh].map((c) => 0.5 * c)];
  const tot = Math.max(f.reduce((a, c) => a + c, 0), 1);
  const out = f.map((c) => Math.sqrt(c / tot));     // Hellinger
  // texture: |Laplacian| (ksize=1: 4-neighbour kernel) of V, and the std of V
  let lap = 0, sum = 0;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const c = val[y * w + x];
    const l = val[y * w + refl(x - 1, w)] + val[y * w + refl(x + 1, w)] + val[refl(y - 1, h) * w + x] +
      val[refl(y + 1, h) * w + x] - 4 * c;
    lap += Math.abs(l);
    sum += c;
  }
  const n = w * h, m = sum / n;
  let ss = 0;
  for (let i = 0; i < n; i++) ss += (val[i] - m) ** 2;
  out.push(Math.min(lap / n / 40, 1.5), Math.sqrt(ss / n) / 80);
  return out;
}

/** Appearance feature (FEAT_DIM numbers) of one person on an RGBA frame, null when shirt or shorts are not visible. */
export function appearanceFeature(rgba, width, height, kpts, scores) {
  const [shirt, shorts] = bodyBoxes(kpts, scores);
  const hs = shirt && boxFeature(rgba, width, height, shirt);
  const hb = shorts && boxFeature(rgba, width, height, shorts);
  if (!hs || !hb) return null;
  return [...hs, ...hb.map((v) => 0.6 * v)];
}

// ---- who plays ----

/** Players per side {near, far} (1 = singles, 2 = doubles): most common head count on each half. */
export function playersPerSide(rows, share = 0.35) {
  // 1 (singles) or 2 (doubles): doubles when >= `share` of the frames show two people on that half
  // (deep players up to 2.5 m behind the baseline count) — same rule as identity.py players_per_side
  const counts = new Map();                         // frame -> {near, far}
  for (const r of rows) {
    if (!(r.X >= -0.5 && r.X <= W + 0.5 && Math.abs(r.Y) < HALF + 2.5)) continue;
    if (!counts.has(r.frame)) counts.set(r.frame, { near: 0, far: 0 });
    counts.get(r.frame)[r.side]++;
  }
  const frames = [...counts.values()];
  const out = {};
  for (const side of ['near', 'far']) {
    const two = frames.filter((c) => c[side] >= 2).length;
    out[side] = frames.length && two / frames.length >= share ? 2 : 1;
  }
  return out;
}

// deterministic RNG (mulberry32): JS cannot reproduce numpy's stream, so the k-means seeds differ from Python
function rng32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const sqd = (X, i, C, p, D) => {
  let s = 0;
  for (let d = 0; d < D; d++) { const e = X[i * D + d] - C[p * D + d]; s += e * e; }
  return s;
};

/** scipy.cluster.vq.kmeans2(X, k, iter=10, minit='++'): k-means++ seeding then 10 Lloyd steps. */
function kmeans2(X, N, D, k, rnd, iters = 10) {
  let C = new Float64Array(k * D);
  const D2 = new Float64Array(N).fill(Infinity);
  for (let c = 0; c < k; c++) {
    let pick;
    if (c === 0) pick = Math.floor(rnd() * N);
    else {
      let tot = 0;
      for (let i = 0; i < N; i++) { D2[i] = Math.min(D2[i], sqd(X, i, C, c - 1, D)); tot += D2[i]; }
      const r = rnd() * tot;
      let acc = 0;
      pick = N - 1;
      for (let i = 0; i < N; i++) { acc += D2[i]; if (acc >= r) { pick = i; break; } }   // searchsorted (left)
    }
    for (let d = 0; d < D; d++) C[c * D + d] = X[pick * D + d];
  }
  const lab = new Int32Array(N);
  const label = () => {
    for (let i = 0; i < N; i++) {
      let b = 0, bd = Infinity;
      for (let p = 0; p < k; p++) { const v = sqd(X, i, C, p, D); if (v < bd) { bd = v; b = p; } }
      lab[i] = b;
    }
  };
  for (let it = 0; it < iters; it++) {
    label();
    const S = new Float64Array(k * D), n = new Int32Array(k);
    for (let i = 0; i < N; i++) { n[lab[i]]++; for (let d = 0; d < D; d++) S[lab[i] * D + d] += X[i * D + d]; }
    for (let p = 0; p < k; p++) {
      if (!n[p]) { for (let d = 0; d < D; d++) S[p * D + d] = C[p * D + d]; continue; }   // empty: keep old centre
      for (let d = 0; d < D; d++) S[p * D + d] /= n[p];
    }
    C = S;
  }
  label();
  let inertia = 0;
  for (let i = 0; i < N; i++) inertia += sqd(X, i, C, lab[i], D);
  return { C, lab, inertia };
}

const median = (a) => {
  if (!a.length) return NaN;
  const s = a.slice().sort((x, y) => x - y), m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};

/**
 * Player identities. rows: [{frame, pid, X, Y, side, ...}] (side = per-frame side), feats: per row a
 * FEAT_DIM array or null. Returns { rows (copies with player 0..k-1 / -1, smoothed side, side_raw),
 * centroids: [k][FEAT_DIM] in player order, perSide: {near, far} }.
 */
export function assign(rows, feats, fps, { maxSpeed = 7.0, wPos = 0.35, maxCost = 1.2, seed = 0 } = {}) {
  const perSide = playersPerSide(rows);
  const k = perSide.near + perSide.far;
  const D = FEAT_DIM;
  const on = [];
  rows.forEach((r, i) => { if (r.X >= 0 && r.X <= W && Math.abs(r.Y) < HALF && feats[i]) on.push(i); });
  const N = on.length, X = new Float64Array(N * D);
  on.forEach((r, i) => X.set(feats[r], i * D));
  let best = null;
  for (let s = 0; s < 8; s++) {                    // k-means restarts, keep the tightest
    const km = kmeans2(X, N, D, k, rng32(seed + s));
    if (!best || km.inertia < best.inertia) best = km;
  }
  const cent = Array.from({ length: k }, (_, p) => Array.from(best.C.subarray(p * D, (p + 1) * D)));
  // typical distance of a detection to its own centre: the scale of "looks like this player"
  const scale = median(Array.from({ length: N }, (_, i) => Math.sqrt(sqd(X, i, best.C, best.lab[i], D)))) + 1e-6;

  const out = new Array(rows.length).fill(-1);
  const last = new Map();                          // player -> [frame, X, Y]
  const byFrame = new Map();
  rows.forEach((r, i) => { if (!byFrame.has(r.frame)) byFrame.set(r.frame, []); byFrame.get(r.frame).push(i); });
  for (const f of [...byFrame.keys()].sort((a, b) => a - b)) {
    const idx = byFrame.get(f);
    const C = idx.map((r) => {
      const ft = feats[r];
      return cent.map((c, p) => {
        const app = ft ? Math.sqrt(c.reduce((a, v, d) => a + (v - ft[d]) ** 2, 0)) / scale : 1.5;
        let pos = 0;
        if (last.has(p)) {
          const [lf, lx, ly] = last.get(p);
          const jump = Math.hypot(rows[r].X - lx, rows[r].Y - ly);
          const allowed = maxSpeed * (f - lf) / fps + 0.4;
          // small moves are free (and slightly preferred), impossible jumps forbidden
          pos = jump > 3 * allowed ? 9 : jump > allowed ? jump / allowed : 0.3 * jump / allowed;
        }
        return 0.5 * app + wPos * pos;
      });
    });
    for (const [a, p] of linearSumAssignment(C)) {
      if (C[a][p] < maxCost) {
        out[idx[a]] = p;
        last.set(p, [f, rows[idx[a]].X, rows[idx[a]].Y]);
      }
    }
  }
  // order players: near side first, then by median X, so labels are stable and readable
  const key = Array.from({ length: k }, (_, p) => {
    const mine = rows.filter((_, i) => out[i] === p);
    const mx = median(mine.map((r) => r.X));
    return [median(mine.map((r) => r.Y)) > 0 ? 1 : 0, Number.isNaN(mx) ? Infinity : mx];
  });
  const order = [...Array(k).keys()].sort((a, b) => key[a][0] - key[b][0] || key[a][1] - key[b][1]);
  const remap = new Map(order.map((p, i) => [p, i]));
  const res = rows.map((r, i) => ({ ...r, player: out[i] >= 0 ? remap.get(out[i]) : -1 }));
  smoothSides(res, fps);
  return { rows: res, centroids: order.map((p) => cent[p]), perSide };
}

/**
 * A player's side is the majority over ~15 s (centred window of int(window_s * fps) of that player's rows),
 * not the sign of Y in each frame. A detection > deep m inside the other half loses its identity.
 * Mutates rows: adds side_raw, rewrites side / player.
 */
export function smoothSides(rows, fps, windowS = 15.0, deep = 2.5) {
  for (const r of rows) r.side_raw = r.side;
  const by = new Map();
  rows.forEach((r, i) => { if (r.player >= 0) { if (!by.has(r.player)) by.set(r.player, []); by.get(r.player).push(i); } });
  const win = Math.trunc(windowS * fps);
  const off = (win - 1) >> 1;                       // pandas centred fixed window: [i - (win - off - 1), i + off]
  for (const g of by.values()) {
    g.sort((a, b) => rows[a].frame - rows[b].frame);
    const n = g.length, cum = new Int32Array(n + 1);
    g.forEach((r, i) => { cum[i + 1] = cum[i] + (rows[r].side_raw === 'near' ? 1 : 0); });
    const side = g.map((_, i) => {
      const end = Math.min(n, i + off + 1), start = Math.max(0, i + off + 1 - win);
      return 2 * (cum[end] - cum[start]) >= end - start ? 'near' : 'far';
    });
    g.forEach((r, i) => {
      const row = rows[r];
      row.side = side[i];
      if ((side[i] === 'near' && row.Y > deep) || (side[i] === 'far' && row.Y < -deep)) {
        row.player = -1;
        row.side = row.side_raw;
      }
    });
  }
  return rows;
}
