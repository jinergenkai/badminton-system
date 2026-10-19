// Lớp gọi API duy nhất cho frontend.
// - Sổ tiền + sân trống + danh bạ: qua serverless Vercel (/api/data, /api/courts, /api/roster)
// - Ranking + pickup: đọc trực tiếp backend (VITE_API_BASE), fallback mirror Blob khi offline.

const API_BASE = (import.meta.env.VITE_API_BASE || "").replace(/\/$/, "");

async function jget(url) {
  const r = await fetch(url, { headers: { accept: "application/json" }, cache: "no-store" });
  if (!r.ok) throw new Error(`${url} → HTTP ${r.status}`);
  return r.json();
}

async function jpost(url, body, token) {
  const headers = { "content-type": "application/json" };
  if (token) headers.authorization = "Bearer " + token;
  const r = await fetch(url, { method: "POST", headers, body: JSON.stringify(body) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error || `HTTP ${r.status}`);
  return j;
}

export const api = {
  // ----- Sổ tiền (Blob qua Vercel) -----
  getBook: () => jget("/api/data"),
  checkPass: (pass) => jpost("/api/data", { pass, check: 1 }),
  saveBook: (pass, rev, data) => jpost("/api/data", { pass, rev, data }),

  // ----- Sân trống -----
  getCourts: () => jget("/api/courts"),
  triggerCrawl: (pass) => jpost("/api/courts?action=crawl", { pass }),

  // ----- Danh bạ (mirror luôn-online) -----
  getRoster: () => jget("/api/roster"),

  // ----- Ranking + pickup (backend; fallback roster mirror) -----
  async getRanking() {
    if (API_BASE) {
      try {
        return (await jget(`${API_BASE}/api/ranking`)).ranking || [];
      } catch (_) {
        /* offline → thử mirror */
      }
    }
    const r = await api.getRoster().catch(() => ({ players: [] }));
    return (r.players || []).filter((p) => p.played > 0).sort((a, b) => b.elo - a.elo);
  },
  getPickup: (sessionId) =>
    jget(`${API_BASE}/api/pickup?session=${encodeURIComponent(sessionId)}`).then(
      (j) => j.pickup || [],
    ),
};

export { API_BASE };
