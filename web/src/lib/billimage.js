// Xuất ảnh bằng canvas — style theo minimal UI: nền sáng, card trắng bo tròn,
// bóng mềm nhiều lớp, tiêu đề Barlow, số Roboto Mono, xanh sân #256E4E / hổ phách.
import * as M from "./model.js";

const IMG_W = 1080, S = 2, BILL_W = 1400;
const C = {
  bg: "#F4F6F8", paper: "#FFFFFF", ink: "#1C252E", soft: "#637381", faint: "#919EAB", line: "#EDEFF2",
  primary: "#256E4E", primaryDark: "#143D2B", primaryTint: "#E7F0EB",
  due: "#B76E00", dueTint: "#FFF7E6", ok: "#118D57", okTint: "#E7F6EC",
};
const SANS = (w, s) => `${w} ${s}px "Be Vietnam Pro",-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif`;
const DISP = (w, s) => `${w} ${s}px "Barlow","Be Vietnam Pro",-apple-system,Arial,sans-serif`;
const MONO = (w, s) => `${w} ${s}px "Roboto Mono",ui-monospace,Menlo,Consolas,monospace`;

const loadImg = (src) => new Promise((res) => { const i = new Image(); i.onload = () => res(i); i.onerror = () => res(null); i.src = src; });
// canvas chỉ dùng được font đã nạp — chờ các weight cần thiết sẵn sàng.
async function readyFonts() {
  try {
    await Promise.all([
      document.fonts.load('800 48px "Barlow"'), document.fonts.load('700 32px "Barlow"'),
      document.fonts.load('800 80px "Roboto Mono"'), document.fonts.load('700 38px "Roboto Mono"'), document.fonts.load('400 24px "Roboto Mono"'),
      document.fonts.load('700 32px "Be Vietnam Pro"'), document.fonts.load('400 24px "Be Vietnam Pro"'),
    ]);
    await document.fonts.ready;
  } catch { /* fallback hệ thống */ }
}
function rrect(x, rx, ry, w, h, r) { x.beginPath(); if (x.roundRect) x.roundRect(rx, ry, w, h, r); else { x.moveTo(rx + r, ry); x.arcTo(rx + w, ry, rx + w, ry + h, r); x.arcTo(rx + w, ry + h, rx, ry + h, r); x.arcTo(rx, ry + h, rx, ry, r); x.arcTo(rx, ry, rx + w, ry, r); x.closePath(); } }
// thẻ trắng bo tròn + bóng mềm (xong thì tắt bóng để vẽ nội dung sắc nét)
function card(x, rx, ry, w, h, r, fill) {
  x.save(); x.shadowColor = "rgba(99,115,129,0.16)"; x.shadowBlur = 28; x.shadowOffsetY = 12;
  rrect(x, rx, ry, w, h, r); x.fillStyle = fill || C.paper; x.fill(); x.restore();
}
function clipText(x, str, maxW) { if (x.measureText(str).width <= maxW) return str; let s = str; while (s.length > 1 && x.measureText(s + "…").width > maxW) s = s.slice(0, -1); return s + "…"; }
function drawAvatar(x, img, m, ax, ay, d) {
  x.save(); x.beginPath(); x.arc(ax + d / 2, ay + d / 2, d / 2, 0, Math.PI * 2); x.clip();
  if (img) x.drawImage(img, ax, ay, d, d);
  else { x.fillStyle = M.hue(m.id); x.fillRect(ax, ay, d, d); x.fillStyle = "#fff"; x.font = SANS(700, Math.round(d * 0.36)); x.textAlign = "center"; x.textBaseline = "middle"; x.fillText(M.initials(m.name), ax + d / 2, ay + d / 2 + 1); }
  x.restore(); x.textAlign = "left"; x.textBaseline = "alphabetic";
}
function mkCanvas(h, w) { const W = w || IMG_W, c = document.createElement("canvas"); c.width = W * S; c.height = Math.round(h) * S; const x = c.getContext("2d"); x.scale(S, S); x.fillStyle = C.bg; x.fillRect(0, 0, W, h); return { c, x }; }
function cropTo(c, h) { const out = document.createElement("canvas"); out.width = c.width; out.height = Math.round(h) * S; out.getContext("2d").drawImage(c, 0, 0); return out; }
function stampLine(x, y, w, updatedAt) { x.fillStyle = C.faint; x.font = SANS(400, 21); x.textAlign = "center"; const t = updatedAt ? new Date(updatedAt).toLocaleString("vi-VN", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }) : "—"; x.fillText("Cập nhật lúc " + t + " · vừa chuyển thì đợi ghi nhận nhé", (w || IMG_W) / 2, y); x.textAlign = "left"; }
function drawCover(x, img, dx, dy, dw, dh, r) { const k = Math.max(dw / img.width, dh / img.height), sw = dw / k, sh = dh / k; x.save(); rrect(x, dx, dy, dw, dh, r); x.clip(); x.drawImage(img, (img.width - sw) / 2, (img.height - sh) / 2, sw, sh, dx, dy, dw, dh); x.restore(); }
function groupRef(ms) { if (ms.length === 1) return M.payRef(ms[0]); return ("CAULONG " + ms.map((m) => M.norm(m.name).replace(/[^a-z0-9]+/g, " ").trim().toUpperCase()).join(" ")).slice(0, 40); }
const out = (c, h, filename) => ({ url: cropTo(c, h).toDataURL("image/png"), filename });

export const exportPersonImage = (book, updatedAt, m) => exportBillImage(book, updatedAt, [m]);

export async function exportBillImage(book, updatedAt, list) {
  await readyFonts();
  const W = BILL_W, P = 64, ms = list.filter(Boolean);
  if (!ms.length) return { error: "Chưa chọn ai." };
  const group = ms.length > 1;
  const per = ms.map((m) => ({ m, ses: M.memberDueSessions(book, m.id), due: M.memberDue(book, m.id), paid: M.memberPaidSum(book, m.id) })).filter((r) => !group || r.due > M.EPS);
  if (!per.length) return { error: "Những người đã chọn không còn nợ buổi nào." };
  const due = per.reduce((a, r) => a + r.due, 0);
  const nRows = per.reduce((a, r) => a + r.ses.length, 0);
  const hasQR = !!book.qr && due > M.EPS;
  const { c, x } = mkCanvas(940 + nRows * 172 + per.length * 128 + (hasQR ? 640 : 0), W);

  const need = new Map(), photos = new Map();
  per.forEach((r) => { need.set(r.m.id, r.m); r.ses.forEach((s2) => { s2.parts.forEach((p) => { const mm = M.memById(book, p.mid); if (mm) need.set(mm.id, mm); }); if (s2.photo) photos.set(s2.id, s2.photo); }); });
  const avImg = new Map(), phImg = new Map();
  await Promise.all([...[...need.values()].map(async (mm) => { if (mm.av) avImg.set(mm.id, await loadImg(mm.av)); }), ...[...photos].map(async ([k, v]) => { phImg.set(k, await loadImg(v)); })]);
  const qr = hasQR ? await loadImg(book.qr) : null;
  let y = P;

  // đầu ảnh
  if (!group) {
    const m = per[0].m;
    drawAvatar(x, avImg.get(m.id), m, P, y, 112);
    x.fillStyle = C.ink; x.font = DISP(800, 50); x.fillText(clipText(x, M.fullName(book, m), W - P * 2 - 150), P + 140, y + 52);
    x.fillStyle = C.soft; x.font = SANS(500, 26); x.fillText(M.memberSessions(book, m.id).length + " buổi đã chơi", P + 140, y + 92);
    y += 150;
  } else {
    const shownHead = per.slice(0, 8);
    shownHead.forEach((r, i) => { x.beginPath(); x.arc(P + i * 60 + 44, y + 44, 46, 0, Math.PI * 2); x.fillStyle = C.bg; x.fill(); drawAvatar(x, avImg.get(r.m.id), r.m, P + i * 60, y, 86); });
    const tx = P + (shownHead.length - 1) * 60 + 116;
    x.fillStyle = C.ink; x.font = DISP(800, 44); x.fillText(`Hoá đơn gộp · ${per.length} người`, tx, y + 42);
    x.fillStyle = C.soft; x.font = SANS(500, 25); x.fillText(clipText(x, per.map((r) => M.fullName(book, r.m)).join(" + "), W - tx - P), tx, y + 80);
    y += 124;
  }
  y += 24;

  // hero "cần chuyển"
  card(x, P, y, W - P * 2, 176, 24, due > M.EPS ? C.dueTint : C.primaryTint);
  x.textAlign = "center";
  x.fillStyle = due > M.EPS ? C.due : C.primary; x.font = SANS(700, 24); x.globalAlpha = 0.8;
  x.fillText(due > M.EPS ? (group ? `TỔNG CẦN CHUYỂN · ${per.length} NGƯỜI` : "CẦN CHUYỂN") : "TÌNH TRẠNG", W / 2, y + 52); x.globalAlpha = 1;
  x.fillStyle = due > M.EPS ? C.due : C.primary; x.font = MONO(800, due > M.EPS ? 84 : 56);
  x.fillText(due > M.EPS ? M.fmt(due) : "Đã trả đủ ✓", W / 2, y + 126);
  if (due > M.EPS) { x.fillStyle = C.soft; x.font = MONO(400, 24); x.fillText(M.vnd(due), W / 2, y + 158); }
  x.textAlign = "left"; y += 176 + 36;

  const ROW = 148, PH = 112, AV = 42, STEP = 32, AMT_W = 200, STRIP_MAX = 440;
  per.forEach((r) => {
    if (group) {
      drawAvatar(x, avImg.get(r.m.id), r.m, P, y - 8, 52);
      x.fillStyle = C.ink; x.font = DISP(700, 34); x.fillText(M.fullName(book, r.m), P + 68, y + 24);
      x.fillStyle = C.soft; x.font = SANS(500, 22); x.fillText(`${r.ses.length} buổi chưa trả`, P + 68, y + 54);
      x.textAlign = "right"; x.fillStyle = C.due; x.font = MONO(800, 38); x.fillText(M.fmt(r.due), W - P, y + 32); x.textAlign = "left";
      y += 88;
    } else if (r.ses.length) { x.fillStyle = C.faint; x.font = SANS(700, 23); x.fillText("CÁC BUỔI CHƯA TRẢ", P, y + 4); y += 30; }
    r.ses.forEach((s2) => {
      card(x, P, y, W - P * 2, ROW, 18);
      let tx = P + 28; const ph = phImg.get(s2.id);
      if (ph) { drawCover(x, ph, P + 20, y + 20, PH, PH, 14); tx = P + 20 + PH + 24; }
      const parts = s2.parts.map((p) => M.memById(book, p.mid)).filter(Boolean);
      const meIdx = parts.findIndex((mm) => mm.id === r.m.id);
      if (meIdx > 0) { parts.unshift(parts.splice(meIdx, 1)[0]); }
      const maxN = Math.max(1, Math.floor((STRIP_MAX - AV) / STEP) + 1);
      const shown = parts.length > maxN ? parts.slice(0, maxN - 1) : parts, more = parts.length - shown.length;
      const cnt = shown.length + (more ? 1 : 0), stripW = AV + (cnt - 1) * STEP;
      const stripR = W - P - 28 - AMT_W, sx = stripR - stripW, sy = y + 30;
      shown.forEach((mm, i) => { const ax = sx + i * STEP; x.beginPath(); x.arc(ax + AV / 2, sy + AV / 2, AV / 2 + 3, 0, Math.PI * 2); x.fillStyle = mm.id === r.m.id ? C.due : C.paper; x.fill(); drawAvatar(x, avImg.get(mm.id), mm, ax, sy, AV); });
      if (more) { const ax = sx + shown.length * STEP; x.beginPath(); x.arc(ax + AV / 2, sy + AV / 2, AV / 2, 0, Math.PI * 2); x.fillStyle = C.primaryTint; x.fill(); x.fillStyle = C.primary; x.font = SANS(700, 15); x.textAlign = "center"; x.fillText("+" + more, ax + AV / 2, sy + AV / 2 + 5); x.textAlign = "left"; }
      x.fillStyle = C.faint; x.font = SANS(400, 20); x.textAlign = "right"; x.fillText(parts.length + " người chơi", stripR, sy + AV + 32); x.textAlign = "left";
      const textW = sx - tx - 24;
      x.fillStyle = C.ink; x.font = DISP(700, 32); x.fillText(clipText(x, s2.date || "—", textW), tx, y + 56);
      x.fillStyle = C.soft; x.font = MONO(400, 21); x.fillText(clipText(x, `(${s2.court} + ${s2.shuttles}×${s2.price || M.DEFAULT_PRICE}) / ${M.wStr(M.sWeight(s2))} suất = ${M.fmt(M.sPerUnit(s2))}/suất`, textW), tx, y + 92);
      const w = (s2.parts.find((p) => p.mid === r.m.id) || {}).weight;
      if (w !== 1) { x.fillStyle = C.due; x.font = SANS(600, 21); x.fillText(clipText(x, `× ${M.wStr(w)} suất` + (w > 1 ? " (gồm người đi cùng)" : ""), textW), tx, y + 122); }
      x.textAlign = "right"; x.fillStyle = C.due; x.font = MONO(700, 40); x.fillText(M.fmt(M.shareIn(s2, r.m.id)), W - P - 28, y + ROW / 2 + 14); x.textAlign = "left";
      y += ROW + 16;
    });
    if (!group && !r.ses.length) { x.fillStyle = C.ok; x.font = SANS(600, 30); x.textAlign = "center"; x.fillText("Không còn buổi nào đang nợ 🎉", W / 2, y + 40); x.textAlign = "left"; y += 70; }
    if (r.paid > M.EPS) { x.fillStyle = C.ok; x.font = SANS(600, 24); x.fillText("✓ Đã trả trước đó " + M.fmt(r.paid) + " (" + M.memberSessions(book, r.m.id).filter((s2) => M.isPaid(s2, r.m.id)).length + " buổi)", P, y + 24); y += 46; }
    if (group) y += 32;
  });

  // chuyển khoản
  if (due > M.EPS) {
    y += 20; card(x, P, y, W - P * 2, (book.note ? 70 : 0) + (qr ? 420 : 0) + 128, 22);
    y += 48; x.textAlign = "center";
    x.fillStyle = C.faint; x.font = SANS(700, 23); x.fillText("NỘI DUNG CHUYỂN KHOẢN", W / 2, y);
    x.fillStyle = C.primary; x.font = MONO(700, 34); x.fillText(groupRef(per.map((r) => r.m)), W / 2, y + 48); y += 86;
    if (book.note) { x.fillStyle = C.ink; x.font = SANS(600, 28); x.fillText(clipText(x, book.note, W - P * 2 - 80), W / 2, y + 24); y += 54; }
    if (qr) { const d = 320; x.drawImage(qr, (W - d) / 2, y + 8, d, d * qr.height / qr.width); y += d * qr.height / qr.width + 24; }
    x.textAlign = "left"; y += 20;
  } else y += 36;

  stampLine(x, y + 34, W, updatedAt);
  const name = group ? "hoa-don-gop-" + per.length + "-nguoi" : M.norm(per[0].m.name).replace(/\s+/g, "-");
  return out(c, y + 62, "caulong-" + name + ".png");
}

export async function exportBoardImage(book, updatedAt) {
  await readyFonts();
  const rows = M.debtors(book).map((m) => ({ m, due: M.memberDue(book, m.id), n: M.memberDueSessions(book, m.id).length })).sort((a, b) => b.due - a.due);
  const due = M.totalDue(book), got = M.totalCollected(book), all = due + got;
  const P = 60, hasQR = !!book.qr;
  const { c, x } = mkCanvas(640 + rows.length * 104 + (book.note ? 64 : 0) + (hasQR ? 600 : 0));
  const avs = await Promise.all(rows.map((r) => (r.m.av ? loadImg(r.m.av) : Promise.resolve(null))));
  const qr = hasQR ? await loadImg(book.qr) : null;
  let y = P;

  x.fillStyle = C.ink; x.font = DISP(800, 54); x.fillText("Tiền cầu lông", P, y + 48);
  x.fillStyle = C.soft; x.font = SANS(500, 26); x.fillText(book.sessions.length + " buổi · " + book.members.length + " người", P, y + 88); y += 124;

  // hai ô tổng kiểu WidgetSummary
  const colW = (IMG_W - P * 2 - 24) / 2;
  card(x, P, y, colW, 132, 20, C.dueTint);
  x.fillStyle = C.due; x.font = SANS(700, 22); x.globalAlpha = 0.8; x.fillText("CÒN THIẾU", P + 28, y + 44); x.globalAlpha = 1;
  x.fillStyle = C.due; x.font = MONO(800, 46); x.fillText(M.fmt(due), P + 28, y + 100);
  card(x, P + colW + 24, y, colW, 132, 20, C.primaryTint);
  x.fillStyle = C.primary; x.font = SANS(700, 22); x.globalAlpha = 0.8; x.fillText("ĐÃ THU", P + colW + 52, y + 44); x.globalAlpha = 1;
  x.fillStyle = C.primary; x.font = MONO(800, 46); x.fillText(M.fmt(got) + " / " + M.fmt(all), P + colW + 52, y + 100);
  y += 132 + 36;

  if (rows.length) {
    x.fillStyle = C.faint; x.font = SANS(700, 23); x.fillText("AI CÒN NỢ", P, y); y += 40;
    rows.forEach((r, i) => {
      card(x, P, y, IMG_W - P * 2, 84, 16);
      drawAvatar(x, avs[i], r.m, P + 18, y + 16, 52);
      x.fillStyle = C.ink; x.font = DISP(700, 30); x.fillText(clipText(x, M.fullName(book, r.m), IMG_W - P * 2 - 340), P + 88, y + 38);
      x.fillStyle = C.soft; x.font = SANS(400, 22); x.fillText(r.n + " buổi chưa trả", P + 88, y + 66);
      x.textAlign = "right"; x.fillStyle = C.due; x.font = MONO(700, 34); x.fillText(M.fmt(r.due), IMG_W - P - 24, y + 52); x.textAlign = "left";
      y += 96;
    });
  } else { x.fillStyle = C.ok; x.font = DISP(700, 36); x.textAlign = "center"; x.fillText("Không ai còn nợ 🎉", IMG_W / 2, y + 46); x.textAlign = "left"; y += 84; }

  x.textAlign = "center";
  if (book.note) { x.fillStyle = C.ink; x.font = SANS(600, 28); x.fillText(clipText(x, book.note, IMG_W - P * 2), IMG_W / 2, y + 40); y += 56; }
  if (qr) { const d = 300, h = d * qr.height / qr.width; x.drawImage(qr, (IMG_W - d) / 2, y + 12, d, h); y += h + 30; }
  x.textAlign = "left";
  stampLine(x, y + 34, IMG_W, updatedAt);
  return out(c, y + 60, "caulong-bang-tong.png");
}
