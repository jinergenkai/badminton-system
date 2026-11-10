// The full analysis after inference, in the browser: the same steps as `python -m badminton`
// (track -> players -> identity -> hits -> flight -> landing -> analytics), on the visitor's CPU.
import { calibrateFromHomography, courtVolumePolygon } from '../core/camera.js';
import { buildTracks, select } from '../core/track.js';
import { trackPlayers } from '../core/players.js';
import { assign } from '../core/identity.js';
import { findHits } from '../core/hits.js';
import { fitOptions, fitRally, recoverMissed } from '../core/flight.js';
import { analyse } from '../core/analytics.js';

const toCols = (rows) => {
  const keys = Object.keys(rows[0] || {});
  const out = {};
  for (const k of keys) out[k] = rows.map((r) => r[k]);
  return out;
};

/**
 * input: {fps, width, height, H (court -> image homography),
 *         cands: [{frame, x, y, area, score}] in video pixels,
 *         poses: {frame: [], kpts: [[17][2]], scores: [[17]]},  feats: per pose detection (or null)}
 * opts:  {poseEvery (frames between pose runs), starts, maxNfev}
 * progress(label, frac) is called between steps.
 */
export function runPipeline(input, opts = {}, progress = () => {}) {
  const { fps, width, height, H, cands, poses, feats } = input;
  const t = {};
  const step = (name, fn) => { const t0 = performance.now(); const r = fn(); t[name] = Math.round(performance.now() - t0); return r; };

  progress('Dựng camera và theo dõi đường cầu', 0.02);
  const cam = calibrateFromHomography(H, width, height);
  const shuttle = step('track', () => select(buildTracks(cands, courtVolumePolygon(cam), { size: [width, height] })));

  progress('Người chơi trên sân', 0.08);
  const { rows: raw, k3d } = step('players', () => trackPlayers(cam, poses.frame, poses.kpts, poses.scores));
  progress('Nhận diện P1–P4 theo màu áo', 0.15);
  const { rows: players, perSide } = step('identity', () => assign(raw, raw.map((r) => feats?.[r.det] ?? null), fps));

  progress('Tìm cú chạm vợt', 0.3);
  // pose may run every few frames only: widen the window a contact looks for a wrist in
  const window = Math.max(3, Math.ceil((opts.poseEvery || 1) / 2) + 1);
  const hits = step('hits', () => findHits(cam, shuttle, players, k3d, fps, { window }));

  progress('Khớp đường bay 3D theo vật lý', 0.35);
  if (opts.starts) fitOptions.starts = opts.starts;
  if (opts.maxNfev) fitOptions.maxNfev = opts.maxNfev;
  let shots = step('flight', () => fitRally(cam, shuttle, hits, fps));
  progress('Khôi phục cú bị sót', 0.85);
  const [all, recovered] = step('recover', () => recoverMissed(cam, shots, shuttle, hits, toCols(players), k3d, fps));
  shots = all;

  // physics landings of the well-fitted final shots (the desktop also finds a still shuttle on the floor)
  const landings = shots.filter((s) => s.good && s.landing).map((s) => ({
    frame: s.landing.frame, court: s.landing.court, in: s.landing.in, source: 'physics fit',
    px: cam.project([[s.landing.court[0], s.landing.court[1], 0]])[0],
    extrapolated_s: Math.round(((s.landing.frame - s.fit_last_frame) / fps) * 100) / 100,
  }));

  progress('Phân tích trận', 0.95);
  const report = step('analytics', () => analyse({ shots, hits, players, k3d, kpts: poses.kpts, scores: poses.scores, landings, fps }));
  progress('Xong', 1);
  return {
    camera: { K: cam.K, R: cam.R, t: cam.t, H: cam.H, size: cam.size, pos: cam.pos },
    shuttle, players, k3d, hits, shots, landings, report, perSide, recovered, timings: t,
  };
}
