// node --test analysis/web/test/   (fixtures: python analysis/tools/export_fixtures.py danh-cau-02)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { analyse, playerTracks, pyRound } from '../src/core/analytics.js';
import { reportHtml } from '../src/core/report.js';

const fx = (p) => JSON.parse(readFileSync(new URL(`./fixtures/danh-cau-02/${p}`, import.meta.url), 'utf8'));
const ref = fx('report.json');
const pose = fx('pose.json');
const cols = fx('players.json');
const rows = cols.frame.map((_, i) => Object.fromEntries(Object.keys(cols).map((k) => [k, cols[k][i]])));
const input = {
  shots: fx('flights.json'), hits: fx('hits.json'), players: rows, k3d: fx('players_k3d.json'),
  kpts: pose.kpts, scores: pose.scores, landings: fx('landings.json'), fps: fx('calib.json').fps,
};
const t0 = performance.now();
const rep = analyse(input);
const ms = performance.now() - t0;

const rel = (a, b) => Math.abs(a - b) <= 1e-6 * Math.max(Math.abs(b), 1e-9);
const agree = (key) => rep.shots.filter((c, i) => c[key] === ref.shots[i][key]).length / ref.shots.length;

test('pyRound follows Python round()', () => {
  assert.equal(pyRound(2.5), 2);
  assert.equal(pyRound(3.5), 4);
  assert.equal(pyRound(0.125, 2), 0.12);
  assert.equal(pyRound(0.375, 2), 0.38);
  assert.equal(pyRound(2.675, 2), 2.67);                 // binary value is below the tie
  assert.equal(pyRound(1.005, 2), 1);
});

test('playerTracks: one sorted track per identified player', () => {
  const tr = playerTracks(rows, 30);
  assert.deepEqual(Object.keys(tr), ['0', '1', '2', '3']);
  for (const t of Object.values(tr)) {
    for (let k = 1; k < t.frame.length; k++) assert.ok(t.frame[k] > t.frame[k - 1]);
    assert.equal(t.X.length, t.frame.length);
    assert.equal(t.speed[0], 0);
  }
});

test(`analyse reproduces report.json shots and rallies (${ms.toFixed(0)} ms)`, () => {
  assert.equal(rep.shots.length, ref.shots.length);
  assert.equal(rep.rallies.length, ref.rallies.length);
  assert.deepEqual(rep.rallies, ref.rallies);
  assert.deepEqual(rep.summary, ref.summary);
  const types = agree('type');
  assert.ok(types >= 0.97, `shot type agreement ${types}`);
  rep.shots.forEach((c, i) => {
    const r = ref.shots[i];
    for (const k of ['speed_kmh', 'apex_m', 'contact_height_m', 'mean_speed_kmh', 'launch_angle_deg', 'flight_s']) {
      assert.ok(rel(c[k], r[k]), `shot ${i} ${k}: ${c[k]} vs ${r[k]}`);
    }
    assert.equal(c.player, r.player, `shot ${i} player`);
    assert.equal(c.speed_reliable, r.speed_reliable, `shot ${i} speed_reliable`);
  });
  assert.ok(agree('jump') >= 0.95, `jump agreement ${agree('jump')}`);
  assert.ok(agree('stroke_side') >= 0.95, `stroke_side agreement ${agree('stroke_side')}`);
});

test('analyse reproduces the per-player stats', () => {
  assert.deepEqual(Object.keys(rep.players).sort(), Object.keys(ref.players).sort());
  for (const [k, r] of Object.entries(ref.players)) {
    const p = rep.players[k];
    assert.ok(Math.abs(p.distance_m - r.distance_m) <= 0.01 * r.distance_m, `${k} distance ${p.distance_m} vs ${r.distance_m}`);
    const a = p.at_opponent_contact, b = r.at_opponent_contact;
    assert.ok(Math.abs(a.ready_stance_pct - b.ready_stance_pct) <= 1, `${k} ready ${a.ready_stance_pct} vs ${b.ready_stance_pct}`);
    if (b.reaction_s === null) assert.equal(a.reaction_s, null);
    else assert.ok(Math.abs(a.reaction_s - b.reaction_s) <= 0.02, `${k} reaction ${a.reaction_s} vs ${b.reaction_s}`);
    assert.deepEqual(p.smash_kmh, r.smash_kmh);
    assert.deepEqual(p.shot_types, r.shot_types);         // deepEqual ignores key order (pandas tie order)
    assert.equal(p.side, r.side);
    assert.equal(p.dominant_hand, r.dominant_hand);
  }
});

test('reportHtml renders every player and shot', () => {
  const html = reportHtml(rep, 'danh-cau-02');
  assert.ok(html.length > 1000);
  assert.ok(html.startsWith('<section class="report">'));
  for (const k of Object.keys(rep.players)) assert.ok(html.includes(`>${k}</span>`), k);
  assert.equal((html.match(/<tr class="type-/g) || []).length, rep.shots.length);
  assert.ok(html.includes('class="kpi"') && html.includes('table class="players"') && html.includes('table class="shots"'));
  if (rep.shots.some((c) => !c.speed_reliable)) assert.ok(/<tr class="[^"]*unreliable/.test(html) && html.includes('~'));
  assert.ok(!/style=/.test(html));
});
