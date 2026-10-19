// Xuất ảnh bằng canvas (không thư viện ngoài) — port §5 của sổ gốc.
// Trả { url, filename } (PNG dataURL) hoặc { error } — component hiện dialog + tải về.
import * as M from "./model.js";

const IMG_W = 1080, S = 2, BILL_W = 1400;
const C = { paper: "#F6F7F4", card: "#FFFFFF", ink: "#17211D", soft: "#5A655E", line: "#E2E6DF", court: "#256E4E", tint: "#E8F0EB", amber: "#B7601F", amberT: "#F7ECE1" };
const F = (w, s) => `${w} ${s}px -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif`;
const FM = (w, s) => `${w} ${s}px ui-monospace,Menlo,Consolas,monospace`;

const loadImg = (src) => new Promise((res) => { const i = new Image(); i.onload = () => res(i); i.onerror = () => res(null); i.src = src; });
function rrect(x, rx, ry, w, h, r) { x.beginPath(); if (x.roundRect) x.roundRect(rx, ry, w, h, r); else { x.moveTo(rx + r, ry); x.arcTo(rx + w, ry, rx + w, ry + h, r); x.arcTo(rx + w, ry + h, rx, ry + h, r); x.arcTo(rx, ry + h, rx, ry, r); x.arcTo(rx, ry, rx + w, ry, r); x.closePath(); } }
function clipText(x, str, maxW) { if (x.measureText(str).width <= maxW) return str; let s = str; while (s.length > 1 && x.measureText(s + "…").width > maxW) s = s.slice(0, -1); return s + "…"; }
function drawAvatar(x, img, m, ax, ay, d) {
  x.save(); x.beginPath(); x.arc(ax + d / 2, ay + d / 2, d / 2, 0, Math.PI * 2); x.clip();
  if (img) x.drawImage(img, ax, ay, d, d);
  else { x.fillStyle = M.hue(m.id); x.fillRect(ax, ay, d, d); x.fillStyle = "#fff"; x.font = F(700, Math.round(d * 0.36)); x.textAlign = "center"; x.textBaseline = "middle"; x.fillText(M.initials(m.name), ax + d / 2, ay + d / 2 + 1); }
  x.restore(); x.textAlign = "left"; x.textBaseline = "alphabetic";
}
function mkCanvas(h, w) { const W = w || IMG_W, c = document.createElement("canvas"); c.width = W * S; c.height = Math.round(h) * S; const x = c.getContext("2d"); x.scale(S, S); x.fillStyle = C.paper; x.fillRect(0, 0, W, h); return { c, x }; }
function cropTo(c, h) { const out = document.createElement("canvas"); out.width = c.width; out.height = Math.round(h) * S; out.getContext("2d").drawImage(c, 0, 0); return out; }
function stampLine(x, y, w, updatedAt) { x.fillStyle = C.soft; x.font = F(400, 22); x.textAlign = "center"; const t = updatedAt ? new Date(updatedAt).toLocaleString("vi-VN", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }) : "—"; x.fillText("Số liệu cập nhật lúc " + t + " · nếu bạn vừa chuyển thì đợi ghi nhận nhé", (w || IMG_W) / 2, y); x.textAlign = "left"; }
function drawCover(x, img, dx, dy, dw, dh, r) { const k = Math.max(dw / img.width, dh / img.height), sw = dw / k, sh = dh / k; x.save(); rrect(x, dx, dy, dw, dh, r); x.clip(); x.drawImage(img, (img.width - sw) / 2, (img.height - sh) / 2, sw, sh, dx, dy, dw, dh); x.restore(); }
function groupRef(ms) { if (ms.length === 1) return M.payRef(ms[0]); return ("CAULONG " + ms.map((m) => M.norm(m.name).replace(/[^a-z0-9]+/g, " ").trim().toUpperCase()).join(" ")).slice(0, 40); }
const out = (c, h, filename) => ({ url: cropTo(c, h).toDataURL("image/png"), filename });

export const exportPersonImage = (book, updatedAt, m) => exportBillImage(book, updatedAt, [m]);

export async function exportBillImage(book, updatedAt, list) {
  const W = BILL_W, P = 60, ms = list.filter(Boolean);
  if (!ms.length) return { error: "Chưa chọn ai." };
  const group = ms.length > 1;
  const per = ms.map((m) => ({ m, ses: M.memberDueSessions(book, m.id), due: M.memberDue(book, m.id), paid: M.memberPaidSum(book, m.id) }))
    .filter((r) => !group || r.due > M.EPS);
  if (!per.length) return { error: "Những người đã chọn không còn nợ buổi nào." };
  const due = per.reduce((a, r) => a + r.due, 0);
  const nRows = per.reduce((a, r) => a + r.ses.length, 0);
  const hasQR = !!book.qr && due > M.EPS;
  const { c, x } = mkCanvas(900 + nRows * 160 + per.length * 120 + (hasQR ? 640 : 0), W);

  const need = new Map(), photos = new Map();
  per.forEach((r) => { need.set(r.m.id, r.m); r.ses.forEach((s2) => { s2.parts.forEach((p) => { const mm = M.memById(book, p.mid); if (mm) need.set(mm.id, mm); }); if (s2.photo) photos.set(s2.id, s2.photo); }); });
  const avImg = new Map(), phImg = new Map();
  await Promise.all([
    ...[...need.values()].map(async (mm) => { if (mm.av) avImg.set(mm.id, await loadImg(mm.av)); }),
    ...[...photos].map(async ([k, v]) => { phImg.set(k, await loadImg(v)); })]);
  const qr = hasQR ? await loadImg(book.qr) : null;
  let y = P;

  if (!group) {
    const m = per[0].m;
    drawAvatar(x, avImg.get(m.id), m, P, y, 120);
    x.fillStyle = C.ink; x.font = F(700, 48); x.fillText(clipText(x, M.fullName(book, m), W - P * 2 - 160), P + 150, y + 58);
    x.fillStyle = C.soft; x.font = F(400, 27); x.fillText(M.memberSessions(book, m.id).length + " buổi đã chơi", P + 150, y + 100);
    y += 160;
  } else {
    const shownHead = per.slice(0, 8);
    shownHead.forEach((r, i) => { x.beginPath(); x.arc(P + i * 62 + 45, y + 45, 48, 0, Math.PI * 2); x.fillStyle = C.paper; x.fill(); drawAvatar(x, avImg.get(r.m.id), r.m, P + i * 62, y, 90); });
    const tx = P + (shownHead.length - 1) * 62 + 120;
    x.fillStyle = C.ink; x.font = F(700, 44); x.fillText(`Hoá đơn gộp · ${per.length} người`, tx, y + 44);
    x.fillStyle = C.soft; x.font = F(400, 26); x.fillText(clipText(x, per.map((r) => M.fullName(book, r.m)).join(" + "), W - tx - P), tx, y + 82);
    y += 130;
  }
  x.fillStyle = C.line; x.fillRect(P, y, W - P * 2, 2); y += 30;

  rrect(x, P, y, W - P * 2, 160, 22); x.fillStyle = due > M.EPS ? C.amberT : C.tint; x.fill();
  x.textAlign = "center"; x.fillStyle = C.soft; x.font = F(700, 25);
  x.fillText(due > M.EPS ? (group ? `TỔNG CẦN CHUYỂN (${per.length} NGƯỜI)` : "CẦN CHUYỂN") : "TÌNH TRẠNG", W / 2, y + 46);
  x.fillStyle = due > M.EPS ? C.amber : C.court; x.font = FM(800, due > M.EPS ? 80 : 54);
  x.fillText(due > M.EPS ? M.fmt(due) : "Đã trả đủ ✓", W / 2, y + 118);
  if (due > M.EPS) { x.fillStyle = C.soft; x.font = FM(400, 25); x.fillText(M.vnd(due), W / 2, y + 150); }
  x.textAlign = "left"; y += 200;

  const ROW = 136, PH = 104, AV = 40, STEP = 30, AMT_W = 190, STRIP_MAX = 440;
  per.forEach((r) => {
    if (group) {
      drawAvatar(x, avImg.get(r.m.id), r.m, P, y - 10, 50);
      x.fillStyle = C.ink; x.font = F(700, 32); x.fillText(M.fullName(book, r.m), P + 64, y + 26);
      x.fillStyle = C.soft; x.font = F(400, 22); x.fillText(`${r.ses.length} buổi chưa trả`, P + 64, y + 56);
      x.textAlign = "right"; x.fillStyle = C.amber; x.font = FM(800, 36); x.fillText(M.fmt(r.due), W - P - 24, y + 34); x.textAlign = "left";
      y += 84;
    } else if (r.ses.length) { x.fillStyle = C.soft; x.font = F(700, 25); x.fillText("CÁC BUỔI CHƯA TRẢ", P, y); y += 26; }
    r.ses.forEach((s2) => {
      rrect(x, P, y, W - P * 2, ROW, 16); x.fillStyle = C.card; x.fill(); x.strokeStyle = C.line; x.lineWidth = 1.5; x.stroke();
      let tx = P + 24; const ph = phImg.get(s2.id);
      if (ph) { drawCover(x, ph, P + 16, y + 16, PH, PH, 12); tx = P + 16 + PH + 22; }
      const parts = s2.parts.map((p) => M.memById(book, p.mid)).filter(Boolean);
      const meIdx = parts.findIndex((mm) => mm.id === r.m.id);
      if (meIdx > 0) { parts.unshift(parts.splice(meIdx, 1)[0]); }
      const maxN = Math.max(1, Math.floor((STRIP_MAX - AV) / STEP) + 1);
      const shown = parts.length > maxN ? parts.slice(0, maxN - 1) : parts, more = parts.length - shown.length;
      const cnt = shown.length + (more ? 1 : 0), stripW = AV + (cnt - 1) * STEP;
      const stripR = W - P - 24 - AMT_W, sx = stripR - stripW, sy = y + 28;
      shown.forEach((mm, i) => { const ax = sx + i * STEP; x.beginPath(); x.arc(ax + AV / 2, sy + AV / 2, AV / 2 + 3, 0, Math.PI * 2); x.fillStyle = mm.id === r.m.id ? C.amber : C.card; x.fill(); drawAvatar(x, avImg.get(mm.id), mm, ax, sy, AV); });
      if (more) { const ax = sx + shown.length * STEP; x.beginPath(); x.arc(ax + AV / 2, sy + AV / 2, AV / 2 + 3, 0, Math.PI * 2); x.fillStyle = C.card; x.fill(); x.beginPath(); x.arc(ax + AV / 2, sy + AV / 2, AV / 2, 0, Math.PI * 2); x.fillStyle = C.tint; x.fill(); x.fillStyle = C.court; x.font = F(700, 15); x.textAlign = "center"; x.fillText("+" + more, ax + AV / 2, sy + AV / 2 + 5); x.textAlign = "left"; }
      x.fillStyle = C.soft; x.font = F(400, 20); x.textAlign = "right"; x.fillText(parts.length + " người chơi", stripR, sy + AV + 32); x.textAlign = "left";
      const textW = sx - tx - 24;
      x.fillStyle = C.ink; x.font = F(700, 32); x.fillText(clipText(x, s2.date || "—", textW), tx, y + 54);
      x.fillStyle = C.soft; x.font = FM(400, 22);
      x.fillText(clipText(x, `(${s2.court} + ${s2.shuttles}×${s2.price || M.DEFAULT_PRICE}) / ${M.wStr(M.sWeight(s2))} suất = ${M.fmt(M.sPerUnit(s2))}/suất`, textW), tx, y + 90);
      const w = (s2.parts.find((p) => p.mid === r.m.id) || {}).weight;
      if (w !== 1) { x.fillStyle = C.amber; x.font = F(600, 21); x.fillText(clipText(x, `× ${M.wStr(w)} suất` + (w > 1 ? " (gồm người đi cùng)" : ""), textW), tx, y + 120); }
      x.textAlign = "right"; x.fillStyle = C.amber; x.font = FM(700, 38); x.fillText(M.fmt(M.shareIn(s2, r.m.id)), W - P - 24, y + ROW / 2 + 13); x.textAlign = "left";
      y += ROW + 14;
    });
    if (!group && !r.ses.length) { x.fillStyle = C.soft; x.font = F(400, 29); x.textAlign = "center"; x.fillText("Không còn buổi nào đang nợ 🎉", W / 2, y + 40); x.textAlign = "left"; y += 70; }
    if (r.paid > M.EPS) { x.fillStyle = C.court; x.font = F(600, 24); x.fillText("✓ Đã trả trước đó " + M.fmt(r.paid) + " (" + M.memberSessions(book, r.m.id).filter((s2) => M.isPaid(s2, r.m.id)).length + " buổi)", P, y + 24); y += 44; }
    if (group) y += 30;
  });

  if (due > M.EPS) {
    y += 30; x.textAlign = "center";
    x.fillStyle = C.soft; x.font = F(700, 25); x.fillText("NỘI DUNG CHUYỂN KHOẢN", W / 2, y);
    x.fillStyle = C.ink; x.font = FM(700, 32); x.fillText(groupRef(per.map((r) => r.m)), W / 2, y + 44); y += 70;
    if (book.note) { x.fillStyle = C.ink; x.font = F(600, 30); x.fillText(clipText(x, book.note, W - P * 2), W / 2, y + 30); y += 48; }
    if (qr) { const d = 340; x.drawImage(qr, (W - d) / 2, y + 10, d, d * qr.height / qr.width); y += d * qr.height / qr.width + 30; }
    x.textAlign = "left";
  } else y += 40;

  stampLine(x, y + 34, W, updatedAt);
  const name = group ? "hoa-don-gop-" + per.length + "-nguoi" : M.norm(per[0].m.name).replace(/\s+/g, "-");
  return out(c, y + 60, "caulong-" + name + ".png");
}

export async function exportBoardImage(book, updatedAt) {
  const rows = M.debtors(book).map((m) => ({ m, due: M.memberDue(book, m.id), n: M.memberDueSessions(book, m.id).length })).sort((a, b) => b.due - a.due);
  const due = M.totalDue(book), got = M.totalCollected(book), all = due + got;
  const P = 56, hasQR = !!book.qr;
  const { c, x } = mkCanvas(620 + rows.length * 100 + (book.note ? 60 : 0) + (hasQR ? 600 : 0));
  const avs = await Promise.all(rows.map((r) => (r.m.av ? loadImg(r.m.av) : Promise.resolve(null))));
  const qr = hasQR ? await loadImg(book.qr) : null;
  let y = P;

  x.fillStyle = C.ink; x.font = F(800, 50); x.fillText("Tiền cầu lông", P, y + 46);
  x.fillStyle = C.soft; x.font = F(400, 26); x.fillText(book.sessions.length + " buổi · " + book.members.length + " người", P, y + 86); y += 120;

  rrect(x, P, y, IMG_W - P * 2, 96, 18); x.fillStyle = C.tint; x.fill();
  x.fillStyle = C.soft; x.font = F(700, 22); x.fillText("CÒN THIẾU", P + 26, y + 36);
  x.fillStyle = C.amber; x.font = FM(800, 42); x.fillText(M.fmt(due), P + 26, y + 78);
  x.textAlign = "right"; x.fillStyle = C.soft; x.font = F(700, 22); x.fillText("ĐÃ THU", IMG_W - P - 26, y + 36);
  x.fillStyle = C.court; x.font = FM(800, 42); x.fillText(M.fmt(got) + " / " + M.fmt(all), IMG_W - P - 26, y + 78);
  x.textAlign = "left"; y += 142;

  if (rows.length) {
    x.fillStyle = C.soft; x.font = F(700, 24); x.fillText("AI CÒN NỢ", P, y); y += 46;
    rows.forEach((r, i) => {
      rrect(x, P, y, IMG_W - P * 2, 80, 14); x.fillStyle = C.card; x.fill(); x.strokeStyle = C.line; x.lineWidth = 1.5; x.stroke();
      drawAvatar(x, avs[i], r.m, P + 16, y + 14, 52);
      x.fillStyle = C.ink; x.font = F(700, 30); x.fillText(clipText(x, M.fullName(book, r.m), IMG_W - P * 2 - 330), P + 84, y + 38);
      x.fillStyle = C.soft; x.font = F(400, 22); x.fillText(r.n + " buổi chưa trả", P + 84, y + 66);
      x.textAlign = "right"; x.fillStyle = C.amber; x.font = FM(700, 34); x.fillText(M.fmt(r.due), IMG_W - P - 20, y + 50); x.textAlign = "left";
      y += 92;
    });
  } else { x.fillStyle = C.court; x.font = F(700, 34); x.textAlign = "center"; x.fillText("Không ai còn nợ 🎉", IMG_W / 2, y + 46); x.textAlign = "left"; y += 80; }

  x.textAlign = "center";
  if (book.note) { x.fillStyle = C.ink; x.font = F(600, 28); x.fillText(clipText(x, book.note, IMG_W - P * 2), IMG_W / 2, y + 36); y += 50; }
  if (qr) { const d = 300, h = d * qr.height / qr.width; x.drawImage(qr, (IMG_W - d) / 2, y + 10, d, h); y += h + 30; }
  x.textAlign = "left";
  stampLine(x, y + 34, IMG_W, updatedAt);
  return out(c, y + 58, "caulong-bang-tong.png");
}
