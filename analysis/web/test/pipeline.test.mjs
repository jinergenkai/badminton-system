// End-to-end: the browser pipeline on the desktop's own inference outputs reproduces the desktop report.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runPipeline } from '../src/app/pipeline.js';

const fx = (p) => JSON.parse(readFileSync(new URL(`./fixtures/danh-cau-02/${p}`, import.meta.url), 'utf8'));

test('runPipeline end to end matches the desktop report', () => {
  const calib = fx('calib.json'), pose = fx('pose.json'), cand = fx('candidates.json');
  const players = fx('players.json'), app = fx('appearance.json'), ref = fx('report.json');
  // appearance per pose detection, from the per-row fixture
  const feats = new Array(pose.frame.length).fill(null);
  players.det.forEach((d, i) => { feats[d] = app[i]; });
  const cands = cand.frame.map((f, i) => ({ frame: f, x: cand.x[i], y: cand.y[i], area: cand.area[i], score: cand.score[i] }));
  const t0 = performance.now();
  const out = runPipeline({ fps: calib.fps, width: calib.size[0], height: calib.size[1], H: calib.H, cands,
    poses: { frame: pose.frame, kpts: pose.kpts, scores: pose.scores }, feats });
  const ms = performance.now() - t0;
  const r = out.report;
  console.log(`pipeline ${Math.round(ms)} ms`, out.timings, `shots ${r.shots.length} (py ${ref.shots.length}),`,
    `rallies ${r.rallies.length} (py ${ref.rallies.length}), players`, Object.keys(r.players).join(','));
  assert.equal(Object.keys(r.players).length, Object.keys(ref.players).length);
  assert.ok(Math.abs(r.shots.length - ref.shots.length) <= 0.08 * ref.shots.length);
  for (const k of Object.keys(ref.players)) {
    assert.ok(Math.abs(r.players[k].distance_m - ref.players[k].distance_m) < 0.02 * ref.players[k].distance_m + 1, k);
  }
  const types = (rep) => rep.shots.map((s) => `${s.frame}:${s.type}`);
  const common = types(r).filter((x) => types(ref).includes(x)).length;
  console.log(`same frame and type: ${common} / ${ref.shots.length}`);
  assert.ok(common >= 0.85 * ref.shots.length);
});
