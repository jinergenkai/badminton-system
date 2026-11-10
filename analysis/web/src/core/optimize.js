// Bounded robust nonlinear least squares: a practical stand-in for
// scipy.optimize.least_squares(method='trf', loss='soft_l1', f_scale, bounds, max_nfev).
//
// Method: Levenberg-Marquardt (Marquardt diagonal scaling) on the robust-scaled system scipy itself uses
// (scale_for_robust_loss_function): with z = (r / f_scale)^2,
//   soft_l1  rho(z) = 2 (sqrt(1 + z) - 1),  rho' = 1/sqrt(1+z),  rho'' = -0.5 (1+z)^-1.5
//   Jacobian rows scaled by sqrt(rho' + 2 rho'' z) = (1+z)^-0.75, residuals by rho' / that,
// so J_s^T f_s is the exact gradient of the robust cost and J_s^T J_s its Gauss-Newton Hessian.
// Bounds: variables sitting on a bound whose gradient pushes outward are frozen for the step, the
// step is clipped to the box (scipy's TRF uses reflective Coleman-Li scaling instead; the minima it
// reaches are the same in practice, the paths differ). Forward-difference Jacobian like '2-point'.
// Not counted in nfev (as in scipy): the n extra evaluations per Jacobian.

const EPS = 2.220446049250313e-16;

/** Robust scaling of the residuals for soft_l1 / linear. Returns {cost, w (row scale), fs (scaled residuals)}. */
function robust(f, loss, fScale) {
  const n = f.length, w = new Float64Array(n), fs = new Float64Array(n);
  let cost = 0;
  if (loss === 'linear') {
    for (let i = 0; i < n; i++) { w[i] = 1; fs[i] = f[i]; cost += f[i] * f[i]; }
    return { cost: 0.5 * cost, w, fs };
  }
  const c2 = fScale * fScale;
  for (let i = 0; i < n; i++) {
    const z = (f[i] * f[i]) / c2, s = 1 + z, sq = Math.sqrt(s);
    cost += c2 * 2 * (sq - 1);
    const js = Math.max(1 / (s * sq), EPS);          // rho' + 2 rho'' z = (1+z)^-1.5
    const r = Math.sqrt(js);
    w[i] = r;
    fs[i] = (f[i] / sq) / r;                          // rho' f / sqrt(js)
  }
  return { cost: 0.5 * cost, w, fs };
}

/** Forward-difference Jacobian (rows = residuals, as arrays of length n). Steps go inward at a bound. */
function jacobian(fun, x, f0, lo, hi) {
  const n = x.length, m = f0.length;
  const J = Array.from({ length: m }, () => new Float64Array(n));
  const xx = x.slice();
  for (let k = 0; k < n; k++) {
    let h = 1.4901161193847656e-8 * Math.max(1, Math.abs(x[k])) * (x[k] >= 0 ? 1 : -1);
    if (x[k] + h > hi[k] || x[k] + h < lo[k]) h = -h;
    xx[k] = x[k] + h;
    h = xx[k] - x[k];
    const f1 = fun(xx);
    for (let i = 0; i < m; i++) J[i][k] = (f1[i] - f0[i]) / h;
    xx[k] = x[k];
  }
  return J;
}

/** Solve the small dense SPD-ish system A x = b (Gaussian elimination, partial pivoting). */
function solveSmall(A, b) {
  const n = b.length;
  const M = A.map((r, i) => [...r, b[i]]);
  for (let c = 0; c < n; c++) {
    let p = c;
    for (let r = c + 1; r < n; r++) if (Math.abs(M[r][c]) > Math.abs(M[p][c])) p = r;
    if (!(Math.abs(M[p][c]) > 1e-300)) return null;
    if (p !== c) { const tmp = M[c]; M[c] = M[p]; M[p] = tmp; }
    for (let r = c + 1; r < n; r++) {
      const f = M[r][c] / M[c][c];
      if (f) for (let k = c; k <= n; k++) M[r][k] -= f * M[c][k];
    }
  }
  const x = new Array(n);
  for (let i = n - 1; i >= 0; i--) {
    let s = M[i][n];
    for (let k = i + 1; k < n; k++) s -= M[i][k] * x[k];
    x[i] = s / M[i][i];
  }
  return x.every(Number.isFinite) ? x : null;
}

/**
 * least_squares-like minimiser.
 * fun(x) -> residual array; x0 start; opts {lo, hi, loss: 'soft_l1'|'linear', fScale, maxNfev, ftol, xtol, gtol}.
 * Returns {x, cost (0.5 sum rho, scipy convention), fun (raw residuals at x), jac (robust-scaled Jacobian at x,
 * like scipy's result.jac, so J^T J is the Gauss-Newton Hessian of the cost), jacRaw (plain Jacobian), nfev, nit}.
 */
export function leastSquares(fun, x0, opts = {}) {
  const n = x0.length;
  const lo = opts.lo || new Array(n).fill(-Infinity), hi = opts.hi || new Array(n).fill(Infinity);
  const loss = opts.loss || 'linear', fScale = opts.fScale || 1;
  const maxNfev = opts.maxNfev || 100 * n, ftol = opts.ftol ?? 1e-8, xtol = opts.xtol ?? 1e-8, gtol = opts.gtol ?? 1e-8;
  let x = x0.map((v, k) => Math.min(Math.max(v, lo[k]), hi[k]));
  let f = fun(x);
  let nfev = 1, nit = 0;
  let R = robust(f, loss, fScale);
  let J = jacobian(fun, x, f, lo, hi);
  let lam = 1e-3;
  const m = f.length;
  for (;;) {
    nit++;
    // normal equations of the robust-scaled system
    const A = Array.from({ length: n }, () => new Array(n).fill(0)), g = new Array(n).fill(0);
    for (let i = 0; i < m; i++) {
      const wi = R.w[i], Ji = J[i], fi = R.fs[i];
      for (let a = 0; a < n; a++) {
        const ja = Ji[a] * wi;
        if (!ja) continue;
        g[a] += ja * fi;
        for (let b = a; b < n; b++) A[a][b] += ja * Ji[b] * wi;
      }
    }
    for (let a = 0; a < n; a++) for (let b = 0; b < a; b++) A[a][b] = A[b][a];
    // freeze variables held by a bound (the gradient pushes them out of the box)
    const free = [];
    let gmax = 0;
    for (let k = 0; k < n; k++) {
      const atLo = x[k] <= lo[k] + 1e-12 * Math.max(1, Math.abs(lo[k])) && g[k] > 0;
      const atHi = x[k] >= hi[k] - 1e-12 * Math.max(1, Math.abs(hi[k])) && g[k] < 0;
      if (!atLo && !atHi) { free.push(k); gmax = Math.max(gmax, Math.abs(g[k])); }
    }
    if (!free.length || gmax < gtol * Math.max(1, R.cost) || nfev >= maxNfev) break;
    const dmax = Math.max(...free.map((k) => A[k][k]), 1e-30);
    let accepted = false, done = false;
    while (nfev < maxNfev) {
      const Af = free.map((a) => free.map((b) => A[a][b] + (a === b ? lam * Math.max(A[a][a], 1e-10 * dmax) : 0)));
      const dx = solveSmall(Af, free.map((k) => -g[k]));
      if (!dx) { lam *= 10; if (lam > 1e16) { done = true; break; } continue; }
      const xn = x.slice();
      free.forEach((k, i) => { xn[k] = Math.min(Math.max(x[k] + dx[i], lo[k]), hi[k]); });
      let stepN = 0, xN = 0;
      for (let k = 0; k < n; k++) { stepN += (xn[k] - x[k]) ** 2; xN += x[k] ** 2; }
      if (Math.sqrt(stepN) < xtol * (xtol + Math.sqrt(xN))) { done = true; break; }
      const fn = fun(xn);
      nfev++;
      const Rn = robust(fn, loss, fScale);
      if (Rn.cost < R.cost) {
        const red = R.cost - Rn.cost;
        x = xn; f = fn;
        const small = red < ftol * R.cost;
        R = Rn;
        J = jacobian(fun, x, f, lo, hi);
        lam = Math.max(lam / 3, 1e-12);
        accepted = true;
        if (small) done = true;
        break;
      }
      lam *= 4;
      if (lam > 1e16) { done = true; break; }
    }
    if (done || !accepted) break;
  }
  const jac = J.map((row, i) => row.map((v) => v * R.w[i]));
  return { x, cost: R.cost, fun: Array.from(f), jac, jacRaw: J, nfev, nit };
}

/** Moore-Penrose pseudo-inverse of a small symmetric matrix (Jacobi eigen-decomposition, numpy rcond 1e-15). */
export function pinvSym(S, rcond = 1e-15) {
  const n = S.length;
  const A = S.map((r) => r.slice());
  const V = Array.from({ length: n }, (_, i) => Array.from({ length: n }, (_, j) => (i === j ? 1 : 0)));
  for (let sweep = 0; sweep < 100; sweep++) {
    let off = 0;
    for (let p = 0; p < n; p++) for (let q = p + 1; q < n; q++) off += A[p][q] * A[p][q];
    if (off < 1e-30) break;
    for (let p = 0; p < n; p++) for (let q = p + 1; q < n; q++) {
      if (Math.abs(A[p][q]) < 1e-300) continue;
      const th = (A[q][q] - A[p][p]) / (2 * A[p][q]);
      const t = Math.sign(th || 1) / (Math.abs(th) + Math.sqrt(th * th + 1));
      const c = 1 / Math.sqrt(t * t + 1), s = t * c;
      for (let k = 0; k < n; k++) {
        const akp = A[k][p], akq = A[k][q];
        A[k][p] = c * akp - s * akq; A[k][q] = s * akp + c * akq;
      }
      for (let k = 0; k < n; k++) {
        const apk = A[p][k], aqk = A[q][k];
        A[p][k] = c * apk - s * aqk; A[q][k] = s * apk + c * aqk;
      }
      for (let k = 0; k < n; k++) {
        const vkp = V[k][p], vkq = V[k][q];
        V[k][p] = c * vkp - s * vkq; V[k][q] = s * vkp + c * vkq;
      }
    }
  }
  const ev = A.map((r, i) => r[i]);
  const cut = rcond * Math.max(...ev.map(Math.abs));
  const out = Array.from({ length: n }, () => new Array(n).fill(0));
  for (let k = 0; k < n; k++) {
    if (Math.abs(ev[k]) <= cut) continue;
    const inv = 1 / ev[k];
    for (let i = 0; i < n; i++) for (let j = 0; j < n; j++) out[i][j] += V[i][k] * V[j][k] * inv;
  }
  return out;
}
