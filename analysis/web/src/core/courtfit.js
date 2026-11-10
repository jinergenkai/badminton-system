// Snap the court model onto the painted white lines (chamfer matching), ported from calibrate.py / background.py.
// Input: the empty-court median background (RGBA) and >= 4 rough clicks (court metres -> pixel).
import { W, HALF } from './camera.js';

const NEAR = [[0, -HALF], [W, -HALF]];
export function courtLines() {
  const L = [];
  for (const x of [0, 0.46, W - 0.46, W]) L.push([[x, -HALF], [x, HALF]]);
  for (const s of [-1, 1]) {
    L.push([[0, s * HALF], [W, s * HALF]], [[0, s * (HALF - 0.76)], [W, s * (HALF - 0.76)]],
      [[0, s * 1.98], [W, s * 1.98]], [[W / 2, s * 1.98], [W / 2, s * HALF]]);
  }
  return L;
}
void NEAR;

/** White, unsaturated, *thin* strokes: (S < 60 and V > 170) minus its 11x11 opening (wide floor glare). */
export function thinWhite(rgba, w, h, floorTop = 0) {
  const m = new Uint8Array(w * h);
  for (let i = 0, j = 0; i < w * h; i++, j += 4) {
    const r = rgba[j], g = rgba[j + 1], b = rgba[j + 2];
    const v = Math.max(r, g, b), mn = Math.min(r, g, b);
    const s = v === 0 ? 0 : ((v - mn) * 255) / v;
    m[i] = s < 60 && v > 170 && i >= floorTop * w ? 1 : 0;
  }
  const open = dilate(erode(m, w, h, 5), w, h, 5);
  for (let i = 0; i < m.length; i++) m[i] = m[i] && !open[i] ? 1 : 0;
  return m;
}

function boxMin(src, w, h, r, horizontal, isMax) {
  const out = new Uint8Array(w * h);
  for (let a = 0; a < (horizontal ? h : w); a++) {
    const n = horizontal ? w : h;
    for (let b = 0; b < n; b++) {
      let v = isMax ? 0 : 1;
      for (let k = Math.max(0, b - r); k <= Math.min(n - 1, b + r); k++) {
        const x = horizontal ? src[a * w + k] : src[k * w + a];
        if (isMax ? x : !x) { v = isMax ? 1 : 0; break; }
      }
      out[horizontal ? a * w + b : b * w + a] = v;
    }
  }
  return out;
}
const erode = (m, w, h, r) => boxMin(boxMin(m, w, h, r, true, false), w, h, r, false, false);
const dilate = (m, w, h, r) => boxMin(boxMin(m, w, h, r, true, true), w, h, r, false, true);

/** Exact Euclidean distance to the nearest set pixel (Felzenszwalb & Huttenlocher). */
export function distanceMap(mask, w, h) {
  const INF = 1e12;
  const f = new Float64Array(Math.max(w, h)), d = new Float64Array(Math.max(w, h));
  const v = new Int32Array(Math.max(w, h)), z = new Float64Array(Math.max(w, h) + 1);
  const g = new Float64Array(w * h);
  const dt1 = (n) => {
    let k = 0; v[0] = 0; z[0] = -INF; z[1] = INF;
    for (let q = 1; q < n; q++) {
      let s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
      while (s <= z[k]) { k--; s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]); }
      k++; v[k] = q; z[k] = s; z[k + 1] = INF;
    }
    k = 0;
    for (let q = 0; q < n; q++) { while (z[k + 1] < q) k++; d[q] = (q - v[k]) ** 2 + f[v[k]]; }
  };
  for (let x = 0; x < w; x++) {
    for (let y = 0; y < h; y++) f[y] = mask[y * w + x] ? 0 : INF;
    dt1(h);
    for (let y = 0; y < h; y++) g[y * w + x] = d[y];
  }
  const out = new Float32Array(w * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) f[x] = g[y * w + x];
    dt1(w);
    for (let x = 0; x < w; x++) out[y * w + x] = Math.sqrt(d[x]);
  }
  return out;
}

/** Least-squares homography (h33 = 1) from >= 4 correspondences. */
export function homographyFrom(src, dst) {
  const M = Array.from({ length: 8 }, () => new Array(9).fill(0));
  for (let i = 0; i < src.length; i++) {
    const [x, y] = src[i], [u, v] = dst[i];
    for (const [row, rhs] of [[[x, y, 1, 0, 0, 0, -u * x, -u * y], u], [[0, 0, 0, x, y, 1, -v * x, -v * y], v]]) {
      for (let a = 0; a < 8; a++) { for (let b = 0; b < 8; b++) M[a][b] += row[a] * row[b]; M[a][8] += row[a] * rhs; }
    }
  }
  for (let c = 0; c < 8; c++) {
    let p = c;
    for (let r = c + 1; r < 8; r++) if (Math.abs(M[r][c]) > Math.abs(M[p][c])) p = r;
    [M[c], M[p]] = [M[p], M[c]];
    if (Math.abs(M[c][c]) < 1e-12) return null;
    for (let r = 0; r < 8; r++) if (r !== c) { const k = M[r][c] / M[c][c]; for (let j = c; j < 9; j++) M[r][j] -= k * M[c][j]; }
  }
  const h = M.map((r, i) => r[8] / r[i]);
  return [[h[0], h[1], h[2]], [h[3], h[4], h[5]], [h[6], h[7], 1]];
}

function nelderMead(fn, x0, step, { maxIter = 4000, tol = 1e-7 } = {}) {
  const n = x0.length;
  let simplex = [x0.slice()];
  for (let i = 0; i < n; i++) { const x = x0.slice(); x[i] += step[i]; simplex.push(x); }
  let vals = simplex.map(fn);
  for (let it = 0; it < maxIter; it++) {
    const ord = vals.map((v, i) => i).sort((a, b) => vals[a] - vals[b]);
    simplex = ord.map((i) => simplex[i]); vals = ord.map((i) => vals[i]);
    if (Math.abs(vals[n] - vals[0]) < tol * (Math.abs(vals[0]) + 1e-9)) break;
    const c = new Array(n).fill(0);
    for (let i = 0; i < n; i++) for (let j = 0; j < n; j++) c[j] += simplex[i][j] / n;
    const at = (t) => c.map((v, j) => v + t * (simplex[n][j] - v));
    const xr = at(-1), fr = fn(xr);
    if (fr < vals[0]) { const xe = at(-2), fe = fn(xe); if (fe < fr) { simplex[n] = xe; vals[n] = fe; } else { simplex[n] = xr; vals[n] = fr; } }
    else if (fr < vals[n - 1]) { simplex[n] = xr; vals[n] = fr; }
    else {
      const xc = at(fr < vals[n] ? -0.5 : 0.5), fc = fn(xc);
      if (fc < Math.min(fr, vals[n])) { simplex[n] = xc; vals[n] = fc; }
      else for (let i = 1; i <= n; i++) { simplex[i] = simplex[i].map((v, j) => simplex[0][j] + 0.5 * (v - simplex[0][j])); vals[i] = fn(simplex[i]); }
    }
  }
  return { x: simplex[0], fun: vals[0] };
}

/**
 * Refine the homography so every court line lies on a thin white stroke, staying near the clicks.
 * Returns {H, cost, seedCost} (cost = mean chamfer distance in px, capped at 12).
 */
export function fitCourt(rgba, w, h, seeds, { floorTop = 0 } = {}) {
  const dist = distanceMap(thinWhite(rgba, w, h, floorTop), w, h);
  const courtPts = seeds.map((s) => s[0]), imgPts = seeds.map((s) => s[1]);
  const H0 = homographyFrom(courtPts, imgPts);
  const samples = [];
  for (const [a, b] of courtLines()) for (let i = 0; i < 120; i++) {
    const t = i / 119;
    samples.push([a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])]);
  }
  const cost = (p) => {
    const H = [[p[0], p[1], p[2]], [p[3], p[4], p[5]], [p[6], p[7], 1]];
    let sum = 0, n = 0;
    for (const [X, Y] of samples) {
      const qz = H[2][0] * X + H[2][1] * Y + 1;
      if (qz <= 1e-6) continue;
      const x = (H[0][0] * X + H[0][1] * Y + H[0][2]) / qz, y = (H[1][0] * X + H[1][1] * Y + H[1][2]) / qz;
      if (x < 0 || x >= w - 1 || y < floorTop || y >= h - 1) continue;
      sum += Math.min(dist[(y | 0) * w + (x | 0)], 12); n++;
    }
    if (n < 150) return 1e6;
    let anchor = 0;
    courtPts.forEach(([X, Y], i) => {
      const qz = H[2][0] * X + H[2][1] * Y + 1;
      const u = (H[0][0] * X + H[0][1] * Y + H[0][2]) / qz, v = (H[1][0] * X + H[1][1] * Y + H[1][2]) / qz;
      anchor += Math.max(Math.hypot(u - imgPts[i][0], v - imgPts[i][1]) - 25, 0);
    });
    return sum / n + 0.05 * anchor;
  };
  const p0 = H0.flat().slice(0, 8);
  const seedCost = cost(p0);
  let best = { x: p0, fun: seedCost };
  // Powell in Python; Nelder-Mead restarts here, each from the best so far with a shrinking simplex
  for (const scale of [0.03, 0.01, 0.003]) {
    const r = nelderMead(cost, best.x, best.x.map((v) => scale * (Math.abs(v) + 1e-4)));
    if (r.fun < best.fun) best = r;
  }
  const p = best.x;
  return { H: [[p[0], p[1], p[2]], [p[3], p[4], p[5]], [p[6], p[7], 1]], cost: best.fun, seedCost };
}
