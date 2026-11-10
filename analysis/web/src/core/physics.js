// Shuttlecock flight physics, ported from analysis/badminton/flight.py (simulate, land, net_clearance, shot_time).
// dv/dt = g - (g / Vinf^2) |v| v   (quadratic drag; Cohen et al. 2015). Vinf ~ 6.7 m/s for feather shuttles.
import { NET_CENTRE, W } from './camera.js';

export const physics = { VINF: 6.7 };

/** Positions at ascending times t (seconds from the contact, t[0] >= 0). RK4, `sub` steps per 1/30 s. */
export function simulate(p0, v0, t, vinf = null, sub = 4) {
  const k = 9.81 / (vinf || physics.VINF) ** 2;
  const out = new Array(t.length);
  let px = p0[0], py = p0[1], pz = p0[2], vx = v0[0], vy = v0[1], vz = v0[2], now = 0;
  const acc = (x, y, z) => { const s = k * Math.sqrt(x * x + y * y + z * z); return [-s * x, -s * y, -9.81 - s * z]; };
  for (let i = 0; i < t.length; i++) {
    const ti = t[i];
    const n = Math.max(1, Math.ceil((ti - now) * 30 * sub - 1e-9));
    const h = (ti - now) / n;
    for (let j = 0; j < n; j++) {
      const a1 = acc(vx, vy, vz);
      const bx = vx + 0.5 * h * a1[0], by = vy + 0.5 * h * a1[1], bz = vz + 0.5 * h * a1[2];
      const a2 = acc(bx, by, bz);
      const cx = vx + 0.5 * h * a2[0], cy = vy + 0.5 * h * a2[1], cz = vz + 0.5 * h * a2[2];
      const a3 = acc(cx, cy, cz);
      const dx = vx + h * a3[0], dy = vy + h * a3[1], dz = vz + h * a3[2];
      const a4 = acc(dx, dy, dz);
      px += (h / 6) * (vx + 2 * bx + 2 * cx + dx);
      py += (h / 6) * (vy + 2 * by + 2 * cy + dy);
      pz += (h / 6) * (vz + 2 * bz + 2 * cz + dz);
      vx += (h / 6) * (a1[0] + 2 * a2[0] + 2 * a3[0] + a4[0]);
      vy += (h / 6) * (a1[1] + 2 * a2[1] + 2 * a3[1] + a4[1]);
      vz += (h / 6) * (a1[2] + 2 * a2[2] + 2 * a3[2] + a4[2]);
    }
    now = ti;
    out[i] = [px, py, pz];
  }
  return out;
}

/** Integrate until the shuttle reaches the floor: [time, [X, Y, 0]] or null (Python land(): dt = 1/240, t_max 4 s). */
export function land(p0, v0, tMax = 4.0, dt = 1 / 240) {
  const n = Math.round(tMax / dt);
  const t = Array.from({ length: n }, (_, i) => (i + 1) * dt);
  const P = simulate(p0, v0, t, null, 1);
  let prev = p0;
  for (let i = 0; i < n; i++) {
    if (P[i][2] <= 0) {
      const a = prev[2] / (prev[2] - P[i][2]);
      const tt = (i + a) * dt;
      return [tt, [prev[0] + a * (P[i][0] - prev[0]), prev[1] + a * (P[i][1] - prev[1]), 0]];
    }
    prev = P[i];
  }
  return null;
}

/** Height above the tape where the path crosses the net between the posts (null if it does not). */
export function netClearance(p0, v0, T, n = 80) {
  const t = Array.from({ length: n }, (_, i) => (i * Math.max(T, 1e-3)) / (n - 1));
  const P = simulate(p0, v0, t);
  for (let j = 0; j < n - 1; j++) {
    if (Math.sign(P[j][1]) !== Math.sign(P[j + 1][1])) {
      const s = P[j][1] / (P[j][1] - P[j + 1][1]);
      const x = P[j][0] + s * (P[j + 1][0] - P[j][0]);
      if (x < -0.3 || x > W + 0.3) return null;
      return P[j][2] + s * (P[j + 1][2] - P[j][2]) - NET_CENTRE;
    }
  }
  return null;
}

/** Seconds since the fitted contact for video frames (the contact is t0 off the detected hit frame). */
export function shotTime(shot, frames, fps) {
  return frames.map((f) => Math.max((f - shot.hit_frame) / fps + (shot.t0 || 0), 0));
}

/** Per-frame 3D positions of a fitted shot for rendering: [frames, positions]. */
export function positions(shot, fps) {
  const fr = [];
  for (let f = shot.hit_frame; f <= shot.end_frame; f++) fr.push(f);
  const P = simulate(shot.p0, shot.v0, shotTime(shot, fr, fps));
  if (shot.landing) for (const p of P) p[2] = Math.max(p[2], 0);
  return [fr, P];
}
