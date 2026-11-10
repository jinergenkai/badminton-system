// Players on our court: floor position from the feet, stable floor-track ids, 3D lift of every keypoint.
// Port of analysis/badminton/players.py (foot_pixel, lift, track_players).
import { W, HALF } from './camera.js';
import { linearSumAssignment } from './assign.js';

// COCO-17 keypoints
export const NOSE = 0, L_SH = 5, R_SH = 6, L_EL = 7, R_EL = 8, L_WR = 9, R_WR = 10, L_HIP = 11, R_HIP = 12,
  L_KNEE = 13, R_KNEE = 14, L_ANK = 15, R_ANK = 16;
export const BONES = [[5, 7], [7, 9], [6, 8], [8, 10], [5, 6], [5, 11], [6, 12], [11, 12], [11, 13], [13, 15], [12, 14],
  [14, 16], [0, 5], [0, 6]];

/** Foot pixel of one person: mean of the confident ankles (+4 px down to the sole), else the lowest keypoint. */
export function footPixel(k, s, thr = 0.3) {
  const ok = [L_ANK, R_ANK].filter((j) => s[j] > thr);
  if (ok.length) {
    const x = ok.reduce((a, j) => a + k[j][0], 0) / ok.length;
    const y = ok.reduce((a, j) => a + k[j][1], 0) / ok.length;
    return [x, y + 4];
  }
  let lo = 0;
  for (let j = 1; j < k.length; j++) if (k[j][1] > k[lo][1]) lo = j;   // first maximum, like np.argmax
  return [k[lo][0], k[lo][1]];
}

/** 3D points of pixels px [[x,y],...] on the vertical plane through footXY that faces the camera. */
export function lift(cam, footXY, px) {
  const C = cam.pos;
  const F = [footXY[0], footXY[1], 0];
  let nx = F[0] - C[0], ny = F[1] - C[1];
  const nn = Math.hypot(nx, ny);
  nx /= nn; ny /= nn;
  const num = nx * (F[0] - C[0]) + ny * (F[1] - C[1]);
  return px.map((p) => {
    const d = cam.ray(p);
    const t = num / (nx * d[0] + ny * d[1]);
    return [C[0] + t * d[0], C[1] + t * d[1], C[2] + t * d[2]];
  });
}

const mean = (a) => a.reduce((s, v) => s + v, 0) / a.length;

/**
 * Keep people standing on (or just around) our court and give them stable ids by floor position.
 * frames: [M] frame of each detection, kpts: [M][17][2], scores: [M][17].
 * Returns { rows: [{frame, pid, X, Y, side, nose_z, lwrist_z, rwrist_z, det}], k3d: [rows][17][3] }.
 */
export function trackPlayers(cam, frames, kpts, scores,
  { margin = 1.2, backMargin = 2.5, maxJump = 1.2, maxAge = 30 } = {}) {
  const rows = [], k3d = [];
  const byFrame = new Map();
  frames.forEach((f, i) => { if (!byFrame.has(f)) byFrame.set(f, []); byFrame.get(f).push(i); });
  const order = [...byFrame.keys()].sort((a, b) => a - b);
  let live = new Map();                                // pid -> [lastFrame, X, Y] (insertion order = Python dict)
  let nextId = 0;
  for (const f of order) {
    const cand = [];
    for (const i of byFrame.get(f)) {
      const [X, Y] = cam.toFloor(footPixel(kpts[i], scores[i]));
      if (X >= -margin && X <= W + margin && Y >= -HALF - backMargin && Y <= HALF + backMargin && mean(scores[i]) > 0.4)
        cand.push([i, X, Y]);
    }
    live = new Map([...live].filter(([, v]) => f - v[0] <= maxAge));
    const pids = [...live.keys()];
    const assigned = new Map();                        // candidate index -> pid
    if (pids.length && cand.length) {
      const cost = pids.map((p) => cand.map(([, X, Y]) => Math.hypot(live.get(p)[1] - X, live.get(p)[2] - Y)));
      for (const [r, c] of linearSumAssignment(cost))
        if (cost[r][c] < maxJump + 0.05 * (f - live.get(pids[r])[0])) assigned.set(c, pids[r]);
    }
    cand.forEach(([i, X, Y], c) => {
      let pid = assigned.get(c);
      if (pid === undefined) pid = nextId++;
      live.set(pid, [f, X, Y]);
      const P = lift(cam, [X, Y], kpts[i]);
      rows.push({ frame: f, pid, X, Y, side: Y < 0 ? 'near' : 'far',
        nose_z: P[NOSE][2], lwrist_z: P[L_WR][2], rwrist_z: P[R_WR][2], det: i });
      k3d.push(P);
    });
  }
  return { rows, k3d };
}
