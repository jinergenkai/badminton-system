// Racket-shuttle contact from the shuttle's view ray and the players' 3D wrists. Port of best_contact and
// index_players from analysis/badminton/hits.py (only what the flight step needs).
// players: column dict like players.csv (frame, pid, side, player, ...); k3d[r] = 17 COCO keypoints [X,Y,Z] (m).

export const NOSE = 0, L_WR = 9, R_WR = 10, L_ANK = 15, R_ANK = 16;

/**
 * Rows plus a frame -> [row indices] map. Bystanders (people walking past, sitting by the court) never match any
 * player's look: floor tracks that are almost never identified are dropped so their wrists cannot "hit".
 * Returns {rows (the column dict), byFrame: Map<frame, number[]>}.
 */
export function indexPlayers(players) {
  const n = players.frame.length;
  const hasPlayer = Array.isArray(players.player);
  let keep = Array.from({ length: n }, (_, i) => i);
  if (hasPlayer) {
    const tot = new Map(), idn = new Map();
    for (let i = 0; i < n; i++) {
      const p = players.pid[i];
      tot.set(p, (tot.get(p) || 0) + 1);
      idn.set(p, (idn.get(p) || 0) + (players.player[i] >= 0 ? 1 : 0));
    }
    keep = keep.filter((i) => idn.get(players.pid[i]) / tot.get(players.pid[i]) >= 0.2 || players.player[i] >= 0);
  }
  const byFrame = new Map();
  for (const i of keep) {
    const f = players.frame[i];
    if (!byFrame.has(f)) byFrame.set(f, []);
    byFrame.get(f).push(i);
  }
  return { rows: players, byFrame };
}

/**
 * Player wrist closest (in 3D) to the shuttle's view ray through px around frame f -> hit object or null.
 * opts {window=3, maxDist=1.0, minZ=0.25, side=null ('near'/'far' restricts to one half)}.
 */
export function bestContact(cam, f, px, rows, byFrame, k3d, opts = {}) {
  const { window = 3, maxDist = 1.0, minZ = 0.25, side = null } = opts;
  const d = cam.ray(px), C = cam.pos;
  let best = null, bestScore = Infinity;
  const r2 = (v) => Math.round(v * 100) / 100;
  for (let ff = f - window; ff <= f + window; ff++) {
    for (const r of byFrame.get(ff) || []) {
      if (side != null && rows.side[r] !== side) continue;
      // body height in pixels, to judge "near the racket" on the image at any depth
      const K = k3d[r];
      const [head, la, ra] = cam.project([K[NOSE], K[L_ANK], K[R_ANK]]);
      const bodyPx = Math.max(Math.hypot(head[0] - (la[0] + ra[0]) / 2, head[1] - (la[1] + ra[1]) / 2), 20.0);
      for (const [name, j] of [['L', L_WR], ['R', R_WR]]) {
        const Wp = [K[j][0] - C[0], K[j][1] - C[1], K[j][2] - C[2]];
        const along = Wp[0] * d[0] + Wp[1] * d[1] + Wp[2] * d[2];
        if (along <= 0) continue;
        const dist = Math.hypot(Wp[0] - along * d[0], Wp[1] - along * d[1], Wp[2] - along * d[2]);
        const contact = [C[0] + along * d[0], C[1] + along * d[1], C[2] + along * d[2]];
        if (contact[2] < minZ) continue;          // at floor level: picking the shuttle up, not a stroke
        // teammates stand at different depths on the same view ray: the shuttle must also be within a
        // racket length on the image
        const q = cam.project([K[j]])[0];
        const img = Math.hypot(q[0] - px[0], q[1] - px[1]) / bodyPx;
        const score = dist + 0.8 * img;
        if (dist < maxDist && score < bestScore) {
          bestScore = score;
          best = {
            frame: Math.trunc(f), pid: Math.trunc(rows.pid[r]), side: rows.side[r], hand: name,
            player: rows.player ? Math.trunc(rows.player[r]) : -1,
            px: [Math.round(px[0] * 10) / 10, Math.round(px[1] * 10) / 10],
            wrist_dist: r2(dist), wrist_z: r2(K[j][2]), contact: contact.map(r2),
          };
        }
      }
    }
  }
  return best;
}
