// Min-cost assignment for small rectangular cost matrices (stand-in for scipy linear_sum_assignment).
// Classic O(n^2 m) Hungarian with potentials (rows <= cols; the matrix is transposed otherwise).

/**
 * cost: number[n][m] (finite values). Returns [[row, col], ...] sorted by row, min(n, m) pairs,
 * minimising the total cost - the same contract as scipy.optimize.linear_sum_assignment.
 */
export function linearSumAssignment(cost) {
  const n0 = cost.length, m0 = n0 ? cost[0].length : 0;
  if (!n0 || !m0) return [];
  const tr = n0 > m0;
  const a = tr ? cost[0].map((_, j) => cost.map((r) => r[j])) : cost;
  const n = a.length, m = a[0].length;
  // 1-based arrays as in the textbook formulation; p[j] = row matched to column j
  const u = new Float64Array(n + 1), v = new Float64Array(m + 1);
  const p = new Int32Array(m + 1), way = new Int32Array(m + 1);
  for (let i = 1; i <= n; i++) {
    p[0] = i;
    let j0 = 0;
    const minv = new Float64Array(m + 1).fill(Infinity);
    const used = new Uint8Array(m + 1);
    do {
      used[j0] = 1;
      const i0 = p[j0];
      let delta = Infinity, j1 = 0;
      for (let j = 1; j <= m; j++) {
        if (used[j]) continue;
        const cur = a[i0 - 1][j - 1] - u[i0] - v[j];
        if (cur < minv[j]) { minv[j] = cur; way[j] = j0; }
        if (minv[j] < delta) { delta = minv[j]; j1 = j; }
      }
      for (let j = 0; j <= m; j++) {
        if (used[j]) { u[p[j]] += delta; v[j] -= delta; } else minv[j] -= delta;
      }
      j0 = j1;
    } while (p[j0] !== 0);
    do { const j1 = way[j0]; p[j0] = p[j1]; j0 = j1; } while (j0);
  }
  const out = [];
  for (let j = 1; j <= m; j++) if (p[j]) out.push(tr ? [j - 1, p[j] - 1] : [p[j] - 1, j - 1]);
  return out.sort((x, y) => x[0] - y[0]);
}
