// Xuất ảnh bằng canvas — kiểu "biên lai" theo minimal UI: dải đầu xanh sân có logo,
// khối số tiền hổ phách, danh sách buổi kẻ nét đứt, đường xé răng cưa, khối chuyển khoản.
// Chữ: Barlow (tiêu đề) · Be Vietnam Pro (chữ) · Roboto Mono (số). Số liệu lấy hết từ model.js.
import * as M from "./model.js";

const S = 2, BILL_W = 1200, BOARD_W = 1080;
const C = {
  bg: "#E9F1EC", bg2: "#F6F8F7", paper: "#FFFFFF", ink: "#1C252E", soft: "#637381", faint: "#919EAB",
  line: "#E3E8EC", neutral: "#F4F6F8",
  primary: "#256E4E", primaryLight: "#62A886", primaryDark: "#1A5139", primaryDarker: "#0E3324", primaryTint: "#E7F0EB",
  due: "#B76E00", dueMain: "#FFAB00", dueTint: "#FFF5E1", ok: "#118D57", okTint: "#E3F6EA",
};
const SANS = (w, s) => `${w} ${s}px "Be Vietnam Pro",-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Arial,sans-serif`;
const DISP = (w, s) => `${w} ${s}px "Barlow","Be Vietnam Pro",-apple-system,Arial,sans-serif`;
const MONO = (w, s) => `${w} ${s}px "Roboto Mono",ui-monospace,Menlo,Consolas,monospace`;

// logo của template (viewBox 512)
const LOGO = [
  "M86.352 246.358C137.511 214.183 161.836 245.017 183.168 285.573C165.515 317.716 153.837 337.331 148.132 344.418C137.373 357.788 125.636 367.911 111.202 373.752C80.856 388.014 43.132 388.681 14 371.048L86.352 246.358Z",
  "M444.31 229.726C398.04 148.77 350.21 72.498 295.267 184.382C287.751 198.766 282.272 226.719 270 226.719V226.577C257.728 226.577 252.251 198.624 244.735 184.24C189.79 72.356 141.96 148.628 95.689 229.584C92.207 235.69 88.862 241.516 86 246.58C192.038 179.453 183.11 382.247 270 383.858V384C356.891 382.389 347.962 179.595 454 246.72C451.139 241.658 447.794 235.832 444.31 229.726Z",
  "M450 384C476.509 384 498 362.509 498 336C498 309.491 476.509 288 450 288C423.491 288 402 309.491 402 336C402 362.509 423.491 384 450 384Z",
];

const loadImg = (src) => new Promise((res) => { const i = new Image(); i.onload = () => res(i); i.onerror = () => res(null); i.src = src; });
// canvas chỉ dùng được font đã nạp — chờ các weight cần thiết sẵn sàng.
async function readyFonts() {
  try {
    await Promise.all([
      document.fonts.load('800 48px "Barlow"'), document.fonts.load('700 32px "Barlow"'), document.fonts.load('600 32px "Barlow"'),
      document.fonts.load('700 80px "Roboto Mono"'), document.fonts.load('600 38px "Roboto Mono"'), document.fonts.load('500 24px "Roboto Mono"'),
      document.fonts.load('700 32px "Be Vietnam Pro"'), document.fonts.load('600 24px "Be Vietnam Pro"'), document.fonts.load('400 24px "Be Vietnam Pro"'),
    ]);
    await document.fonts.ready;
  } catch { /* fallback hệ thống */ }
}

// ---------- primitives ----------
function rrect(x, rx, ry, w, h, r) { x.beginPath(); if (x.roundRect) x.roundRect(rx, ry, w, h, r); else { x.moveTo(rx + r, ry); x.arcTo(rx + w, ry, rx + w, ry + h, r); x.arcTo(rx + w, ry + h, rx, ry + h, r); x.arcTo(rx, ry + h, rx, ry, r); x.arcTo(rx, ry, rx + w, ry, r); x.closePath(); } }
function fillR(x, rx, ry, w, h, r, fill) { rrect(x, rx, ry, w, h, r); x.fillStyle = fill; x.fill(); }
function clipText(x, str, maxW) { if (x.measureText(str).width <= maxW) return str; let s = str; while (s.length > 1 && x.measureText(s + "…").width > maxW) s = s.slice(0, -1); return s + "…"; }
function text(x, str, tx, ty, font, color, align = "left", maxW) {
  x.font = font; x.fillStyle = color; x.textAlign = align; x.textBaseline = "alphabetic";
  x.fillText(maxW ? clipText(x, str, maxW) : str, tx, ty); x.textAlign = "left";
}
function dashed(x, x1, x2, y, color = C.line, dash = [8, 8], w = 2) { x.save(); x.strokeStyle = color; x.lineWidth = w; x.setLineDash(dash); x.beginPath(); x.moveTo(x1, y); x.lineTo(x2, y); x.stroke(); x.restore(); }
function drawAvatar(x, img, m, ax, ay, d, ring) {
  if (ring) { x.beginPath(); x.arc(ax + d / 2, ay + d / 2, d / 2 + ring.w, 0, Math.PI * 2); x.fillStyle = ring.c; x.fill(); }
  x.save(); x.beginPath(); x.arc(ax + d / 2, ay + d / 2, d / 2, 0, Math.PI * 2); x.clip();
  if (img) x.drawImage(img, ax, ay, d, d);
  else { x.fillStyle = M.hue(m.id); x.fillRect(ax, ay, d, d); x.fillStyle = "#fff"; const ini = d < 50 ? M.initials(m.name).slice(0, 1) : M.initials(m.name); x.font = SANS(700, Math.round(d * (d < 50 ? 0.44 : 0.36))); x.textAlign = "center"; x.textBaseline = "middle"; x.fillText(ini, ax + d / 2, ay + d / 2 + 1); }
  x.restore(); x.textAlign = "left"; x.textBaseline = "alphabetic";
}
function drawCover(x, img, dx, dy, dw, dh, r) { const k = Math.max(dw / img.width, dh / img.height), sw = dw / k, sh = dh / k; x.save(); rrect(x, dx, dy, dw, dh, r); x.clip(); x.drawImage(img, (img.width - sw) / 2, (img.height - sh) / 2, sw, sh, dx, dy, dw, dh); x.restore(); }
function drawLogo(x, lx, ly, size, color) {
  x.save(); x.translate(lx, ly); x.scale(size / 512, size / 512); x.fillStyle = color;
  LOGO.forEach((d) => x.fill(new Path2D(d), "evenodd")); x.restore();
}
function pill(x, str, px, py, font, fg, bg, padX = 14, h = 34, align = "left") {
  x.font = font; const w = x.measureText(str).width + padX * 2; const sx = align === "right" ? px - w : align === "center" ? px - w / 2 : px;
  fillR(x, sx, py, w, h, h / 2, bg); x.fillStyle = fg; x.textBaseline = "middle"; x.fillText(str, sx + padX, py + h / 2 + 1); x.textBaseline = "alphabetic";
  return w;
}
function canvas(w, h, transparent) {
  const c = document.createElement("canvas"); c.width = w * S; c.height = Math.round(h) * S;
  const x = c.getContext("2d"); x.scale(S, S); if (!transparent) { x.fillStyle = C.paper; x.fillRect(0, 0, w, h); } return { c, x };
}
function groupRef(ms) { if (ms.length === 1) return M.payRef(ms[0]); return ("CAULONG " + ms.map((m) => M.norm(m.name).replace(/[^a-z0-9]+/g, " ").trim().toUpperCase()).join(" ")).slice(0, 40); }
const stampTxt = (updatedAt) => updatedAt ? new Date(updatedAt).toLocaleString("vi-VN", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—";

// Ghép: nền xanh nhạt + thẻ biên lai trắng (bóng mềm) + lớp nội dung, khoét răng cưa ở các mốc notch.
const MARGIN = 44, RADIUS = 36;
function compose(W, layer, contentH, notches) {
  const H = contentH + MARGIN * 2;
  const { c, x } = canvas(W, H);
  const g = x.createLinearGradient(0, 0, W, H); g.addColorStop(0, C.bg); g.addColorStop(1, C.bg2);
  x.fillStyle = g; x.fillRect(0, 0, W, H);
  // chấm hoa văn nhẹ
  x.fillStyle = "rgba(37,110,78,0.07)";
  for (let yy = 18; yy < H; yy += 28) for (let xx = 18 + ((yy / 28) % 2) * 14; xx < W; xx += 28) { x.beginPath(); x.arc(xx, yy, 1.6, 0, Math.PI * 2); x.fill(); }
  const cw = W - MARGIN * 2;
  x.save(); x.shadowColor = "rgba(14,51,36,0.16)"; x.shadowBlur = 48; x.shadowOffsetY = 20;
  fillR(x, MARGIN, MARGIN, cw, contentH, RADIUS, C.paper); x.restore();
  x.save(); rrect(x, MARGIN, MARGIN, cw, contentH, RADIUS); x.clip(); x.drawImage(layer, MARGIN, MARGIN, cw, contentH); x.restore();
  notches.forEach((ny) => {
    x.save(); x.beginPath(); x.rect(0, MARGIN + ny - 22, MARGIN + 1, 44); x.rect(W - MARGIN - 1, MARGIN + ny - 22, MARGIN + 1, 44); x.clip();
    x.fillStyle = g; x.fillRect(0, MARGIN + ny - 22, W, 44); x.restore();
    [MARGIN, W - MARGIN].forEach((cx) => { x.beginPath(); x.arc(cx, MARGIN + ny, 20, 0, Math.PI * 2); x.fillStyle = g; x.fill(); });
    dashed(x, MARGIN + 34, W - MARGIN - 34, MARGIN + ny, "#D5DCE1", [12, 10], 2.5);
  });
  return c;
}

// dải đầu xanh: logo + tên sổ + nhãn + ngày
function header(x, w, title, subtitle, updatedAt, h = 210) {
  const g = x.createLinearGradient(0, 0, w, h); g.addColorStop(0, C.primary); g.addColorStop(1, C.primaryDarker);
  x.fillStyle = g; x.fillRect(0, 0, w, h);
  // vòng tròn trang trí
  x.save(); x.globalAlpha = 0.08; x.fillStyle = "#fff";
  x.beginPath(); x.arc(w - 90, -30, 190, 0, Math.PI * 2); x.fill();
  x.beginPath(); x.arc(w - 300, h + 40, 120, 0, Math.PI * 2); x.fill(); x.restore();
  drawLogo(x, 52, 44, 64, "rgba(255,255,255,0.95)");
  text(x, "SỔ CẦU LÔNG", 132, 82, DISP(800, 36), "#fff");
  text(x, subtitle, 132, 114, SANS(500, 21), "rgba(255,255,255,0.72)");
  text(x, title, w - 52, 82, DISP(700, 26), "rgba(255,255,255,0.95)", "right");
  text(x, stampTxt(updatedAt), w - 52, 114, MONO(500, 19), "rgba(255,255,255,0.65)", "right");
  return h;
}

const out = (c, filename) => ({ url: c.toDataURL("image/png"), filename });

export const exportPersonImage = (book, updatedAt, m) => exportBillImage(book, updatedAt, [m]);

export async function exportBillImage(book, updatedAt, list) {
  await readyFonts();
  const ms = list.filter(Boolean);
  if (!ms.length) return { error: "Chưa chọn ai." };
  const group = ms.length > 1;
  const per = ms.map((m) => ({ m, ses: M.memberDueSessions(book, m.id), due: M.memberDue(book, m.id), paid: M.memberPaidSum(book, m.id) })).filter((r) => !group || r.due > M.EPS);
  if (!per.length) return { error: "Những người đã chọn không còn nợ buổi nào." };
  const due = per.reduce((a, r) => a + r.due, 0);
  const nRows = per.reduce((a, r) => a + r.ses.length, 0);
  const hasQR = !!book.qr && due > M.EPS;

  const need = new Map(), photos = new Map();
  per.forEach((r) => { need.set(r.m.id, r.m); r.ses.forEach((s2) => { s2.parts.forEach((p) => { const mm = M.memById(book, p.mid); if (mm) need.set(mm.id, mm); }); if (s2.photo) photos.set(s2.id, s2.photo); }); });
  const avImg = new Map(), phImg = new Map();
  await Promise.all([...[...need.values()].map(async (mm) => { if (mm.av) avImg.set(mm.id, await loadImg(mm.av)); }), ...[...photos].map(async ([k, v]) => { phImg.set(k, await loadImg(v)); })]);
  const qr = hasQR ? await loadImg(book.qr) : null;

  const W = BILL_W - MARGIN * 2, P = 56;
  const { c: layer, x } = canvas(W, 1200 + nRows * 190 + per.length * 160 + (hasQR ? 520 : 0), true);
  const notches = [];
  let y = header(x, W, group ? "HOÁ ĐƠN GỘP" : "HOÁ ĐƠN", "Biên nhận tiền sân + cầu", updatedAt);

  // ---- người nhận (avatar đè lên dải xanh) ----
  if (!group) {
    const m = per[0].m, AV = 132, ay = y - AV / 2;
    drawAvatar(x, avImg.get(m.id), m, P, ay, AV, { w: 7, c: C.paper });
    const tx = P + AV + 32;
    text(x, M.fullName(book, m), tx, y + 46, DISP(800, 50), C.ink, "left", W - tx - P);
    const nAll = M.memberSessions(book, m.id).length;
    let px = tx; px += pill(x, `${nAll} buổi đã chơi`, px, y + 66, SANS(600, 19), C.soft, C.neutral) + 10;
    if (per[0].ses.length) pill(x, `${per[0].ses.length} buổi chưa trả`, px, y + 66, SANS(600, 19), C.due, C.dueTint);
    else pill(x, "Đã trả đủ", px, y + 66, SANS(600, 19), C.ok, C.okTint);
    y += 136;
  } else {
    const shown = per.slice(0, 7), AV = 96, STEP = 62, ay = y - AV / 2;
    shown.forEach((r, i) => drawAvatar(x, avImg.get(r.m.id), r.m, P + i * STEP, ay, AV, { w: 6, c: C.paper }));
    if (per.length > shown.length) { const ax = P + shown.length * STEP; x.beginPath(); x.arc(ax + AV / 2, ay + AV / 2, AV / 2 + 6, 0, Math.PI * 2); x.fillStyle = C.paper; x.fill(); x.beginPath(); x.arc(ax + AV / 2, ay + AV / 2, AV / 2, 0, Math.PI * 2); x.fillStyle = C.primaryTint; x.fill(); text(x, "+" + (per.length - shown.length), ax + AV / 2, ay + AV / 2 + 10, DISP(700, 30), C.primary, "center"); }
    y += AV / 2 + 26;
    text(x, `${per.length} người · ${nRows} buổi chưa trả`, P, y + 30, DISP(800, 42), C.ink);
    text(x, per.map((r) => M.fullName(book, r.m)).join(" · "), P, y + 68, SANS(500, 22), C.soft, "left", W - P * 2);
    y += 100;
  }

  // ---- hero số tiền ----
  y += 12;
  const HH = due > M.EPS ? 210 : 150;
  const hg = x.createLinearGradient(P, y, W - P, y + HH);
  if (due > M.EPS) { hg.addColorStop(0, "#FFF8E6"); hg.addColorStop(1, "#FFEBC2"); } else { hg.addColorStop(0, C.okTint); hg.addColorStop(1, "#C9EFD6"); }
  fillR(x, P, y, W - P * 2, HH, 28, hg);
  x.save(); rrect(x, P, y, W - P * 2, HH, 28); x.clip(); x.globalAlpha = 0.1; x.fillStyle = due > M.EPS ? C.dueMain : C.ok;
  x.beginPath(); x.arc(W - P - 40, y + 20, 130, 0, Math.PI * 2); x.fill(); x.beginPath(); x.arc(P + 30, y + HH, 80, 0, Math.PI * 2); x.fill(); x.restore();
  if (due > M.EPS) {
    text(x, group ? `TỔNG CẦN CHUYỂN · ${per.length} NGƯỜI` : "CẦN CHUYỂN", W / 2, y + 54, SANS(700, 22), C.due, "center");
    text(x, M.fmt(due), W / 2, y + 140, MONO(700, 92), "#8A5200", "center");
    text(x, M.vnd(due), W / 2, y + 182, MONO(500, 24), C.due, "center");
  } else {
    text(x, "TÌNH TRẠNG", W / 2, y + 54, SANS(700, 22), C.ok, "center");
    text(x, "Đã trả đủ ✓", W / 2, y + 112, DISP(800, 56), C.ok, "center");
  }
  y += HH + 44;

  // ---- danh sách buổi ----
  const ROW = 128, PH = 88, AV = 38, STEP = 26, AMT_W = 170, STRIP_MAX = 300;
  per.forEach((r, ri) => {
    if (group) {
      if (ri) { dashed(x, P, W - P, y - 14); y += 16; }
      drawAvatar(x, avImg.get(r.m.id), r.m, P, y, 56);
      text(x, M.fullName(book, r.m), P + 74, y + 26, DISP(700, 32), C.ink, "left", W - P * 2 - 300);
      text(x, `${r.ses.length} buổi chưa trả`, P + 74, y + 54, SANS(500, 20), C.soft);
      pill(x, M.fmt(r.due), W - P, y + 8, MONO(700, 28), "#8A5200", C.dueTint, 18, 46, "right");
      y += 80;
    } else if (r.ses.length) {
      text(x, "CÁC BUỔI CHƯA TRẢ", P, y, SANS(700, 20), C.faint);
      text(x, "SỐ TIỀN", W - P, y, SANS(700, 20), C.faint, "right");
      y += 22;
    }
    r.ses.forEach((s2, si) => {
      if (si || group) dashed(x, P, W - P, y, C.line, [6, 8], 2);
      const top = y + 20;
      let tx = P;
      const ph = phImg.get(s2.id);
      if (ph) { drawCover(x, ph, P, top, PH, PH, 18); tx = P + PH + 22; }
      else {
        // ô lịch: ngày/tháng
        fillR(x, P, top, PH, PH, 20, C.primaryTint);
        const [dd, mm] = String(s2.date || "").split(/[/.-]/);
        if (dd && mm) { text(x, dd, P + PH / 2, top + 50, DISP(800, 40), C.primary, "center"); text(x, "TH " + mm, P + PH / 2, top + 74, SANS(700, 15), C.primaryLight, "center"); }
        else text(x, "📅", P + PH / 2, top + 58, SANS(400, 36), C.primary, "center");
        tx = P + PH + 22;
      }
      const parts = s2.parts.map((p) => M.memById(book, p.mid)).filter(Boolean);
      const meIdx = parts.findIndex((mm) => mm.id === r.m.id);
      if (meIdx > 0) { parts.unshift(parts.splice(meIdx, 1)[0]); }
      const maxN = Math.max(1, Math.floor((STRIP_MAX - AV) / STEP) + 1);
      const shown = parts.length > maxN ? parts.slice(0, maxN - 1) : parts, more = parts.length - shown.length;
      const cnt = shown.length + (more ? 1 : 0), stripW = AV + (cnt - 1) * STEP;
      const stripR = W - P - AMT_W, sx = stripR - stripW, sy = top + 8;
      shown.forEach((mm, i) => drawAvatar(x, avImg.get(mm.id), mm, sx + i * STEP, sy, AV, { w: 3, c: mm.id === r.m.id ? C.dueMain : C.paper }));
      if (more) { const ax = sx + shown.length * STEP; x.beginPath(); x.arc(ax + AV / 2, sy + AV / 2, AV / 2 + 3, 0, Math.PI * 2); x.fillStyle = C.paper; x.fill(); x.beginPath(); x.arc(ax + AV / 2, sy + AV / 2, AV / 2, 0, Math.PI * 2); x.fillStyle = C.primaryTint; x.fill(); text(x, "+" + more, ax + AV / 2, sy + AV / 2 + 5, SANS(700, 14), C.primary, "center"); }
      text(x, parts.length + " người chơi", stripR, sy + AV + 28, SANS(500, 17), C.faint, "right");
      const textW = sx - tx - 20;
      text(x, s2.date || "—", tx, top + 32, DISP(700, 30), C.ink, "left", textW);
      text(x, `(${s2.court} + ${s2.shuttles}×${s2.price || M.DEFAULT_PRICE}) / ${M.wStr(M.sWeight(s2))} suất`, tx, top + 60, MONO(500, 18), C.soft, "left", textW);
      text(x, `= ${M.fmt(M.sPerUnit(s2))} / suất`, tx, top + 84, MONO(500, 18), C.faint, "left", textW);
      const w = (s2.parts.find((p) => p.mid === r.m.id) || {}).weight;
      if (w !== 1) pill(x, `× ${M.wStr(w)} suất` + (w > 1 ? " · gồm người đi cùng" : ""), tx, top + 94, SANS(600, 15), C.due, C.dueTint, 10, 26);
      text(x, M.fmt(M.shareIn(s2, r.m.id)), W - P, top + PH / 2 + 14, MONO(700, 38), C.due, "right");
      y += ROW + (w !== 1 ? 14 : 0);
    });
    if (!group && !r.ses.length) { text(x, "Không còn buổi nào đang nợ 🎉", W / 2, y + 30, SANS(600, 28), C.ok, "center"); y += 64; }
    if (r.paid > M.EPS) {
      const nPaid = M.memberSessions(book, r.m.id).filter((s2) => M.isPaid(s2, r.m.id)).length;
      fillR(x, P, y + 6, W - P * 2, 52, 14, C.okTint);
      text(x, `✓  Đã trả trước đó · ${nPaid} buổi`, P + 20, y + 40, SANS(600, 20), C.ok);
      text(x, M.fmt(r.paid), W - P - 20, y + 41, MONO(600, 22), C.ok, "right");
      y += 70;
    }
    y += group ? 24 : 8;
  });

  // ---- tổng ----
  if (due > M.EPS) {
    dashed(x, P, W - P, y + 4, "#C4CDD5", [2, 0], 2);
    text(x, "TỔNG CỘNG", P, y + 58, DISP(800, 28), C.ink);
    text(x, M.fmt(due), W - P, y + 60, MONO(700, 44), C.ink, "right");
    y += 96;
  }

  // ---- đường xé + chuyển khoản ----
  if (due > M.EPS) {
    y += 20; notches.push(y); y += 44;
    const ref = groupRef(per.map((r) => r.m));
    if (qr) {
      const QD = 300, qh = QD * qr.height / qr.width, colW = W - P * 2 - QD - 48;
      const top = y;
      text(x, "NỘI DUNG CHUYỂN KHOẢN", P, top + 22, SANS(700, 20), C.faint);
      x.font = MONO(700, 30); const lines = wrapMono(x, ref, colW - 44);
      const bh = 32 + lines.length * 40;
      fillR(x, P, top + 40, colW, bh, 18, C.primaryTint);
      x.save(); x.strokeStyle = "rgba(37,110,78,0.35)"; x.setLineDash([8, 6]); x.lineWidth = 2; rrect(x, P + 1, top + 41, colW - 2, bh - 2, 17); x.stroke(); x.restore();
      lines.forEach((ln, i) => text(x, ln, P + 22, top + 40 + 46 + i * 40, MONO(700, 30), C.primaryDark));
      let ly = top + 40 + bh + 44;
      if (book.note) {
        text(x, "NGƯỜI NHẬN", P, ly, SANS(700, 20), C.faint);
        x.font = SANS(600, 26); wrapText(x, book.note, colW).slice(0, 3).forEach((ln, i) => text(x, ln, P, ly + 38 + i * 36, SANS(600, 26), C.ink));
        ly += 38 + Math.min(3, wrapText(x, book.note, colW).length) * 36;
      }
      text(x, "Quét mã QR bằng app ngân hàng →", P, ly + 18, SANS(500, 19), C.soft);
      const qx = W - P - QD, qy = top;
      fillR(x, qx - 14, qy - 14, QD + 28, qh + 28, 24, C.neutral);
      fillR(x, qx - 4, qy - 4, QD + 8, qh + 8, 16, C.paper);
      x.save(); x.imageSmoothingEnabled = false; rrect(x, qx, qy, QD, qh, 12); x.clip(); x.drawImage(qr, qx, qy, QD, qh); x.restore();
      y = Math.max(ly + 40, qy + qh + 30);
    } else {
      text(x, "NỘI DUNG CHUYỂN KHOẢN", W / 2, y + 22, SANS(700, 20), C.faint, "center");
      pill(x, ref, W / 2, y + 42, MONO(700, 30), C.primaryDark, C.primaryTint, 28, 64, "center");
      y += 132;
      if (book.note) { text(x, book.note, W / 2, y + 6, SANS(600, 26), C.ink, "center", W - P * 2); y += 46; }
    }
    y += 16;
  }

  // ---- chân ----
  fillR(x, 0, y, W, 84, 0, C.neutral);
  drawLogo(x, P, y + 26, 32, C.primaryLight);
  text(x, "Vừa chuyển thì đợi admin ghi nhận nhé · cảm ơn!", P + 44, y + 50, SANS(500, 19), C.soft);
  text(x, "Cập nhật " + stampTxt(updatedAt), W - P, y + 50, MONO(500, 17), C.faint, "right");
  y += 84;

  const name = group ? "hoa-don-gop-" + per.length + "-nguoi" : M.norm(per[0].m.name).replace(/\s+/g, "-");
  return out(compose(BILL_W, crop(layer, W, y), y, notches), "caulong-" + name + ".png");
}

function crop(c, w, h) { const o = document.createElement("canvas"); o.width = w * S; o.height = Math.round(h) * S; o.getContext("2d").drawImage(c, 0, 0); return o; }
function wrapText(x, str, maxW) {
  const words = String(str).split(/\s+/); const lines = []; let cur = "";
  words.forEach((w) => { const t = cur ? cur + " " + w : w; if (x.measureText(t).width > maxW && cur) { lines.push(cur); cur = w; } else cur = t; });
  if (cur) lines.push(cur); return lines;
}
const wrapMono = wrapText;

export async function exportBoardImage(book, updatedAt) {
  await readyFonts();
  const rows = M.debtors(book).map((m) => ({ m, due: M.memberDue(book, m.id), n: M.memberDueSessions(book, m.id).length })).sort((a, b) => b.due - a.due);
  const due = M.totalDue(book), got = M.totalCollected(book), all = due + got;
  const pct = all > M.EPS ? Math.round((got / all) * 100) : 0;
  const hasQR = !!book.qr;
  const W = BOARD_W - MARGIN * 2, P = 48;
  const { c: layer, x } = canvas(W, 900 + rows.length * 92 + (book.note ? 80 : 0) + (hasQR ? 460 : 0), true);
  const avs = await Promise.all(rows.map((r) => (r.m.av ? loadImg(r.m.av) : Promise.resolve(null))));
  const qr = hasQR ? await loadImg(book.qr) : null;
  const notches = [];
  let y = header(x, W, "BẢNG TỔNG", `${book.sessions.length} buổi · ${book.members.length} người`, updatedAt, 180);
  y += 36;

  // hai ô tổng kiểu WidgetSummary
  const colW = (W - P * 2 - 20) / 2, BH = 150;
  [[P, "CÒN THIẾU", M.fmt(due), M.vnd(due), "#FFF8E6", "#FFE6B0", C.due, "#8A5200"],
   [P + colW + 20, "ĐÃ THU", M.fmt(got), `trên ${M.fmt(all)}`, "#EAF4EE", "#C6E3D3", C.primary, C.primaryDarker]].forEach(([bx, lb, big, sub, g1, g2, c1, c2]) => {
    const g = x.createLinearGradient(bx, y, bx + colW, y + BH); g.addColorStop(0, g1); g.addColorStop(1, g2);
    fillR(x, bx, y, colW, BH, 24, g);
    text(x, lb, bx + 26, y + 42, SANS(700, 19), c1);
    text(x, big, bx + 26, y + 98, MONO(700, 46), c2, "left", colW - 40);
    text(x, sub, bx + 26, y + 130, MONO(500, 18), c1, "left", colW - 40);
  });
  y += BH + 26;

  // thanh tiến độ
  fillR(x, P, y, W - P * 2 - 90, 14, 7, C.primaryTint);
  if (pct) fillR(x, P, y, Math.max(14, (W - P * 2 - 90) * pct / 100), 14, 7, C.primary);
  text(x, pct + "%", W - P, y + 14, MONO(700, 22), C.primary, "right");
  text(x, `${rows.length} người còn nợ · ${book.sessions.filter((s) => !M.sSettled(s)).length}/${book.sessions.length} buổi chưa thu xong`, P, y + 48, SANS(500, 19), C.soft);
  y += 84;

  if (rows.length) {
    text(x, "AI CÒN NỢ", P, y, SANS(700, 20), C.faint);
    text(x, "SỐ TIỀN", W - P, y, SANS(700, 20), C.faint, "right");
    y += 18;
    rows.forEach((r, i) => {
      if (i) dashed(x, P, W - P, y, C.line, [6, 8], 2);
      text(x, String(i + 1).padStart(2, "0"), P, y + 54, MONO(500, 18), C.faint);
      drawAvatar(x, avs[i], r.m, P + 40, y + 18, 54);
      text(x, M.fullName(book, r.m), P + 112, y + 44, DISP(700, 28), C.ink, "left", W - P * 2 - 330);
      text(x, r.n + " buổi chưa trả", P + 112, y + 72, SANS(500, 18), C.soft);
      text(x, M.fmt(r.due), W - P, y + 58, MONO(700, 32), C.due, "right");
      y += 90;
    });
  } else { text(x, "Không ai còn nợ 🎉", W / 2, y + 46, DISP(700, 36), C.ok, "center"); y += 84; }

  if (book.note || qr) {
    y += 16; notches.push(y); y += 40;
    text(x, "CHUYỂN KHOẢN", W / 2, y + 20, SANS(700, 20), C.faint, "center"); y += 36;
    if (book.note) { text(x, book.note, W / 2, y + 30, SANS(600, 26), C.ink, "center", W - P * 2); y += 56; }
    if (qr) { const d = 280, h = d * qr.height / qr.width, qx = (W - d) / 2; fillR(x, qx - 14, y + 4, d + 28, h + 28, 24, C.neutral); fillR(x, qx - 4, y + 14, d + 8, h + 8, 16, C.paper); x.save(); x.imageSmoothingEnabled = false; x.drawImage(qr, qx, y + 18, d, h); x.restore(); y += h + 56; }
  }
  y += 10;
  fillR(x, 0, y, W, 76, 0, C.neutral);
  drawLogo(x, P, y + 22, 32, C.primaryLight);
  text(x, "Vừa chuyển thì đợi admin ghi nhận nhé", P + 44, y + 46, SANS(500, 18), C.soft);
  text(x, stampTxt(updatedAt), W - P, y + 46, MONO(500, 16), C.faint, "right");
  y += 76;
  return out(compose(BOARD_W, crop(layer, W, y), y, notches), "caulong-bang-tong.png");
}
