// Match analytics from the reconstructed 3D scene, ported from analysis/badminton/analytics.py.
// Pure ES module: runs in a Web Worker and in Node (no DOM, no Node APIs).
//
// Per shot: type (serve / smash / clear / drop / lift / net / drive / push), launch and mean speed, apex,
// net clearance, direction, zones, stroke height, forehand / backhand (2D skeleton), jump.
// Per player: movement stats, heatmap, posture at the opponent's contact, reaction and recovery times.
// Rallies: split at landings and at > 3 s gaps.
import { simulate, shotTime } from './physics.js';
import { HALF, NET_CENTRE, W } from './camera.js';

export const SHORT = 1.98;
const NOSE = 0, L_SH = 5, R_SH = 6, L_WR = 9, R_WR = 10, L_HIP = 11, R_HIP = 12, L_KNEE = 13, R_KNEE = 14, L_ANK = 15, R_ANK = 16;
export const RALLY_GAP_S = 3.0;
export const TYPES_VI = {
  serve: 'giao cầu', smash: 'đập', clear: 'phông cao', drop: 'bỏ nhỏ (trên cao)',
  lift: 'lốp', net: 'cầu lưới', drive: 'tạt', push: 'đẩy / chặn',
};

export const zone = (yAbs) => (yAbs < SHORT + 0.3 ? 'front' : yAbs < HALF - 2.0 ? 'mid' : 'back');

// ---------------------------------------------------------------- numeric helpers (Python / numpy semantics)

/** Python round(x, n): correctly rounded on the exact binary value, ties to even. */
export function pyRound(x, n = 0) {
  if (x === null || x === undefined || !Number.isFinite(x)) return x;
  const s = Math.abs(x).toFixed(100);                     // exact decimal expansion of the double
  const [ip, frac] = s.split('.');
  const rest = frac.slice(n);
  if (rest[0] === '5' && /^50*$/.test(rest)) {          // exact tie: Python picks the even neighbour
    const kept = ip + frac.slice(0, n);
    const lo = Number(n ? `${ip}.${frac.slice(0, n)}` : ip);
    const even = Number(kept.at(-1)) % 2 === 0 ? lo : Number((lo + 10 ** -n).toFixed(n));
    return x < 0 ? -even : even;
  }
  return Number(x.toFixed(n));                            // toFixed: exact value, nearest (ties excluded above)
}

/** numpy.round (multiply, round half to even, divide) — used for the heatmap like Python. */
function npRound(x, n) {
  const m = 10 ** n, y = x * m, f = Math.floor(y), d = y - f;
  const r = d > 0.5 ? f + 1 : d < 0.5 ? f : (f % 2 === 0 ? f : f + 1);
  return r / m;
}

const sortNum = (a) => Float64Array.from(a).sort();

/** numpy.percentile / pandas.quantile with linear interpolation (NaNs dropped as pandas does). */
export function quantile(values, q) {
  const v = sortNum(values.filter((x) => !Number.isNaN(x)));
  if (!v.length) return NaN;
  const pos = q * (v.length - 1), lo = Math.floor(pos), hi = Math.min(lo + 1, v.length - 1), g = pos - lo;
  return v[lo] + (v[hi] - v[lo]) * g;
}
export const median = (values) => quantile(values, 0.5);
const mean = (a) => (a.length ? a.reduce((s, x) => s + x, 0) / a.length : NaN);

/** pandas Series.mode()[0]: most frequent value, smallest on ties. */
function mode(values) {
  const c = new Map();
  for (const v of values) c.set(v, (c.get(v) || 0) + 1);
  let best, bn = -1;
  for (const [v, n] of c) if (n > bn || (n === bn && v < best)) { best = v; bn = n; }
  return best;
}

/** pandas value_counts().to_dict(): count descending. Ties: first appearance (pandas' tie order is not
 *  stable across numpy builds, so key order may differ from Python on ties; the counts are the same). */
function valueCounts(values) {
  const c = new Map();
  for (const v of values) c.set(v, (c.get(v) || 0) + 1);
  const out = {};
  for (const [k, n] of [...c].sort((a, b) => b[1] - a[1])) out[k] = n;   // Array sort is stable
  return out;
}

/** pandas rolling(w, center=True, min_periods=1) median / mean over rows. */
function rollingMedian(a, w) {
  const h = Math.floor(w / 2), n = a.length, out = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const win = Array.from(a.subarray(Math.max(0, i - h), Math.min(n, i + w - h))).sort((x, y) => x - y);
    const m = win.length;
    out[i] = m % 2 ? win[(m - 1) / 2] : (win[m / 2 - 1] + win[m / 2]) / 2;
  }
  return out;
}
function rollingMean(a, w) {
  const h = Math.floor(w / 2), n = a.length, out = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const lo = Math.max(0, i - h), hi = Math.min(n, i + w - h);
    let s = 0;
    for (let j = lo; j < hi; j++) s += a[j];
    out[i] = s / (hi - lo);
  }
  return out;
}

// ---------------------------------------------------------------- input normalisation

/** Accept players as an array of row objects, or as a column dict (players.json). */
export function playerRows(players) {
  if (Array.isArray(players)) return players;
  const cols = Object.keys(players), n = players[cols[0]].length, rows = new Array(n);
  for (let i = 0; i < n; i++) {
    const r = {};
    for (const c of cols) r[c] = players[c][i];
    rows[i] = r;
  }
  return rows;
}

// ---------------------------------------------------------------- players: movement

/**
 * Per player: smoothed floor positions and speeds (gaps not bridged), like analytics.player_tracks.
 * Returns {[player]: track} (numeric keys, ascending), each track a column set sorted by frame, unique frames:
 *   { frame: Int32Array, X: Float64Array, Y: Float64Array, speed: Float64Array (m/s, 0 across gaps >= 0.2 s),
 *     side: string[], row: Int32Array (index into the players rows / k3d) }
 * Look up a frame with trackIndex(track, frame) (-1 if absent); frame ranges with trackRange.
 */
export function playerTracks(players, fps) {
  const rows = playerRows(players);
  const by = new Map();
  rows.forEach((r, i) => {
    if (!(r.player >= 0)) return;
    if (!by.has(r.player)) by.set(r.player, []);
    by.get(r.player).push(i);
  });
  const out = {};
  for (const p of [...by.keys()].sort((a, b) => a - b)) {
    // sort by frame (stable; pandas' quicksort is not, which only matters for duplicate frames), keep first
    const idx = by.get(p).sort((a, b) => rows[a].frame - rows[b].frame)
      .filter((i, k, arr) => k === 0 || rows[i].frame !== rows[arr[k - 1]].frame);
    const n = idx.length;
    const frame = Int32Array.from(idx, (i) => rows[i].frame);
    // median then mean filter: foot keypoints jitter a few cm, occasionally jump
    const X = rollingMean(rollingMedian(Float64Array.from(idx, (i) => rows[i].X), 5), 7);
    const Y = rollingMean(rollingMedian(Float64Array.from(idx, (i) => rows[i].Y), 5), 7);
    const speed = new Float64Array(n);
    for (let k = 1; k < n; k++) {
      const dt = (frame[k] - frame[k - 1]) / fps;
      speed[k] = dt > 0 && dt <= 0.25 ? Math.hypot(X[k] - X[k - 1], Y[k] - Y[k - 1]) / Math.max(dt, 1e-6) : 0;
    }
    out[p] = { frame, X, Y, speed, side: idx.map((i) => rows[i].side), row: Int32Array.from(idx) };
  }
  return out;
}

/** Position of `f` in track.frame, or -1. */
export function trackIndex(t, f) {
  let lo = 0, hi = t.frame.length - 1;
  while (lo <= hi) {
    const m = (lo + hi) >> 1, v = t.frame[m];
    if (v === f) return m;
    if (v < f) lo = m + 1; else hi = m - 1;
  }
  return -1;
}
/** [start, end) positions of frames in [a, b] (inclusive, like DataFrame.loc[a:b]). */
export function trackRange(t, a, b) {
  const lb = (x) => { let lo = 0, hi = t.frame.length; while (lo < hi) { const m = (lo + hi) >> 1; if (t.frame[m] < x) lo = m + 1; else hi = m; } return lo; };
  return [lb(a), lb(b + 1)];
}

export function movementStats(t, fps) {
  const n = t.frame.length;
  let dist = 0;
  const moving = [];
  for (let k = 0; k < n; k++) {
    if (!(t.speed[k] < 8.0)) continue;                   // faster than any human: a foot-keypoint glitch
    moving.push(t.speed[k]);
    if (k > 0) dist += (t.speed[k] * (t.frame[k] - t.frame[k - 1])) / fps;   // speed is 0 across gaps > 0.25 s
  }
  const fast = moving.filter((v) => v > 0.3);
  const zc = { front: 0, mid: 0, back: 0 };
  for (let k = 0; k < n; k++) zc[zone(Math.abs(t.Y[k]))]++;
  return {
    distance_m: pyRound(dist, 1),
    seen_s: pyRound(n / fps, 1),
    mean_speed_ms: fast.length ? pyRound(mean(fast), 2) : 0.0,
    top_speed_ms: moving.length ? pyRound(quantile(moving, 0.99), 2) : 0.0,
    zones_pct: Object.fromEntries(['front', 'mid', 'back'].map((k) => [k, pyRound((100 * zc[k]) / n, 1)])),
    base_position: [pyRound(median(Array.from(t.X)), 2), pyRound(median(Array.from(t.Y)), 2)],
  };
}

/** numpy.histogram2d over the court (+1 m / +2 m margins), normalised, rounded to 4 decimals. */
export function heatmap(t, cell = 0.5) {
  const nx = Math.ceil((W + 2) / cell), ny = Math.ceil((2 * HALF + 4) / cell);
  const ex = Array.from({ length: nx + 1 }, (_, i) => -1 + (i * (W + 2)) / nx);       // np.linspace edges
  const ey = Array.from({ length: ny + 1 }, (_, i) => -HALF - 2 + (i * (2 * HALF + 4)) / ny);
  ex[nx] = W + 1; ey[ny] = HALF + 2;
  const bin = (e, v) => {                               // searchsorted(side='right') - 1, right edge inclusive
    const n = e.length - 1;
    if (v < e[0] || v > e[n]) return -1;
    if (v === e[n]) return n - 1;
    let lo = 0, hi = e.length;
    while (lo < hi) { const m = (lo + hi) >> 1; if (e[m] <= v) lo = m + 1; else hi = m; }
    return lo - 1;
  };
  const H = Array.from({ length: nx }, () => new Array(ny).fill(0));
  let total = 0;
  for (let k = 0; k < t.frame.length; k++) {
    const i = bin(ex, t.X[k]), j = bin(ey, t.Y[k]);
    if (i >= 0 && j >= 0) { H[i][j]++; total++; }
  }
  const d = Math.max(total, 1);
  return H.map((r) => r.map((v) => npRound(v / d, 4)));
}

// ---------------------------------------------------------------- players: posture

const sub2 = (a, b) => [a[0] - b[0], a[1] - b[1]];
function angle(a, b, c) {
  const u = sub2(a, b), v = sub2(c, b);
  const cos = (u[0] * v[0] + u[1] * v[1]) / (Math.hypot(u[0], u[1]) * Math.hypot(v[0], v[1]) + 1e-9);
  return (Math.acos(Math.min(1, Math.max(-1, cos))) * 180) / Math.PI;
}

/** Stance width (m), knee angle (deg, 180 = straight; NaN if unseen), hip height (m) of one detection. */
export function posture(row, rows, k3d, kpts, scores) {
  const k = k3d[row], det = rows[row].det, k2 = kpts[det], s2 = scores[det];
  const width = Math.hypot(k[L_ANK][0] - k[R_ANK][0], k[L_ANK][1] - k[R_ANK][1]);
  const knees = [[L_HIP, L_KNEE, L_ANK], [R_HIP, R_KNEE, R_ANK]]
    .filter(([h, kn, a]) => Math.min(s2[h], s2[kn], s2[a]) > 0.3)
    .map(([h, kn, a]) => angle(k2[h], k2[kn], k2[a]));
  return [width, knees.length ? mean(knees) : NaN, (k[L_HIP][2] + k[R_HIP][2]) / 2];
}

// ---------------------------------------------------------------- shots

/** Was the player off the floor at frame f? Ankles AND hips higher on the image than 0.6-0.25 s earlier
 *  by > 7% of the body's pixel height. */
export function jumped(t, f, rows, kpts, scores, fps) {
  const pts = (fr) => {
    const i = trackIndex(t, fr);
    if (i < 0) return null;
    const det = rows[t.row[i]].det, k = kpts[det], sc = scores[det];
    if (Math.min(sc[L_ANK], sc[R_ANK], sc[L_HIP], sc[R_HIP], sc[NOSE]) < 0.3) return null;
    const ank = (k[L_ANK][1] + k[R_ANK][1]) / 2;
    return [ank, (k[L_HIP][1] + k[R_HIP][1]) / 2, Math.abs(ank - k[NOSE][1])];
  };
  const now = pts(f);
  const before = [];
  for (let fr = f - Math.trunc(0.6 * fps); fr < f - Math.trunc(0.25 * fps); fr++) {
    const b = pts(fr);
    if (b) before.push(b);
  }
  if (!now || before.length < 3) return false;
  const [ank0, hip0, body] = [0, 1, 2].map((j) => median(before.map((b) => b[j])));
  return ank0 - now[0] > 0.07 * body && hip0 - now[1] > 0.07 * body;
}

export function classify(s, firstOfRally, fps) {
  const p0 = s.p0, v0 = s.v0;
  const vn = Math.hypot(v0[0], v0[1], v0[2]);
  const speed = vn * 3.6;
  const elev = (Math.asin(v0[2] / Math.max(vn, 1e-6)) * 180) / Math.PI;
  const T = Math.max(shotTime(s, [s.end_frame], fps)[0], 1 / fps);
  const step = T / 59;                                    // np.linspace(0, T, 60)
  const t = Array.from({ length: 60 }, (_, i) => i * step);
  t[59] = T;
  const P = simulate(p0, v0, t);
  const end = s.landing ? [s.landing.court[0], s.landing.court[1], 0.0] : P[P.length - 1];
  let apex = -Infinity;
  for (const q of P) apex = Math.max(apex, q[2]);
  let net = null;
  for (let j = 0; j < P.length - 1; j++) {
    if (Math.sign(P[j + 1][1]) !== Math.sign(P[j][1])) {
      const a = P[j][1] / (P[j][1] - P[j + 1][1]);
      net = P[j][2] + a * (P[j + 1][2] - P[j][2]) - NET_CENTRE;
      break;
    }
  }
  const hz = Math.hypot(v0[0], v0[1]);
  const ang = hz > 0.5 ? (Math.atan2(Math.abs(v0[0]), Math.max(Math.abs(v0[1]), 1e-6)) * 180) / Math.PI : 0.0;
  let sumStep = 0;
  for (let j = 0; j < P.length - 1; j++) sumStep += Math.hypot(P[j + 1][0] - P[j][0], P[j + 1][1] - P[j][1], P[j + 1][2] - P[j][2]);
  const meanSpeed = (sumStep / (P.length - 1) / (t[1] - t[0])) * 3.6;
  const z0 = p0[2], y0 = Math.abs(p0[1]), yend = Math.abs(end[1]);
  const rise = apex - z0;                                 // how much the shuttle climbs after the contact
  const to = zone(yend);
  let kind;
  if (firstOfRally) kind = 'serve';
  else if (z0 >= 1.9 && speed >= 110 && elev < 5) kind = 'smash';
  else if (apex >= 3.0 && to === 'back') kind = z0 >= 1.6 ? 'clear' : 'lift';
  else if (z0 < 1.3 && elev > 15 && rise > 0.6 && (to !== 'front' || apex >= 2.8)) kind = 'lift';
  else if (to === 'front' && z0 < 1.8 && speed < 60 && apex < 2.6) kind = y0 < SHORT + 1.0 ? 'net' : 'push';
  else if (z0 >= 1.6 && rise < 0.6 && (to === 'front' || to === 'mid') && speed < 110) kind = 'drop';
  else if (rise < 0.7 && speed >= 50 && z0 >= 0.6 && z0 <= 2.2) kind = 'drive';
  else kind = 'push';
  return {
    type: kind, type_vi: TYPES_VI[kind], speed_kmh: pyRound(speed, 1),
    mean_speed_kmh: pyRound(meanSpeed, 1), launch_angle_deg: pyRound(elev, 1),
    contact_height_m: pyRound(z0, 2), apex_m: pyRound(apex, 2),
    net_clearance_m: net === null ? null : pyRound(net, 2),
    flight_s: pyRound(T, 2), direction: ang > 15 ? 'cross' : 'straight',
    to_zone: zone(yend), end_point: [pyRound(end[0], 2), pyRound(end[1], 2)],
  };
}

/** forehand / backhand / centre from the 2D skeleton at the contact (hitting wrist projected on the
 *  hitter's left -> right shoulder axis). null when not measurable. */
export function strokeSide(k2, s2, hand) {
  if ((hand !== 'L' && hand !== 'R') || Math.min(s2[L_SH], s2[R_SH]) < 0.3) return null;
  const wr = hand === 'L' ? L_WR : R_WR;
  if (s2[wr] < 0.3) return null;
  const a = k2[L_SH], ab = sub2(k2[R_SH], a);
  const ab2 = ab[0] * ab[0] + ab[1] * ab[1];
  if (ab2 < 4) return null;                             // shoulders overlap: side-on to the camera
  const w = sub2(k2[wr], a);
  const u = (w[0] * ab[0] + w[1] * ab[1]) / ab2;        // 0 = left shoulder, 1 = right shoulder
  const own = hand === 'R' ? u : 1 - u;
  return own > 0.65 ? 'forehand' : own < 0.25 ? 'backhand' : 'centre';
}

// ---------------------------------------------------------------- main

const valid = (p) => p !== null && p !== undefined && p >= 0;

/**
 * analyse({shots, hits, players, k3d, kpts, scores, landings, fps}) -> report, same keys as Python's
 * analytics.analyse(): {players: {P1: {...}}, shots: [...], rallies: [...], summary}.
 *   shots: flights.json; players: array of row objects (or the column dict); k3d: [row][17][3];
 *   kpts: [det][17][2]; scores: [det][17]; landings: landings.json.
 * `hits` is accepted for signature parity (the Python ignores it too).
 */
export function analyse({ shots, hits, players, k3d, kpts, scores, landings, fps }) { // eslint-disable-line no-unused-vars
  const rows = playerRows(players);
  // < 10 km/h is not a stroke (a shuttle tossed to the server, a degenerate fit)
  const good = shots.filter((s) => s.good && s.speed_kmh >= 10).sort((a, b) => a.hit_frame - b.hit_frame);
  const floorFrames = landings.map((e) => e.frame).sort((a, b) => a - b);
  const tracks = playerTracks(rows, fps);
  const ids = Object.keys(tracks).map(Number);
  const height = {};
  for (const p of ids) height[p] = quantile(rows.filter((r) => r.player === p).map((r) => r.nose_z), 0.9) + 0.12;

  const who = (frame, side, near) => {
    let best = null, bd = 1e9;
    for (const p of ids) {
      const t = tracks[p], i = trackIndex(t, frame);
      if (i < 0 || t.side[i] !== side) continue;
      const d = near ? Math.hypot(t.X[i] - near[0], t.Y[i] - near[1]) : 0;
      if (d < bd) { best = p; bd = d; }
    }
    return best;
  };
  const sameTrack = (s) => {
    if (!valid(s.pid ?? -1)) return null;
    const near = rows.filter((r) => r.pid === s.pid && r.player >= 0 && Math.abs(r.frame - s.hit_frame) <= 15);
    return near.length ? mode(near.map((r) => r.player)) : null;
  };
  const detAt = (p, f) => {
    const t = tracks[p];
    if (!t) return -1;
    const i = trackIndex(t, f);
    return i < 0 ? -1 : rows[t.row[i]].det;
  };

  // racket hand: at overhead contacts the racket arm is the raised one (higher wrist on the image)
  const hand = {};
  for (const s of shots) {
    const p = s.player ?? -1;
    if (!s.good || !valid(p) || s.p0[2] < 1.8 || !tracks[p]) continue;
    const det = detAt(p, s.hit_frame);
    if (det < 0) continue;
    const k2 = kpts[det], s2 = scores[det];
    if (Math.min(s2[L_WR], s2[R_WR]) > 0.3 && Math.abs(k2[L_WR][1] - k2[R_WR][1]) > 15) {
      (hand[p] ||= []).push(k2[L_WR][1] < k2[R_WR][1] ? 'L' : 'R');
    }
  }
  // Python: max(set(v), key=v.count) — on a tie the winner depends on string hashing; here 'L' then 'R'.
  const dominant = {};
  for (const [p, v] of Object.entries(hand)) {
    const nl = v.filter((h) => h === 'L').length, nr = v.length - nl;
    dominant[p] = nr > nl ? 'R' : 'L';
  }

  // rallies end when the shuttle lands or play pauses for RALLY_GAP_S
  const rallies = [];
  let cur = [];
  for (const s of good) {
    if (cur.length) {
      const last = cur[cur.length - 1].hit_frame;
      const landed = floorFrames.some((f) => last < f && f <= s.hit_frame);
      if (landed || (s.hit_frame - last) / fps > RALLY_GAP_S) { rallies.push(cur); cur = []; }
    }
    cur.push(s);
  }
  if (cur.length) rallies.push(cur);

  const shotRows = [];
  rallies.forEach((r, ri) => r.forEach((s, i) => {
    let p = s.player ?? -1;
    if (!valid(p)) { p = sameTrack(s); if (p == null) p = who(s.hit_frame, s.side, s.p0); }   // player 0 (P1) is valid
    const c = classify(s, i === 0, fps);
    let side2d = null;
    if (p !== null) {
      const det = detAt(p, s.hit_frame);
      if (det >= 0) side2d = strokeSide(kpts[det], scores[det], dominant[p] ?? s.hand);
    }
    const hgt = height[p] ?? 1.7;
    const z0 = s.p0[2];
    const sd = s.speed_sd_kmh ?? null;
    Object.assign(c, {
      speed_sd_kmh: sd,
      // launch speed is well determined (< 10 %) except for shots along the line of sight
      speed_reliable: sd !== null && sd < 0.10 * Math.max(c.speed_kmh, 1),
      rally: ri + 1, shot_in_rally: i + 1, frame: s.hit_frame,
      time_s: pyRound(s.hit_frame / fps, 2), player: p === null ? null : p + 1,
      side: s.side, confidence: s.confidence ?? 'high',
      stroke_height: z0 > 0.85 * hgt ? 'overhead' : z0 > 0.5 * hgt ? 'side' : 'underarm',
      stroke_side: side2d,
      jump: p !== null && !!tracks[p] && z0 > 1.7 && jumped(tracks[p], s.hit_frame, rows, kpts, scores, fps),
      landing_in: s.landing ? s.landing.in : null,
    });
    shotRows.push(c);
  }));

  const rallyRows = rallies.map((r, ri) => {
    const last = r[r.length - 1];
    let winner = null;
    if (last.landing) winner = last.landing.in ? last.side : (last.side === 'near' ? 'far' : 'near');
    return {
      rally: ri + 1, start_s: pyRound(r[0].hit_frame / fps, 1),
      duration_s: pyRound((last.end_frame - r[0].hit_frame) / fps, 1), shots: r.length, winner_side: winner,
    };
  });

  // per player
  const perPlayer = {};
  for (const p of ids) {
    const t = tracks[p];
    const side = mode(t.side);
    const st = movementStats(t, fps);
    Object.assign(st, { player: p + 1, side, height_m: pyRound(height[p], 2), dominant_hand: dominant[p] ?? null });
    // readiness, reaction at the opponent's contacts
    const widths = [], knees = [], reacts = [];
    let ready = 0;
    for (const s of good) {
      if (s.side === side) continue;
      const f = s.hit_frame, i = trackIndex(t, f);
      if (i < 0) continue;
      const [w, kn] = posture(t.row[i], rows, k3d, kpts, scores);
      if (Number.isNaN(kn)) continue;
      widths.push(w);
      knees.push(kn);
      if (w >= 0.22 * height[p] && kn <= 165) ready++;
      // reaction: only when (nearly) standing at the contact, else the push-off already happened
      if (t.speed[i] < 0.8) {
        const [a, b] = trackRange(t, f, f + Math.trunc(fps));
        for (let k = a; k < b; k++) if (t.speed[k] > 1.5) { reacts.push((t.frame[k] - f) / fps); break; }
      }
    }
    const n = widths.length;
    st.at_opponent_contact = {
      samples: n,
      stance_width_m: n ? pyRound(median(widths), 2) : null,
      knee_angle_deg: n ? pyRound(median(knees), 1) : null,
      ready_stance_pct: n ? pyRound((100 * ready) / n, 1) : null,
      reaction_s: reacts.length ? pyRound(median(reacts), 2) : null,
    };
    // recovery after own shot: time to come back within 1 m of the base position
    const base = st.base_position, recs = [];
    for (const s of good) {
      if ((s.player ?? -1) !== p) continue;                // the shot's own label, not the fallback hitter
      const i = trackIndex(t, s.hit_frame);
      if (i < 0) continue;
      const far = Math.hypot(t.X[i] - base[0], t.Y[i] - base[1]) >= 1.0;
      if (!far) continue;
      const [a, b] = trackRange(t, s.hit_frame, s.hit_frame + Math.trunc(2 * fps));
      for (let k = a; k < b; k++) {
        if (Math.hypot(t.X[k] - base[0], t.Y[k] - base[1]) < 1.0) { recs.push((t.frame[k] - s.hit_frame) / fps); break; }
      }
    }
    st.recovery_s = recs.length ? pyRound(median(recs), 2) : null;
    const mine = shotRows.filter((c) => c.player === p + 1);
    st.shots = mine.length;
    st.shot_types = valueCounts(mine.map((c) => c.type));
    const allsm = mine.filter((c) => c.type === 'smash');
    const smash = allsm.filter((c) => c.speed_reliable).map((c) => c.speed_kmh);
    st.smash_kmh = {
      count: allsm.length, measured: smash.length,
      mean: smash.length ? pyRound(mean(smash), 1) : null,
      max: smash.length ? pyRound(Math.max(...smash), 1) : null,
    };
    st.jump_shots = mine.filter((c) => c.jump).length;
    st.contact_height_m = mine.length ? pyRound(median(mine.map((c) => c.contact_height_m)), 2) : null;
    st.strokes = valueCounts(mine.map((c) => c.stroke_side).filter((v) => v));
    st['heatmap_0.5m'] = heatmap(t);
    perPlayer[`P${p + 1}`] = st;
  }

  return {
    players: perPlayer, shots: shotRows, rallies: rallyRows,
    summary: {
      players: ids.length, rallies: rallies.length, shots: shotRows.length,
      shot_types: valueCounts(shotRows.map((c) => c.type)), landings: landings.length,
    },
  };
}
