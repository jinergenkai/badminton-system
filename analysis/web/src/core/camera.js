// Pinhole camera of the court, ported from analysis/badminton/calibrate.py (Camera + the K, R, t part of fit).
// Court frame (metres): X across 0..6.1, Y along the court (0 = net, negative = camera half), Z up.
export const W = 6.1;
export const HALF = 6.7;
export const NET_CENTRE = 1.524;
export const NET_POST = 1.55;

const mat3 = {
  mul: (A, B) => A.map((r) => [0, 1, 2].map((j) => r[0] * B[0][j] + r[1] * B[1][j] + r[2] * B[2][j])),
  vec: (A, v) => A.map((r) => r[0] * v[0] + r[1] * v[1] + r[2] * v[2]),
  T: (A) => [0, 1, 2].map((i) => [0, 1, 2].map((j) => A[j][i])),
  inv(m) {
    const [a, b, c, d, e, f, g, h, i] = m.flat();
    const A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g;
    const det = a * A + b * B + c * C;
    return [[A, -(b * i - c * h), b * f - c * e], [B, a * i - c * g, -(a * f - c * d)], [C, -(a * h - b * g), a * e - b * d]]
      .map((r) => r.map((v) => v / det));
  },
};
export { mat3 };

export function rodrigues(rv) {
  const th = Math.hypot(rv[0], rv[1], rv[2]);
  if (th < 1e-12) return [[1, 0, 0], [0, 1, 0], [0, 0, 1]];
  const [x, y, z] = rv.map((v) => v / th);
  const c = Math.cos(th), s = Math.sin(th), C = 1 - c;
  return [[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
    [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
    [z * x * C - y * s, z * y * C + x * s, c + z * z * C]];
}

function makeCamera({ K, R, t, H, size }) {
  const Ki = mat3.inv(K);
  const RT = mat3.T(R);
  const pos = mat3.vec(RT, t).map((v) => -v);
  const Hinv = H ? mat3.inv(H) : null;
  return {
    K, R, t, H, Hinv, size, pos,
    /** points: [[X,Y,Z], ...] -> [[x,y], ...] (no lens distortion) */
    project(points) {
      return points.map((P) => {
        const c = [0, 1, 2].map((i) => R[i][0] * P[0] + R[i][1] * P[1] + R[i][2] * P[2] + t[i]);
        return [K[0][0] * c[0] / c[2] + K[0][2], K[1][1] * c[1] / c[2] + K[1][2]];
      });
    },
    /** depth of a world point in front of the camera (> 0 = visible side) */
    depth(P) {
      return R[2][0] * P[0] + R[2][1] * P[1] + R[2][2] * P[2] + t[2];
    },
    /** unit view-ray direction (world) through pixel px */
    ray(px) {
      const d = mat3.vec(RT, mat3.vec(Ki, [px[0], px[1], 1]));
      const n = Math.hypot(d[0], d[1], d[2]);
      return d.map((v) => v / n);
    },
    /** pixel -> court (X, Y) assuming the point lies on the floor */
    toFloor(px) {
      const q = mat3.vec(Hinv, [px[0], px[1], 1]);
      return [q[0] / q[2], q[1] / q[2]];
    },
  };
}

/** Camera from a calib.json written by the desktop pipeline (K, rvec, tvec, H, size). */
export function cameraFromCalib(calib) {
  return makeCamera({ K: calib.K, R: rodrigues(calib.rvec), t: calib.tvec, H: calib.H, size: calib.size });
}

/** Closest rotation to M (polar decomposition by averaging with the inverse transpose). */
function orthonormalize(M) {
  let R = M;
  for (let k = 0; k < 30; k++) {
    const IT = mat3.T(mat3.inv(R));
    R = R.map((r, i) => r.map((v, j) => 0.5 * (v + IT[i][j])));
  }
  return R;
}

/**
 * Camera (K, R, t) from the floor homography H (court X,Y -> pixel), as calibrate.py does:
 * focal length from the orthogonality of the floor axes (square pixels, principal point at the centre),
 * then the pose from K^-1 H = [r1 r2 t] / lambda.
 */
export function calibrateFromHomography(H, width, height) {
  const cx = width / 2, cy = height / 2;
  const A = mat3.mul([[1, 0, -cx], [0, 1, -cy], [0, 0, 1]], H);
  const h1 = [A[0][0], A[1][0], A[2][0]], h2 = [A[0][1], A[1][1], A[2][1]];
  const f2 = -(h1[0] * h2[0] + h1[1] * h2[1]) / (h1[2] * h2[2]);
  const f = f2 > 0 ? Math.sqrt(f2) : width;
  const K = [[f, 0, cx], [0, f, cy], [0, 0, 1]];
  const M = mat3.mul(mat3.inv(K), H);
  const c1 = [M[0][0], M[1][0], M[2][0]], c2 = [M[0][1], M[1][1], M[2][1]], c3 = [M[0][2], M[1][2], M[2][2]];
  let lam = 2 / (Math.hypot(...c1) + Math.hypot(...c2));
  // the court centre must be in front of the camera
  if (c3[2] * lam < 0) lam = -lam;
  const r1 = c1.map((v) => v * lam), r2 = c2.map((v) => v * lam), t = c3.map((v) => v * lam);
  const r3 = [r1[1] * r2[2] - r1[2] * r2[1], r1[2] * r2[0] - r1[0] * r2[2], r1[0] * r2[1] - r1[1] * r2[0]];
  const R0 = orthonormalize([[r1[0], r2[0], r3[0]], [r1[1], r2[1], r3[1]], [r1[2], r2[2], r3[2]]]);
  const { R, t: tr } = refinePose(K, R0, t, H);
  return makeCamera({ K, R, t: tr, H, size: [width, height] });
}

/**
 * Pose refinement like cv2.solvePnP(ITERATIVE): Gauss-Newton on (small rotation w, translation) so that a
 * 7 x 15 grid of floor points projects where the homography puts them.
 */
function refinePose(K, R0, t0, H) {
  const grid = [];
  for (let i = 0; i < 7; i++) for (let j = 0; j < 15; j++) {
    const X = (W * i) / 6, Y = -HALF + (2 * HALF * j) / 14;
    const q = mat3.vec(H, [X, Y, 1]);
    if (q[2] > 1e-6) grid.push([X, Y, q[0] / q[2], q[1] / q[2]]);
  }
  const resid = (p) => {
    const R = mat3.mul(rodrigues(p.slice(0, 3)), R0), t = p.slice(3);
    const r = [];
    for (const [X, Y, u, v] of grid) {
      const c = [0, 1, 2].map((k) => R[k][0] * X + R[k][1] * Y + t[k]);
      r.push(K[0][0] * c[0] / c[2] + K[0][2] - u, K[1][1] * c[1] / c[2] + K[1][2] - v);
    }
    return r;
  };
  let p = [0, 0, 0, ...t0];
  for (let it = 0; it < 15; it++) {
    const r0 = resid(p);
    const J = p.map((_, k) => {
      const q = p.slice(); const h = k < 3 ? 1e-6 : 1e-6 * Math.max(1, Math.abs(p[k]));
      q[k] += h;
      return resid(q).map((v, m) => (v - r0[m]) / h);
    });
    const A = Array.from({ length: 6 }, (_, a) => Array.from({ length: 6 }, (_, b) => J[a].reduce((s, v, m) => s + v * J[b][m], 0)));
    const g = J.map((col) => -col.reduce((s, v, m) => s + v * r0[m], 0));
    const dx = solve(A, g);
    if (!dx) break;
    p = p.map((v, k) => v + dx[k]);
    if (Math.hypot(...dx) < 1e-10) break;
  }
  return { R: mat3.mul(rodrigues(p.slice(0, 3)), R0), t: p.slice(3) };
}

/** Solve A x = b (small dense, partial pivoting). */
export function solve(A, b) {
  const n = b.length;
  const M = A.map((r, i) => [...r, b[i]]);
  for (let c = 0; c < n; c++) {
    let piv = c;
    for (let r = c + 1; r < n; r++) if (Math.abs(M[r][c]) > Math.abs(M[piv][c])) piv = r;
    if (Math.abs(M[piv][c]) < 1e-14) return null;
    [M[c], M[piv]] = [M[piv], M[c]];
    for (let r = 0; r < n; r++) if (r !== c) {
      const f = M[r][c] / M[c][c];
      for (let k = c; k <= n; k++) M[r][k] -= f * M[c][k];
    }
  }
  return M.map((r, i) => r[n] / r[i]);
}

/**
 * Image polygon of the box above our court (court_volume_mask in calibrate.py, as a convex hull):
 * [-1.5, W+1.5] x [-HALF-1.5, HALF+1.5] x [0, 10] m, points behind the camera dropped.
 */
export function courtVolumePolygon(cam, margin = 1.5, height = 10) {
  const pts = [];
  for (const X of [-margin, W / 2, W + margin]) for (const Y of [-HALF - margin, -HALF / 2, 0, HALF / 2, HALF + margin])
    for (const Z of [0, height / 2, height]) if (cam.depth([X, Y, Z]) > 0.3) pts.push(cam.project([[X, Y, Z]])[0]);
  return convexHull(pts);
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

export function pointInPoly([x, y], poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i], [xj, yj] = poly[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
