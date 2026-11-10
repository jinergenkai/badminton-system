// Post-processing in the browser, ported from analysis/badminton/track.py (+ a light players.py).
import { apply, convexHull, COURT_W, HALF_L, pointInPoly } from './geom.js';

// Image region the shuttle can be in: the box above our court, approximated without a full camera
// model by the expanded floor polygon stretched up to the top of the frame.
export function shuttleGate(H, width, height) {
  if (!H) return null;
  const pts = [];
  for (const X of [-1.5, COURT_W + 1.5]) for (const Y of [-8.2, 0, 8.2]) {
    const p = apply(H, [X, Y]);
    if (p[2] > 0) pts.push([p[0], p[1]], [p[0], 0]);
  }
  if (pts.length < 3) return null;
  return convexHull(pts.map(([x, y]) => [Math.max(-width, Math.min(2 * width, x)), Math.max(0, Math.min(height, y))]));
}

// cands[f] = [{x, y, ...}] in video pixels
export function buildTracks(cands, gate, { maxGap = 5, gateBase = 30, gatePerFrame = 18 } = {}) {
  let live = [];
  const finished = [];
  for (let f = 0; f < cands.length; f++) {
    const pts = (cands[f] || []).filter((c) => !gate || pointInPoly([c.x, c.y], gate)).map((c) => [c.x, c.y]);
    live = live.filter((t) => (f - t.f.at(-1) > maxGap ? (finished.push(t), false) : true));
    if (!pts.length) continue;
    const pairs = [];
    live.forEach((t, ti) => {
      const gap = f - t.f.at(-1);
      const px = t.p.at(-1)[0] + t.v[0] * gap, py = t.p.at(-1)[1] + t.v[1] * gap;
      pts.forEach((q, ci) => {
        const d = Math.hypot(q[0] - px, q[1] - py);
        if (d < gateBase + gatePerFrame * gap) pairs.push([d, ti, ci]);
      });
    });
    pairs.sort((a, b) => a[0] - b[0]);
    const usedT = new Set(), usedC = new Set();
    for (const [, ti, ci] of pairs) {
      if (usedT.has(ti) || usedC.has(ci)) continue;
      const t = live[ti], gap = f - t.f.at(-1), last = t.p.at(-1);
      const v = [(pts[ci][0] - last[0]) / gap, (pts[ci][1] - last[1]) / gap];
      t.v = t.f.length > 1 ? [0.5 * t.v[0] + 0.5 * v[0], 0.5 * t.v[1] + 0.5 * v[1]] : v;
      t.f.push(f); t.p.push(pts[ci]);
      usedT.add(ti); usedC.add(ci);
    }
    pts.forEach((q, ci) => { if (!usedC.has(ci)) live.push({ f: [f], p: [q], v: [0, 0] }); });
  }
  return finished.concat(live);
}

// keep real flights, then per frame the single best one; short gaps linearly interpolated
export function selectTracks(tracks, { minLen = 8, minTravel = 40 } = {}) {
  const good = [];
  for (const t of tracks) {
    if (t.f.length < minLen) continue;
    const xs = t.p.map((p) => p[0]), ys = t.p.map((p) => p[1]);
    const travel = Math.hypot(Math.max(...xs) - Math.min(...xs), Math.max(...ys) - Math.min(...ys));
    if (travel >= minTravel) good.push({ ...t, score: (t.f.length / (t.f.at(-1) - t.f[0] + 1)) * t.f.length });
  }
  const owner = new Map();
  good.forEach((t, k) => {
    for (let fr = t.f[0]; fr <= t.f.at(-1); fr++) if (!owner.has(fr) || good[owner.get(fr)].score < t.score) owner.set(fr, k);
  });
  const rows = [];
  good.forEach((t, k) => {
    let j = 0;
    for (let fr = t.f[0]; fr <= t.f.at(-1); fr++) {
      while (t.f[j + 1] !== undefined && t.f[j + 1] <= fr) j++;
      if (owner.get(fr) !== k) continue;
      const a = t.f[j], b = t.f[Math.min(j + 1, t.f.length - 1)];
      const u = b === a ? 0 : (fr - a) / (b - a);
      const pa = t.p[j], pb = t.p[Math.min(j + 1, t.p.length - 1)];
      rows.push({ frame: fr, x: pa[0] + (pb[0] - pa[0]) * u, y: pa[1] + (pb[1] - pa[1]) * u, track: k, detected: fr === a });
    }
  });
  return rows.sort((a, b) => a.frame - b.frame);
}

// sharp turn or sudden speed-up of the image trajectory ~ racket contact (2D only, no physics here)
export function turnPoints(seg, { k = 3, minTurnDeg = 50, minSpeedup = 2.5, minSep = 8 } = {}) {
  const out = [];
  for (let i = k; i < seg.length - k; i++) {
    const a = seg[i - k], m = seg[i], b = seg[i + k];
    const vb = [(m.x - a.x) / (m.frame - a.frame), (m.y - a.y) / (m.frame - a.frame)];
    const va = [(b.x - m.x) / (b.frame - m.frame), (b.y - m.y) / (b.frame - m.frame)];
    const nb = Math.hypot(...vb), na = Math.hypot(...va);
    if (nb < 1e-6 || na < 1e-6) continue;
    const turn = (Math.acos(Math.max(-1, Math.min(1, (vb[0] * va[0] + vb[1] * va[1]) / (nb * na)))) * 180) / Math.PI;
    if ((turn > minTurnDeg || na / nb > minSpeedup) && (!out.length || m.frame - out.at(-1).frame >= minSep)) out.push({ frame: m.frame, x: m.x, y: m.y });
  }
  return out;
}

// ---------- players ----------

const ANKLES = [15, 16];

// poses: Map(frame -> [{kp:[x,y,s]*17 (video px), score}]) at key frames. Two slots per court side.
export function trackPlayers(poses, Hinv, scaleY) {
  const slots = [];          // {id, side, last:[X,Y], pts:[{f,X,Y}]}
  const frames = [...poses.keys()].sort((a, b) => a - b);
  for (const f of frames) {
    for (const person of poses.get(f)) {
      person.court = null;
      if (!Hinv) continue;
      const k = person.kp;
      const ok = ANKLES.filter((i) => k[i * 3 + 2] > 0.3);
      if (!ok.length) continue;
      const fx = ok.reduce((s, i) => s + k[i * 3], 0) / ok.length;
      const fy = ok.reduce((s, i) => s + k[i * 3 + 1], 0) / ok.length + 4 * scaleY;
      const [X, Y, w] = apply(Hinv, [fx, fy]);
      if (w > 0 && X > -1.2 && X < COURT_W + 1.2 && Math.abs(Y) < HALF_L + 1.2) person.court = [X, Y];
    }
    for (const side of [-1, 1]) {
      const people = poses.get(f).filter((p) => p.court && Math.sign(p.court[1]) === side).sort((a, b) => b.score - a.score).slice(0, 2);
      const mine = slots.filter((s) => s.side === side);
      while (mine.length < people.length) { const s = { id: slots.length, side, last: null, pts: [] }; slots.push(s); mine.push(s); }
      // brute-force assignment (≤ 2 × 2)
      const cost = (s, p) => (s.last ? Math.hypot(s.last[0] - p.court[0], s.last[1] - p.court[1]) : 0);
      let best = null;
      const perms = mine.length === 2 ? [[0, 1], [1, 0]] : [[0]];
      for (const perm of perms) {
        let c = 0;
        people.forEach((p, i) => { c += cost(mine[perm[i]], p); });
        if (!best || c < best.c) best = { c, perm };
      }
      people.forEach((p, i) => {
        const s = mine[best.perm[i]];
        p.player = s.id;
        s.last = p.court;
        s.pts.push({ f, X: p.court[0], Y: p.court[1] });
      });
    }
  }
  return slots.filter((s) => s.pts.length >= 5);
}

export function playerStats(slot, fps) {
  // moving average over 5 key frames, ignore implausible jumps (> 8 m/s)
  const p = slot.pts;
  const sm = p.map((_, i) => {
    const w = p.slice(Math.max(0, i - 2), i + 3);
    return { f: p[i].f, X: w.reduce((s, q) => s + q.X, 0) / w.length, Y: w.reduce((s, q) => s + q.Y, 0) / w.length };
  });
  let dist = 0;
  for (let i = 1; i < sm.length; i++) {
    const d = Math.hypot(sm[i].X - sm[i - 1].X, sm[i].Y - sm[i - 1].Y);
    const dt = (sm[i].f - sm[i - 1].f) / fps;
    if (dt > 0 && d / dt < 8) dist += d;
  }
  return { distance: dist, seconds: (p.at(-1).f - p[0].f) / fps, smooth: sm };
}

// ---------- rallies, shots, landings ----------

// a 2D turn only counts as a racket contact if some player's wrist is near it (racket ~ 0.4 body heights)
function nearWrist(hit, poses, every) {
  if (!poses || !every) return true;
  const k0 = Math.round(hit.frame / every) * every;
  for (const k of [k0, k0 - every, k0 + every]) {
    for (const p of poses.get(k) || []) {
      const h = p.box[3] - p.box[1];
      for (const w of [9, 10]) {
        if (p.kp[w * 3 + 2] < 0.3) continue;
        if (Math.hypot(p.kp[w * 3] - hit.x, p.kp[w * 3 + 1] - hit.y) < 0.45 * h) return true;
      }
    }
  }
  return false;
}

export function rallies(shuttle, fps, Hinv, poses = null, every = 0) {
  const out = [];
  let cur = null;
  for (const r of shuttle) {
    if (cur && r.frame - cur.pts.at(-1).frame <= fps * 1.0) cur.pts.push(r);
    else { if (cur) out.push(cur); cur = { pts: [r] }; }
  }
  if (cur) out.push(cur);
  return out
    .filter((r) => r.pts.at(-1).frame - r.pts[0].frame >= fps * 1.0)
    .map((r) => {
      const hits = turnPoints(r.pts).filter((h) => nearWrist(h, poses, every));
      let landing = null;
      const det = r.pts.filter((q) => q.detected);
      const tail = det.slice(-5);
      if (Hinv && tail.length === 5 && tail.every((q, i) => i === 0 || q.y >= tail[i - 1].y - 1) && tail.at(-1).y - tail[0].y > 8) {
        const [X, Y, w] = apply(Hinv, [tail.at(-1).x, tail.at(-1).y]);
        if (w > 0 && X > -1.5 && X < COURT_W + 1.5 && Math.abs(Y) < HALF_L + 1.5) {
          landing = { frame: tail.at(-1).frame, X, Y, inDoubles: X >= 0 && X <= COURT_W && Math.abs(Y) <= HALF_L };
        }
      }
      return { start: r.pts[0].frame, end: r.pts.at(-1).frame, shots: hits.length + 1, hits, landing };
    });
}
