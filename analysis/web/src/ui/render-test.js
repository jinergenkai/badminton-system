// Dev page for src/ui/render.js: fixtures from test/fixtures/danh-cau-02, frame 300 as the background.
import { cameraFromCalib } from '../core/camera.js';
import { buildPoses, createRenderer, rowsFromColumns } from './render.js';

const $ = (s) => document.querySelector(s);
// a plain string: Vite rewrites `new URL('<literal>', import.meta.url)` and drops the trailing slash
const BASE = '/test/fixtures/danh-cau-02/';
const get = (f) => fetch(BASE + f).then((r) => { if (!r.ok) throw new Error(`${f}: ${r.status}`); return r; });
const json = (f) => get(f).then((r) => r.json());

const t0 = performance.now();
const [calib, shuttle, flights, report, landings, players, k3d, pose, rgba] = await Promise.all([
  json('calib.json'), json('shuttle.json'), json('flights.json'), json('report.json'), json('landings.json'),
  json('players.json'), json('players_k3d.json'), json('pose.json'), get('frame300.rgba').then((r) => r.arrayBuffer()),
]);
const [w, h] = calib.size, fps = calib.fps || 30;
const tLoad = performance.now();
const rows = rowsFromColumns(players);
const poses = buildPoses(rows, pose.kpts, pose.scores, k3d);
const tPose = performance.now();
const cam = cameraFromCalib(calib), good = flights.filter((s) => s.good);
const make = (sel) => createRenderer({
  cam, fps, width: w, height: h, shots: good, report, landings, shuttleRows: shuttle, poses, players: rows,
  layout: sel.startsWith('vertical') ? 'vertical' : 'horizontal', panelPosition: sel.endsWith('above') ? 'above' : 'below',
});
let R = make('horizontal');
const tInit = performance.now();

const bg = new OffscreenCanvas(w, h);
bg.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(rgba), w, h), 0, 0);
const out = $('#out');
const size = () => { out.width = R.compositeWidth; out.height = R.compositeHeight; };
size();
const ctx = out.getContext('2d');
const last = Math.max(...shuttle.frame, ...rows.map((r) => r.frame));
$('#frame').max = $('#num').max = last;

const info = `tải ${((tLoad - t0) / 1000).toFixed(1)} s · buildPoses ${(tPose - tLoad).toFixed(0)} ms · createRenderer ${(tInit - tPose).toFixed(0)} ms`;
function draw(f) {
  const a = performance.now();
  R.drawComposite(ctx, f, bg);
  $('#stat').textContent = `frame ${f} · ${(f / fps).toFixed(2)} s · vẽ ${(performance.now() - a).toFixed(2)} ms · ${info}`;
}
const setF = (f) => { f = Math.max(0, Math.min(last, f | 0)); $('#frame').value = $('#num').value = f; draw(f); };
$('#layout').onchange = (e) => { R = make(e.target.value); window.renderTest.R = R; size(); setF(+$('#frame').value); };
$('#frame').oninput = (e) => setF(+e.target.value);
$('#num').onchange = (e) => setF(+e.target.value);
let playing = false;
$('#play').onclick = () => {
  playing = !playing; $('#play').textContent = playing ? '❚❚' : '▶';
  const step = () => { if (!playing) return; setF(+$('#frame').value + 1); requestAnimationFrame(step); };
  step();
};

/** Times drawComposite / drawOverlay / drawPanel over a range of frames; result also on window.benchResult. */
function bench(from = 0, n = 1500) {
  const overlay = new OffscreenCanvas(w, h).getContext('2d'), panel = new OffscreenCanvas(R.panelWidth, R.panelHeight).getContext('2d');
  const stats = (a) => { a.sort((x, y) => x - y); return { mean: a.reduce((s, v) => s + v, 0) / a.length, p95: a[Math.floor(0.95 * a.length)], max: a.at(-1) }; };
  const tc = [], to = [], tp = [];
  for (let f = from; f < from + n; f++) {
    let a = performance.now(); R.drawComposite(ctx, f, bg); tc.push(performance.now() - a);
    a = performance.now(); overlay.clearRect(0, 0, w, h); R.drawOverlay(overlay, f); to.push(performance.now() - a);
    a = performance.now(); R.drawPanel(panel, f); tp.push(performance.now() - a);
  }
  ctx.getImageData(0, 0, 1, 1);                                   // flush the GPU queue once
  const r = { frames: n, composite: stats(tc), overlay: stats(to), panel: stats(tp) };
  window.benchResult = r;
  return r;
}
window.renderBench = bench;
window.renderTest = { R, setF, make, size };
$('#bench').onclick = () => {
  const r = bench();
  const f = (x) => `${x.mean.toFixed(2)} / ${x.p95.toFixed(2)} / ${x.max.toFixed(2)}`;
  $('#note').textContent = `${r.frames} frame — trung bình / p95 / max (ms): composite ${f(r.composite)} · overlay ${f(r.overlay)} · panel ${f(r.panel)}`;
};
setF(300);
