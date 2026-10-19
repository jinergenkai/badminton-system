// Mô hình + tính tiền — PORT VERBATIM từ sổ cũ (web/_legacy/index.html mục 1).
// Giữ nguyên công thức. Khác biệt duy nhất: nhận `book` làm tham số thay cho biến
// toàn cục `st`, để React truyền state vào.

export const DEFAULT_PRICE = 30;
export const LEGACY = "legacy";
export const LOG_MAX = 250;
export const EPS = 0.05;
export const W_MAX = 20;

export const id = () =>
  Math.random().toString(36).slice(2, 9) + Date.now().toString(36).slice(-3);

export const round1 = (x) => Math.round(x * 10) / 10;
export const numStr = (x) => {
  const r = round1(x) + 0;
  return Number.isInteger(r) ? String(r) : r.toFixed(1);
};
export const fmt = (x) => numStr(x) + "k";
export const wStr = (x) => String(Math.round((+x || 0) * 100) / 100 + 0);

export function parseWeight(t) {
  const v = Number(String(t).trim().replace(",", "."));
  if (String(t).trim() === "" || !isFinite(v) || v < 0 || v > W_MAX) return null;
  return Math.round(v * 100) / 100;
}

export const vnd = (x) => Math.round(x * 1000).toLocaleString("vi-VN") + " đ";

export const norm = (s) =>
  String(s || "").toLowerCase().normalize("NFD")
    .replace(/[̀-ͯ]/g, "").replace(/đ/g, "d");

// Nâng đời v1→v2→v3 (giống hệt sổ cũ). Luôn chạy trên bản sao ở caller.
export function migrate(o) {
  if (!o || typeof o !== "object") throw new Error("dữ liệu không phải object");
  if (!Array.isArray(o.sessions)) throw new Error("thiếu danh sách buổi chơi");
  if (!Array.isArray(o.members)) throw new Error("thiếu danh sách thành viên");
  o.flags = o.flags && typeof o.flags === "object" && !Array.isArray(o.flags) ? o.flags : {};
  o.qr = typeof o.qr === "string" ? o.qr : "";
  o.note = typeof o.note === "string" ? o.note : "";
  o.log = Array.isArray(o.log) ? o.log.filter((e) => e && e.t && e.m).slice(-LOG_MAX) : [];
  o.sessions.forEach((s) => {
    s.id = s.id || id();
    s.date = s.date == null ? "" : String(s.date);
    s.court = +s.court || 0;
    s.shuttles = +s.shuttles || 0;
    s.price = +s.price || DEFAULT_PRICE;
    s.parts = Array.isArray(s.parts) ? s.parts : [];
    s.photo = typeof s.photo === "string" ? s.photo : "";
    if (!s.paid || typeof s.paid !== "object" || Array.isArray(s.paid)) s.paid = {};
  });
  if (o.paid && typeof o.paid === "object" && !Array.isArray(o.paid)) {
    Object.keys(o.paid).forEach((n) => {
      if (!o.paid[n]) return;
      o.sessions.forEach((s) => {
        if (s.parts.some((p) => p.name === n) && !s.paid[n]) s.paid[n] = LEGACY;
      });
    });
    delete o.paid;
  }
  if (!(o.v >= 3)) {
    const byName = new Map();
    o.members = o.members.map((m) => {
      const mm = typeof m === "string"
        ? { id: id(), name: m, av: "" }
        : { id: m.id || id(), name: String(m.name || "?"), av: typeof m.av === "string" ? m.av : "" };
      if (!byName.has(mm.name)) byName.set(mm.name, mm.id);
      return mm;
    });
    const midOf = (n) => {
      if (byName.has(n)) return byName.get(n);
      const mm = { id: id(), name: String(n), av: "" };
      o.members.push(mm); byName.set(mm.name, mm.id); return mm.id;
    };
    const remap = (ob) => {
      const out = {};
      Object.keys(ob).forEach((k) => { out[byName.has(k) ? byName.get(k) : k] = ob[k]; });
      return out;
    };
    o.sessions.forEach((s) => {
      s.parts = s.parts.map((p) =>
        p.mid ? { mid: p.mid, weight: +p.weight || 0 } : { mid: midOf(p.name), weight: +p.weight || 0 });
      s.paid = remap(s.paid);
    });
    o.flags = remap(o.flags);
  } else {
    o.members = o.members.map((m) => ({
      id: m.id || id(), name: String(m.name || "?"), av: typeof m.av === "string" ? m.av : "",
    }));
  }
  const ids = new Set(o.members.map((m) => m.id));
  o.sessions.forEach((s) => {
    const seen = new Set();
    s.parts = s.parts.filter((p) => {
      if (!ids.has(p.mid) || seen.has(p.mid)) return false;
      seen.add(p.mid); return true;
    });
    Object.keys(s.paid).forEach((k) => { if (!seen.has(k)) delete s.paid[k]; });
  });
  Object.keys(o.flags).forEach((k) => { if (!ids.has(k)) delete o.flags[k]; });
  o.v = 3;
  return o;
}

export const EMPTY_BOOK = () => ({ v: 3, sessions: [], members: [], flags: {}, qr: "", note: "" });

// ----- Tính tiền (thuần, nhận book) -----
export const sTotal = (s) => s.court + s.shuttles * (s.price || DEFAULT_PRICE);
export const sWeight = (s) => s.parts.reduce((a, p) => a + (+p.weight || 0), 0);
export const sPerUnit = (s) => { const w = sWeight(s); return w > 0 ? sTotal(s) / w : 0; };
export const shareIn = (s, mid) => { const p = s.parts.find((x) => x.mid === mid); return p ? p.weight * sPerUnit(s) : 0; };
export const isPaid = (s, mid) => !!(s.paid && s.paid[mid]);
export function setPaid(s, mid, on) {
  if (!s.paid) s.paid = {};
  if (on) s.paid[mid] = new Date().toISOString();
  else delete s.paid[mid];
}
export const sUnpaid = (s) => s.parts.filter((p) => !isPaid(s, p.mid)).map((p) => p.mid);
export const sDue = (s) => s.parts.reduce((a, p) => a + (isPaid(s, p.mid) ? 0 : p.weight * sPerUnit(s)), 0);
export const sCollected = (s) => s.parts.reduce((a, p) => a + (isPaid(s, p.mid) ? p.weight * sPerUnit(s) : 0), 0);
export const sSettled = (s) => s.parts.length > 0 && sUnpaid(s).length === 0;

export const memById = (book, mid) => book.members.find((m) => m.id === mid);
export const memberSessions = (book, mid) => book.sessions.filter((s) => s.parts.some((p) => p.mid === mid));
export const memberDueSessions = (book, mid) => memberSessions(book, mid).filter((s) => !isPaid(s, mid));
export const memberDue = (book, mid) => memberDueSessions(book, mid).reduce((a, s) => a + shareIn(s, mid), 0);
export const memberPaidSum = (book, mid) =>
  memberSessions(book, mid).filter((s) => isPaid(s, mid)).reduce((a, s) => a + shareIn(s, mid), 0);
export const totalDue = (book) => book.sessions.reduce((a, s) => a + sDue(s), 0);
export const totalCollected = (book) => book.sessions.reduce((a, s) => a + sCollected(s), 0);
export const debtors = (book) => book.members.filter((m) => memberDue(book, m.id) > EPS);
export const orderedSessions = (book) => book.sessions.slice().reverse();

export function whenLabel(v) {
  if (!v || v === LEGACY) return "";
  const d = new Date(v);
  return isNaN(d) ? "" : d.getDate() + "/" + (d.getMonth() + 1);
}
export function dupTag(book, m) {
  const same = book.members.filter((x) => x.name === m.name);
  return same.length < 2 ? "" : " #" + (same.indexOf(m) + 1);
}
export const fullName = (book, m) => m.name + dupTag(book, m);
export function initials(n) {
  const w = String(n || "").replace(/[^\p{L}\p{N}\s]/gu, " ").trim().split(/\s+/).filter(Boolean);
  return !w.length ? "?" : (w.length > 1 ? w[w.length - 2][0] + w[w.length - 1][0] : w[0].slice(0, 2)).toUpperCase();
}
export function hue(s) {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 360;
  return `hsl(${h} 42% 52%)`;
}
export const payRef = (m) =>
  ("CAULONG " + norm(m.name).replace(/[^a-z0-9]+/g, " ").trim().toUpperCase()).slice(0, 40);

// Liệt kê đúng những chỗ hai bản khác nhau (hộp conflict). Port từ sổ cũ, trả text thuần.
export function diffSummary(mine, theirs) {
  const out = [];
  const nm = (d, mid) => { const m = (d.members || []).find((x) => x.id === mid); return m ? m.name : "(ai đó)"; };
  const map = (d) => new Map((d.sessions || []).map((s) => [s.id, s]));
  const A = map(mine), B = map(theirs);
  A.forEach((s, k) => { if (!B.has(k)) out.push(`Buổi ${s.date || "?"}: chỉ có ở máy này`); });
  B.forEach((s, k) => { if (!A.has(k)) out.push(`Buổi ${s.date || "?"}: chỉ có trên web`); });
  A.forEach((a, k) => {
    const b = B.get(k); if (!b) return;
    const d = a.date || "?";
    if (a.court !== b.court || a.shuttles !== b.shuttles || a.price !== b.price || a.date !== b.date)
      out.push(`Buổi ${d}: tiền hoặc ngày khác nhau`);
    if ((a.parts || []).length !== (b.parts || []).length)
      out.push(`Buổi ${d}: số người khác (${a.parts.length} ở máy này / ${b.parts.length} trên web)`);
    Object.keys(a.paid || {}).forEach((mid) => { if (!(b.paid || {})[mid])
      out.push(`Buổi ${d} · ${nm(mine, mid)}: máy này ghi đã trả, web chưa`); });
    Object.keys(b.paid || {}).forEach((mid) => { if (!(a.paid || {})[mid])
      out.push(`Buổi ${d} · ${nm(theirs, mid)}: web ghi đã trả, máy này chưa`); });
    if ((a.photo || "") !== (b.photo || "")) out.push(`Buổi ${d}: ảnh buổi chơi khác nhau`);
  });
  const mA = new Map((mine.members || []).map((m) => [m.id, m]));
  const mB = new Map((theirs.members || []).map((m) => [m.id, m]));
  mA.forEach((m, k) => { if (!mB.has(k)) out.push(`Người ${m.name}: chỉ có ở máy này`); });
  mB.forEach((m, k) => { if (!mA.has(k)) out.push(`Người ${m.name}: chỉ có trên web`); });
  mA.forEach((m, k) => { const o = mB.get(k); if (!o) return;
    if (m.name !== o.name) out.push(`Tên khác: "${m.name}" ở máy này / "${o.name}" trên web`);
    if ((m.av || "") !== (o.av || "")) out.push(`Ảnh đại diện của ${m.name} khác nhau`); });
  if ((mine.note || "") !== (theirs.note || "")) out.push("Thông tin ngân hàng khác nhau");
  if ((mine.qr || "") !== (theirs.qr || "")) out.push("Mã QR khác nhau");
  return out;
}

export const picName = (book, t) => !t ? "" : (t.k === "m"
  ? (memById(book, t.id)?.name || "")
  : ("buổi " + (book.sessions.find((x) => x.id === t.id)?.date || "?")));
