// 3D shuttle flight from a single camera by fitting shuttlecock physics. Port of analysis/badminton/flight.py
// (fit_shot, fit_rally, recover_missed, validate; simulate/land/net_clearance live in physics.js).
// Each shot (one hit to the next, or to the end of the flight) has 7 unknowns: contact position, launch velocity
// and t0 (the contact is between frames). Every TrackNet observation gives 2 equations, gravity gives the metric
// scale. Anchors: start near the racket contact from the pose, end near the next contact, clear the net, stay
// above the floor.
import { W, HALF, NET_CENTRE } from './camera.js';
import { simulate, land, netClearance, shotTime } from './physics.js';
import { leastSquares, pinvSym } from './optimize.js';
import { turnPoints } from './track.js';
import { bestContact, indexPlayers } from './contact.js';

export const isIn = (x, y) => x >= 0 && x <= W && y >= -HALF && y <= HALF;

const rnd = (v, d) => { const s = 10 ** d; return Math.round(v * s) / s; };
const median = (a) => {
  if (!a.length) return NaN;
  const s = Float64Array.from(a).sort(), m = s.length >> 1;
  return s.length % 2 ? s[m] : 0.5 * (s[m - 1] + s[m]);
};
const norm = (v) => Math.hypot(v[0], v[1], v[2]);

/** Projection without allocations: P (n x 3 rows) -> fills out[2i], out[2i+1]. */
function projector(cam) {
  const { K, R, t } = cam;
  const fx = K[0][0], fy = K[1][1], cx = K[0][2], cy = K[1][2];
  return (X, Y, Z) => {
    const a = R[0][0] * X + R[0][1] * Y + R[0][2] * Z + t[0];
    const b = R[1][0] * X + R[1][1] * Y + R[1][2] * Z + t[1];
    const c = R[2][0] * X + R[2][1] * Y + R[2][2] * Z + t[2];
    return [fx * a / c + cx, fy * b / c + cy];
  };
}

/** Residual vector of one shot (same layout as flight.py _residuals). */
function makeResiduals(proj, t, px, pAnchor, end, crosses, w) {
  const n = t.length;
  const tt = end == null ? t : t.concat([end[0]]);
  const m = 2 * n + 3 + (end ? 3 : 0) + n + 1;
  return (x) => {
    const t0 = x[6];
    const P = simulate([x[0], x[1], x[2]], [x[3], x[4], x[5]], tt.map((v) => Math.max(v + t0, 0)));   // t0: contact between frames
    const r = new Float64Array(m);
    let k = 0;
    for (let i = 0; i < n; i++) {                                   // pixels
      const q = proj(P[i][0], P[i][1], P[i][2]);
      r[k++] = q[0] - px[i][0]; r[k++] = q[1] - px[i][1];
    }
    for (let j = 0; j < 3; j++) r[k++] = (x[j] - pAnchor[j]) / w.anchor[j];      // start at the racket
    if (end) for (let j = 0; j < 3; j++) r[k++] = (P[P.length - 1][j] - end[1][j]) / w.end;   // reach the next racket
    for (let i = 0; i < n; i++) r[k++] = Math.min(P[i][2], 0) / 0.05;           // never below the floor
    // whenever the path crosses the net plane between the posts it must pass over the tape
    let net = crosses ? 10.0 : 0.0;                                             // else: must reach the other side
    for (let j = 0; j < P.length - 1; j++) {
      if (Math.sign(P[j][1]) !== Math.sign(P[j + 1][1])) {
        const s = P[j][1] / (P[j][1] - P[j + 1][1]);
        const X = P[j][0] + s * (P[j + 1][0] - P[j][0]);
        const Z = P[j][2] + s * (P[j + 1][2] - P[j][2]);
        net = X >= -0.3 && X <= W + 0.3 ? Math.max(0, NET_CENTRE - Z) / 0.05 : 0.0;
        break;
      }
    }
    r[k++] = net;
    return r;
  };
}

function* initVelocities(p0, towardsFar) {
  const sign = towardsFar ? 1 : -1;
  const target = [W / 2, sign * HALF * 0.6, 0];
  const base = Math.atan2(target[1] - p0[1], target[0] - p0[0]);
  const rad = Math.PI / 180;
  for (const az of [-30, 0, 30].map((d) => base + d * rad))
    for (const el of [-35, -10, 10, 35, 60].map((d) => d * rad))
      for (const speed of [6, 12, 22, 40])
        yield [speed * Math.cos(el) * Math.cos(az), speed * Math.cos(el) * Math.sin(az), speed * Math.sin(el)];
}

/** 1-sigma launch speed / contact position from the Gauss-Newton covariance (scaled by the robust pixel spread). */
function uncertainty(sol, nObs, v0) {
  const J = sol.jac, n = sol.x.length;
  const pix = sol.fun.slice(0, 2 * nObs);
  const s = pix.length ? 1.4826 * median(pix.map(Math.abs)) : 1.0;
  const JTJ = Array.from({ length: n }, (_, a) => Array.from({ length: n }, (_, b) => {
    let acc = 0;
    for (const row of J) acc += row[a] * row[b];
    return acc;
  }));
  const sc = Math.max(s, 1.0) ** 2;
  const cov = pinvSym(JTJ).map((r) => r.map((v) => v * sc));
  const speed = norm(v0);
  const g = v0.map((v) => v / Math.max(speed, 1e-6));
  let q = 0;
  for (let a = 0; a < 3; a++) for (let b = 0; b < 3; b++) q += g[a] * cov[3 + a][3 + b] * g[b];
  const tr = cov[0][0] + cov[1][1] + cov[2][2];
  return { speed_sd_kmh: rnd(Math.sqrt(Math.max(q, 0)) * 3.6, 1), p0_sd_m: rnd(Math.sqrt(Math.max(tr, 0)), 2) };
}

/** Optimiser settings (exposed so a caller can trade accuracy for speed). */
export const fitOptions = { starts: 4, maxNfev: 300 };

/**
 * Fit one shot. frames / px: TrackNet observations after the hit (px = [[x, y], ...]). hit / nextHit: hit objects
 * ({frame, contact, side, pid, player, hand}). Returns a shot object (flights.json keys) or null.
 * If only the first part of the observations fits (a missed hit merged two shots), refits on that part.
 */
export function fitShot(cam, frames, px, fps, hit, nextHit = null, opts = {}) {
  const { w = { anchor: [0.25, 0.25, 0.25], end: 0.4 }, allowLanding = true, retry = true, pinM = 1.2 } = opts;
  const pAnchor = hit.contact.map(Number);
  const keepIdx = [];
  frames.forEach((f, i) => { if ((f - hit.frame) / fps >= 0) keepIdx.push(i); });
  const fr = keepIdx.map((i) => frames[i]);
  const t = fr.map((f) => (f - hit.frame) / fps);
  px = keepIdx.map((i) => px[i]);
  // fast flat exchanges (drives, blocks) last only 5-10 frames; with the receiver's racket as an end anchor
  // they are still well constrained
  const minObs = nextHit != null ? 5 : 8;
  if (t.length < Math.min(minObs, 6)) return null;
  const towardsFar = hit.side === 'near';
  let end = null, crosses = false;
  if (nextHit != null) {
    end = [(nextHit.frame - hit.frame) / fps, nextHit.contact.map(Number)];
    crosses = nextHit.side !== hit.side;
  }
  const proj = projector(cam);
  const fun = makeResiduals(proj, t, px, pAnchor, end, crosses, w);

  // physical bounds: contact 0.3-3.2 m high (3.2: a tall player's jump smash), launch speed below ~430 km/h,
  // contact within 1.5 frames of the detected hit frame (t0)
  const lo = [-2, -HALF - 2.5, 0.3, -120, -120, -120, -1.5 / fps];
  const hi = [W + 2, HALF + 2.5, 3.2, 120, 120, 120, 1.5 / fps];
  // pin the start near the racket contact (soft-L1 also down-weights a large anchor term, so the anchor alone
  // cannot stop the fit sliding along the view rays); height pinned tighter than the floor position
  const pin = [pinM, pinM, 0.6];
  for (let j = 0; j < 3; j++) { lo[j] = Math.max(lo[j], pAnchor[j] - pin[j]); hi[j] = Math.min(hi[j], pAnchor[j] + pin[j]); }
  for (let j = 0; j < 3; j++) if (lo[j] >= hi[j]) return null;
  const pStart = pAnchor.map((v, j) => Math.min(Math.max(v, lo[j] + 1e-3), hi[j] - 1e-3));
  const starts = [...initVelocities(pStart, towardsFar)].map((v) => [...pStart, ...v, 0.0]);
  const costs = starts.map((x) => fun(x).reduce((s, v) => s + v * v, 0));
  const order = costs.map((c, i) => [c, i]).sort((a, b) => a[0] - b[0]).map((a) => a[1]);
  let best = null;
  for (const i of order.slice(0, fitOptions.starts)) {
    const sol = leastSquares(fun, starts[i], { lo, hi, loss: 'soft_l1', fScale: 6.0, maxNfev: fitOptions.maxNfev });
    if (best == null || sol.cost < best.cost) best = sol;
  }
  const p0 = best.x.slice(0, 3), v0 = best.x.slice(3, 6), t0 = best.x[6];
  const obs = simulate(p0, v0, t.map((v) => Math.max(v + t0, 0)));
  const err = obs.map((P, i) => { const q = proj(P[0], P[1], P[2]); return Math.hypot(q[0] - px[i][0], q[1] - px[i][1]); });
  const res = {
    hit_frame: Math.trunc(hit.frame), pid: hit.pid, side: hit.side, player: hit.player ?? -1, hand: hit.hand ?? null,
    p0: p0.map((v) => rnd(v, 3)), v0: v0.map((v) => rnd(v, 3)), t0: rnd(t0, 4),
    speed_kmh: rnd(norm(v0) * 3.6, 1),
    n_obs: t.length, median_px: rnd(median(err), 2),
    inliers: rnd(err.filter((e) => e < 8).length / err.length, 2),
    anchor_shift_m: rnd(Math.hypot(p0[0] - pAnchor[0], p0[1] - pAnchor[1], p0[2] - pAnchor[2]), 2),
  };
  res.confidence = t.length >= 8 ? 'high' : 'medium';
  Object.assign(res, uncertainty(best, t.length, v0));
  // through the net is impossible: such a fit slid along the view rays
  const tEnd = (end ? end[0] : t.at(-1)) + t0;
  const clear = netClearance(p0, v0, Math.max(tEnd, t.at(-1) + t0));
  res.net_clearance_m = clear == null ? null : rnd(clear, 2);
  res.good = res.median_px < 6 && res.inliers > 0.7 && t.length >= minObs && res.anchor_shift_m < 1.5
    && res.speed_kmh < 360 && (clear == null || clear > -0.1);
  if (!res.good && retry) {
    // first run of 3 misses in a row
    let cut = err.length;
    for (let i = 0; i + 2 < err.length; i++) if (err[i] > 8 && err[i + 1] > 8 && err[i + 2] > 8) { cut = i; break; }
    if (cut >= 8 && cut < err.length)
      return fitShot(cam, fr.slice(0, cut), px.slice(0, cut), fps, hit, null, { w, allowLanding: false, retry: false });
    // the whole fit is garbage (several shots or a shuttle on the floor mixed in): grow a window from the hit
    // instead and keep the longest one that still fits
    if (t.length > 12) {
      let bestW = null;
      for (const k of [10, 14, 20, 28, 40]) {
        if (k >= t.length) break;
        const r = fitShot(cam, fr.slice(0, k), px.slice(0, k), fps, hit, null, { w, allowLanding: false, retry: false });
        if (r == null || !r.good) break;
        bestW = r;
      }
      if (bestW != null) {
        bestW.cut = 'longest window that fits (mixed observations after it)';
        return bestW;
      }
    }
  }
  res.end_frame = Math.trunc(nextHit == null ? fr.at(-1) : nextHit.frame);
  res.fit_last_frame = Math.trunc(fr.at(-1));                       // beyond this the path is extrapolated
  if (nextHit == null && allowLanding) {
    const lp = land(p0, v0);
    if (lp != null) {
      res.landing = { frame: Math.trunc(hit.frame + Math.round((lp[0] - t0) * fps)),
        court: [rnd(lp[1][0], 2), rnd(lp[1][1], 2)], in: isIn(lp[1][0], lp[1][1]) };
      res.end_frame = res.landing.frame;
    }
  }
  return res;
}

const detectedRows = (shuttle) => shuttle.filter((r) => r.detected === true || r.detected === 'True' || r.detected === 1);

/**
 * Split into shots between consecutive hits and fit each. shuttleRows: [{frame,x,y,track,detected}].
 * hits: hit objects (mutated like Python: when physics picks an alternative hitter, hits[i] is swapped and gets
 * side_by='flight fit'). Returns the shot list.
 */
export function fitRally(cam, shuttleRows, hits, fps, opts = {}) {
  const { maxShotS = 3.0, topPx = 30 } = opts;
  const obs = detectedRows(shuttleRows);
  const out = [];
  for (let i = 0; i < hits.length; i++) {
    const h = hits[i];
    let nxt = i + 1 < hits.length ? hits[i + 1] : null;
    if (nxt != null && (nxt.frame - h.frame) / fps > maxShotS) nxt = null;           // rally ended in between
    const stop = nxt ? nxt.frame : h.frame + Math.trunc(maxShotS * fps);
    let seg = obs.filter((r) => r.frame > h.frame && r.frame < stop);
    const landingOk = nxt == null;
    if (seg.length) {
      // follow only the flight that starts right after the hit, up to its first gap; a high clear leaves through
      // the top of the frame and falls back in (same flight), so such a gap does not end the shot
      for (let j = 0; j + 1 < seg.length; j++) {
        const throughTop = seg[j].y < topPx && seg[j + 1].y < topPx;
        if (seg[j + 1].frame - seg[j].frame > 6 && !throughTop) {
          seg = seg.slice(0, j + 1);
          if (nxt != null && nxt.frame - seg.at(-1).frame > 8) nxt = null;           // lost before the next hit
          break;
        }
      }
    }
    // who hit it? fit the flight from every candidate contact and keep the one physics agrees with
    const prevSide = i && (h.frame - hits[i - 1].frame) / fps <= maxShotS ? hits[i - 1].side : null;
    let best = null, bestKey = null, bestH = h;
    const frames = seg.map((r) => r.frame), px = seg.map((r) => [r.x, r.y]);
    for (const cand of [h, ...(h.alts || [])]) {
      const r = fitShot(cam, frames, px, fps, cand, nxt, { allowLanding: landingOk });
      if (!r) continue;
      const key = [r.good ? 0 : 1, r.median_px + (cand.side === prevSide ? 1.5 : 0) + 2 * r.anchor_shift_m];
      if (best == null || key[0] < bestKey[0] || (key[0] === bestKey[0] && key[1] < bestKey[1])) {
        best = r; bestKey = key; bestH = cand;
      }
    }
    if (bestH !== h) {                                   // physics picked the other player: swap
      const strip = (o) => { const c = { ...o }; delete c.alts; return c; };
      hits[i] = { ...strip(bestH), alts: [strip(h)], side_by: 'flight fit' };
    }
    if (best) out.push(validate(cam, best, obs, fps));
  }
  return out;
}

/**
 * Fill flights no fitted shot explains (a hit we did not detect). For each orphan stretch infer the hit that
 * started it: the end of a previous shot that was just cut (its predicted position), else the closest wrist to
 * the view ray with a loose gate. Fit it as a new shot, repeat. players: column dict, k3d: [row][17][3].
 * Returns [shots (sorted by hit_frame), added].
 */
export function recoverMissed(cam, shots, shuttleRows, hits, players, k3d, fps, opts = {}) {
  const { minObs = 8, passes = 3 } = opts;
  const { rows, byFrame } = indexPlayers(players);
  const obs = detectedRows(shuttleRows);
  let added = 0;
  for (let pass = 0; pass < passes; pass++) {
    const covered = new Set();
    for (const s of shots) if (s.good) for (let f = s.hit_frame; f <= s.end_frame; f++) covered.add(f);
    const free = obs.filter((r) => !covered.has(r.frame));
    if (!free.length) break;
    // runs split at gaps > 6 frames, except out through the top of the image and back (same flight)
    const runs = [];
    let cur = [free[0]];
    for (let j = 0; j + 1 < free.length; j++) {
      const throughTop = free[j].y < 30 && free[j + 1].y < 30;
      if (free[j + 1].frame - free[j].frame > 6 && !throughTop) { runs.push(cur); cur = []; }
      cur.push(free[j + 1]);
    }
    runs.push(cur);
    const pieces = [];
    for (const seg of runs) {                           // an orphan run can hold several shots: split at sharp turns
      const turns = turnPoints(seg, { minSep: 6 }).map(([f]) => f);
      const edges = [seg[0].frame, ...turns, seg.at(-1).frame + 1];
      for (let e = 0; e + 1 < edges.length; e++) pieces.push(seg.filter((r) => r.frame >= edges[e] && r.frame < edges[e + 1]));
    }
    let nNew = 0;
    for (const seg of pieces) {
      if (seg.length < minObs) continue;
      const fs = Math.trunc(seg[0].frame), px0 = [seg[0].x, seg[0].y];
      let hit = null;
      const prev = shots.filter((s) => s.good && s.cut && fs - s.end_frame >= 0 && fs - s.end_frame <= 10);
      if (prev.length) {
        const s = prev.at(-1);
        const fh = s.end_frame + 1;
        const p = simulate(s.p0, s.v0, shotTime(s, [fh], fps))[0];
        p[2] = Math.max(p[2], 0.3);
        // the receiver stands where the shuttle is: Y > 0 = far half (fixed in flight.py too)
        hit = { frame: fh, pid: -1, side: p[1] > 0 ? 'far' : 'near',
          contact: p.map((v) => rnd(v, 2)), how: 'end of the previous predicted path' };
        const near = bestContact(cam, fh, cam.project([p])[0], rows, byFrame, k3d, { maxDist: 1.6 });
        if (near) { hit.pid = near.pid; hit.side = near.side; }
      } else {
        // no wrist within 1.6 m: no anchor (an unanchored fit slides along the view ray)
        const near = bestContact(cam, fs - 1, px0, rows, byFrame, k3d, { window: 5, maxDist: 1.6 });
        if (near) hit = { ...near, frame: fs - 1, how: 'closest wrist (loose gate)' };
      }
      if (hit == null) continue;
      const last = seg.at(-1).frame;
      let nxt = hits.find((h) => h.frame > last) || null;
      if (nxt != null && nxt.frame - last > 8) nxt = null;
      const res = fitShot(cam, seg.map((r) => r.frame), seg.map((r) => [r.x, r.y]), fps, hit, nxt, { allowLanding: nxt == null });
      if (res && res.good) {
        res.inferred_hit = hit.how;
        shots.push(validate(cam, res, obs, fps));
        nNew++;
      }
    }
    added += nNew;
    if (!nNew) break;
  }
  shots.sort((a, b) => a.hit_frame - b.hit_frame);
  return [shots, added];
}

/** Check the extrapolated part against later TrackNet points: if the real shuttle leaves the predicted path
 * (a missed hit), the shot ends there and its predicted landing is dropped. */
export function validate(cam, shot, obs, fps, maxPx = 25, run = 2) {
  const later = obs.filter((r) => r.frame > shot.fit_last_frame && r.frame <= shot.end_frame);
  if (!later.length) return shot;
  const f = later.map((r) => r.frame);
  const P = simulate(shot.p0, shot.v0, shotTime(shot, f, fps));
  const q = cam.project(P);
  const off = q.map((p, i) => Math.hypot(p[0] - later[i].x, p[1] - later[i].y) > maxPx);
  for (let i = 0; i + run <= off.length; i++) {
    if (off.slice(i, i + run).every(Boolean)) {
      shot.end_frame = Math.trunc(f[i] - 1);
      shot.cut = 'shuttle left the predicted path (missed hit?)';
      delete shot.landing;
      break;
    }
  }
  return shot;
}
