// Huy hiệu — tính thuần (không React) từ:
//   • hồ sơ trận (GET /api/profile: matches cũ -> mới, có elo_before/delta/rallies...)
//   • sổ tiền (book đã migrate, id thành viên = id người chơi)
// Mỗi huy hiệu có 4 ngưỡng -> cấp 1..4 = Đồng/Bạc/Vàng/Kim cương (màu viền + số hạt).
import * as M from "./model.js";

export const BADGE_TIERS = ["dong", "bac", "vang", "kim-cuong"];
export const TIER_LABEL = { dong: "Đồng", bac: "Bạc", vang: "Vàng", "kim-cuong": "Kim cương" };

export const BADGES = [
  { key: "chuyen-can", name: "Chuyên cần", src: "book", unit: "buổi liền", steps: [5, 10, 20, 40], desc: "Có mặt nhiều buổi cầu liên tiếp" },
  { key: "dai-gia", name: "Đại gia sân cầu", src: "book", unit: "lần top tháng", steps: [1, 2, 4, 6], desc: "Chi nhiều nhất trong một tháng" },
  { key: "song-phang", name: "Sòng phẳng", src: "book", unit: "buổi liền", steps: [5, 15, 30, 60], desc: "Trả đủ, không nợ nhiều buổi liền" },
  { key: "keo-an", name: "Chiến thần kèo ăn", src: "book", unit: "kèo", steps: [3, 10, 25, 50], desc: "Góp mặt kèo ăn" },
  { key: "chuoi-thang", name: "Chuỗi thắng", src: "match", unit: "trận liền", steps: [3, 5, 8, 12], desc: "Thắng liên tiếp" },
  { key: "bach-thang", name: "Bách thắng", src: "match", unit: "trận thắng", steps: [10, 50, 100, 250], desc: "Tổng số trận thắng" },
  { key: "nguoc-dong", name: "Lội ngược dòng", src: "match", unit: "lần", steps: [1, 3, 6, 10], desc: "Thắng sau khi bị dẫn từ 5 điểm" },
  { key: "ha-guc", name: "Hạ gục khổng lồ", src: "match", unit: "lần", steps: [1, 3, 6, 10], desc: "Thắng đội có Elo cao hơn từ 100" },
  { key: "cap-bai-trung", name: "Cặp bài trùng", src: "match", unit: "trận thắng", steps: [10, 25, 50, 100], desc: "Thắng nhiều trận với cùng một người" },
  { key: "xa-giao", name: "Ai cũng là đồng đội", src: "match", unit: "người", steps: [10, 20, 30, 45], desc: "Đánh cặp với nhiều người khác nhau" },
  { key: "marathon", name: "Marathon", src: "match", unit: "trận", steps: [1, 3, 6, 10], desc: "Trận vào deuce (20–20)" },
  { key: "cu-dem", name: "Cú đêm", src: "match", unit: "trận", steps: [5, 20, 40, 80], desc: "Đánh sau 22h" },
];
export const badgeByKey = (k) => BADGES.find((b) => b.key === k);

const COMEBACK = 5, GIANT = 100, NIGHT_HOUR = 22;

/** Chuỗi dài nhất các phần tử thoả `ok` liên tiếp + chuỗi đang chạy ở cuối. */
function runs(list, ok) {
  let best = 0, cur = 0;
  for (const x of list) { cur = ok(x) ? cur + 1 : 0; if (cur > best) best = cur; }
  return { best, cur };
}

/** Thống kê + giá trị huy hiệu từ hồ sơ trận. `prof.matches` cũ -> mới. */
export function matchStats(prof) {
  const ms = prof?.matches || [];
  const p = prof?.player || {};
  const wins = ms.filter((m) => m.won).length;
  const streak = runs(ms, (m) => m.won);
  // chuỗi Elo: trước trận đầu, rồi sau mỗi trận
  const elo = ms.length ? [ms[0].elo_before, ...ms.map((m) => m.elo_before + m.delta)] : [Number(p.elo) || 1000];
  const peak = Math.max(...elo);
  // đồng đội / đối thủ
  const mate = new Map(), opp = new Map();
  for (const m of ms) {
    for (const x of m.partners) { const s = mate.get(x) || { id: x, n: 0, w: 0 }; s.n++; if (m.won) s.w++; mate.set(x, s); }
    for (const x of m.opponents) { const s = opp.get(x) || { id: x, n: 0, l: 0 }; s.n++; if (!m.won) s.l++; opp.set(x, s); }
  }
  const mates = [...mate.values()], opps = [...opp.values()];
  const bestPartner = mates.filter((s) => s.n >= 3).sort((a, b) => b.w / b.n - a.w / a.n || b.n - a.n)[0] || null;
  const nemesis = opps.filter((s) => s.n >= 3 && s.l > s.n / 2).sort((a, b) => b.l / b.n - a.l / a.n || b.l - a.l)[0] || null;
  const comeback = (r) => { let d = 0, worst = 0; for (const c of r || "") { d += c === "W" ? 1 : -1; if (d < worst) worst = d; } return -worst; };
  const hour = (t) => { const h = /T(\d{2}):/.exec(t || ""); return h ? +h[1] : -1; };
  return {
    played: ms.length, wins, losses: ms.length - wins,
    winRate: ms.length ? Math.round((wins / ms.length) * 100) : 0,
    streak: streak.cur, bestStreak: streak.best,
    elo, peak, form: ms.slice(-10).map((m) => m.won),
    bestPartner, nemesis,
    values: {
      "chuoi-thang": streak.best,
      "bach-thang": wins,
      "nguoc-dong": ms.filter((m) => m.won && m.rallies && comeback(m.rallies) >= COMEBACK).length,
      "ha-guc": ms.filter((m) => m.won && m.opp_elo - m.team_elo >= GIANT).length,
      "cap-bai-trung": Math.max(0, ...mates.map((s) => s.w)),
      "xa-giao": mates.length,
      "marathon": ms.filter((m) => m.score >= 20 && m.opp_score >= 20).length,
      "cu-dem": ms.filter((m) => hour(m.played_at) >= NIGHT_HOUR).length,
    },
  };
}

/** Tháng của buổi: lấy từ đầu chuỗi ngày "dd/mm ..." (sổ không có năm). null = không đọc được. */
export function sessionMonth(s) {
  const m = /^\s*(\d{1,2})[/.-](\d{1,2})/.exec(String(s?.date || ""));
  if (!m) return null;
  const mo = +m[2];
  return mo >= 1 && mo <= 12 ? mo : null;
}

/** Gom buổi theo tháng, theo thứ tự trong sổ: tháng đổi -> nhóm mới (12 -> 1 sang năm mới vẫn tách đúng). */
export function monthGroups(book) {
  const out = [];
  for (const s of book?.sessions || []) {
    const mo = sessionMonth(s);
    if (mo == null) continue;
    let g = out[out.length - 1];
    if (!g || g.month !== mo) { g = { month: mo, sessions: [] }; out.push(g); }
    g.sessions.push(s);
  }
  return out;
}

/** Người chi nhiều nhất mỗi tháng (cả buổi cầu lẫn kèo ăn). Hoà -> không ai. */
export function monthTops(book) {
  return monthGroups(book).map((g) => {
    const spend = new Map();
    for (const s of g.sessions) for (const p of s.parts) spend.set(p.mid, (spend.get(p.mid) || 0) + M.shareIn(s, p.mid));
    const arr = [...spend.entries()].sort((a, b) => b[1] - a[1]);
    const top = arr[0] && arr[0][1] > M.EPS && !(arr[1] && Math.abs(arr[1][1] - arr[0][1]) <= M.EPS) ? { mid: arr[0][0], amount: arr[0][1] } : null;
    return { month: g.month, top, sessions: g.sessions.length };
  });
}

/** Thống kê sổ tiền của 1 người (công khai: KHÔNG có tiền nợ). */
export function bookStats(book, mid) {
  if (!book || !mid) return null;
  const mine = M.memberSessions(book, mid);
  if (!mine.length && !M.memById(book, mid)) return null;
  const plays = book.sessions.filter((s) => !M.isMeal(s));
  const attend = runs(plays, (s) => s.parts.some((p) => p.mid === mid));
  const paidRun = runs(mine, (s) => M.isPaid(s, mid));
  const recent = plays.slice(-10);
  return {
    plays: M.playCount(book, mid),
    meals: mine.filter(M.isMeal).length,
    spent: mine.reduce((a, s) => a + M.shareIn(s, mid), 0),
    recentIn: recent.filter((s) => s.parts.some((p) => p.mid === mid)).length, recentOf: recent.length,
    values: {
      "chuyen-can": attend.best,
      "dai-gia": monthTops(book).filter((t) => t.top?.mid === mid).length,
      "song-phang": paidRun.best,
      "keo-an": mine.filter(M.isMeal).length,
    },
  };
}

/** Giá trị -> cấp (0 = chưa đạt) + ngưỡng kế tiếp. */
export function levelOf(b, v) {
  const level = b.steps.filter((x) => v >= x).length;
  return { level, tier: level ? BADGE_TIERS[level - 1] : null, next: b.steps[level] ?? null };
}

/** Danh sách huy hiệu đã tính: [{...def, value, level, tier, next, known}]. `known=false` khi thiếu nguồn. */
export function badgeList(values) {
  return BADGES.map((b) => {
    const known = values[b.key] !== undefined;
    const value = known ? values[b.key] : 0;
    return { ...b, value, known, ...levelOf(b, value) };
  });
}

/** Huy hiệu nổi bật (cấp cao trước, cùng cấp thì gần lên cấp hơn) và sắp lên cấp (đã có nguồn, % tới ngưỡng cao nhất). */
export function showcase(list, n = 4) {
  return list.filter((b) => b.level > 0).sort((a, b) => b.level - a.level || b.value / b.steps[b.level - 1] - a.value / a.steps[a.level - 1]).slice(0, n);
}
export function upcoming(list, n = 2) {
  return list.filter((b) => b.known && b.next != null && b.value > 0)
    .sort((a, b) => b.value / b.next - a.value / a.next).slice(0, n);
}
