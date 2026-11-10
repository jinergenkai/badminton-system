// node --test analysis/web/test/render.test.mjs   (pure parts of src/ui/render.js; no canvas needed)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildPoses, posesAt, fillShort, smoothNaN } from '../src/ui/render.js';

// One player (0) plus a bystander (-1); every row has its own detection.
function synth(n, { missing = () => false, jointOk = () => true, value = (f, j) => [100 + f + j, 200 + j] } = {}) {
  const players = [], kpts = [], scores = [], k3d = [];
  for (let f = 0; f < n; f++) {
    for (const player of [0, -1]) {
      if (player === 0 && missing(f)) continue;
      const det = kpts.length;
      kpts.push(Array.from({ length: 17 }, (_, j) => value(f, j)));
      scores.push(Array.from({ length: 17 }, (_, j) => (player === 0 && !jointOk(f, j) ? 0.1 : 0.9)));
      k3d.push(Array.from({ length: 17 }, (_, j) => [1 + 0.01 * f, -2, 0.1 * j]));
      players.push({ frame: f, det, player });
    }
  }
  return { players, kpts, scores, k3d };
}

const visibleFrames = (poses, n) => Array.from({ length: n }, (_, f) => f).filter((f) => posesAt(poses, f).length);

test('fills a 5-frame gap, not a 20-frame gap', () => {
  const a = synth(60, { missing: (f) => (f >= 10 && f < 15) || (f >= 30 && f < 50) });
  const poses = buildPoses(a.players, a.kpts, a.scores, a.k3d);
  assert.deepEqual([...poses.keys()], [0], 'only identified players');
  const vis = new Set(visibleFrames(poses, 60));
  for (let f = 10; f < 15; f++) assert.ok(vis.has(f), `frame ${f} filled`);
  for (let f = 30; f < 50; f++) assert.ok(!vis.has(f), `frame ${f} not filled`);
  // the filled values follow the linear motion
  const k2 = posesAt(poses, 12)[0].k2;
  assert.ok(Math.abs(k2[3][0] - (100 + 12 + 3)) < 0.5, `x ${k2[3][0]}`);
  const k3 = posesAt(poses, 12)[0].k3;
  assert.ok(Math.abs(k3[3][0] - 1.12) < 0.01);
});

test('fillShort leaves edges and long runs alone', () => {
  const a = Float64Array.from([NaN, 1, NaN, NaN, 4, NaN, NaN, NaN, NaN, 9, NaN]);
  const r = fillShort(a.slice(), 3);
  assert.deepEqual(Array.from(r.slice(1, 5)), [1, 2, 3, 4]);
  assert.ok(Number.isNaN(r[0]) && Number.isNaN(r[6]) && Number.isNaN(r[10]));
});

test('smoothing reduces jitter on a noisy track', () => {
  let seed = 7;
  const rnd = () => { seed = (seed * 1103515245 + 12345) % 2 ** 31; return seed / 2 ** 31 - 0.5; };
  const truth = (f) => 300 + 80 * Math.sin(f / 15);
  const noise = Array.from({ length: 200 }, () => 8 * rnd());
  const a = synth(200, { value: (f, j) => [truth(f) + noise[f], 200 + j] });
  const poses = buildPoses(a.players, a.kpts, a.scores, a.k3d);
  const raw = [], sm = [];
  for (let f = 5; f < 195; f++) { raw.push(truth(f) + noise[f]); sm.push(posesAt(poses, f)[0].k2[0][0]); }
  const err = (a) => a.reduce((t, v, i) => t + Math.abs(v - truth(i + 5)), 0);
  // jitter = mean |second difference| (the true motion is slow, so this is almost all noise)
  const jit = (a) => a.slice(1, -1).reduce((t, v, i) => t + Math.abs(a[i] - 2 * v + a[i + 2]), 0);
  assert.ok(err(sm) < 0.6 * err(raw), `error ${err(sm).toFixed(1)} vs ${err(raw).toFixed(1)}`);
  assert.ok(jit(sm) < 0.3 * jit(raw), `jitter ${jit(sm).toFixed(1)} vs ${jit(raw).toFixed(1)}`);
  // NaN-aware: a NaN sample does not poison its neighbours
  const s = smoothNaN(Float64Array.from([1, 1, NaN, 1, 1]), 1.2);
  assert.ok(Number.isNaN(s[2]) && Math.abs(s[1] - 1) < 1e-9 && Math.abs(s[3] - 1) < 1e-9);
});

test('posesAt returns only frames with >= 8 joints', () => {
  // joints 0..6 always good; joints 7..16 only before frame 20 -> 7 joints from frame 20 on
  const a = synth(60, { jointOk: (f, j) => j < 7 || f < 20 });
  const poses = buildPoses(a.players, a.kpts, a.scores, a.k3d);
  const vis = visibleFrames(poses, 60);
  assert.deepEqual(vis, Array.from({ length: 20 }, (_, f) => f));
  const p = posesAt(poses, 5)[0];
  assert.equal(p.player, 0);
  assert.equal(p.k2.length, 17);
  assert.equal(p.k3.length, 17);
  assert.equal(posesAt(poses, 25).length, 0);
  assert.equal(posesAt(poses, 25, 7).length, 1);
});

test('headOf finds the head from the nose, the eyes/ears, or above the shoulders (back view)', async () => {
  const { headOf } = await import('../src/ui/render.js');
  const k = Array(17).fill(null);
  k[5] = [100, 100]; k[6] = [140, 100]; k[11] = [105, 180]; k[12] = [135, 180];
  const back = headOf(k, false);
  assert.ok(back && back.p[1] < 100 && Math.abs(back.p[0] - 120) < 1);
  k[3] = [115, 70]; k[4] = [125, 70];
  assert.deepEqual(headOf(k, false).p, [120, 70]);
  k[0] = [120, 72];
  assert.deepEqual(headOf(k, false).p, [120, 72]);
  const k3 = Array(17).fill(null);
  k3[5] = [1, 0, 1.4]; k3[6] = [1.4, 0, 1.4]; k3[11] = [1.05, 0, 0.9]; k3[12] = [1.35, 0, 0.9];
  assert.ok(headOf(k3, true).p[2] > 1.5);
});
