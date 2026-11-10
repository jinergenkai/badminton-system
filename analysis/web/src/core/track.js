// Per-frame candidates -> shuttle flights; pick the one that belongs to our court. Port of analysis/badminton/track.py.
// 1. Gate: drop candidates outside the image region of the box above our court (a polygon here, an image mask
//    in Python: courtVolumePolygon(cam)).
// 2. Multi-target tracking: each live track predicts its next position from its velocity and takes the nearest
//    candidate inside a gate that widens with the frame gap; unmatched candidates start new tracks.
// 3. Drop tracks that are too short or barely move (ceiling lights, white shoes).
// 4. Per frame keep the best track (long and dense), fill short gaps by linear interpolation.
import { pointInPoly } from './camera.js';

/** Column dict ({frame: [...], x: [...]}) or row array -> row array. */
export function toRows(d) {
  if (Array.isArray(d)) return d;
  const keys = Object.keys(d), n = d[keys[0]].length;
  const out = new Array(n);
  for (let i = 0; i < n; i++) { const r = {}; for (const k of keys) r[k] = d[k][i]; out[i] = r; }
  return out;
}

/**
 * cands: rows or column dict with frame, x, y. gate: image polygon [[x,y],...] or null (no gating).
 * opts {maxGap=5, gate=30, gatePerFrame=18, size=[w,h] (optional, clips points to the image like the mask lookup)}.
 * Returns [{f: [frames], p: [[x,y], ...]}] in the order Python produces them (finished first, then still live).
 */
export function buildTracks(cands, gatePolygon = null, opts = {}) {
  const { maxGap = 5, gate = 30, gatePerFrame = 18, size = null } = opts;
  let c = toRows(cands);
  if (gatePolygon) {
    c = c.filter((r) => {
      let x = r.x, y = r.y;
      if (size) { x = Math.trunc(Math.min(Math.max(x, 0), size[0] - 1)); y = Math.trunc(Math.min(Math.max(y, 0), size[1] - 1)); }
      return pointInPoly([x, y], gatePolygon);
    });
  }
  // groupby('frame'): ascending frames, candidates keep their file order
  const groups = new Map();
  for (const r of c) { if (!groups.has(r.frame)) groups.set(r.frame, []); groups.get(r.frame).push([r.x, r.y]); }
  const frames = [...groups.keys()].sort((a, b) => a - b);
  let live = [];
  const finished = [];
  for (const f of frames) {
    const pts = groups.get(f);
    const still = [];
    for (const t of live) (f - t.f.at(-1) > maxGap ? finished : still).push(t);
    live = still;
    // greedy assignment, closest (track, candidate) pairs first
    const pairs = [];
    live.forEach((t, ti) => {
      const gap = f - t.f.at(-1), last = t.p.at(-1);
      const px = last[0] + t.v[0] * gap, py = last[1] + t.v[1] * gap;
      pts.forEach((q, ci) => {
        const d = Math.hypot(q[0] - px, q[1] - py);
        if (d < gate + gatePerFrame * gap) pairs.push([d, ti, ci]);
      });
    });
    pairs.sort((a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2]);
    const usedT = new Set(), usedC = new Set();
    for (const [, ti, ci] of pairs) {
      if (usedT.has(ti) || usedC.has(ci)) continue;
      const t = live[ti], gap = f - t.f.at(-1), last = t.p.at(-1);
      const v = [(pts[ci][0] - last[0]) / gap, (pts[ci][1] - last[1]) / gap];
      t.v = t.f.length > 1 ? [0.5 * t.v[0] + 0.5 * v[0], 0.5 * t.v[1] + 0.5 * v[1]] : v;
      t.f.push(f);
      t.p.push(pts[ci]);
      usedT.add(ti);
      usedC.add(ci);
    }
    pts.forEach((q, ci) => { if (!usedC.has(ci)) live.push({ f: [f], p: [q], v: [0, 0] }); });
  }
  return finished.concat(live).map((t) => ({ f: t.f, p: t.p }));
}

function interp(x, xs, ys) {
  // np.interp on a strictly increasing xs, x inside [xs[0], xs.at(-1)]
  let lo = 0, hi = xs.length - 1;
  if (x <= xs[0]) return ys[0];
  if (x >= xs[hi]) return ys[hi];
  while (hi - lo > 1) { const m = (lo + hi) >> 1; if (xs[m] <= x) lo = m; else hi = m; }
  return ys[lo] + ((x - xs[lo]) * (ys[hi] - ys[lo])) / (xs[hi] - xs[lo]);
}

/** Keep real flights, then for every frame the single best track. Returns rows [{frame,x,y,track,detected}] by frame. */
export function select(tracks, opts = {}) {
  const { minLen = 8, minTravel = 40 } = opts;
  const good = [];
  for (const { f, p } of tracks) {
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
    for (const q of p) { x0 = Math.min(x0, q[0]); x1 = Math.max(x1, q[0]); y0 = Math.min(y0, q[1]); y1 = Math.max(y1, q[1]); }
    const travel = Math.hypot(x1 - x0, y1 - y0);
    if (f.length >= minLen && travel >= minTravel) good.push({ f, p, score: (f.length / (f.at(-1) - f[0] + 1)) * f.length });
  }
  const owner = new Map();
  good.forEach(({ f, score }, k) => {
    for (let fr = f[0]; fr <= f.at(-1); fr++) if (!owner.has(fr) || good[owner.get(fr)].score < score) owner.set(fr, k);
  });
  const rows = [];
  good.forEach(({ f, p }, k) => {
    const det = new Set(f), xs = p.map((q) => q[0]), ys = p.map((q) => q[1]);
    for (let fr = f[0]; fr <= f.at(-1); fr++) {
      if (owner.get(fr) !== k) continue;
      rows.push({ frame: fr, x: interp(fr, f, xs), y: interp(fr, f, ys), track: k, detected: det.has(fr) });
    }
  });
  rows.sort((a, b) => a.frame - b.frame);
  return rows;
}

/** Last point [frame, x, y] of each selected track if the shuttle was moving down the image before it. */
export function fallingEnds(rows, n = 5) {
  const by = new Map();
  for (const r of rows) if (r.detected) { if (!by.has(r.track)) by.set(r.track, []); by.get(r.track).push(r); }
  const out = [];
  for (const k of [...by.keys()].sort((a, b) => a - b)) {
    const tail = by.get(k).slice(-n);
    if (tail.length !== n) continue;
    let down = true;
    for (let i = 1; i < n; i++) if (tail[i].y - tail[i - 1].y < -1) down = false;
    if (down && tail.at(-1).y - tail[0].y > 8) out.push([tail.at(-1).frame, tail.at(-1).x, tail.at(-1).y]);
  }
  return out;
}

/** [[frame, [x, y]], ...] where an image trajectory turns sharply or suddenly speeds up: likely racket contacts. */
export function turnPoints(seg, opts = {}) {
  const { k = 3, minTurnDeg = 50, minSpeedup = 2.5, minSep = 0 } = opts;
  const out = [];
  for (let i = k; i < seg.length - k; i++) {
    const a = seg[i - k], b = seg[i], c = seg[i + k];
    const vb = [(b.x - a.x) / (b.frame - a.frame), (b.y - a.y) / (b.frame - a.frame)];
    const va = [(c.x - b.x) / (c.frame - b.frame), (c.y - b.y) / (c.frame - b.frame)];
    const nb = Math.hypot(...vb), na = Math.hypot(...va);
    if (nb < 1e-6 || na < 1e-6) continue;
    const cos = Math.min(Math.max((vb[0] * va[0] + vb[1] * va[1]) / (nb * na), -1), 1);
    const turn = (Math.acos(cos) * 180) / Math.PI;
    if ((turn > minTurnDeg || na / nb > minSpeedup) && (!out.length || b.frame - out.at(-1)[0] >= minSep))
      out.push([b.frame, [b.x, b.y]]);
  }
  return out;
}
