// Court geometry (same coordinate system as the desktop pipeline, metres):
// X across the court 0..6.1 (doubles sidelines), Y along it, 0 = net, negative = camera half.
export const COURT_W = 6.1;
export const HALF_L = 6.7;

// 4 corners the user clicks, in this order
export const CORNERS = [
  { name: 'Góc gần – trái', court: [0, -HALF_L] },
  { name: 'Góc gần – phải', court: [COURT_W, -HALF_L] },
  { name: 'Góc xa – phải', court: [COURT_W, HALF_L] },
  { name: 'Góc xa – trái', court: [0, HALF_L] },
];

export const COURT_LINES = (() => {
  const L = [];
  for (const x of [0, 0.46, 5.64, COURT_W]) L.push([[x, -HALF_L], [x, HALF_L]]);
  for (const y of [-HALF_L, -5.94, -1.98, 1.98, 5.94, HALF_L]) L.push([[0, y], [COURT_W, y]]);
  L.push([[3.05, 1.98], [3.05, HALF_L]], [[3.05, -1.98], [3.05, -HALF_L]]);
  return L;
})();
export const NET = [[-0.3, 0], [COURT_W + 0.3, 0]];

// Solve 8 unknowns of H (h33 = 1) from >= 4 correspondences src -> dst (least squares via normal equations)
export function homography(src, dst) {
  const A = [], b = [];
  for (let i = 0; i < src.length; i++) {
    const [x, y] = src[i], [u, v] = dst[i];
    A.push([x, y, 1, 0, 0, 0, -u * x, -u * y]); b.push(u);
    A.push([0, 0, 0, x, y, 1, -v * x, -v * y]); b.push(v);
  }
  const M = Array.from({ length: 8 }, () => new Array(9).fill(0));
  for (let r = 0; r < A.length; r++) for (let i = 0; i < 8; i++) {
    for (let j = 0; j < 8; j++) M[i][j] += A[r][i] * A[r][j];
    M[i][8] += A[r][i] * b[r];
  }
  for (let c = 0; c < 8; c++) {
    let p = c;
    for (let r = c + 1; r < 8; r++) if (Math.abs(M[r][c]) > Math.abs(M[p][c])) p = r;
    [M[c], M[p]] = [M[p], M[c]];
    if (Math.abs(M[c][c]) < 1e-12) return null;
    for (let r = 0; r < 8; r++) if (r !== c) {
      const f = M[r][c] / M[c][c];
      for (let j = c; j < 9; j++) M[r][j] -= f * M[c][j];
    }
  }
  const h = M.map((row, i) => row[8] / row[i]);
  return [h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], 1];
}

export function invert3(m) {
  const [a, b, c, d, e, f, g, h, i] = m;
  const A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g;
  const det = a * A + b * B + c * C;
  return [A, -(b * i - c * h), b * f - c * e, B, a * i - c * g, -(a * f - c * d), C, -(a * h - b * g), a * e - b * d].map((v) => v / det);
}

export function apply(H, [x, y]) {
  const w = H[6] * x + H[7] * y + H[8];
  return [(H[0] * x + H[1] * y + H[2]) / w, (H[3] * x + H[4] * y + H[5]) / w, w];
}

// court -> image, clipping the part of a segment behind the camera (w <= 0)
export function projectSegment(H, p, q, steps = 24) {
  const pts = [];
  for (let s = 0; s <= steps; s++) {
    const t = s / steps;
    const r = apply(H, [p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t]);
    if (r[2] > 0) pts.push(r);
  }
  return pts;
}

export function pointInPoly([x, y], poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i], [xj, yj] = poly[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

export function convexHull(points) {
  const p = points.slice().sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  if (p.length < 3) return p;
  const cross = (o, a, b) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
  const lo = [], up = [];
  for (const q of p) { while (lo.length >= 2 && cross(lo.at(-2), lo.at(-1), q) <= 0) lo.pop(); lo.push(q); }
  for (const q of p.reverse()) { while (up.length >= 2 && cross(up.at(-2), up.at(-1), q) <= 0) up.pop(); up.push(q); }
  return lo.slice(0, -1).concat(up.slice(0, -1));
}
