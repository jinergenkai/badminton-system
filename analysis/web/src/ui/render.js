// Broadcast-style render, ported from analysis/badminton/render.py (OpenCV + Pillow) to Canvas 2D.
//
// Video overlay (kept clean, no text boxes): thin court lines / net / posts, players as smoothed skeletons in
//   a fixed colour with a small P# tag, the glowing shuttle trail + ball, the fitted 3D flight projected back
//   (solid = measured part, dotted = prediction) and landing rings (IN green / OUT red) for ~2 s, fading.
// Analysis panel: a fixed 3/4 view of the 3D scene (players with floor shadows, flight path with the ball
//   height, contacts, landings for ~2 s with an IN / OUT tag), rally / shot count and time chips, the
//   "last shot" card and one card per player (running distance, shots so far).
// Layouts: 'horizontal' (video | panel) or 'vertical' (9:16 portrait, panel below or above the video).
//
// Only identified players (player >= 0) are drawn. Video sizes scale with s = h / 576.
//
// Usage:
//   const poses = buildPoses(playerRows, pose.kpts, pose.scores, k3d);
//   const R = createRenderer({ cam, fps, width, height, shots, report, landings, shuttleRows, poses,
//                              players: playerRows, layout: 'horizontal' | 'vertical', panelPosition: 'below' | 'above' });
//   live:   overlayCtx.clearRect(0, 0, w, h); R.drawOverlay(overlayCtx, f);  R.drawPanel(panelCtx, f)  (panelWidth x panelHeight)
//   export: canvas compositeWidth x compositeHeight;  R.drawComposite(ctx, f, videoElementOrCanvas);
import { HALF, NET_CENTRE, NET_POST, W } from '../core/camera.js';
import { positions } from '../core/physics.js';

// ---------------------------------------------------------------- court geometry (court.py)

export const NET_BOTTOM = 0.79;
const SINGLES_INSET = 0.46, SHORT = 1.98, LONG_DOUBLES = HALF - 0.76;

/** Floor lines as [[x0, y0], [x1, y1]] segments. */
export function courtLines() {
  const L = [];
  for (const x of [0, SINGLES_INSET, W - SINGLES_INSET, W]) L.push([[x, -HALF], [x, HALF]]);
  for (const s of [-1, 1]) {
    L.push([[0, s * HALF], [W, s * HALF]]);
    L.push([[0, s * LONG_DOUBLES], [W, s * LONG_DOUBLES]]);
    L.push([[0, s * SHORT], [W, s * SHORT]]);
    L.push([[W / 2, s * SHORT], [W / 2, s * HALF]]);
  }
  return L;
}

/** Net tape: 1.55 m at the posts, sagging to 1.524 m at the centre. */
export function netTop(n = 40) {
  return Array.from({ length: n }, (_, i) => {
    const x = (W * i) / (n - 1);
    return [x, 0, NET_POST - (NET_POST - NET_CENTRE) * (1 - Math.abs(x - W / 2) / (W / 2))];
  });
}

export const BONES = [[5, 7], [7, 9], [6, 8], [8, 10], [5, 6], [5, 11], [6, 12], [11, 12], [11, 13], [13, 15], [12, 14],
  [14, 16], [0, 5], [0, 6]];

// ---------------------------------------------------------------- style

export const HIT_SHOW = 28;        // frames a hit callout stays up
export const TRAIL = 14;           // shuttle trail length (frames)
export const PLAYER_HEX = ['#4FC3F7', '#FFB74D', '#F06292', '#AED581', '#BA68C8', '#4DD0E1'];
const SHUTTLE_HEX = '#FF5252', PATH_HEX = '#B3E5FC', IN_HEX = '#69F0AE', OUT_HEX = '#FF5252', GOLD = '#FFD54F';
const BG_TOP = '#0D1117', BG_BOTTOM = '#161B22';
const TEXT = '#E6EDF3', MUTED = '#8B949E', CARD = 'rgba(22,27,34,0.843)', INK = 'rgb(15,17,21)';
export const TYPES_VI = { serve: 'Giao cầu', smash: 'Đập', clear: 'Phông cao', drop: 'Bỏ nhỏ', lift: 'Lốp',
  net: 'Cầu lưới', drive: 'Tạt', push: 'Đẩy / chặn' };
const FAMILY = "'Segoe UI', system-ui, sans-serif";

export const pcol = (p) => PLAYER_HEX[((p % PLAYER_HEX.length) + PLAYER_HEX.length) % PLAYER_HEX.length];
function rgba(hex, a) {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${n >> 16},${(n >> 8) & 255},${n & 255},${a})`;
}

// ---------------------------------------------------------------- smoothed skeletons

/** Linear interpolation of NaN runs no longer than maxGap that have data on both sides (in place). */
export function fillShort(a, maxGap) {
  const n = a.length;
  let prev = -1;                                   // last valid index
  for (let i = 0; i < n; i++) {
    if (Number.isNaN(a[i])) continue;
    if (prev >= 0 && i - prev - 1 > 0 && i - prev - 1 <= maxGap) {
      const v0 = a[prev], v1 = a[i];
      for (let k = prev + 1; k < i; k++) a[k] = v0 + ((v1 - v0) * (k - prev)) / (i - prev);
    }
    prev = i;
  }
  return a;
}

/** NaN-aware Gaussian smoothing along time (1-D), same rule as render._smooth. Returns a new array. */
export function smoothNaN(a, sigma) {
  const r = Math.floor(3 * sigma), n = a.length;
  const k = new Float64Array(2 * r + 1);
  let ks = 0;
  for (let j = -r; j <= r; j++) { k[j + r] = Math.exp(-0.5 * (j / sigma) ** 2); ks += k[j + r]; }
  const out = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    if (Number.isNaN(a[i])) { out[i] = NaN; continue; }
    let num = 0, den = 0;
    for (let j = -r; j <= r; j++) {
      const v = a[i + j];
      if (i + j < 0 || i + j >= n || Number.isNaN(v)) continue;
      num += v * k[j + r]; den += k[j + r];
    }
    out[i] = den > 0.35 * ks ? num / Math.max(den, 1e-9) : NaN;
  }
  return out;
}

const num = (v) => (v === null || v === undefined ? NaN : v);

/** Column dict ({frame: [...], det: [...], ...}) -> array of row objects. */
export function rowsFromColumns(cols) {
  const keys = Object.keys(cols), n = cols[keys[0]].length;
  const rows = new Array(n);
  for (let i = 0; i < n; i++) { const r = {}; for (const k of keys) r[k] = cols[k][i]; rows[i] = r; }
  return rows;
}

/**
 * Smoothed per-player skeletons (render.build_poses).
 * players: array of rows {frame, det, player} (player 0-based, -1 = not a player); k3d[i] is aligned with players[i].
 * kpts[det] = 17 x [x, y] pixels, scores[det] = 17 scores.
 * Joints with score <= thr are missing; every joint coordinate is interpolated through gaps <= maxGap frames
 * and Gaussian-smoothed (sigma frames).
 *
 * Returns Map(player -> {f0, n, K2, K3, nValid}):
 *   K2: Float32Array(n * 34), joint j of frame f0 + i at [(i * 17 + j) * 2 + 0..1]    (NaN = missing)
 *   K3: Float32Array(n * 51), joint j of frame f0 + i at [(i * 17 + j) * 3 + 0..2]    (court metres, NaN = missing)
 *   nValid: Uint8Array(n), number of valid 2D joints per frame.
 */
// left/right keypoint pairs (COCO): eyes, ears, shoulders, elbows, wrists, hips, knees, ankles
const LR = [[1, 2], [3, 4], [5, 6], [7, 8], [9, 10], [11, 12], [13, 14], [15, 16]];
const MIRROR = Array.from({ length: 17 }, (_, j) => j);
for (const [a, b] of LR) { MIRROR[a] = b; MIRROR[b] = a; }

/**
 * Clean the pose samples of one player before gaps are interpolated:
 *  1. left/right swaps: a small one-stage model seen from behind often labels the left arm as the right one.
 *     If mirroring the sample fits the previous sample much better (< 60 % of the cost), mirror it.
 *  2. big moves between two samples (a racket swing with pose every few frames): linear interpolation would
 *     sweep the arm through the body, so the frames in between hold the nearest sample instead.
 * K2 / K3: flat arrays (n x 17 x 2 / 3); sampleIdx: indices of the frames that have a pose.
 */
export function fixSamples(K2, K3, sampleIdx, maxGap = 12) {
  const at = (i, j) => [K2[(i * 17 + j) * 2], K2[(i * 17 + j) * 2 + 1]];
  const ok = (i, j) => !Number.isNaN(K2[(i * 17 + j) * 2]);
  const samples = [...new Set(sampleIdx)].sort((a, b) => a - b);
  const swap = (i) => {
    for (const [a, b] of LR) {
      for (let c = 0; c < 2; c++) { const x = (i * 17 + a) * 2 + c, y = (i * 17 + b) * 2 + c; [K2[x], K2[y]] = [K2[y], K2[x]]; }
      for (let c = 0; c < 3; c++) { const x = (i * 17 + a) * 3 + c, y = (i * 17 + b) * 3 + c; [K3[x], K3[y]] = [K3[y], K3[x]]; }
    }
  };
  const torso = (i) => {
    if (!(ok(i, 5) && ok(i, 6) && ok(i, 11) && ok(i, 12))) return NaN;
    const n = at(i, 5).map((v, c) => (v + at(i, 6)[c]) / 2), h = at(i, 11).map((v, c) => (v + at(i, 12)[c]) / 2);
    return Math.hypot(n[0] - h[0], n[1] - h[1]);
  };
  let prev = -1;
  for (const i of samples) {
    if (prev >= 0) {
      let same = 0, mirr = 0, cnt = 0;
      for (let j = 5; j < 17; j++) {
        if (!ok(i, j) || !ok(prev, j) || !ok(i, MIRROR[j])) continue;
        const q = at(prev, j), a = at(i, j), b = at(i, MIRROR[j]);
        same += Math.hypot(a[0] - q[0], a[1] - q[1]); mirr += Math.hypot(b[0] - q[0], b[1] - q[1]); cnt++;
      }
      if (cnt >= 4 && mirr < 0.6 * same) swap(i);
      // hold instead of interpolating across a big arm move
      const g = i - prev, T = torso(prev);
      if (g > 1 && g <= maxGap && T > 0) {
        let d = 0, m = 0;
        for (const j of [7, 8, 9, 10]) if (ok(i, j) && ok(prev, j)) { const a = at(i, j), q = at(prev, j); d += Math.hypot(a[0] - q[0], a[1] - q[1]); m++; }
        if (m && d / m > Math.max(0.6 * T, 20)) {
          for (let k = prev + 1; k < i; k++) {
            const src = k - prev <= i - k ? prev : i;
            for (let j = 0; j < 17; j++) {
              for (let c = 0; c < 2; c++) K2[(k * 17 + j) * 2 + c] = K2[(src * 17 + j) * 2 + c];
              for (let c = 0; c < 3; c++) K3[(k * 17 + j) * 3 + c] = K3[(src * 17 + j) * 3 + c];
            }
          }
        }
      }
    }
    prev = i;
  }
}

export function buildPoses(players, kpts, scores, k3d, opts = {}) {
  const { maxGap = 12, sigma = 1.2, thr = 0.3 } = opts;
  const groups = new Map();
  players.forEach((row, idx) => {
    if (!(row.player >= 0)) return;
    if (!groups.has(row.player)) groups.set(row.player, []);
    groups.get(row.player).push(idx);
  });
  const out = new Map();
  for (const [p, idxs] of [...groups].sort((a, b) => a[0] - b[0])) {
    idxs.sort((a, b) => players[a].frame - players[b].frame || a - b);       // stable by row order
    const f0 = players[idxs[0]].frame, f1 = players[idxs.at(-1)].frame, n = f1 - f0 + 1;
    const K2 = new Float32Array(n * 34).fill(NaN), K3 = new Float32Array(n * 51).fill(NaN);
    let last = -1;
    for (const r of idxs) {
      const row = players[r], i = row.frame - f0;
      if (i === last) continue;                                                // drop duplicate frames (keep first)
      last = i;
      const det = row.det, sc = scores[det], kp = kpts[det], k3 = k3d ? k3d[r] : null;
      for (let j = 0; j < 17; j++) {
        if (!(sc[j] > thr)) continue;
        K2[(i * 17 + j) * 2] = num(kp[j][0]); K2[(i * 17 + j) * 2 + 1] = num(kp[j][1]);
        if (k3) for (let c = 0; c < 3; c++) K3[(i * 17 + j) * 3 + c] = num(k3[j][c]);
      }
    }
    fixSamples(K2, K3, idxs.map((r) => players[r].frame - f0), maxGap);
    const col = new Float64Array(n);
    for (const [arr, stride] of [[K2, 34], [K3, 51]]) {
      for (let c = 0; c < stride; c++) {
        for (let i = 0; i < n; i++) col[i] = arr[i * stride + c];
        const sm = smoothNaN(fillShort(col, maxGap), sigma);
        for (let i = 0; i < n; i++) arr[i * stride + c] = sm[i];
      }
    }
    const nValid = new Uint8Array(n);
    for (let i = 0; i < n; i++) {
      let c = 0;
      for (let j = 0; j < 17; j++) if (!Number.isNaN(K2[(i * 17 + j) * 2])) c++;
      nValid[i] = c;
    }
    out.set(p, { f0, n, K2, K3, nValid });
  }
  return out;
}

/** Players visible at frame f (>= minJoints valid joints): [{player, k2: [[x,y]|null]*17, k3: [[X,Y,Z]|null]*17}]. */
export function posesAt(poses, f, minJoints = 8) {
  const res = [];
  for (const [player, P] of poses) {
    const i = f - P.f0;
    if (i < 0 || i >= P.n || P.nValid[i] < minJoints) continue;
    const k2 = new Array(17), k3 = new Array(17);
    for (let j = 0; j < 17; j++) {
      const a = (i * 17 + j) * 2, b = (i * 17 + j) * 3;
      k2[j] = Number.isNaN(P.K2[a]) ? null : [P.K2[a], P.K2[a + 1]];
      k3[j] = Number.isNaN(P.K3[b]) ? null : [P.K3[b], P.K3[b + 1], P.K3[b + 2]];
    }
    res.push({ player, k2, k3 });
  }
  return res;
}

// ---------------------------------------------------------------- running distance (analytics.player_tracks)

function rolling(a, win, fn) {
  const h = Math.floor(win / 2), out = new Float64Array(a.length);
  for (let i = 0; i < a.length; i++) out[i] = fn(a.slice(Math.max(0, i - h), Math.min(a.length, i + win - h)));
  return out;
}
const median = (v) => { const s = Array.from(v).sort((x, y) => x - y), m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };
const mean = (v) => v.reduce((s, x) => s + x, 0) / v.length;

/** rows {frame, player, X, Y} -> Map(player -> {frames: Int32Array, cum: Float64Array}) cumulative metres run. */
export function runningDistance(rows, fps) {
  const groups = new Map();
  for (const r of rows) {
    if (!(r.player >= 0) || r.X == null || r.Y == null) continue;
    if (!groups.has(r.player)) groups.set(r.player, new Map());
    const g = groups.get(r.player);
    if (!g.has(r.frame)) g.set(r.frame, r);
  }
  const out = new Map();
  for (const [p, g] of groups) {
    const rs = [...g.values()].sort((a, b) => a.frame - b.frame);
    const fr = Int32Array.from(rs, (r) => r.frame);
    const X = rolling(rolling(Float64Array.from(rs, (r) => r.X), 5, median), 7, mean);
    const Y = rolling(rolling(Float64Array.from(rs, (r) => r.Y), 5, median), 7, mean);
    const cum = new Float64Array(rs.length);
    for (let i = 1; i < rs.length; i++) {
      const dt = (fr[i] - fr[i - 1]) / fps;
      // steps up to 0.25 s apart count (pose may run every few frames); faster than 8 m/s = keypoint glitch
      const v = dt > 0 && dt <= 0.25 ? Math.hypot(X[i] - X[i - 1], Y[i] - Y[i - 1]) / dt : 0;
      cum[i] = cum[i - 1] + (v < 8 ? v * dt : 0);
    }
    out.set(p, { frames: fr, cum });
  }
  return out;
}

/** index of the last element <= v in ascending array a (-1 if none) */
function lastLE(a, v) {
  let lo = 0, hi = a.length;
  while (lo < hi) { const m = (lo + hi) >> 1; if (a[m] <= v) lo = m + 1; else hi = m; }
  return lo - 1;
}

// ---------------------------------------------------------------- drawing helpers

function makeCanvas(w, h) {
  if (typeof OffscreenCanvas !== 'undefined') return new OffscreenCanvas(w, h);
  const c = document.createElement('canvas'); c.width = w; c.height = h; return c;
}

function rrect(ctx, x, y, w, h, r) {
  r = Math.max(0, Math.min(r, w / 2, h / 2));
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

function polyline(ctx, pts, closed = false) {
  ctx.beginPath();
  for (let i = 0; i < pts.length; i++) ctx[i ? 'lineTo' : 'moveTo'](pts[i][0], pts[i][1]);
  if (closed) ctx.closePath();
}

function fade(age, total, rise = 4, fall = 8) {
  if (age < rise) return age / rise;
  if (age > total - fall) return Math.max(0, (total - age) / fall);
  return 1;
}

const fmt = (v, d) => (v === null || v === undefined || Number.isNaN(v) ? '–' : Number(v).toFixed(d));
const signed = (v, d) => (v >= 0 ? '+' : '') + v.toFixed(d);

// ---------------------------------------------------------------- the renderer

export const LANDING_SHOW_S = 2.0;   // a landing is shown this long after its frame, fading out over the last part
const LANDING_FADE_S = 0.7;
const ZOOM = 1.15;                   // 3D view: ~15% closer than render.py's framing

/**
 * createRenderer({cam, fps, width, height, shots, report, landings, shuttleRows, poses, contacts?, players?, distance?,
 *                 layout?, panelPosition?})
 *   cam:           cameraFromCalib(calib)
 *   shots:         good flights (flights.json entries with good = true)
 *   report:        report.json (shots[], rallies[])
 *   landings:      [{frame, court: [X, Y], in}]
 *   shuttleRows:   column dict {frame, x, y, ...} or array of {frame, x, y}
 *   poses:         buildPoses(...) result
 *   contacts:      [{frame, contact: [X,Y,Z], px}]; default = the shots' starts (p0), as the pipeline does
 *   players:       player rows with X, Y (for the running distance), or `distance` = runningDistance(...) result
 *   layout:        'horizontal' (default): video | analysis panel side by side, panel height = video height.
 *                  'vertical': 9:16 portrait (TikTok): video full width, analysis area above or below it.
 *   panelPosition: 'below' (default) | 'above' (vertical layout only).
 * Returns {layout, panelWidth, panelHeight, compositeWidth, compositeHeight, videoRect: {x, y, w, h},
 *          panelRect: {x, y, w, h}, drawOverlay(ctx, f), drawPanel(ctx, f), drawComposite(ctx, f, src)}.
 * drawOverlay draws on a transparent video-sized canvas and does not clear it; drawPanel paints the whole
 * analysis area (panelWidth x panelHeight); drawComposite paints the whole composite canvas.
 */
/**
 * Where the head is, also when the face is not visible (players seen from behind: nose/eyes score low).
 * Nose; else the mean of eyes/ears; else above the shoulders along the hips -> shoulders direction.
 * k: 17 points ([x,y] or [X,Y,Z], null = missing). Returns {p, neck, r} or null.
 */
/** shoulder-centre to hip-centre length (NaN when not visible) */
export function torsoLen(k) {
  if (!(k[5] && k[6] && k[11] && k[12])) return NaN;
  return Math.hypot((k[5][0] + k[6][0] - k[11][0] - k[12][0]) / 2, (k[5][1] + k[6][1] - k[11][1] - k[12][1]) / 2);
}

/** A limb can look shorter (foreshortened), never much longer than the body allows: drop impossible bones. */
const BONE_MAX = { arm: 1.05, leg: 1.4, width: 1.25 };
export function plausibleBone(a, b, k, T) {
  if (!(T > 0)) return true;
  const L = Math.hypot(k[a][0] - k[b][0], k[a][1] - k[b][1]);
  const kind = a >= 11 || b >= 13 ? (a === 11 && b === 12 ? 'width' : 'leg') : (a === 5 && b === 6 ? 'width' : (b <= 10 ? 'arm' : 'leg'));
  return L <= BONE_MAX[kind] * T;
}

export function headOf(k, is3d) {
  const mid = (a, b) => (k[a] && k[b] ? k[a].map((v, i) => (v + k[b][i]) / 2) : k[a] || k[b] || null);
  const neck = mid(5, 6), hips = mid(11, 12);
  const sw = k[5] && k[6] ? Math.hypot(...k[5].map((v, i) => v - k[6][i])) : 0;
  let p = k[0];
  if (!p) {
    const face = [1, 2, 3, 4].filter((j) => k[j]);
    if (face.length) p = k[face[0]].map((_, i) => face.reduce((a, j) => a + k[j][i], 0) / face.length);
  }
  if (!p && neck) {
    if (hips) p = neck.map((v, i) => v + 0.42 * (v - hips[i]));
    else p = is3d ? [neck[0], neck[1], neck[2] + 0.25] : [neck[0], neck[1] - Math.max(sw, 10) * 0.8];
  }
  if (!p) return null;
  const torso = neck && hips ? Math.hypot(...neck.map((v, i) => v - hips[i])) : sw * 1.5;
  return { p, neck, r: Math.max(4, Math.min(0.2 * torso, 0.45 * sw || 0.2 * torso)) };
}

export function createRenderer(o) {
  const { cam, fps, width: w, height: h } = o;
  const layout = o.layout === 'vertical' ? 'vertical' : 'horizontal';
  const above = layout === 'vertical' && o.panelPosition === 'above';
  const s = h / 576;                                       // video overlay scale
  const I = (v) => Math.trunc(v);

  // ---- layout
  let pw, ph, sp, compW, compH;
  if (layout === 'horizontal') {
    pw = Math.round((0.5 * w) / 2) * 2; ph = h; sp = s;
    compW = w + pw; compH = h;
  } else {
    pw = w; compW = w;
    compH = Math.round((w * 16) / 9 / 2) * 2;
    if (compH - h < 0.6 * w) compH = Math.round((h + 0.6 * w) / 2) * 2;      // video already tall-ish
    ph = compH - h;
    sp = Math.min(pw / 512, ph / 560);                    // same proportions as the 512 px wide side panel
  }
  const videoRect = layout === 'horizontal' ? { x: 0, y: 0, w, h } : { x: 0, y: above ? ph : 0, w, h };
  const panelRect = layout === 'horizontal' ? { x: w, y: 0, w: pw, h: ph } : { x: 0, y: above ? 0 : h, w: pw, h: ph };
  const P = (v) => I(v * sp);                              // panel sizes
  const cardH = P(118), playerH = P(96);
  const h3d = layout === 'horizontal' ? Math.floor((ph * 0.56) / 2) * 2
    : Math.max(Math.floor(ph * 0.4), ph - cardH - playerH - P(8 + 10 + 12));

  const fz = (size, k) => Math.max(8, I(size * k));
  const fonts = (k) => ({
    small: `400 ${fz(13, k)}px ${FAMILY}`, body: `400 ${fz(15, k)}px ${FAMILY}`, label: `600 ${fz(14, k)}px ${FAMILY}`,
    title: `700 ${fz(17, k)}px ${FAMILY}`, big: `700 ${fz(34, k)}px ${FAMILY}`, tag: `700 ${fz(13, k)}px ${FAMILY}`,
  });
  const F = fonts(s), FP = fonts(sp);

  // ---- data
  const shots = o.shots || [];
  const paths = shots.map((sh) => positions(sh, fps));
  const fitLast = shots.map((sh) => sh.fit_last_frame);
  let maxF = 0;
  for (const [fr] of paths) if (fr.length) maxF = Math.max(maxF, fr.at(-1));
  const cover = new Int32Array(maxF + 2).fill(-1);
  paths.forEach(([fr], i) => { for (const f of fr) cover[f] = i; });
  const shotOf = (f) => (f >= 0 && f < cover.length ? cover[f] : -1);
  const pathPx = paths.map(([, Pp]) => cam.project(Pp));
  const pathNFit = paths.map(([fr], i) => lastLE(fr, fitLast[i]) + 1);

  const sr = Array.isArray(o.shuttleRows) ? o.shuttleRows : rowsFromColumns(o.shuttleRows || { frame: [] });
  let sMax = 0;
  for (const r of sr) sMax = Math.max(sMax, r.frame);
  const SX = new Float32Array(sMax + 1).fill(NaN), SY = new Float32Array(sMax + 1).fill(NaN);
  for (const r of sr) if (r.x != null && r.y != null) { SX[r.frame] = r.x; SY[r.frame] = r.y; }
  const shuttle = (f) => (f >= 0 && f <= sMax && !Number.isNaN(SX[f]) ? [SX[f], SY[f]] : null);

  const rshots = ((o.report && o.report.shots) || []).slice().sort((a, b) => a.frame - b.frame);
  const shotFrames = rshots.map((c) => c.frame);
  const rallyStart = ((o.report && o.report.rallies) || []).map((r) => Math.round(r.start_s * fps)).sort((a, b) => a - b);
  const contacts = (o.contacts || shots.map((sh) => ({ frame: sh.hit_frame, contact: sh.p0 })))
    .map((c) => ({ frame: c.frame, C: c.contact })).sort((a, b) => a.frame - b.frame);
  const contactFrames = contacts.map((c) => c.frame);
  const landings = (o.landings || []).slice().sort((a, b) => a.frame - b.frame);
  const landFrames = landings.map((e) => e.frame);
  const ring = (X, Y, r, n, z = 0) => Array.from({ length: n }, (_, i) => {
    const t = (2 * Math.PI * i) / (n - 1);
    return [X + r * Math.cos(t), Y + r * Math.sin(t), z];
  });
  const landPx = landings.map((e) => (cam.depth([...e.court, 0]) > 0.3 ? cam.project(ring(e.court[0], e.court[1], 0.25, 24)) : null));
  const poses = o.poses || new Map();
  const distance = o.distance || (o.players ? runningDistance(o.players, fps) : new Map());
  const nPlayers = poses.size || distance.size;

  /** landings shown at f with their opacity: [[index, alpha]] */
  function activeLandings(f) {
    const out = [], show = LANDING_SHOW_S * fps, fadeN = LANDING_FADE_S * fps;
    for (let i = lastLE(landFrames, f); i >= 0 && f - landings[i].frame < show; i--) {
      const age = f - landings[i].frame;
      out.push([i, Math.min(1, (show - age) / fadeN)]);
    }
    return out.reverse();
  }

  // ---- text
  const mcache = new Map();
  function measure(ctx, font, str) {
    const key = font + '|' + str;
    let m = mcache.get(key);
    if (!m) {
      ctx.font = font;
      const t = ctx.measureText(str);
      m = { w: t.width, asc: t.actualBoundingBoxAscent, desc: t.actualBoundingBoxDescent };
      mcache.set(key, m);
    }
    return m;
  }
  function text(ctx, str, x, y, font, color, align = 'left') {   // y = top of the text box (Pillow-like)
    ctx.font = font; ctx.fillStyle = color; ctx.textBaseline = 'top'; ctx.textAlign = align;
    ctx.fillText(str, x, y);
  }
  function pill(ctx, x, y, str, font, fill, fg, pad = [9, 4], r = null) {
    const m = measure(ctx, font, str);
    const w_ = m.w + 2 * pad[0], h_ = m.asc + m.desc + 2 * pad[1];
    ctx.fillStyle = fill; rrect(ctx, x, y, w_, h_, r !== null ? r : h_ / 2); ctx.fill();
    ctx.font = font; ctx.fillStyle = fg; ctx.textBaseline = 'alphabetic'; ctx.textAlign = 'left';
    ctx.fillText(str, x + pad[0], y + pad[1] + m.asc);
    return [w_, h_];
  }

  // ---- static court overlay (video)
  const courtLayer = makeCanvas(w, h);
  {
    const c = courtLayer.getContext('2d');
    c.lineCap = 'round'; c.lineJoin = 'round';
    const seg = (a, b, n = 40) => Array.from({ length: n }, (_, i) => a.map((v, k) => v + ((b[k] - v) * i) / (n - 1)));
    const pl = (pts, col, th) => {
      const vis = pts.filter((Q) => cam.depth(Q) > 0.3);
      if (vis.length < 2) return;
      c.strokeStyle = col; c.lineWidth = th; polyline(c, cam.project(vis)); c.stroke();
    };
    for (const [a, b] of courtLines()) pl(seg([...a, 0], [...b, 0]), 'rgb(235,245,250)', 2);
    pl(netTop(), '#FFFFFF', 2);
    pl(seg([0, 0, NET_BOTTOM], [W, 0, NET_BOTTOM]), 'rgb(200,200,200)', 1);
    for (const x of [0, W]) pl(seg([x, 0, 0], [x, 0, NET_POST], 2), '#FFB74D', 3);
  }

  // ---- 3D view (Court3D): fixed virtual camera, framed to fit the view area (pw x h3d)
  const view = (() => {
    const c = [W / 2, 0, 1.2];
    const yaw = Math.atan2(cam.pos[1], cam.pos[0] - W / 2) + (22 * Math.PI) / 180;
    const eye = [c[0] + 17.5 * Math.cos(yaw), c[1] + 17.5 * Math.sin(yaw), c[2] + 10];
    const nrm = (v) => { const l = Math.hypot(...v); return v.map((x) => x / l); };
    const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
    const fw = nrm(c.map((v, i) => v - eye[i]));
    const r = nrm(cross(fw, [0, 0, 1]));
    const R = [r, cross(fw, r), fw];
    const t = R.map((row) => -(row[0] * eye[0] + row[1] * eye[1] + row[2] * eye[2]));
    const norm = (Q) => {
      const x = R[0][0] * Q[0] + R[0][1] * Q[1] + R[0][2] * Q[2] + t[0];
      const y = R[1][0] * Q[0] + R[1][1] * Q[1] + R[1][2] * Q[2] + t[1];
      const z = R[2][0] * Q[0] + R[2][1] * Q[1] + R[2][2] * Q[2] + t[2];
      return [x / z, y / z];
    };
    // render.py: f = 0.8 * width for a 512 x 322 area. Target ZOOM x that (for the area's binding dimension),
    // but never so close that the court (with apron) leaves the width or a 6.5 m clear apex leaves the top.
    const ext = (pts) => {
      const q = pts.map(norm), xs = q.map((v) => v[0]), ys = q.map((v) => v[1]);
      return { x0: Math.min(...xs), x1: Math.max(...xs), y0: Math.min(...ys), y1: Math.max(...ys) };
    };
    const m = 2.2, apron = ext([[-m, -HALF - m, 0], [W + m, -HALF - m, 0], [W + m, HALF + m, 0], [-m, HALF + m, 0]]);
    const tall = ext([[-0.8, -HALF - 0.8, 0], [W + 0.8, -HALF - 0.8, 0], [W + 0.8, HALF + 0.8, 0], [-0.8, HALF + 0.8, 0],
      [0, -3, 6.5], [W, -3, 6.5], [0, 3, 6.5], [W, 3, 6.5]]);
    const f = Math.min(ZOOM * 0.8 * Math.min(pw, (h3d * 512) / 322), (0.97 * pw) / (apron.x1 - apron.x0),
      (0.92 * h3d) / (tall.y1 - tall.y0));
    const cx = pw / 2 - (f * (apron.x0 + apron.x1)) / 2;
    const cy = 0.53 * h3d - (f * (tall.y0 + tall.y1)) / 2;
    const p1 = (Q) => { const q = norm(Q); return [f * q[0] + cx, f * q[1] + cy]; };
    return { p1, p: (pts) => pts.map(p1) };
  })();
  const line3 = (ctx, pts, col, th, closed = false) => {
    ctx.strokeStyle = col; ctx.lineWidth = th; polyline(ctx, view.p(pts), closed); ctx.stroke();
  };
  const pathPanel = paths.map(([, Pp]) => view.p(Pp));
  const landPanel = landings.map((e) => ({ ring: view.p(ring(e.court[0], e.court[1], 0.22, 32, 0.01)), at: view.p1([...e.court, 0]) }));
  const k3 = sp;                                             // 3D mark sizes (render.py: fixed px at 576 p)

  // static panel: background gradient, 3D court, card frames
  const cx0 = P(12), cy0 = h3d + P(8), cw = pw - P(24);
  const gy = cy0 + cardH + P(10), cols = Math.max(1, nPlayers);
  const gw = Math.floor((cw - P(8) * (cols - 1)) / cols), gh = ph - gy - P(12);
  const panelBase = makeCanvas(pw, ph);
  {
    const c = panelBase.getContext('2d');
    c.lineCap = 'round'; c.lineJoin = 'round';
    let g = c.createLinearGradient(0, 0, 0, ph);
    g.addColorStop(0, BG_TOP); g.addColorStop(1, BG_BOTTOM);
    c.fillStyle = g; c.fillRect(0, 0, pw, ph);
    g = c.createLinearGradient(0, 0, 0, h3d);
    g.addColorStop(0, BG_TOP); g.addColorStop(1, BG_BOTTOM);
    c.fillStyle = g; c.fillRect(0, 0, pw, h3d);
    c.save(); c.beginPath(); c.rect(0, 0, pw, h3d); c.clip();
    const m = 2.2;
    c.fillStyle = '#1B3A2A';
    polyline(c, view.p([[-m, -HALF - m, 0], [W + m, -HALF - m, 0], [W + m, HALF + m, 0], [-m, HALF + m, 0]]), true); c.fill();
    c.fillStyle = '#1F6B47';
    polyline(c, view.p([[0, -HALF, 0], [W, -HALF, 0], [W, HALF, 0], [0, HALF, 0]]), true); c.fill();
    for (const [a, b] of courtLines()) line3(c, [[...a, 0], [...b, 0]], 'rgb(240,240,235)', k3);
    c.globalAlpha = 0.22; c.fillStyle = 'rgb(220,220,220)';
    polyline(c, view.p([[0, 0, NET_BOTTOM], [W, 0, NET_BOTTOM], [W, 0, NET_POST], [0, 0, NET_POST]]), true); c.fill();
    c.globalAlpha = 1;
    line3(c, netTop(), '#FFFFFF', k3);
    for (const x of [0, W]) line3(c, [[x, 0, 0], [x, 0, NET_POST]], '#FFB74D', 2 * k3);
    const Pc = cam.pos;                                             // the real camera, small
    line3(c, [[Pc[0], Pc[1], 0], Pc], 'rgb(130,120,110)', k3);
    const q = view.p1(Pc);
    c.fillStyle = '#79C0FF'; c.beginPath(); c.arc(q[0], q[1], 5 * k3, 0, 2 * Math.PI); c.fill();
    c.restore();
    text(c, 'SÂN 3D', P(14), P(12), FP.tag, MUTED);
    // cards
    c.fillStyle = CARD; rrect(c, cx0, cy0, cw, cardH, P(12)); c.fill();
    text(c, 'CÚ VỪA ĐÁNH', cx0 + P(14), cy0 + P(10), FP.tag, MUTED);
    for (let p = 0; p < cols; p++) {
      const x = cx0 + p * (gw + P(8));
      c.fillStyle = CARD; rrect(c, x, gy, gw, gh, P(10)); c.fill();
      c.fillStyle = pcol(p); rrect(c, x, gy, gw, P(4), P(2)); c.fill();
      text(c, `P${p + 1}`, x + P(10), gy + P(10), FP.title, pcol(p));
    }
  }

  // ---- per frame: video overlay (lines, skeletons + name tags, shuttle, projected flight, landing rings)
  const th = Math.max(2, I(2.5 * s));

  function drawSkeleton(ctx, k2, col) {
    const hd = headOf(k2, false);
    ctx.beginPath();
    const T = torsoLen(k2);
    for (const [a, b] of BONES) {
      if (!a || !b || !k2[a] || !k2[b] || !plausibleBone(a, b, k2, T)) continue;
      ctx.moveTo(k2[a][0], k2[a][1]); ctx.lineTo(k2[b][0], k2[b][1]);
    }
    if (hd && hd.neck) { ctx.moveTo(hd.neck[0], hd.neck[1]); ctx.lineTo(hd.p[0], hd.p[1]); }
    ctx.strokeStyle = 'rgb(20,20,20)'; ctx.lineWidth = th + 3; ctx.stroke();
    ctx.strokeStyle = col; ctx.lineWidth = th; ctx.stroke();
    if (hd) {                                            // the head is always drawn, seen from the back too
      ctx.beginPath(); ctx.arc(hd.p[0], hd.p[1], hd.r, 0, 2 * Math.PI);
      ctx.strokeStyle = 'rgb(20,20,20)'; ctx.lineWidth = th + 3; ctx.stroke();
      ctx.strokeStyle = col; ctx.lineWidth = th; ctx.stroke();
    }
    ctx.fillStyle = '#FFFFFF'; ctx.beginPath();
    const r = Math.max(2, th - 1);
    for (let j = 5; j < 17; j++) if (k2[j]) { ctx.moveTo(k2[j][0] + r, k2[j][1]); ctx.arc(k2[j][0], k2[j][1], r, 0, 2 * Math.PI); }
    ctx.fill();
  }

  function drawOverlay(ctx, f, people = posesAt(poses, f)) {
    ctx.save();
    ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    ctx.globalAlpha = 0.55; ctx.drawImage(courtLayer, 0, 0); ctx.globalAlpha = 1;

    // fitted flight projected back (measured part faint, prediction dotted)
    const si = shotOf(f);
    if (si >= 0) {
      const q = pathPx[si], nFit = pathNFit[si];
      if (nFit > 1) { ctx.globalAlpha = 0.5; ctx.strokeStyle = PATH_HEX; ctx.lineWidth = 2; polyline(ctx, q.slice(0, nFit)); ctx.stroke(); ctx.globalAlpha = 1; }
      ctx.fillStyle = PATH_HEX; ctx.beginPath();
      for (let a = Math.max(nFit - 1, 0); a < q.length - 1; a += 3) { ctx.moveTo(q[a][0] + 2, q[a][1]); ctx.arc(q[a][0], q[a][1], 2, 0, 2 * Math.PI); }
      ctx.fill();
    }

    for (const { player, k2 } of people) drawSkeleton(ctx, k2, pcol(player));

    const trail = [];
    for (let k = f - TRAIL; k <= f; k++) { const q = shuttle(k); if (q) trail.push(q); }
    if (trail.length > 1) {
      ctx.strokeStyle = SHUTTLE_HEX;
      polyline(ctx, trail);
      ctx.globalAlpha = 0.35; ctx.lineWidth = I(9 * s); ctx.stroke();
      ctx.globalAlpha = 1; ctx.lineWidth = Math.max(2, I(2 * s)); ctx.stroke();
    }
    const cur = shuttle(f);
    if (cur) {
      ctx.strokeStyle = SHUTTLE_HEX; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(cur[0], cur[1], I(9 * s), 0, 2 * Math.PI); ctx.stroke();
      ctx.fillStyle = '#FFFFFF'; ctx.beginPath(); ctx.arc(cur[0], cur[1], I(4 * s), 0, 2 * Math.PI); ctx.fill();
    }

    for (const [i, a] of activeLandings(f)) {
      if (!landPx[i]) continue;
      ctx.globalAlpha = a; ctx.strokeStyle = landings[i].in ? IN_HEX : OUT_HEX; ctx.lineWidth = Math.max(2, I(2 * s));
      polyline(ctx, landPx[i], true); ctx.stroke();
    }
    ctx.globalAlpha = 1;

    for (const { player, k2 } of people) {                       // small name tags, above the head
      const hd = headOf(k2, false);
      if (!hd) continue;
      const t = `P${player + 1}`, m = measure(ctx, F.tag, t);
      pill(ctx, I(hd.p[0] - m.w / 2 - 8), I(hd.p[1] - hd.r - 26 * s), t, F.tag, rgba(pcol(player), 0.9), INK);
    }
    ctx.restore();
  }

  // ---- per frame: analysis panel
  function drawPanel(ctx, f, people = posesAt(poses, f)) {
    ctx.save();
    ctx.drawImage(panelBase, 0, 0);
    ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    ctx.beginPath(); ctx.rect(0, 0, pw, h3d); ctx.save(); ctx.clip();

    ctx.globalAlpha = 0.6; ctx.fillStyle = 'rgb(14,20,10)'; ctx.beginPath();       // floor shadows
    for (const { k3: K } of people) {
      const ft = [K[15], K[16]].filter(Boolean);
      if (!ft.length) continue;
      const q = view.p1([ft.reduce((a, v) => a + v[0], 0) / ft.length, ft.reduce((a, v) => a + v[1], 0) / ft.length, 0]);
      ctx.moveTo(q[0] + 14 * k3, q[1]); ctx.ellipse(q[0], q[1], 14 * k3, 5 * k3, 0, 0, 2 * Math.PI);
    }
    ctx.fill(); ctx.globalAlpha = 1;
    for (const { player, k2, k3: K } of people) {
      const col = pcol(player);
      ctx.strokeStyle = col; ctx.lineWidth = 2 * k3; ctx.beginPath();
      const q = K.map((Q) => (Q ? view.p1(Q) : null));
      const T = torsoLen(k2);
      for (const [a, b] of BONES) {
        if (!a || !b || !q[a] || !q[b] || (k2[a] && k2[b] && !plausibleBone(a, b, k2, T))) continue;
        ctx.moveTo(q[a][0], q[a][1]); ctx.lineTo(q[b][0], q[b][1]);
      }
      const hd = headOf(K, true);
      if (hd && hd.neck) { const n = view.p1(hd.neck), hp = view.p1(hd.p); ctx.moveTo(n[0], n[1]); ctx.lineTo(hp[0], hp[1]); }
      ctx.stroke();
      if (hd) { const hp = view.p1(hd.p); ctx.fillStyle = col; ctx.beginPath(); ctx.arc(hp[0], hp[1], 5 * k3, 0, 2 * Math.PI); ctx.fill(); }
    }
    for (let i = lastLE(contactFrames, f); i >= 0 && f - contacts[i].frame < HIT_SHOW; i--) {    // live contacts
      const C = contacts[i].C;
      ctx.globalAlpha = fade(f - contacts[i].frame, HIT_SHOW);
      line3(ctx, [[C[0], C[1], 0], C], GOLD, k3);
      const q = view.p1(C);
      ctx.fillStyle = GOLD; ctx.beginPath(); ctx.arc(q[0], q[1], 6 * k3, 0, 2 * Math.PI); ctx.fill();
    }
    ctx.globalAlpha = 1;
    let ball = null;
    const si = shotOf(f);
    if (si >= 0) {
      const [fr, Pp] = paths[si], Q = pathPanel[si];
      const k = lastLE(fr, f) + 1;
      ctx.strokeStyle = PATH_HEX;
      ctx.globalAlpha = 0.35; ctx.lineWidth = k3; polyline(ctx, Q); ctx.stroke();
      if (k >= 2) {
        polyline(ctx, Q.slice(0, k));
        ctx.globalAlpha = 0.3; ctx.lineWidth = 6 * k3; ctx.stroke();
        ctx.globalAlpha = 1; ctx.lineWidth = 2 * k3; ctx.stroke();
      }
      ctx.globalAlpha = 1;
      const cur = Pp[Math.max(k - 1, 0)];
      line3(ctx, [[cur[0], cur[1], 0], cur], 'rgb(150,140,130)', k3);
      const q0 = view.p1([cur[0], cur[1], 0]);
      ctx.fillStyle = 'rgb(50,50,40)'; ctx.beginPath(); ctx.ellipse(q0[0], q0[1], 6 * k3, 2 * k3, 0, 0, 2 * Math.PI); ctx.fill();
      const q = Q[Math.max(k - 1, 0)];
      ctx.fillStyle = '#FFFFFF'; ctx.beginPath(); ctx.arc(q[0], q[1], 7 * k3, 0, 2 * Math.PI); ctx.fill();
      ctx.strokeStyle = SHUTTLE_HEX; ctx.lineWidth = 2 * k3; ctx.beginPath(); ctx.arc(q[0], q[1], 9 * k3, 0, 2 * Math.PI); ctx.stroke();
      ball = [q, cur[2]];
    }
    const act = activeLandings(f);
    for (const [i, a] of act) {
      ctx.globalAlpha = a; ctx.strokeStyle = landings[i].in ? IN_HEX : OUT_HEX; ctx.lineWidth = 2 * k3;
      polyline(ctx, landPanel[i].ring, true); ctx.stroke();
    }
    ctx.globalAlpha = 1;
    ctx.restore();                                                  // end clip

    // 3D labels
    if (ball) pill(ctx, I(ball[0][0] + 12 * sp), I(ball[0][1] - 12 * sp), `${ball[1].toFixed(1)} m`, FP.small, 'rgba(255,255,255,0.88)', INK);
    for (const [i, a] of act) {
      const e = landings[i], [mx, my] = landPanel[i].at;
      ctx.globalAlpha = a;
      pill(ctx, I(mx + 10 * sp), I(my - 10 * sp), e.in ? 'IN' : 'OUT', FP.tag, rgba(e.in ? IN_HEX : OUT_HEX, 0.92), INK);
    }
    ctx.globalAlpha = 1;

    // status chips (top right of the 3D area): rally / shot count and time
    const ri = rallyStart.length ? lastLE(rallyStart, f) + 1 : 0;
    let nShot = 0;
    if (ri) for (const c of rshots) { if (c.frame > f) break; if (c.rally === ri) nShot++; }
    const status = ri ? `PHA ${ri}  ·  CÚ ${nShot}` : 'KHỞI ĐỘNG';
    const sec = f / fps;
    const tt = `${String(Math.floor(sec / 60)).padStart(2, '0')}:${(sec % 60).toFixed(1).padStart(4, '0')}`;
    const mS = measure(ctx, FP.label, status), mT = measure(ctx, FP.small, tt);
    const xr = pw - P(12), yTop = P(10);
    const [wt] = [mT.w + 18];
    pill(ctx, xr - wt, yTop + (mS.asc + mS.desc - mT.asc - mT.desc) / 2, tt, FP.small, 'rgba(13,17,23,0.63)', MUTED, [9, 4], P(6));
    pill(ctx, xr - wt - P(6) - (mS.w + 18), yTop, status, FP.label, 'rgba(13,17,23,0.78)', TEXT, [9, 4], P(8));

    // last shot card
    const k = lastLE(shotFrames, f);
    if (k >= 0) {
      const c = rshots[k], p = (c.player || 1) - 1;
      pill(ctx, cx0 + P(14), cy0 + P(34), `P${p + 1}`, FP.tag, pcol(p), INK);
      text(ctx, (TYPES_VI[c.type] || c.type_vi || c.type) + (c.jump ? ' · bật nhảy' : ''), cx0 + P(54), cy0 + P(32), FP.title, TEXT);
      const unsure = c.speed_reliable === false;
      const spd = (unsure ? '~' : '') + fmt(c.speed_kmh, 0);
      text(ctx, spd, cx0 + P(14), cy0 + P(58), FP.big, unsure ? MUTED : TEXT);
      const sd = c.speed_sd_kmh;
      text(ctx, 'km/h' + (sd != null ? `  ± ${sd.toFixed(0)}` : ''), cx0 + P(20) + measure(ctx, FP.big, spd).w, cy0 + P(76), FP.small, MUTED);
      const facts = [`chạm ${fmt(c.contact_height_m, 2)} m`, `đỉnh ${fmt(c.apex_m, 1)} m`, c.direction === 'cross' ? 'chéo sân' : 'thẳng'];
      if (c.net_clearance_m != null) facts.splice(2, 0, `qua lưới ${signed(c.net_clearance_m, 2)} m`);
      const fx = cx0 + I(Math.max(150 * sp, cw * 0.45));
      facts.slice(0, 4).forEach((t, i) => text(ctx, t, fx, cy0 + P(34 + 19 * i), FP.small, TEXT));
    } else {
      text(ctx, 'Chưa có cú đánh', cx0 + P(14), cy0 + P(40), FP.body, MUTED);
    }

    // player cards
    for (let p = 0; p < cols; p++) {
      const x = cx0 + p * (gw + P(8));
      let dm = 0;
      const d = distance.get(p);
      if (d) { const j = lastLE(d.frames, f); dm = j >= 0 ? d.cum[j] : 0; }
      let n = 0;
      for (const c of rshots) { if (c.frame > f) break; if ((c.player || 0) - 1 === p) n++; }
      text(ctx, `${dm.toFixed(0)} m`, x + P(10), gy + P(36), FP.label, TEXT);
      text(ctx, `${n} cú`, x + P(10), gy + P(56), FP.small, MUTED);
    }
    ctx.restore();
  }

  /** Video frame (anything drawImage takes, or ImageData) + overlay + panel on a compositeWidth x compositeHeight canvas. */
  function drawComposite(ctx, f, src) {
    const people = posesAt(poses, f);
    const { x: vx, y: vy } = videoRect;
    if (src && typeof ImageData !== 'undefined' && src instanceof ImageData) ctx.putImageData(src, vx, vy);
    else if (src) ctx.drawImage(src, vx, vy, w, h);
    else { ctx.fillStyle = '#000'; ctx.fillRect(vx, vy, w, h); }
    ctx.save(); ctx.beginPath(); ctx.rect(vx, vy, w, h); ctx.clip(); ctx.translate(vx, vy);
    drawOverlay(ctx, f, people);
    ctx.restore();
    ctx.save(); ctx.translate(panelRect.x, panelRect.y);
    drawPanel(ctx, f, people);
    ctx.restore();
  }

  return {
    layout, panelWidth: pw, panelHeight: ph, compositeWidth: compW, compositeHeight: compH,
    videoRect, panelRect, drawOverlay, drawPanel, drawComposite,
  };
}
