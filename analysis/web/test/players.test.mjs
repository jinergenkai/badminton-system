// node --test analysis/web/test/   (fixtures: python analysis/tools/export_fixtures.py danh-cau-02)
// Players, identities and hits against the Python pipeline's outputs on the same video.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { cameraFromCalib } from '../src/core/camera.js';
import { trackPlayers } from '../src/core/players.js';
import { appearanceFeature, assign } from '../src/core/identity.js';
import { findHits } from '../src/core/hits.js';
import { linearSumAssignment } from '../src/core/assign.js';

const dir = new URL('./fixtures/danh-cau-02/', import.meta.url);
const fx = (p) => JSON.parse(readFileSync(new URL(p, dir), 'utf8'));
const calib = fx('calib.json');
const cam = cameraFromCalib(calib);
const fps = calib.fps;
const pl = fx('players.json');
const plRows = pl.frame.map((_, i) => Object.fromEntries(Object.keys(pl).map((c) => [c, pl[c][i]])));

test('linearSumAssignment finds the optimum (rectangular both ways)', () => {
  const brute = (C) => {
    const n = C.length, m = C[0].length, rows = n <= m;
    const A = rows ? C : C[0].map((_, j) => C.map((r) => r[j]));
    let best = Infinity;
    const rec = (i, used, s) => {
      if (i === A.length) { best = Math.min(best, s); return; }
      for (let j = 0; j < A[0].length; j++) if (!used.has(j)) { used.add(j); rec(i + 1, used, s + A[i][j]); used.delete(j); }
    };
    rec(0, new Set(), 0);
    return best;
  };
  let seed = 7;
  const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  for (let t = 0; t < 200; t++) {
    const n = 1 + Math.floor(rnd() * 5), m = 1 + Math.floor(rnd() * 5);
    const C = Array.from({ length: n }, () => Array.from({ length: m }, () => Math.round(rnd() * 50) / 10));
    const pairs = linearSumAssignment(C);
    assert.equal(pairs.length, Math.min(n, m));
    assert.equal(new Set(pairs.map((p) => p[1])).size, pairs.length);
    assert.ok(Math.abs(pairs.reduce((s, [r, c]) => s + C[r][c], 0) - brute(C)) < 1e-9);
  }
});

test('trackPlayers reproduces players.csv and players_k3d.npy', (t) => {
  const z = fx('pose.json');
  const t0 = performance.now();
  const { rows, k3d } = trackPlayers(cam, z.frame, z.kpts, z.scores);
  const ms = performance.now() - t0;
  const ref3 = fx('players_k3d.json');
  const n = pl.frame.length;
  assert.ok(Math.abs(rows.length - n) <= 0.01 * n, `${rows.length} rows vs ${n}`);
  let okXY = 0, okK = 0, okPid = 0;
  for (let i = 0; i < Math.min(n, rows.length); i++) {
    const r = rows[i];
    if (r.frame === pl.frame[i] && r.det === pl.det[i] && Math.hypot(r.X - pl.X[i], r.Y - pl.Y[i]) < 0.01) okXY++;
    if (r.pid === pl.pid[i]) okPid++;
    if (k3d[i].every((P, j) => Math.hypot(P[0] - ref3[i][j][0], P[1] - ref3[i][j][1], P[2] - ref3[i][j][2]) < 0.02)) okK++;
  }
  t.diagnostic(`${rows.length} rows in ${ms.toFixed(0)} ms; X/Y < 1 cm ${(100 * okXY / n).toFixed(2)}%, ` +
    `k3d < 2 cm ${(100 * okK / n).toFixed(2)}%, same pid ${(100 * okPid / n).toFixed(2)}%`);
  assert.ok(okXY >= 0.99 * n);
  assert.ok(okK >= 0.99 * n);
});

test('appearanceFeature matches identity._hist on frame 300', (t) => {
  const rgba = new Uint8Array(readFileSync(new URL('frame300.rgba', dir)));
  const ref = fx('frame300.json');
  for (const r of ref.rows) {
    const f = appearanceFeature(rgba, 1024, 576, r.kpts, r.scores);
    if (!r.feature) { assert.equal(f, null, `row ${r.row}`); continue; }
    assert.ok(f, `row ${r.row}: feature missing`);
    assert.equal(f.length, r.feature.length);
    const d = Math.hypot(...f.map((v, i) => v - r.feature[i]));
    t.diagnostic(`row ${r.row}: L2 ${d.toExponential(2)}`);
    assert.ok(d < 0.05, `row ${r.row}: L2 ${d}`);
  }
});

test('assign gives the same P1..P4 as identity.assign', (t) => {
  const rows = plRows.map((r) => ({ frame: r.frame, pid: r.pid, X: r.X, Y: r.Y, side: r.side_raw, det: r.det }));
  const feats = fx('appearance.json').map((a) => (a && !a.includes(null) ? a : null));
  const t0 = performance.now();
  const { rows: out, perSide } = assign(rows, feats, fps);
  const ms = performance.now() - t0;
  let ident = 0, agree = 0, sideOk = 0;
  out.forEach((r, i) => {
    if (r.player >= 0 || pl.player[i] >= 0) { ident++; if (r.player === pl.player[i]) agree++; }
    if (r.side === pl.side[i]) sideOk++;
  });
  t.diagnostic(`per side ${JSON.stringify(perSide)}, ${ms.toFixed(0)} ms; label agreement ${(100 * agree / ident).toFixed(2)}% ` +
    `of ${ident} identified rows, side agreement ${(100 * sideOk / out.length).toFixed(2)}%`);
  assert.ok(agree >= 0.95 * ident);
  const count = new Map();
  for (const r of out) if (r.player >= 0) {
    const key = `${r.frame}:${r.side}`;
    count.set(key, (count.get(key) || 0) + 1);
    assert.ok(count.get(key) <= perSide[r.side], `frame ${r.frame}: too many identified on ${r.side}`);
  }
});

test('findHits matches hits.py (before the flight fit re-assigns sides)', (t) => {
  const ref = fx('hits.json');
  const shuttle = fx('shuttle.json'), k3d = fx('players_k3d.json');
  const t0 = performance.now();
  const hits = findHits(cam, shuttle, plRows, k3d, fps);
  const ms = performance.now() - t0;
  // entries swapped by the flight fit carry the original find_hits choice in alts[0]
  const orig = ref.map((h) => (h.side_by && h.alts ? h.alts[0] : h));
  const matched = orig.filter((h) => hits.some((m) => Math.abs(m.frame - h.frame) <= 2 && m.side === h.side)).length;
  t.diagnostic(`${hits.length} hits vs ${ref.length} in ${ms.toFixed(0)} ms; ${(100 * matched / ref.length).toFixed(1)}% matched (±2 frames, same side)`);
  assert.ok(Math.abs(hits.length - ref.length) <= 0.1 * ref.length);
  assert.ok(matched >= 0.9 * ref.length);
  for (const k of ['frame', 'pid', 'side', 'hand', 'player', 'px', 'wrist_dist', 'wrist_z', 'contact', 'kind'])
    assert.ok(k in hits[0], k);
});
