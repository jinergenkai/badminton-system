// Racket-shuttle contacts ("hits") from the shuttle track + player poses. Port of analysis/badminton/hits.py.
// Candidate moments: a flight starts / ends, or the shuttle turns sharply / speeds up. A candidate is a hit when,
// in 3D, the shuttle's view ray passes close to a player's wrist; the nearest ray point is the contact estimate.
// Sides alternate within a rally (Viterbi), and the same side never hits twice in a row.
import { L_ANK, L_WR, R_ANK, R_WR } from './players.js';

// Python round(v, n): correctly rounded, ties (exact binary halves such as 0.125) to even
function pyRound(v, n) {
  const m = 10 ** n, t = v * m;
  if (t % 1 !== 0 && (t * 2) % 1 === 0) { const lo = Math.floor(t); return (lo % 2 === 0 ? lo : lo + 1) / m; }
  return Number(v.toFixed(n));
}

/** (frame, pixel) where an image trajectory turns sharply or suddenly speeds up (track.turn_points). */
export function turnPoints(f, p, { k = 3, minTurnDeg = 50, minSpeedup = 2.5, minSep = 0 } = {}) {
  const out = [];
  for (let i = k; i < f.length - k; i++) {
    const vb = [(p[i][0] - p[i - k][0]) / (f[i] - f[i - k]), (p[i][1] - p[i - k][1]) / (f[i] - f[i - k])];
    const va = [(p[i + k][0] - p[i][0]) / (f[i + k] - f[i]), (p[i + k][1] - p[i][1]) / (f[i + k] - f[i])];
    const nb = Math.hypot(...vb), na = Math.hypot(...va);
    if (nb < 1e-6 || na < 1e-6) continue;
    const cos = Math.min(1, Math.max(-1, (vb[0] * va[0] + vb[1] * va[1]) / (nb * na)));
    const turn = (Math.acos(cos) * 180) / Math.PI;
    if ((turn > minTurnDeg || na / nb > minSpeedup) && (!out.length || f[i] - out.at(-1)[0] >= minSep))
      out.push([f[i], p[i]]);
  }
  return out;
}

// shuttle rows [{frame, x, y, track, detected}] or the column dict of shuttle.csv
function toRows(sh) {
  if (Array.isArray(sh)) return sh;
  return sh.frame.map((frame, i) => ({ frame, x: sh.x[i], y: sh.y[i], track: sh.track[i], detected: sh.detected[i] }));
}

/** Candidate contact moments [frame, [x, y], kind]: start, end and turn points of every detected track. */
export function candidates(shuttle) {
  const tracks = new Map();
  for (const r of toRows(shuttle)) {
    if (!(r.detected === true || r.detected === 'True' || r.detected === 1)) continue;
    if (!tracks.has(r.track)) tracks.set(r.track, []);
    tracks.get(r.track).push(r);
  }
  const out = [];
  for (const id of [...tracks.keys()].sort((a, b) => a - b)) {   // pandas groupby: sorted track ids
    const t = tracks.get(id);
    const f = t.map((r) => r.frame), p = t.map((r) => [r.x, r.y]);
    out.push([f[0], p[0], 'start']);
    // the contact is often inside a short detection gap that splits the track: the old one ends at the racket
    out.push([f.at(-1), p.at(-1), 'end']);
    for (const [ff, pp] of turnPoints(f, p)) out.push([ff, pp, 'turn']);
  }
  return out;
}

/**
 * Rows to search + rows per frame. With a 'player' column, floor tracks (pid) that are almost never
 * identified (bystanders walking past) are dropped unless the row itself is identified.
 * Returns { rows, byFrame: Map(frame -> [row index]) }.
 */
export function indexPlayers(rows) {
  let keep = rows.map((_, i) => i);
  if (rows.length && 'player' in rows[0]) {
    const tot = new Map(), idd = new Map();
    for (const r of rows) {
      tot.set(r.pid, (tot.get(r.pid) || 0) + 1);
      if (r.player >= 0) idd.set(r.pid, (idd.get(r.pid) || 0) + 1);
    }
    keep = keep.filter((i) => (idd.get(rows[i].pid) || 0) / tot.get(rows[i].pid) >= 0.2 || rows[i].player >= 0);
  }
  const byFrame = new Map();
  for (const i of keep) {
    const f = rows[i].frame;
    if (!byFrame.has(f)) byFrame.set(f, []);
    byFrame.get(f).push(i);
  }
  return { rows, byFrame };
}

/**
 * Player wrist closest (in 3D) to the shuttle's view ray around frame f -> hit object or null.
 * side 'near' / 'far' restricts the search to one half of the court.
 */
export function bestContact(cam, f, px, rows, byFrame, k3d, { window = 3, maxDist = 1.0, minZ = 0.25, side = null } = {}) {
  const d = cam.ray(px), C = cam.pos;
  let best = null, bestScore = Infinity;
  for (let ff = f - window; ff <= f + window; ff++) {
    for (const r of byFrame.get(ff) || []) {
      if (side !== null && rows[r].side !== side) continue;
      const K = k3d[r];
      // body height in pixels, to judge "near the racket" on the image at any depth
      const [head, la, ra] = cam.project([K[0], K[L_ANK], K[R_ANK]]);
      const bodyPx = Math.max(Math.hypot(head[0] - (la[0] + ra[0]) / 2, head[1] - (la[1] + ra[1]) / 2), 20);
      for (const [name, j] of [['L', L_WR], ['R', R_WR]]) {
        const Wp = [K[j][0] - C[0], K[j][1] - C[1], K[j][2] - C[2]];
        const along = Wp[0] * d[0] + Wp[1] * d[1] + Wp[2] * d[2];
        if (along <= 0) continue;
        const dist = Math.hypot(Wp[0] - along * d[0], Wp[1] - along * d[1], Wp[2] - along * d[2]);
        const contact = [C[0] + along * d[0], C[1] + along * d[1], C[2] + along * d[2]];
        if (contact[2] < minZ) continue;         // at floor level: picking the shuttle up, not a stroke
        // teammates stand at different depths on one view ray: the shuttle must also be near the wrist on the image
        const q = cam.project([K[j]])[0];
        const img = Math.hypot(q[0] - px[0], q[1] - px[1]) / bodyPx;
        const score = dist + 0.8 * img;
        if (dist < maxDist && score < bestScore) {
          bestScore = score;
          best = {
            frame: f, pid: rows[r].pid, side: rows[r].side, hand: name,
            player: 'player' in rows[r] ? rows[r].player : -1,
            px: [pyRound(px[0], 1), pyRound(px[1], 1)],
            wrist_dist: pyRound(dist, 2), wrist_z: pyRound(K[j][2], 2),
            contact: contact.map((v) => pyRound(v, 2)),
          };
        }
      }
    }
  }
  return best;
}

const SIDES = ['near', 'far'];

/** Hitting side of every moment, by Viterbi over each rally (sides alternate; repeating one costs switchCost). */
function chooseSides(moments, fps, switchCost, rallyGapS) {
  const out = [];
  let i = 0;
  while (i < moments.length) {
    let j = i + 1;
    while (j < moments.length && moments[j].frame - moments[j - 1].frame <= rallyGapS * fps) j++;
    const rally = moments.slice(i, j);
    const cost = rally.map((m) => Object.fromEntries(SIDES.map((s) => [s, m.opts[s] ? m.opts[s].wrist_dist : Infinity])));
    const acc = [{ ...cost[0] }], back = [{}];
    for (let k = 1; k < rally.length; k++) {
      const a = {}, b = {};
      for (const s of SIDES) {
        const prev = Object.fromEntries(SIDES.map((p) => [p, acc.at(-1)[p] + (p === s ? switchCost : 0)]));
        const p = prev.far < prev.near ? 'far' : 'near';     // Python min(): first key on ties
        a[s] = prev[p] + cost[k][s];
        b[s] = p;
      }
      acc.push(a);
      back.push(b);
    }
    let s = acc.at(-1).far < acc.at(-1).near ? 'far' : 'near';
    const path = [s];
    for (let k = rally.length - 1; k > 0; k--) { s = back[k][s]; path.push(s); }
    path.reverse();
    rally.forEach((m, k) => {
      const h = { ...m.opts[path[k]] };
      const other = path[k] === 'near' ? 'far' : 'near';
      if (m.opts[other]) h.alts = [m.opts[other]];   // the flight fit may still prefer the other player
      out.push(h);
    });
    i = j;
  }
  return out;
}

/**
 * Hits from the shuttle track and the players (rows with 'side' and, ideally, 'player'; k3d aligned with rows).
 * Returns [{frame, pid, side, hand, player, px, wrist_dist, wrist_z, contact, kind, alts?}] in frame order.
 */
export function findHits(cam, shuttle, players, k3d, fps = 30.0,
  { window = 3, maxDist = 1.0, merge = 8, minGapSameSide = 20, minZ = 0.25, switchCost = 0.8, rallyGapS = 3.0 } = {}) {
  const { rows, byFrame } = indexPlayers(players);
  const found = [];
  for (const [f, px, kind] of candidates(shuttle)) {
    const opts = {};
    for (const side of SIDES) {                   // best wrist on EACH side: the closest overall is often wrong
      const b = bestContact(cam, f, px, rows, byFrame, k3d, { window, maxDist, minZ, side });
      if (b) { b.kind = kind; opts[side] = b; }
    }
    if (Object.keys(opts).length) found.push({ frame: f, opts });
  }
  // one hit per moment: merge candidates close in time, keep the best supported one per side
  found.sort((a, b) => a.frame - b.frame);       // stable, like Python's sort
  const moments = [];
  for (const m of found) {
    const lastM = moments.at(-1);
    if (lastM && m.frame - lastM.frame <= merge) {
      for (const s of SIDES) {
        const b = m.opts[s];
        if (!b) continue;
        const cur = lastM.opts[s];
        if (!cur || b.wrist_dist < cur.wrist_dist) lastM.opts[s] = b;
      }
    } else moments.push(m);
  }
  const merged = chooseSides(moments, fps, switchCost, rallyGapS);
  // the same side never hits twice in a row (a quick double means one of them is wrong)
  const final = [];
  for (const h of merged) {
    const prev = final.at(-1);
    if (prev && h.side === prev.side && h.frame - prev.frame < minGapSameSide) {
      if (h.wrist_dist < prev.wrist_dist) final[final.length - 1] = h;
    } else final.push(h);
  }
  return final;
}
