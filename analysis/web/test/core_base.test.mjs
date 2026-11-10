// node --test analysis/web/test/   (fixtures: python analysis/tools/export_fixtures.py danh-cau-02)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { cameraFromCalib, calibrateFromHomography } from '../src/core/camera.js';
import { simulate, land, netClearance } from '../src/core/physics.js';

const fx = (p) => JSON.parse(readFileSync(new URL(`./fixtures/${p}`, import.meta.url), 'utf8'));
const calib = fx('danh-cau-02/calib.json');

test('camera from calib reproduces the Python projections and rays', () => {
  const cam = cameraFromCalib(calib);
  cam.project(calib.check.points).forEach((q, i) => {
    assert.ok(Math.hypot(q[0] - calib.check.pixels[i][0], q[1] - calib.check.pixels[i][1]) < 0.01);
  });
  calib.check.ray_px.forEach((px, i) => {
    const d = cam.ray(px);
    d.forEach((v, j) => assert.ok(Math.abs(v - calib.check.rays[i][j]) < 1e-6));
  });
  cam.pos.forEach((v, j) => assert.ok(Math.abs(v - calib.pos[j]) < 1e-6));
});

test('camera from the floor homography matches calibrate.py (focal, position, projections)', () => {
  const cam = calibrateFromHomography(calib.H, calib.size[0], calib.size[1]);
  assert.ok(Math.abs(cam.K[0][0] - calib.K[0][0]) / calib.K[0][0] < 0.01, `f ${cam.K[0][0]} vs ${calib.K[0][0]}`);
  assert.ok(Math.hypot(...cam.pos.map((v, j) => v - calib.pos[j])) < 0.05, `pos ${cam.pos} vs ${calib.pos}`);
  cam.project(calib.check.points).forEach((q, i) => {
    const e = Math.hypot(q[0] - calib.check.pixels[i][0], q[1] - calib.check.pixels[i][1]);
    assert.ok(e < 1.5, `point ${i}: ${e.toFixed(2)} px`);
  });
});

test('physics matches flight.py (simulate, land, net clearance)', () => {
  const ref = fx('physics_ref.json');
  const p0 = [2.7, -1.3, 1.27], v0 = [-2.0, 7.1, 3.4];
  simulate(p0, v0, [0.1, 0.5, 1.0]).forEach((p, i) => p.forEach((v, j) => assert.ok(Math.abs(v - ref.sim[i][j]) < 1e-9)));
  const L = land(p0, v0);
  assert.ok(Math.abs(L[0] - ref.land[0]) < 1e-9);
  L[1].forEach((v, j) => assert.ok(Math.abs(v - ref.land[1][j]) < 1e-9));
  assert.ok(Math.abs(netClearance(p0, v0, 1.0) - ref.net) < 1e-9);
});

test('court fit snaps the clicks onto the white lines like calibrate.py', async () => {
  const { fitCourt } = await import('../src/core/courtfit.js');
  const s = fx('danh-cau-02/seeds.json');
  const rgba = new Uint8Array(readFileSync(new URL('./fixtures/danh-cau-02/background.rgba', import.meta.url)));
  const t0 = performance.now();
  const r = fitCourt(rgba, s.size[0], s.size[1], s.seeds, { floorTop: s.floor_top });
  const ms = performance.now() - t0;
  const H = r.H, P = calib.H;
  const proj = (M, X, Y) => { const z = M[2][0] * X + M[2][1] * Y + M[2][2]; return [(M[0][0] * X + M[0][1] * Y + M[0][2]) / z, (M[1][0] * X + M[1][1] * Y + M[1][2]) / z]; };
  const errs = [[0, -1.98], [6.1, -1.98], [6.1, 6.7], [0, 6.7], [3.05, 1.98], [0.46, -5.94]].map(([X, Y]) => {
    const a = proj(H, X, Y), b = proj(P, X, Y); return Math.hypot(a[0] - b[0], a[1] - b[1]);
  });
  console.log(`court fit: cost ${r.seedCost.toFixed(2)} -> ${r.cost.toFixed(2)} px (python ${calib.fit_cost_px}), vs python H: ${errs.map((e) => e.toFixed(1)).join(' ')} px, ${ms.toFixed(0)} ms`);
  assert.ok(r.cost < r.seedCost);
  assert.ok(Math.max(...errs) < 4);
});
