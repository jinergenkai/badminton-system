// node --test analysis/web/test/   (fixtures: python analysis/tools/export_fixtures.py danh-cau-02)
// Port checks of track.py / flight.py against the Python outputs of one 150 s video.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { cameraFromCalib, courtVolumePolygon } from '../src/core/camera.js';
import { simulate } from '../src/core/physics.js';
import { buildTracks, select, toRows } from '../src/core/track.js';
import { fitShot, fitRally, recoverMissed } from '../src/core/flight.js';

const fx = (p) => JSON.parse(readFileSync(new URL(`./fixtures/danh-cau-02/${p}`, import.meta.url), 'utf8'));
const calib = fx('calib.json');
const cam = cameraFromCalib(calib);
const fps = calib.fps;
const median = (a) => { const s = [...a].sort((x, y) => x - y), m = s.length >> 1; return s.length % 2 ? s[m] : 0.5 * (s[m - 1] + s[m]); };

test('track: buildTracks + select on the candidates reproduce shuttle.json', () => {
  const t = performance.now();
  const rows = select(buildTracks(fx('candidates.json'), courtVolumePolygon(cam), { size: calib.size }));
  const ref = toRows(fx('shuttle.json'));
  const nMine = rows.filter((r) => r.detected).length, nRef = ref.filter((r) => r.detected).length;
  console.log(`  track: ${nMine} detected (python ${nRef}), ${rows.length} rows (python ${ref.length}), ${(performance.now() - t).toFixed(0)} ms`);
  assert.ok(Math.abs(nMine - nRef) / nRef < 0.02, `detected ${nMine} vs ${nRef}`);
  const byF = new Map(ref.map((r) => [r.frame, r]));
  const d = rows.filter((r) => byF.has(r.frame)).map((r) => Math.hypot(r.x - byF.get(r.frame).x, r.y - byF.get(r.frame).y));
  assert.ok(d.length / ref.length > 0.98 && median(d) < 0.5);
});

test('flight: fitRally + recoverMissed match flights.json', () => {
  const shuttle = toRows(fx('shuttle.json')), hits = fx('hits.json'), ref = fx('flights.json');
  const players = fx('players.json'), k3d = fx('players_k3d.json');
  let t = performance.now();
  const shots = fitRally(cam, shuttle, hits, fps);
  const tRally = performance.now() - t;
  t = performance.now();
  const [all, added] = recoverMissed(cam, shots, shuttle, hits, players, k3d, fps);
  const tRec = performance.now() - t;
  const good = all.filter((s) => s.good), refGood = ref.filter((s) => s.good);
  const rm = new Map(refGood.map((s) => [s.hit_frame, s]));
  const pairs = good.filter((s) => rm.has(s.hit_frame)).map((s) => [s, rm.get(s.hit_frame)]);
  const dSpeed = median(pairs.map(([s, r]) => Math.abs(s.speed_kmh - r.speed_kmh) / r.speed_kmh));
  const dP0 = median(pairs.map(([s, r]) => Math.hypot(...s.p0.map((v, j) => v - r.p0[j]))));
  const mPx = median(good.map((s) => s.median_px));
  console.log(`  fitRally ${tRally.toFixed(0)} ms (${shots.length - added} shots), recoverMissed ${tRec.toFixed(0)} ms (+${added})`);
  console.log(`  good ${good.length} (python ${refGood.length}), matched ${pairs.length}, median |dspeed|/speed ${(100 * dSpeed).toFixed(1)}%,`
    + ` median |dp0| ${dP0.toFixed(3)} m, median median_px ${mPx.toFixed(2)}`);
  assert.ok(Math.abs(good.length - refGood.length) / refGood.length <= 0.08, `good ${good.length} vs ${refGood.length}`);
  assert.ok(dSpeed < 0.10, `speed ${dSpeed}`);
  assert.ok(dP0 < 0.3, `p0 ${dP0}`);
  assert.ok(mPx < 3, `px ${mPx}`);
  // same keys as the Python output
  const keys = new Set(ref.flatMap((s) => Object.keys(s)));
  for (const s of all) for (const k of Object.keys(s)) assert.ok(keys.has(k), `unexpected key ${k}`);
});

test('flight: a synthetic shot is recovered (speed within 5%, contact within 0.2 m)', () => {
  const p0 = [3.0, -4.0, 2.2], v0 = [-1.0, 20.0, 9.0];
  const frames = Array.from({ length: 24 }, (_, i) => 101 + i);
  const P = simulate(p0, v0, frames.map((f) => (f - 100) / fps));
  // deterministic +-0.5 px noise
  const px = cam.project(P).map(([x, y], i) => [x + 0.5 * Math.sin(1.7 * i), y + 0.5 * Math.cos(2.3 * i)]);
  const hit = { frame: 100, pid: 0, side: 'near', player: 0, hand: 'R', contact: [3.08, -4.06, 2.15] };   // racket estimate ~0.1 m off
  const t = performance.now();
  const r = fitShot(cam, frames, px, fps, hit);
  const speed = Math.hypot(...v0) * 3.6;
  const dp = Math.hypot(...r.p0.map((v, j) => v - p0[j]));
  console.log(`  synthetic: ${r.speed_kmh} km/h (true ${speed.toFixed(1)}), |dp0| ${dp.toFixed(3)} m, ${r.median_px} px,`
    + ` sd ${r.speed_sd_kmh} km/h, ${(performance.now() - t).toFixed(0)} ms`);
  assert.ok(r.good);
  assert.ok(Math.abs(r.speed_kmh - speed) / speed < 0.05);
  assert.ok(dp < 0.2);
});
