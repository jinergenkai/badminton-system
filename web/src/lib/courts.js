// Logic xếp sân — hàm thuần, không đụng React (test được bằng node).
//
// Bảng 1 ngày: { present:[id], courts:[{ name, slots:[đỏ1, đỏ2, xanh1, xanh2] }] }
// Đỏ = đội A, Xanh = đội B — cùng quy ước band/phone (log AABB…).

/**
 * Chia 4 người thành 2 cặp cân Elo nhất. Có 3 cách chia; chọn cách lệch tổng Elo ít
 * nhất (hoà thì giữ thứ tự gốc). Trả { red:[p,p], blue:[p,p], diff }.
 * Đỏ = đội A, Xanh = đội B — cùng quy ước với band/phone (log AABB…).
 */
export function balancePairs(four) {
  if (!four || four.length !== 4) return null;
  const e = (p) => Number(p.elo) || 1000;
  const [a, b, c, d] = four;
  const splits = [[[a, b], [c, d]], [[a, c], [b, d]], [[a, d], [b, c]]];
  let best = null;
  for (const [x, y] of splits) {
    const diff = Math.abs(e(x[0]) + e(x[1]) - e(y[0]) - e(y[1]));
    if (!best || diff < best.diff - 1e-9) best = { red: x, blue: y, diff };
  }
  return best;
}


export const RED = [0, 1];
export const BLUE = [2, 3];
export const MAX_COURTS = 8;

export const emptyCourt = (i) => ({ name: `Sân ${i + 1}`, slots: [null, null, null, null] });
export const emptyBoard = () => ({ present: [], courts: [emptyCourt(0)] });

/** played_at / ended_at là giờ VN không offset -> ms. Rỗng/hỏng -> null. */
export function vnTime(s) {
  if (!s) return null;
  const t = Date.parse(String(s).slice(0, 19) + "+07:00");
  return Number.isNaN(t) ? null : t;
}

/** Phút đã chờ kể từ lần rời sân gần nhất. Chưa đánh trận nào hôm nay -> Infinity. */
export function waitMinutes(p, nowMs = Date.now()) {
  const t = vnTime(p.last_ended || p.last_played);
  if (t == null) return Infinity;
  return Math.max(0, Math.round((nowMs - t) / 60000));
}

/**
 * Thứ tự ưu tiên vào sân: chờ lâu nhất trước (chưa đánh = chờ vô hạn), rồi ít trận
 * hơn, rồi tên. Elo không dùng để CHỌN ai vào — chỉ để CHIA cặp cho cân.
 */
export function byPriority(list, nowMs = Date.now()) {
  return list
    .map((p) => ({ p, w: waitMinutes(p, nowMs) }))
    .sort((a, b) => (b.w - a.w) || ((a.p.played || 0) - (b.p.played || 0)) || String(a.p.name).localeCompare(String(b.p.name), "vi"))
    .map((x) => x.p);
}

/** id đang đứng trên bất kỳ sân nào. */
export function onCourtIds(board) {
  const s = new Set();
  for (const c of board.courts) for (const id of c.slots) if (id) s.add(id);
  return s;
}

/** Sân nào đang giữ id (index) hoặc -1. */
export function courtOf(board, id) {
  return board.courts.findIndex((c) => c.slots.includes(id));
}

/** Gỡ id khỏi mọi ô (bất biến: trả board mới). */
export function removeEverywhere(board, id) {
  return { ...board, courts: board.courts.map((c) => ({ ...c, slots: c.slots.map((x) => (x === id ? null : x)) })) };
}

/**
 * Đặt id vào ô [ci, si]. Người đó đang ở chỗ khác thì được dời qua (không bao giờ ở
 * 2 ô). Ô đích đang có người thì người cũ bị đẩy ra khay.
 */
export function place(board, ci, si, id) {
  const b = removeEverywhere(board, id);
  const courts = b.courts.map((c, i) => (i === ci ? { ...c, slots: c.slots.map((x, j) => (j === si ? id : x)) } : c));
  const present = b.present.includes(id) ? b.present : [...b.present, id];
  return { ...b, courts, present };
}

/**
 * Kéo-thả: thả id vào ô [ci, si].
 *  - Kéo từ một ô khác sang ô đang có người -> ĐỔI CHỖ hai người.
 *  - Kéo từ khay vào ô đang có người -> người cũ về khay.
 *  - Thả vào chính ô của mình -> không đổi gì.
 */
export function moveTo(board, ci, si, id) {
  const target = board.courts[ci]?.slots[si];
  if (target === undefined || target === id) return board;
  const fromCi = courtOf(board, id);
  if (target && fromCi >= 0) {
    const fromSi = board.courts[fromCi].slots.indexOf(id);
    const courts = board.courts.map((c, i) => ({
      ...c,
      slots: c.slots.map((x, j) => {
        if (i === ci && j === si) return id;
        if (i === fromCi && j === fromSi) return target;
        return x;
      }),
    }));
    return { ...board, courts };
  }
  return place(board, ci, si, id);
}

/** Ô trống đầu tiên của sân, ưu tiên ô [pref] nếu trống. -1 nếu đầy. */
export function firstEmpty(court, pref = -1) {
  if (pref >= 0 && !court.slots[pref]) return pref;
  return court.slots.findIndex((x) => !x);
}

/**
 * Tự xếp sân ci từ khay (người có mặt, chưa ở sân nào), theo byPriority.
 *  - Sân trống hẳn: lấy 4 người ưu tiên nhất, chia 2 cặp lệch Elo ít nhất.
 *  - Sân đã có vài người: chỉ lấp ô trống theo thứ tự ưu tiên, giữ người đã xếp.
 * Thiếu người thì lấp được bao nhiêu hay bấy nhiêu.
 */
export function autoFill(board, ci, people, nowMs = Date.now()) {
  const busy = onCourtIds(board);
  const tray = byPriority(people.filter((p) => board.present.includes(p.id) && !busy.has(p.id)), nowMs);
  const court = board.courts[ci];
  const empties = court.slots.map((x, i) => (x ? -1 : i)).filter((i) => i >= 0);
  if (!empties.length || !tray.length) return board;
  let slots = court.slots.slice();
  if (empties.length === 4 && tray.length >= 4) {
    const pr = balancePairs(tray.slice(0, 4));
    slots = [pr.red[0].id, pr.red[1].id, pr.blue[0].id, pr.blue[1].id];
  } else {
    empties.forEach((si, k) => { if (tray[k]) slots[si] = tray[k].id; });
  }
  return { ...board, courts: board.courts.map((c, i) => (i === ci ? { ...c, slots } : c)) };
}

/** Kết thúc trận trên sân ci: 4 người về khay (vẫn có mặt). */
export function clearCourt(board, ci) {
  return { ...board, courts: board.courts.map((c, i) => (i === ci ? { ...c, slots: [null, null, null, null] } : c)) };
}

export function addCourt(board) {
  if (board.courts.length >= MAX_COURTS) return board;
  return { ...board, courts: [...board.courts, emptyCourt(board.courts.length)] };
}

/** Xoá sân ci (người trên đó về khay). Luôn chừa ít nhất 1 sân. */
export function removeCourt(board, ci) {
  if (board.courts.length <= 1) return board;
  const courts = board.courts.filter((_, i) => i !== ci).map((c, i) => ({ ...c, name: /^Sân \d+$/.test(c.name) ? `Sân ${i + 1}` : c.name }));
  return { ...board, courts };
}

/** Bật/tắt có mặt. Tắt thì gỡ luôn khỏi sân. */
export function togglePresent(board, id) {
  if (board.present.includes(id)) {
    const b = removeEverywhere(board, id);
    return { ...b, present: b.present.filter((x) => x !== id) };
  }
  return { ...board, present: [...board.present, id] };
}

/** "chờ 25'" / "chờ 1h05" / "chưa đánh". */
export function waitLabel(p, nowMs = Date.now()) {
  const w = waitMinutes(p, nowMs);
  if (w === Infinity) return "chưa đánh";
  if (w < 60) return `chờ ${w}'`;
  return `chờ ${Math.floor(w / 60)}h${String(w % 60).padStart(2, "0")}`;
}

/** Ngày YYYY-MM-DD cộng n ngày (không phụ thuộc múi giờ máy). */
export function shiftDay(day, n) {
  const d = new Date(day + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

const DOW = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"];
/** "T2 · 23/11" */
export function dayLabel(day) {
  const d = new Date(day + "T00:00:00Z");
  return `${DOW[d.getUTCDay()]} · ${String(d.getUTCDate()).padStart(2, "0")}/${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}
