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
  // Ưu tiên backend (gộp crawler); backend offline thì đọc cache blob qua Vercel.
  async getCourts() {
    const blob = () => jget("/api/courts");
    if (!API_BASE) return blob();
    try {
      const j = await jget(`${API_BASE}/api/courts`);
      if (j && j.data && (j.data.branches || []).length) return j;  // backend có data thật
      return await blob().catch(() => j);                            // backend rỗng (chưa cào) → cache blob cũ
    } catch (_) {
      return blob();                                                 // backend offline → cache blob
    }
  },
  async triggerCrawl(pass) {
    if (API_BASE) { try { return await jpost(`${API_BASE}/api/courts/crawl`, { pass }); } catch (_) { /* fallback Vercel */ } }
    return jpost("/api/courts?action=crawl", { pass });
  },
  getCourtsStatus: () => (API_BASE ? jget(`${API_BASE}/api/courts/status`) : Promise.reject(new Error("cần VITE_API_BASE"))),
  getCourtsConfig: () => (API_BASE ? jget(`${API_BASE}/api/courts/config`) : Promise.reject(new Error("cần VITE_API_BASE"))),
  getCourtsDirectory: () => (API_BASE ? jget(`${API_BASE}/api/courts/directory`) : Promise.reject(new Error("cần VITE_API_BASE"))),
  saveCourtsConfig: (pass, branches, days_window) => jpost(`${API_BASE}/api/courts/config`, { pass, branches, days_window }),

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
  // Theo NGÀY (YYYY-MM-DD giờ VN): { date, matches, pickup:[{id,name,short,avatar,elo,guest,played,last_played}] }
  getPickupDay: (day) => {
    if (!API_BASE) return Promise.reject(new Error("cần VITE_API_BASE"));
    return jget(`${API_BASE}/api/pickup?date=${encodeURIComponent(day)}`);
  },

  // ----- Bảng xếp sân theo ngày (backend) -----
  // GET → { date, rev, updated_at, board:{present, courts:[{name, slots[4]}]} }
  getBoard: (day) => {
    if (!API_BASE) return Promise.reject(new Error("cần VITE_API_BASE"));
    return jget(`${API_BASE}/api/board?date=${encodeURIComponent(day)}`);
  },
  // Lưu với rev đang cầm. Trả { ok:true, ...bản mới } hoặc { conflict:true, server } khi
  // máy khác vừa lưu (409) — KHÔNG ném lỗi, để trang tự lấy bản server.
  async saveBoard(pass, day, rev, board) {
    const r = await fetch(`${API_BASE}/api/board`, {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ pass, date: day, rev, board }),
    });
    const j = await r.json().catch(() => ({}));
    if (r.status === 409 && j.server) return { conflict: true, server: j.server };
    if (!r.ok) throw new Error(j.error || `HTTP ${r.status}`);
    return j;
  },

  // ----- Trình độ (Elo khởi điểm) -----
  setLevel: (pass, id, level) => jpost(`${API_BASE}/api/players/level`, { pass, id, level }),
  setHost: (pass, id, host) => jpost(`${API_BASE}/api/players/host`, { pass, id, host }),

  // ----- Khách vãng lai (backend, mật khẩu quản trị) -----
  addGuest: (pass, name) => jpost(`${API_BASE}/api/guests`, { pass, name }).then((j) => j.player),
  hideGuest: (pass, id) => jpost(`${API_BASE}/api/guests/hide`, { pass, id }),
};

/** Ngày hôm nay theo giờ VN (UTC+7), YYYY-MM-DD — không phụ thuộc múi giờ máy. */
export const todayVN = () => new Date(Date.now() + 7 * 3600 * 1000).toISOString().slice(0, 10);

// Chia cặp cân Elo: nằm ở courts.js (hàm thuần, test bằng node), export lại cho tiện.
export { balancePairs } from "./courts.js";

export { API_BASE };
