import { useEffect, useRef, useState } from "react";
import {
  Alert, Avatar, Box, Button, Card, Checkbox, CircularProgress, Collapse, Dialog, DialogActions,
  DialogContent, DialogTitle, IconButton, InputAdornment, LinearProgress, List,
  ListItem, ListItemAvatar, ListItemButton, ListItemText, Paper, Snackbar, Stack,
  TextField, ToggleButton, ToggleButtonGroup, Tooltip, Typography,
} from "@mui/material";
import { alpha } from "@mui/material/styles";
import * as M from "../lib/model.js";
import { useBook } from "../lib/useBook.js";
import { exportBillImage, exportBoardImage, exportPersonImage } from "../lib/billimage.js";
import { Iconify } from "../components/iconify/index.jsx";
import { Label } from "../components/label/index.jsx";
import WidgetSummary from "../components/WidgetSummary.jsx";
import Money, { SectionLabel } from "../components/Money.jsx";

const money = (x) => M.fmt(x);
const ME_KEY = "bmw_me";
const DUE = "warning.dark"; // màu hổ phách cho số còn nợ (như bản gốc)
const monoFont = { fontFamily: "'Roboto Mono', monospace" };

export default function BillBook() {
  const B = useBook();
  const { book, isAdmin } = B;
  const [sub, setSub] = useState("all");
  const [toast, setToast] = useState("");
  const [img, setImg] = useState(null);       // {url,filename} ảnh đã xuất
  const [imgBusy, setImgBusy] = useState(false);
  const [picFor, setPicFor] = useState(null);  // {k:'m'|'s', id} đích dán ảnh
  const fileRef = useRef(null);

  // chuyển sub mặc định khi vào/ra admin
  const prevAdmin = useRef(isAdmin);
  useEffect(() => {
    if (isAdmin !== prevAdmin.current) { setSub(isAdmin ? "sessions" : "all"); prevAdmin.current = isAdmin; setPicFor(null); }
  }, [isAdmin]);

  // dán ảnh (Ctrl+V) cho đích đang chọn
  useEffect(() => {
    if (!isAdmin) return;
    const onPaste = (e) => {
      if (!picFor) return;
      for (const it of e.clipboardData?.items || []) {
        if (it.type && it.type.startsWith("image")) { const f = it.getAsFile(); if (f) { e.preventDefault(); applyPic(picFor, f); return; } }
      }
      setToast("Clipboard không có ảnh — copy ảnh rồi thử lại.");
    };
    const onKey = (e) => { if (e.key === "Escape" && picFor) setPicFor(null); };
    document.addEventListener("paste", onPaste);
    document.addEventListener("keydown", onKey);
    return () => { document.removeEventListener("paste", onPaste); document.removeEventListener("keydown", onKey); };
  }); // eslint-disable-line react-hooks/exhaustive-deps

  const applyPic = (t, file) => {
    if (!t) return;
    if (t.k === "m") shrinkSquare(file, 96, (url) => B.mutate((d) => { const mm = d.members.find((x) => x.id === t.id); if (mm) mm.av = url; }, `Đổi ảnh đại diện: ${M.memById(book, t.id)?.name || "?"}`));
    else shrinkMax(file, 340, (url) => B.mutate((d) => { const s = d.sessions.find((x) => x.id === t.id); if (s) s.photo = url; }, `Thêm ảnh buổi ${M.sessionById(book, t.id)?.date || "?"}`));
    setToast("Đã cập nhật ảnh.");
  };
  const onFile = (e) => { const f = e.target.files[0]; e.target.value = ""; if (f && picFor) applyPic(picFor, f); };
  const runExport = async (fn) => {
    setImgBusy(true);
    try { const r = await fn(); if (r.error) setToast(r.error); else setImg(r); }
    catch (e) { setToast("Không tạo được ảnh: " + (e.message || e)); }
    finally { setImgBusy(false); }
  };

  if (B.loadErr && !book) return <Alert severity="error">Không tải được sổ: {B.loadErr}</Alert>;
  if (!book) return <Box sx={{ display: "grid", placeItems: "center", py: 8 }}><CircularProgress /></Box>;

  const viewerTabs = [["me", "Của tôi"], ["all", "Cả nhóm"], ["sessions", "Các buổi"]];
  const adminTabs = [["sessions", "Buổi chơi"], ["members", "Thành viên"], ["collect", "Thu tiền"]];
  const tabs = isAdmin ? adminTabs : viewerTabs;
  if (!tabs.some(([k]) => k === sub)) setSub(tabs[0][0]);

  const goMe = (id) => { try { localStorage.setItem(ME_KEY, id); } catch { /* */ } setSub("me"); };
  const ctx = { B, book, setToast, isAdmin, picFor, setPicFor, runExport, imgBusy, goMe };

  return (
    <Box sx={{ pb: isAdmin ? 12 : 2 }}>
      <input ref={fileRef} type="file" accept="image/*" hidden onChange={onFile} />
      <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 2 }}>
        <Box sx={{ flexGrow: 1 }}>
          <Typography variant="h4" sx={{ fontFamily: (t) => t.typography.fontSecondaryFamily, fontWeight: 800, lineHeight: 1.1 }}>Tiền cầu</Typography>
          <Typography variant="caption" color="text.secondary">{book.members.length} thành viên · {book.sessions.length} buổi</Typography>
        </Box>
        {isAdmin && <Label color="primary" variant="soft" startIcon={<Iconify icon="solar:verified-check-bold" />}>Quản trị</Label>}
      </Stack>

      {B.loadErr && !B.online && <Alert severity="warning" sx={{ mb: 2 }}>Mất kết nối máy chủ — đang xem số đã lưu trong máy.</Alert>}

      <ToggleButtonGroup exclusive fullWidth value={sub} onChange={(_, v) => v && setSub(v)} sx={{ mb: 2.5 }}>
        {tabs.map(([k, label]) => <ToggleButton key={k} value={k} sx={{ py: 0.9 }}>{label}</ToggleButton>)}
      </ToggleButtonGroup>

      {!isAdmin && sub === "me" && <ViewMe {...ctx} />}
      {!isAdmin && sub === "all" && <ViewAll {...ctx} />}
      {(sub === "sessions") && (isAdmin ? <AdminSessions {...ctx} /> : <ViewSessions {...ctx} />)}
      {isAdmin && sub === "members" && <AdminMembers {...ctx} pickFile={() => fileRef.current?.click()} applyPic={applyPic} />}
      {isAdmin && sub === "collect" && <AdminCollect {...ctx} />}

      <SaveBar B={B} />
      <ConflictDialog B={B} />
      <PicBar ctx={ctx} pickFile={() => fileRef.current?.click()} />
      <ImageDialog img={img} onClose={() => setImg(null)} />
      {imgBusy && <Box sx={{ position: "fixed", inset: 0, bgcolor: "rgba(0,0,0,.3)", display: "grid", placeItems: "center", zIndex: 1400 }}><CircularProgress /></Box>}
      <Snackbar open={!!toast} autoHideDuration={2600} onClose={() => setToast("")} message={toast}
        anchorOrigin={{ vertical: "bottom", horizontal: "center" }} sx={{ bottom: { xs: 150, sm: 90 } }} />
    </Box>
  );
}

function MemAvatar({ m, size = 40 }) {
  return <Avatar src={m.av || undefined} sx={{ width: size, height: size, bgcolor: M.hue(m.id), fontSize: size * 0.4, color: "#fff" }}>{M.initials(m.name)}</Avatar>;
}
function DueTag({ due }) {
  return due > M.EPS
    ? <Money sx={{ color: DUE, fontWeight: 700, fontSize: 15 }}>{money(due)}</Money>
    : <Label color="success" startIcon={<Iconify icon="solar:check-circle-bold" />}>Đã trả</Label>;
}
// Một dòng buổi: ô lịch ngày/tháng + mô tả + số tiền + trạng thái (bấm để đổi nếu có onToggle)
function SesLine({ s, mid, paid, onToggle }) {
  const raw = String(s.date || "—").trim();
  const mt = raw.match(/^(\d{1,2})[/.-](\d{1,2})[.,]?\s*(.*)$/);
  const rest = mt ? mt[3].replace(/^[-–·\s]+/, "") : raw;
  const w = (s.parts.find((p) => p.mid === mid) || {}).weight;
  const when = paid ? M.whenLabel(s.paid?.[mid]) : "";
  return (
    <Stack direction="row" alignItems="center" spacing={1.25} sx={{ p: 0.75, borderRadius: 1.25, bgcolor: "background.paper", "& + &": { mt: 0.75 }, opacity: paid ? 0.78 : 1 }}>
      <Box sx={{ width: 42, height: 42, flexShrink: 0, borderRadius: 1.25, display: "grid", placeItems: "center", alignContent: "center", lineHeight: 1,
        bgcolor: (t) => alpha(paid ? t.palette.success.main : t.palette.primary.main, 0.1), color: paid ? "success.dark" : "primary.main" }}>
        {mt ? <><Box sx={{ fontFamily: (t) => t.typography.fontSecondaryFamily, fontWeight: 800, fontSize: 18 }}>{mt[1]}</Box><Box sx={{ fontSize: 9.5, fontWeight: 700, opacity: 0.8, mt: 0.25 }}>TH {mt[2]}</Box></>
          : <Iconify icon="solar:calendar-bold-duotone" width={22} />}
      </Box>
      <Box sx={{ flexGrow: 1, minWidth: 0 }}>
        <Typography variant="subtitle2" noWrap sx={{ lineHeight: 1.3 }}>{mt ? `${mt[1]}/${mt[2]}` : raw}{w !== 1 && <Money sx={{ ml: 0.75, fontSize: 11, color: "warning.dark" }}>×{M.wStr(w)}</Money>}</Typography>
        <Typography variant="caption" color="text.secondary" noWrap component="div">{mt ? rest || `${s.parts.length} người chơi` : `${s.parts.length} người chơi`}</Typography>
      </Box>
      <Money sx={{ fontWeight: 700, fontSize: 14, color: paid ? "text.disabled" : DUE, textDecoration: paid ? "line-through" : "none" }}>{money(M.shareIn(s, mid))}</Money>
      {onToggle && (
        <Box component="button" onClick={onToggle} sx={{ font: "inherit", cursor: "pointer", border: 0, flexShrink: 0, minWidth: 96, height: 30, px: 1.25, borderRadius: 4,
          display: "inline-flex", alignItems: "center", justifyContent: "center", gap: 0.5, fontSize: 12.5, fontWeight: 700, transition: "all .15s",
          bgcolor: (t) => paid ? alpha(t.palette.success.main, 0.16) : "transparent", color: paid ? "success.dark" : "text.secondary",
          boxShadow: (t) => paid ? "none" : `inset 0 0 0 1px ${alpha(t.palette.grey[500], 0.32)}`,
          "&:hover": { boxShadow: (t) => `inset 0 0 0 1px ${paid ? t.palette.success.main : t.palette.primary.main}`, color: paid ? "success.dark" : "primary.main" } }}>
          <Iconify icon={paid ? "solar:check-circle-bold" : "solar:clock-circle-bold"} width={15} />
          {paid ? `Đã trả${when ? " " + when : ""}` : "Chưa trả"}
        </Box>
      )}
    </Stack>
  );
}

function SearchBox({ value, onChange, placeholder }) {
  return <TextField fullWidth placeholder={placeholder} value={value} onChange={(e) => onChange(e.target.value)}
    sx={{ "& .MuiOutlinedInput-root": { bgcolor: "background.paper" } }}
    InputProps={{ startAdornment: <InputAdornment position="start"><Iconify icon="solar:magnifer-linear" sx={{ color: "text.disabled" }} /></InputAdornment> }} />;
}
function EmptyRow({ children }) {
  return <ListItem sx={{ py: 3, justifyContent: "center" }}><Typography variant="body2" color="text.secondary">{children}</Typography></ListItem>;
}

// ---------- Viewer ----------
function ViewAll({ book, goMe, runExport }) {
  const [q, setQ] = useState("");
  const [filter, setFilter] = useState("due");
  const [gallery, setGallery] = useState(false);
  const due = M.totalDue(book), got = M.totalCollected(book), all = due + got;
  let rows = book.members.map((m) => ({ m, due: M.memberDue(book, m.id), n: M.memberDueSessions(book, m.id).length, tot: M.memberSessions(book, m.id).length })).filter((r) => r.tot > 0);
  const nDue = rows.filter((r) => r.due > M.EPS).length;
  rows = rows.filter((r) => filter === "all" || (filter === "due" ? r.due > M.EPS : r.due <= M.EPS))
    .filter((r) => !q || M.norm(r.m.name).includes(M.norm(q)))
    .sort((a, b) => b.due - a.due || a.m.name.localeCompare(b.m.name, "vi"));
  const pct = all > M.EPS ? Math.round((got / all) * 100) : 0;
  return (
    <Stack spacing={2}>
      <StatCard due={due} got={got} all={all} pct={pct} sub={`${nDue} người còn nợ · ${book.sessions.length} buổi đã chơi`} />
      <SearchBox placeholder="Tìm tên…" value={q} onChange={setQ} />
      <Stack direction="row" alignItems="center" spacing={1}>
        <ToggleButtonGroup size="small" exclusive value={filter} onChange={(_, v) => v && setFilter(v)}>
          <ToggleButton value="due">Còn nợ · {nDue}</ToggleButton>
          <ToggleButton value="ok">Đã xong</ToggleButton>
          <ToggleButton value="all">Tất cả</ToggleButton>
        </ToggleButtonGroup>
        <Box flexGrow={1} />
        <Tooltip title={gallery ? "Dạng danh sách" : "Dạng gallery"}>
          <IconButton size="small" onClick={() => setGallery((v) => !v)} color={gallery ? "primary" : "default"}>
            <Iconify icon={gallery ? "solar:list-bold" : "solar:gallery-wide-bold"} />
          </IconButton>
        </Tooltip>
      </Stack>
      {gallery ? (
        <Box sx={{ display: "grid", gap: 1.25, gridTemplateColumns: "repeat(auto-fill, minmax(96px, 1fr))" }}>
          {rows.map((r) => (
            <Card key={r.m.id} onClick={() => goMe(r.m.id)} sx={{ p: 1.25, textAlign: "center", cursor: "pointer",
              border: (t) => r.due > M.EPS ? `1px solid ${alpha(t.palette.warning.main, 0.4)}` : undefined, "&:hover": { boxShadow: (t) => t.customShadows.z8 } }}>
              <Box sx={{ display: "grid", placeItems: "center" }}><MemAvatar m={r.m} size={46} /></Box>
              <Typography variant="caption" sx={{ display: "block", mt: 0.75, fontWeight: 600, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{M.fullName(book, r.m)}</Typography>
              {r.due > M.EPS ? <Money sx={{ color: DUE, fontWeight: 700, fontSize: 12 }}>{money(r.due)}</Money> : <Iconify icon="solar:check-circle-bold" width={16} sx={{ color: "success.main" }} />}
            </Card>
          ))}
          {rows.length === 0 && <Typography variant="body2" color="text.secondary" sx={{ gridColumn: "1/-1", textAlign: "center", py: 3 }}>Không có ai trong mục này.</Typography>}
        </Box>
      ) : (
        <Card><List disablePadding>
          {rows.map((r, i) => (
            <ListItemButton key={r.m.id} divider={i < rows.length - 1} onClick={() => goMe(r.m.id)} sx={{ py: 1.25 }}>
              <ListItemAvatar><MemAvatar m={r.m} size={38} /></ListItemAvatar>
              <ListItemText primary={M.fullName(book, r.m)} secondary={r.due > M.EPS ? `${r.n} buổi chưa trả` : `${r.tot} buổi · đã trả đủ`} />
              <DueTag due={r.due} />
            </ListItemButton>
          ))}
          {rows.length === 0 && <EmptyRow>Không có ai trong mục này.</EmptyRow>}
        </List></Card>
      )}
      <Button variant="outlined" color="inherit" startIcon={<Iconify icon="solar:gallery-download-bold" />} onClick={() => runExport(() => exportBoardImage(book, bookUpdatedAt()))}>Tải ảnh bảng tổng</Button>
    </Stack>
  );
}

// updatedAt không có trong book; dùng thời điểm hiện tại cho dấu mốc ảnh là đủ.
const bookUpdatedAt = () => new Date().toISOString();

function ViewMe({ book, setToast, runExport }) {
  const [meId, setMeId] = useState(() => {
    try { const u = new URLSearchParams(location.search).get("me"); if (u) { localStorage.setItem(ME_KEY, u); return u; } return localStorage.getItem(ME_KEY); } catch { return null; }
  });
  const [q, setQ] = useState("");
  const m = meId ? M.memById(book, meId) : null;
  const pick = (id) => { setMeId(id); try { localStorage.setItem(ME_KEY, id); } catch { /* */ } };
  if (!m) {
    const rows = book.members.map((x) => ({ m: x, due: M.memberDue(book, x.id) }))
      .filter((r) => !q || M.norm(r.m.name).includes(M.norm(q)))
      .sort((a, b) => b.due - a.due || a.m.name.localeCompare(b.m.name, "vi"));
    return (
      <Stack spacing={2}>
        <Alert severity="info" icon={<Iconify icon="solar:user-rounded-bold-duotone" />}>Bấm vào tên bạn để xem mình nợ bao nhiêu, gồm những buổi nào.</Alert>
        <SearchBox placeholder="Gõ tên để tìm…" value={q} onChange={setQ} />
        <Box sx={{ display: "grid", gap: 1.25, gridTemplateColumns: "repeat(auto-fill, minmax(96px, 1fr))" }}>
          {rows.map((r) => (
            <Card key={r.m.id} onClick={() => pick(r.m.id)} sx={{ p: 1.25, textAlign: "center", cursor: "pointer",
              border: (t) => r.due > M.EPS ? `1px solid ${alpha(t.palette.warning.main, 0.4)}` : undefined, "&:hover": { boxShadow: (t) => t.customShadows.z8 } }}>
              <Box sx={{ display: "grid", placeItems: "center" }}><MemAvatar m={r.m} size={46} /></Box>
              <Typography variant="caption" sx={{ display: "block", mt: 0.75, fontWeight: 600, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{M.fullName(book, r.m)}</Typography>
              {r.due > M.EPS ? <Money sx={{ color: DUE, fontWeight: 700, fontSize: 12 }}>{money(r.due)}</Money> : <Iconify icon="solar:check-circle-bold" width={16} sx={{ color: "success.main" }} />}
            </Card>
          ))}
          {rows.length === 0 && <Typography variant="body2" color="text.secondary" sx={{ gridColumn: "1/-1", textAlign: "center", py: 3 }}>{book.members.length === 0 ? "Sổ chưa có ai." : "Không tìm thấy ai."}</Typography>}
        </Box>
      </Stack>
    );
  }
  const due = M.memberDue(book, m.id), paidSum = M.memberPaidSum(book, m.id);
  const dueSes = M.memberDueSessions(book, m.id);
  const paidSes = M.memberSessions(book, m.id).filter((s) => M.isPaid(s, m.id)).reverse();
  const flag = book.flags?.[m.id];
  const shareLink = () => { const url = location.origin + location.pathname + "?me=" + m.id; try { navigator.clipboard.writeText(url); } catch { /* */ } setToast("Đã chép link riêng của " + m.name); };
  return (
    <Stack spacing={2}>
      <Card sx={{ p: 3, textAlign: "center", overflow: "hidden" }}>
        <Box sx={{ position: "absolute", inset: 0, height: 88, zIndex: -1, background: (t) => `linear-gradient(135deg, ${t.palette.primary.main}, ${t.palette.primary.dark})` }} />
        <MemAvatar m={m} size={80} />
        <Typography variant="h6" sx={{ mt: 1.5 }}>{M.fullName(book, m)}</Typography>
        {due > M.EPS ? (
          <>
            <Typography variant="overline" color="text.secondary" sx={{ display: "block", mt: 1.5 }}>Cần chuyển</Typography>
            <Money sx={{ display: "block", color: DUE, fontSize: { xs: 40, sm: 46 }, fontWeight: 700, lineHeight: 1.1 }}>{money(due)}</Money>
            <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}><Money sx={{ fontWeight: 500 }}>{M.vnd(due)}</Money> · {dueSes.length} buổi</Typography>
            <Box sx={{ mt: 2.5, mx: "auto", p: 1.5, maxWidth: 340, borderRadius: 1.5, bgcolor: (t) => alpha(t.palette.primary.main, 0.08), border: (t) => `1px dashed ${alpha(t.palette.primary.main, 0.32)}` }}>
              <Typography variant="caption" color="text.secondary">Nội dung chuyển khoản</Typography>
              <Stack direction="row" alignItems="center" justifyContent="center" spacing={0.5}>
                <Money sx={{ fontWeight: 700, fontSize: 16, color: "primary.dark" }}>{M.payRef(m)}</Money>
                <IconButton size="small" onClick={() => { try { navigator.clipboard.writeText(M.payRef(m)); } catch { /* */ } setToast("Đã chép nội dung chuyển khoản"); }}><Iconify icon="solar:copy-bold" width={16} /></IconButton>
              </Stack>
            </Box>
            {book.note && <Typography fontWeight={700} sx={{ mt: 1.5 }}>{book.note}</Typography>}
            {book.qr && <Box sx={{ mt: 1.5 }}><img src={book.qr} alt="QR" style={{ maxWidth: 210, borderRadius: 12, boxShadow: "0 8px 16px rgba(145,158,171,.24)" }} /></Box>}
          </>
        ) : (
          <Stack alignItems="center" spacing={1} sx={{ mt: 2 }}>
            <Iconify icon="solar:check-circle-bold" width={48} sx={{ color: "success.main" }} />
            <Typography variant="h5" color="success.dark">Không nợ gì 🎉</Typography>
            {paidSum > M.EPS && <Typography variant="body2" color="text.secondary">Đã trả đủ {money(paidSum)}</Typography>}
          </Stack>
        )}
      </Card>

      {dueSes.length > 0 && (<>
        <SectionLabel>Các buổi chưa trả · {dueSes.length}</SectionLabel>
        <Card><List disablePadding>
          {dueSes.map((s, i) => (
            <ListItem key={s.id} divider={i < dueSes.length - 1} secondaryAction={<Money sx={{ color: DUE, fontWeight: 700 }}>{money(M.shareIn(s, m.id))}</Money>}>
              <ListItemText primary={s.date || "—"}
                secondary={<Money sx={{ fontWeight: 400, fontSize: 12 }}>({s.court} + {s.shuttles}×{s.price || M.DEFAULT_PRICE}) / {M.wStr(M.sWeight(s))} suất{(s.parts.find((p) => p.mid === m.id) || {}).weight !== 1 ? ` × ${M.wStr((s.parts.find((p) => p.mid === m.id) || {}).weight)} suất của bạn` : ""}</Money>} />
            </ListItem>
          ))}
        </List></Card>
      </>)}

      {paidSes.length > 0 && (<>
        <SectionLabel>Đã trả rồi · {paidSes.length} buổi · {money(paidSum)}</SectionLabel>
        <Card><List disablePadding>
          {paidSes.map((s, i) => (
            <ListItem key={s.id} divider={i < paidSes.length - 1}
              secondaryAction={<Label color="success" startIcon={<Iconify icon="solar:check-circle-bold" />}>{M.whenLabel(s.paid[m.id]) ? "ghi nhận " + M.whenLabel(s.paid[m.id]) : "đã trả"}</Label>}>
              <ListItemText primary={s.date || "—"} primaryTypographyProps={{ color: "text.secondary" }}
                secondary={<Money sx={{ fontSize: 12, textDecoration: "line-through", color: "text.disabled" }}>{money(M.shareIn(s, m.id))}</Money>} />
            </ListItem>
          ))}
        </List></Card>
      </>)}

      {flag && <Alert severity="warning" icon={<Iconify icon="solar:danger-triangle-bold" />}>{flag}</Alert>}

      <Button variant="contained" startIcon={<Iconify icon="solar:camera-bold" />} onClick={() => runExport(() => exportPersonImage(book, bookUpdatedAt(), m))}>Tải ảnh của tôi</Button>
      <Stack direction="row" spacing={1}>
        <Button size="small" color="inherit" sx={{ color: "text.secondary" }} onClick={() => { setMeId(null); try { localStorage.removeItem(ME_KEY); } catch { /* */ } }}>Tôi không phải {m.name}</Button>
        <Box flexGrow={1} />
        <Button size="small" color="inherit" startIcon={<Iconify icon="solar:link-bold" width={18} />} onClick={shareLink}>Chép link riêng</Button>
      </Stack>
    </Stack>
  );
}

function ViewSessions({ book }) {
  const list = M.orderedSessions(book);
  const [zoom, setZoom] = useState(null);
  return (
    <Stack spacing={1.5}>
      {list.map((s) => <SessionCard key={s.id} book={book} s={s} onZoom={setZoom} />)}
      {list.length === 0 && <Alert severity="info">Chưa có buổi nào.</Alert>}
      <PhotoZoom photo={zoom} onClose={() => setZoom(null)} />
    </Stack>
  );
}

function SessionHead({ s, picFor, setPicFor, onZoom }) {
  const settled = M.sSettled(s);
  const admin = !!setPicFor;
  const armed = picFor && picFor.k === "s" && picFor.id === s.id;
  const thumb = admin
    ? <Box component="button" onClick={() => setPicFor(armed ? null : { k: "s", id: s.id })}
        sx={{ p: 0, border: (t) => armed ? `2px solid ${t.palette.warning.main}` : "none", borderRadius: 1.5, cursor: "pointer", bgcolor: "transparent", lineHeight: 0, flexShrink: 0 }}>
        {s.photo ? <Box component="img" src={s.photo} sx={{ width: 40, height: 40, borderRadius: 1.5, objectFit: "cover" }} />
          : <Box sx={{ width: 40, height: 40, borderRadius: 1.5, display: "grid", placeItems: "center", bgcolor: (t) => alpha(t.palette.primary.main, 0.1), color: "primary.main", border: (t) => `1.5px dashed ${alpha(t.palette.primary.main, 0.4)}` }}><Iconify icon="solar:camera-add-bold" width={20} /></Box>}
      </Box>
    : s.photo
      ? <Box component="button" onClick={() => onZoom?.(s.photo)} sx={{ p: 0, border: "none", borderRadius: 1.5, cursor: "pointer", bgcolor: "transparent", lineHeight: 0, flexShrink: 0 }}><Box component="img" src={s.photo} sx={{ width: 40, height: 40, borderRadius: 1.5, objectFit: "cover" }} /></Box>
      : <Box sx={{ width: 40, height: 40, borderRadius: 1.5, display: "grid", placeItems: "center", flexShrink: 0, bgcolor: (t) => alpha(t.palette.primary.main, 0.1), color: "primary.main" }}><Iconify icon="solar:calendar-bold-duotone" width={22} /></Box>;
  return (
    <>
      <Stack direction="row" alignItems="center" spacing={1}>
        {thumb}
        <Box sx={{ flexGrow: 1, minWidth: 0 }}>
          <Typography variant="subtitle1" sx={{ lineHeight: 1.3 }}>{s.date || "(chưa đặt ngày)"}</Typography>
          <Typography variant="caption" color="text.secondary">{s.parts.length} người</Typography>
        </Box>
        <Box sx={{ textAlign: "right" }}>
          <Money sx={{ fontSize: 17, fontWeight: 700, display: "block" }}>{money(M.sTotal(s))}</Money>
          {settled ? <Label color="success">Đã thu đủ</Label> : <Label color="warning">Còn {M.sUnpaid(s).length} người</Label>}
        </Box>
      </Stack>
      <Box sx={{ mt: 1.5, px: 1.25, py: 0.75, borderRadius: 1, bgcolor: "background.neutral" }}>
        <Money sx={{ fontSize: 12, fontWeight: 500, color: "text.secondary", whiteSpace: "normal" }}>
          ({s.court} + {s.shuttles}×{s.price || M.DEFAULT_PRICE}) / {M.wStr(M.sWeight(s))} suất = <Box component="b" sx={{ color: "text.primary" }}>{money(M.sPerUnit(s))}</Box>/suất
        </Money>
      </Box>
    </>
  );
}

function PartChip({ book, s, p, onClick }) {
  const m = M.memById(book, p.mid); if (!m) return null;
  const on = M.isPaid(s, p.mid);
  return (
    <Box component={onClick ? "button" : "span"} onClick={onClick}
      sx={{ display: "inline-flex", alignItems: "center", gap: 0.75, pl: 0.4, pr: 1.1, py: 0.4, borderRadius: 5, font: "inherit", fontSize: 13, fontWeight: 600, cursor: onClick ? "pointer" : "default", transition: "all .15s",
        border: (t) => `1px solid ${on ? "transparent" : alpha(t.palette.grey[500], 0.32)}`, bgcolor: (t) => on ? alpha(t.palette.success.main, 0.16) : t.palette.background.paper, color: on ? "success.dark" : "text.primary", "&:hover": onClick ? { borderColor: "primary.main" } : undefined }}>
      <MemAvatar m={m} size={22} />
      <span style={on ? { textDecoration: "line-through", textDecorationThickness: 1 } : undefined}>{M.fullName(book, m)}</span>
      {p.weight !== 1 && <Money sx={{ fontSize: 11, opacity: 0.7 }}>×{M.wStr(p.weight)}</Money>}
      {on && <Iconify icon="solar:check-circle-bold" width={16} />}
    </Box>
  );
}

function SessionCard({ book, s, onZoom }) {
  const got = M.sCollected(s), tot = M.sTotal(s);
  return (
    <Card sx={{ p: 2 }}>
      <SessionHead s={s} onZoom={onZoom} />
      <LinearProgress variant="determinate" color={M.sSettled(s) ? "success" : "primary"} value={tot > M.EPS ? Math.round((got / tot) * 100) : 0} sx={{ my: 1.5, height: 6 }} />
      <Box sx={{ display: "flex", flexWrap: "wrap", gap: 0.75 }}>
        {s.parts.map((p) => <PartChip key={p.mid} book={book} s={s} p={p} />)}
      </Box>
    </Card>
  );
}

function StatCard({ due, got, all, pct, sub }) {
  return (
    <Box>
      <Box sx={{ display: "grid", gap: 1.5, gridTemplateColumns: "repeat(2, 1fr)" }}>
        <WidgetSummary color="warning" mono title="Còn thiếu" icon="solar:hand-money-bold-duotone" total={due > M.EPS ? money(due) : "0k"} caption={due > M.EPS ? M.vnd(due) : "Xong hết 🎉"} />
        <WidgetSummary color="primary" mono title="Đã thu" icon="solar:wallet-money-bold-duotone" total={money(got)} caption={<>trên <Money sx={{ fontWeight: 600 }}>{money(all)}</Money></>} />
      </Box>
      <Card sx={{ mt: 1.5, px: 2, py: 1.5 }}>
        <Stack direction="row" alignItems="center" spacing={1.5}>
          <LinearProgress variant="determinate" value={pct} sx={{ flexGrow: 1, height: 8 }} />
          <Money sx={{ fontWeight: 700, color: "primary.main", fontSize: 14 }}>{pct}%</Money>
        </Stack>
        <Typography variant="caption" color="text.secondary">{sub}</Typography>
      </Card>
    </Box>
  );
}

// ---------- Admin ----------
function AdminSessions({ B, book, setToast, picFor, setPicFor }) {
  const [filter, setFilter] = useState("open");
  const [edit, setEdit] = useState(null);
  const due = M.totalDue(book), got = M.totalCollected(book), all = due + got;
  const openN = book.sessions.filter((s) => !M.sSettled(s)).length;
  const list = M.orderedSessions(book).filter((s) => filter === "all" || (filter === "open" ? !M.sSettled(s) : M.sSettled(s)));

  const togglePaid = (s, mid) => {
    const on = M.isPaid(s, mid);
    B.mutate((d) => { M.setPaid(d.sessions.find((x) => x.id === s.id), mid, !on); }, `${on ? "Bỏ dấu đã trả" : "Đánh dấu đã trả"}: ${M.memById(book, mid)?.name || "?"} · buổi ${s.date || "?"}`);
    if (!on) setToast(`${M.memById(book, mid)?.name} đã trả · buổi ${s.date || "?"}`);
  };
  const payAll = (s) => {
    const mids = M.sUnpaid(s); if (!mids.length) return;
    if (!confirm(`Ghi nhận ĐÃ TRẢ cho cả ${mids.length} người còn nợ của buổi ${s.date || "?"} (${money(M.sDue(s))})?`)) return;
    B.mutate((d) => { const ss = d.sessions.find((x) => x.id === s.id); mids.forEach((mid) => M.setPaid(ss, mid, true)); }, `Thu hết buổi ${s.date || "?"}: ${mids.length} người · ${money(M.sDue(s))}`);
    setToast(`Đã thu ${mids.length} người · buổi ${s.date || "?"}`);
  };
  const reopen = (s) => { if (!confirm(`Bỏ dấu "đã trả" của cả ${s.parts.length} người trong buổi ${s.date || "?"}?`)) return; B.mutate((d) => { d.sessions.find((x) => x.id === s.id).paid = {}; }, `Bỏ dấu đã trả cả buổi ${s.date || "?"}`); };
  const del = (s) => { if (!confirm(`Xóa buổi ${s.date || "?"}? Lịch sử đã thu của buổi này cũng mất.`)) return; B.mutate((d) => { d.sessions = d.sessions.filter((x) => x.id !== s.id); }, `Xóa buổi ${s.date || "?"}`); };

  return (
    <Stack spacing={2}>
      <StatCard due={due} got={got} all={all} pct={all > M.EPS ? Math.round(got / all * 100) : 0} sub={`${M.debtors(book).length} người còn nợ · ${openN}/${book.sessions.length} buổi chưa thu xong`} />
      <Button variant="contained" size="large" startIcon={<Iconify icon="mingcute:add-line" />} onClick={() => setEdit(newSession())}>Thêm buổi chơi</Button>
      <ToggleButtonGroup size="small" exclusive value={filter} onChange={(_, v) => v && setFilter(v)} sx={{ alignSelf: "flex-start" }}>
        <ToggleButton value="open">Chưa xong · {openN}</ToggleButton>
        <ToggleButton value="done">Đã xong · {book.sessions.length - openN}</ToggleButton>
        <ToggleButton value="all">Tất cả · {book.sessions.length}</ToggleButton>
      </ToggleButtonGroup>
      {list.map((s) => (
        <Card key={s.id} sx={{ p: 2 }}>
          <SessionHead s={s} picFor={picFor} setPicFor={setPicFor} />
          <Typography variant="caption" color="text.disabled" sx={{ display: "block", mt: 1.5, mb: 0.75 }}>Bấm tên để đánh dấu đã trả</Typography>
          <Box sx={{ display: "flex", flexWrap: "wrap", gap: 0.75 }}>
            {s.parts.map((p) => <PartChip key={p.mid} book={book} s={s} p={p} onClick={() => togglePaid(s, p.mid)} />)}
          </Box>
          <Stack direction="row" spacing={1} alignItems="center" sx={{ mt: 2, pt: 1.5, borderTop: (t) => `1px dashed ${t.palette.divider}` }}>
            {M.sSettled(s)
              ? <Button size="small" color="inherit" onClick={() => reopen(s)}>Bỏ dấu tất cả</Button>
              : <Button size="small" variant="contained" color="inherit" onClick={() => payAll(s)}>Thu hết <Money sx={{ ml: 0.75 }}>{money(M.sDue(s))}</Money></Button>}
            <Box flexGrow={1} />
            <Tooltip title="Sửa"><IconButton size="small" onClick={() => setEdit(clone(s))}><Iconify icon="solar:pen-bold" width={18} /></IconButton></Tooltip>
            <Tooltip title="Xóa"><IconButton size="small" color="error" onClick={() => del(s)}><Iconify icon="solar:trash-bin-trash-bold" width={18} /></IconButton></Tooltip>
          </Stack>
        </Card>
      ))}
      {list.length === 0 && <Alert severity="info">{book.sessions.length === 0 ? "Chưa có buổi nào." : "Không có buổi nào ở mục này."}</Alert>}
      {edit && <SessionDialog B={B} book={book} draft={edit} onClose={() => setEdit(null)} setToast={setToast} />}
    </Stack>
  );
}

const newSession = () => ({ id: M.id(), date: "", court: 0, price: M.DEFAULT_PRICE, shuttles: 0, parts: [], paid: {} });
const clone = (o) => JSON.parse(JSON.stringify(o));
const numInput = { inputProps: { inputMode: "numeric", style: { ...monoFont, fontVariantNumeric: "tabular-nums" } } };

function SessionDialog({ B, book, draft, onClose, setToast }) {
  const [d, setD] = useState(draft);
  const [newMem, setNewMem] = useState("");
  const editing = book.sessions.some((s) => s.id === d.id);
  const upd = (patch) => setD((cur) => ({ ...cur, ...patch }));
  const chosen = new Map(d.parts.map((p) => [p.mid, p.weight]));
  const toggle = (mid) => setD((cur) => ({ ...cur, parts: chosen.has(mid) ? cur.parts.filter((p) => p.mid !== mid) : [...cur.parts, { mid, weight: 1 }] }));
  const setW = (mid, w) => setD((cur) => ({ ...cur, parts: cur.parts.map((p) => p.mid === mid ? { ...p, weight: w } : p) }));
  const addMem = () => {
    const nm = newMem.trim(); if (!nm) return;
    const m = { id: M.id(), name: nm, av: "" };
    B.mutate((bk) => { bk.members.push(m); }, `Thêm thành viên: ${nm}`);
    setD((cur) => ({ ...cur, parts: [...cur.parts, { mid: m.id, weight: 1 }] }));
    setNewMem("");
  };
  const save = () => {
    if (!d.parts.length) { alert("Chọn ít nhất 1 người chơi."); return; }
    if (M.sWeight(d) <= 0) { alert("Tổng hệ số đang bằng 0 — không chia được tiền."); return; }
    const fixed = clone(d);
    Object.keys(fixed.paid).forEach((k) => { if (!fixed.parts.some((p) => p.mid === k)) delete fixed.paid[k]; });
    B.mutate((bk) => { const i = bk.sessions.findIndex((s) => s.id === fixed.id); if (i < 0) bk.sessions.push(fixed); else bk.sessions[i] = fixed; }, `${editing ? "Sửa" : "Thêm"} buổi ${fixed.date || "?"} · ${money(M.sTotal(fixed))} · ${fixed.parts.length} người`);
    setToast(editing ? "Đã lưu buổi" : "Đã thêm buổi"); onClose();
  };
  return (
    <Dialog open onClose={onClose} fullWidth maxWidth="sm">
      <DialogTitle>{editing ? "Sửa buổi" : "Buổi mới"}</DialogTitle>
      <DialogContent>
        <Box sx={{ display: "grid", gap: 1.5, gridTemplateColumns: "1fr 1fr", mt: 1 }}>
          <TextField label="Ngày" placeholder="vd: 20/6" value={d.date} onChange={(e) => upd({ date: e.target.value })} />
          <TextField label="Tiền sân (k)" type="number" value={d.court || ""} onChange={(e) => upd({ court: +e.target.value || 0 })} {...numInput} />
          <TextField label="Số cầu" type="number" value={d.shuttles || ""} onChange={(e) => upd({ shuttles: +e.target.value || 0 })} {...numInput} />
          <TextField label="Giá 1 cầu (k)" type="number" value={d.price} onChange={(e) => upd({ price: +e.target.value || M.DEFAULT_PRICE })} {...numInput} />
        </Box>
        <SectionLabel sx={{ mt: 2.5 }} right={<Typography variant="caption" color="text.secondary">{d.parts.length} đã chọn</Typography>}>Người chơi & hệ số</SectionLabel>
        <Paper variant="outlined" sx={{ maxHeight: 320, overflow: "auto", borderRadius: 1.5 }}>
          <List dense disablePadding>
            {book.members.map((m) => {
              const on = chosen.has(m.id), wt = on ? chosen.get(m.id) : 1;
              return (
                <ListItem key={m.id} divider sx={{ bgcolor: (t) => on ? alpha(t.palette.primary.main, 0.05) : undefined, flexWrap: "wrap", gap: 0.5 }}>
                  <Checkbox edge="start" checked={on} onChange={() => toggle(m.id)} />
                  <ListItemAvatar sx={{ minWidth: 40 }}><MemAvatar m={m} size={28} /></ListItemAvatar>
                  <ListItemText primary={M.fullName(book, m)} onClick={() => toggle(m.id)} sx={{ cursor: "pointer", flex: "1 1 80px" }} />
                  {on && <WeightPicker wt={wt} onPick={(w) => setW(m.id, w)} onCustom={(v) => { if (v === null) setToast(`Hệ số không hợp lệ — nhập 0…${M.W_MAX}, vd 1 · 1.5 · 2`); else setW(m.id, v); }} />}
                </ListItem>
              );
            })}
          </List>
        </Paper>
        <Stack direction="row" spacing={1} sx={{ mt: 1.5 }}>
          <TextField placeholder="Thêm người mới" value={newMem} onChange={(e) => setNewMem(e.target.value)} onKeyDown={(e) => e.key === "Enter" && addMem()} fullWidth
            InputProps={{ startAdornment: <InputAdornment position="start"><Iconify icon="solar:user-plus-bold" sx={{ color: "text.disabled" }} /></InputAdornment> }} />
          <Button variant="outlined" onClick={addMem}>Thêm</Button>
        </Stack>
        <Stack direction="row" alignItems="center" sx={{ mt: 2, p: 1.5, borderRadius: 1.5, bgcolor: (t) => alpha(t.palette.primary.main, 0.08), color: "primary.darker" }}>
          <Typography variant="body2" sx={{ flexGrow: 1 }}>Tổng <Money sx={{ fontWeight: 700 }}>{money(M.sTotal(d))}</Money> · <Money>{M.wStr(M.sWeight(d))}</Money> suất</Typography>
          <Money sx={{ fontWeight: 700, fontSize: 18 }}>{money(M.sPerUnit(d))}<Typography component="span" variant="caption">/suất</Typography></Money>
        </Stack>
      </DialogContent>
      <DialogActions><Button color="inherit" onClick={onClose}>Đóng</Button><Button variant="contained" onClick={save}>Lưu buổi</Button></DialogActions>
    </Dialog>
  );
}

// ½ · 1 · 2 nhanh + ô nhập hệ số tuỳ ý (như sổ gốc)
function WeightPicker({ wt, onPick, onCustom }) {
  const preset = wt === 0.5 || wt === 1 || wt === 2;
  const [txt, setTxt] = useState(M.wStr(wt));
  useEffect(() => { setTxt(M.wStr(wt)); }, [wt]);
  const commit = () => { const v = M.parseWeight(txt); onCustom(v); if (v === null) setTxt(M.wStr(wt)); };
  const ok = M.parseWeight(txt) !== null;
  return (
    <Stack direction="row" alignItems="center" spacing={0.5}>
      <ToggleButtonGroup size="small" exclusive value={preset ? wt : null} onChange={(_, v) => v != null && onPick(v)} sx={{ p: 0.4, gap: 0.4 }}>
        {[0.5, 1, 2].map((q) => <ToggleButton key={q} value={q} sx={{ px: 1, py: 0.1, minWidth: 28, ...monoFont }}>{q === 0.5 ? "½" : q}</ToggleButton>)}
      </ToggleButtonGroup>
      <TextField size="small" value={txt} onChange={(e) => setTxt(e.target.value)} onBlur={commit} onKeyDown={(e) => e.key === "Enter" && commit()}
        error={!ok} inputProps={{ inputMode: "decimal", style: { ...monoFont, width: 40, textAlign: "center", padding: "6px 4px" } }} sx={{ "& .MuiOutlinedInput-root": { bgcolor: !preset ? (t) => alpha(t.palette.primary.main, 0.08) : undefined } }} />
    </Stack>
  );
}

function AdminMembers({ B, book, setToast, picFor, setPicFor, pickFile }) {
  const [filter, setFilter] = useState("all");
  const [newName, setNewName] = useState("");
  const [open, setOpen] = useState(null);
  const rows = book.members.map((m) => ({ m, due: M.memberDue(book, m.id), paid: M.memberPaidSum(book, m.id), n: M.memberSessions(book, m.id).length, nDue: M.memberDueSessions(book, m.id).length }))
    .sort((a, b) => b.due - a.due || a.m.name.localeCompare(b.m.name, "vi"));
  const nDue = rows.filter((r) => r.due > M.EPS).length;
  const list = rows.filter((r) => filter === "all" || r.due > M.EPS);
  const add = () => { const nm = newName.trim(); if (!nm) return; B.mutate((d) => d.members.push({ id: M.id(), name: nm, av: "" }), `Thêm thành viên: ${nm}`); setNewName(""); setFilter("all"); };
  const rename = (m) => { const nw = (prompt("Đổi tên:", m.name) || "").trim(); if (!nw || nw === m.name) return; B.mutate((d) => { d.members.find((x) => x.id === m.id).name = nw; }, `Đổi tên: "${m.name}" → "${nw}"`); };
  const note = (m) => { const cur = book.flags?.[m.id] || ""; const nw = prompt(`Ghi chú cho ${m.name} (để trống để xóa):`, cur); if (nw === null) return; B.mutate((d) => { if (nw.trim()) d.flags[m.id] = nw.trim(); else delete d.flags[m.id]; }, `${nw.trim() ? "Đặt" : "Xóa"} ghi chú cho ${m.name}`); };
  const del = (m) => { const used = M.memberSessions(book, m.id).length; if (used > 0 && !confirm(`${m.name} có mặt trong ${used} buổi. Xóa khỏi cả các buổi đó?`)) return; B.mutate((d) => { d.members = d.members.filter((x) => x.id !== m.id); d.sessions.forEach((s) => { s.parts = s.parts.filter((p) => p.mid !== m.id); delete s.paid[m.id]; }); delete d.flags[m.id]; }, `Xóa thành viên ${m.name}`); };
  const payAll = (m) => {
    const ses = M.memberDueSessions(book, m.id), amt = M.memberDue(book, m.id); if (!ses.length) return;
    if (!confirm(`Ghi nhận ${m.name} đã trả ${money(amt)} (${ses.length} buổi)?`)) return;
    B.mutate((d) => { ses.forEach((s) => M.setPaid(d.sessions.find((x) => x.id === s.id), m.id, true)); }, `Thu của ${m.name}: ${money(amt)} (${ses.length} buổi)`);
    setToast(`${m.name} đã trả ${money(amt)}`);
  };
  const toggleSes = (s, mid) => { const on = M.isPaid(s, mid); B.mutate((d) => { M.setPaid(d.sessions.find((x) => x.id === s.id), mid, !on); }, `${on ? "Bỏ dấu đã trả" : "Đánh dấu đã trả"}: ${M.memById(book, mid)?.name} · buổi ${s.date || "?"}`); };
  const armPic = (id) => setPicFor(picFor && picFor.k === "m" && picFor.id === id ? null : { k: "m", id });

  return (
    <Stack spacing={2}>
      <Alert severity="info" icon={<Iconify icon="solar:gallery-add-bold-duotone" />}>Bấm vào ảnh rồi <b>Ctrl+V</b> để dán ảnh nhận diện (hoặc kéo-thả / chọn file).</Alert>
      <Stack direction="row" spacing={1}>
        <TextField placeholder="Tên thành viên mới" value={newName} onChange={(e) => setNewName(e.target.value)} onKeyDown={(e) => e.key === "Enter" && add()} fullWidth
          sx={{ "& .MuiOutlinedInput-root": { bgcolor: "background.paper" } }}
          InputProps={{ startAdornment: <InputAdornment position="start"><Iconify icon="solar:user-plus-bold" sx={{ color: "text.disabled" }} /></InputAdornment> }} />
        <Button variant="contained" onClick={add}>Thêm</Button>
      </Stack>
      <ToggleButtonGroup size="small" exclusive value={filter} onChange={(_, v) => v && setFilter(v)} sx={{ alignSelf: "flex-start" }}>
        <ToggleButton value="due">Còn nợ · {nDue}</ToggleButton>
        <ToggleButton value="all">Tất cả · {rows.length}</ToggleButton>
      </ToggleButtonGroup>
      <Card><List disablePadding>
        {list.map((r, i) => {
          const m = r.m, armed = picFor && picFor.k === "m" && picFor.id === m.id, isOpen = open === m.id;
          const ses = isOpen ? M.memberSessions(book, m.id).slice().reverse() : [];
          return (
            <Box key={m.id} sx={{ borderBottom: (t) => i < list.length - 1 ? `1px solid ${t.palette.divider}` : "none" }}>
              <ListItem sx={{ py: 1.25, pr: 1, flexWrap: "wrap", gap: 0.5 }}>
                <ListItemAvatar>
                  <Tooltip title="Bấm rồi Ctrl+V để dán ảnh">
                    <IconButton onClick={() => armPic(m.id)} onDragOver={(e) => e.preventDefault()} onDrop={(e) => { e.preventDefault(); const f = e.dataTransfer?.files?.[0]; if (f && f.type.startsWith("image")) { setPicFor({ k: "m", id: m.id }); setTimeout(() => {}, 0); applyPicDrop(B, book, m.id, f); } }}
                      sx={{ p: 0, outline: (t) => armed ? `2px solid ${t.palette.warning.main}` : "none", outlineOffset: 2 }}><MemAvatar m={m} size={40} /></IconButton>
                  </Tooltip>
                </ListItemAvatar>
                <ListItemText sx={{ minWidth: 0, flex: "1 1 120px" }} primary={<>{M.fullName(book, m)}{book.flags?.[m.id] && <Iconify icon="solar:notes-bold" width={14} style={{ marginLeft: 4, verticalAlign: -2, opacity: 0.6 }} />}</>}
                  secondary={r.due > M.EPS ? <>nợ <Money sx={{ color: DUE }}>{money(r.due)}</Money> · {r.nDue}/{r.n} buổi</> : `${r.n} buổi · đã trả đủ`} />
                <Stack direction="row" spacing={0.25} alignItems="center">
                  {r.due > M.EPS && <Button size="small" color="warning" onClick={() => payAll(m)} sx={{ bgcolor: (t) => alpha(t.palette.warning.main, 0.16), color: "warning.dark", "&:hover": { bgcolor: (t) => alpha(t.palette.warning.main, 0.28) } }}>Thu <Money sx={{ ml: 0.5 }}>{money(r.due)}</Money></Button>}
                  <Tooltip title="Chi tiết"><IconButton size="small" onClick={() => setOpen(isOpen ? null : m.id)}><Iconify icon={isOpen ? "solar:alt-arrow-up-bold" : "solar:alt-arrow-down-bold"} width={18} /></IconButton></Tooltip>
                  <Tooltip title="Ghi chú"><IconButton size="small" onClick={() => note(m)}><Iconify icon="solar:notes-bold" width={18} /></IconButton></Tooltip>
                  <Tooltip title="Đổi tên"><IconButton size="small" onClick={() => rename(m)}><Iconify icon="solar:pen-bold" width={18} /></IconButton></Tooltip>
                  <Tooltip title="Xóa"><IconButton size="small" color="error" onClick={() => del(m)}><Iconify icon="solar:trash-bin-trash-bold" width={18} /></IconButton></Tooltip>
                </Stack>
              </ListItem>
              {book.flags?.[m.id] && <Box sx={{ px: 2, pb: 1 }}><Typography variant="caption" sx={{ color: "error.main" }}>⚠ {book.flags[m.id]}</Typography></Box>}
              <Collapse in={isOpen} unmountOnExit>
                <Box sx={{ mx: 2, mb: 1.5, p: 0.75, borderRadius: 1.5, bgcolor: "background.neutral" }}>
                  {ses.length ? ses.map((s) => <SesLine key={s.id} s={s} mid={m.id} paid={M.isPaid(s, m.id)} onToggle={() => toggleSes(s, m.id)} />)
                    : <Typography variant="body2" color="text.secondary" sx={{ p: 1.5 }}>Chưa tham gia buổi nào.</Typography>}
                </Box>
              </Collapse>
            </Box>
          );
        })}
        {list.length === 0 && <EmptyRow>{rows.length ? "Không ai còn nợ 🎉" : "Chưa có thành viên nào."}</EmptyRow>}
      </List></Card>
    </Stack>
  );
}
// kéo-thả ảnh vào avatar: áp dụng ngay (không cần arm trước)
function applyPicDrop(B, book, mid, file) {
  shrinkSquare(file, 96, (url) => B.mutate((d) => { const mm = d.members.find((x) => x.id === mid); if (mm) mm.av = url; }, `Đổi ảnh đại diện: ${M.memById(book, mid)?.name || "?"}`));
}

function AdminCollect({ B, book, setToast, runExport }) {
  const [sel, setSel] = useState(() => new Set());
  const owing = M.debtors(book).map((m) => ({ m, due: M.memberDue(book, m.id), n: M.memberDueSessions(book, m.id).length })).sort((a, b) => b.due - a.due);
  const chosen = owing.filter((r) => sel.has(r.m.id));
  const grand = chosen.reduce((a, r) => a + r.due, 0);
  const toggle = (id) => setSel((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n; });
  const go = () => {
    if (!chosen.length) return;
    if (!confirm(`Ghi nhận đã thu ${money(grand)} từ ${chosen.length} người?\n\n${chosen.map((r) => M.fullName(book, r.m)).join(", ")}`)) return;
    B.mutate((d) => { chosen.forEach((r) => M.memberDueSessions(book, r.m.id).forEach((s) => M.setPaid(d.sessions.find((x) => x.id === s.id), r.m.id, true))); }, `Thu ${money(grand)} từ ${chosen.length} người`);
    setToast(`Đã ghi nhận ${money(grand)} từ ${chosen.length} người`); setSel(new Set());
  };
  return (
    <Stack spacing={2}>
      <Alert severity="info" icon={<Iconify icon="solar:card-transfer-bold-duotone" />}>Tick người vừa chuyển khoản rồi bấm Đã nhận tiền. Sổ tự lưu lên web.</Alert>
      <SectionLabel right={<Stack direction="row" spacing={0.5}><Button size="small" onClick={() => setSel(new Set(owing.map((r) => r.m.id)))}>Chọn hết</Button><Button size="small" color="inherit" onClick={() => setSel(new Set())}>Bỏ chọn</Button></Stack>}>
        Đang nợ · {owing.length} người · <Money>{money(owing.reduce((a, r) => a + r.due, 0))}</Money>
      </SectionLabel>
      <Card><List disablePadding>
        {owing.map((r, i) => (
          <ListItemButton key={r.m.id} divider={i < owing.length - 1} selected={sel.has(r.m.id)} onClick={() => toggle(r.m.id)} sx={{ py: 1, "&.Mui-selected": { bgcolor: (t) => alpha(t.palette.primary.main, 0.08) } }}>
            <Checkbox edge="start" checked={sel.has(r.m.id)} tabIndex={-1} />
            <ListItemAvatar><MemAvatar m={r.m} size={34} /></ListItemAvatar>
            <ListItemText primary={M.fullName(book, r.m)} secondary={`${r.n} buổi chưa trả`} />
            <Money sx={{ color: DUE, fontWeight: 700 }}>{money(r.due)}</Money>
          </ListItemButton>
        ))}
        {owing.length === 0 && <EmptyRow>Không ai còn nợ 🎉</EmptyRow>}
      </List></Card>
      {chosen.length > 0 && (<>
        <SectionLabel>Chi tiết {chosen.length} người đang chọn · <Money>{money(grand)}</Money></SectionLabel>
        <Card sx={{ overflow: "hidden" }}>
          {chosen.map((r, i) => (
            <Box key={r.m.id} sx={{ p: 1.5, borderBottom: (t) => `1px dashed ${t.palette.divider}` }}>
              <Stack direction="row" alignItems="center" spacing={1.25} sx={{ px: 0.5, mb: 1 }}>
                <MemAvatar m={r.m} size={36} />
                <Box sx={{ flexGrow: 1, minWidth: 0 }}>
                  <Typography variant="subtitle2" noWrap>{M.fullName(book, r.m)}</Typography>
                  <Typography variant="caption" color="text.secondary">{r.n} buổi chưa trả</Typography>
                </Box>
                <Label color="warning" sx={{ height: 28, px: 1.25, fontSize: 14 }}><Money sx={{ fontWeight: 700 }}>{money(r.due)}</Money></Label>
              </Stack>
              <Box sx={{ p: 0.75, borderRadius: 1.5, bgcolor: "background.neutral" }}>
                {M.memberDueSessions(book, r.m.id).map((s) => <SesLine key={s.id} s={s} mid={r.m.id} paid={false} />)}
              </Box>
            </Box>
          ))}
          <Stack direction="row" alignItems="center" sx={{ px: 2, py: 1.5, bgcolor: (t) => alpha(t.palette.warning.main, 0.1) }}>
            <Typography variant="overline" sx={{ flexGrow: 1, color: "warning.darker" }}>Tổng cần thu · {chosen.length} người</Typography>
            <Money sx={{ color: DUE, fontWeight: 700, fontSize: 20 }}>{money(grand)}</Money>
          </Stack>
        </Card>
        <Button variant="outlined" color="inherit" startIcon={<Iconify icon="solar:gallery-download-bold" />} onClick={() => runExport(() => exportBillImage(book, bookUpdatedAt(), chosen.map((r) => r.m)))}>Xuất ảnh hoá đơn{chosen.length > 1 ? ` gộp ${chosen.length} người` : ""}</Button>
      </>)}
      <Button variant="contained" size="large" disabled={!chosen.length} onClick={go} startIcon={<Iconify icon="solar:check-circle-bold" />}>
        Đã nhận tiền{chosen.length ? <>&nbsp;· <Money sx={{ mx: 0.5 }}>{money(grand)}</Money> · {chosen.length} người</> : ""}
      </Button>
      <SettingsCard B={B} book={book} setToast={setToast} />
    </Stack>
  );
}

function SettingsCard({ B, book, setToast }) {
  const qrRef = useRef(null), jsonRef = useRef(null);
  const [logN, setLogN] = useState(15);
  const log = (book.log || []).slice().reverse();
  const onQr = (e) => { const f = e.target.files[0]; e.target.value = ""; if (!f) return; shrinkMax(f, 480, (d) => B.mutate((bk) => { bk.qr = d; }, "Cập nhật mã QR")); };
  const onJson = (e) => {
    const f = e.target.files[0]; e.target.value = ""; if (!f) return;
    const rd = new FileReader();
    rd.onload = (ev) => {
      let next; try { next = M.migrate(JSON.parse(ev.target.result)); } catch (err) { alert("File không hợp lệ: " + err.message); return; }
      if (!confirm(`Nhập ${next.sessions.length} buổi / ${next.members.length} người? Sổ trên web sẽ bị ghi đè.`)) return;
      B.mutate((bk) => { Object.keys(bk).forEach((k) => delete bk[k]); Object.assign(bk, next); }, `Nhập JSON: ${next.sessions.length} buổi / ${next.members.length} người`);
      setToast("Đã nhập — đang lưu lên web…");
    };
    rd.readAsText(f);
  };
  const exportJson = () => { const b = new Blob([JSON.stringify(book, null, 2)], { type: "application/json" }); const a = document.createElement("a"); a.href = URL.createObjectURL(b); a.download = "so-cau-long-" + new Date().toISOString().slice(0, 10) + ".json"; a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 4000); };
  const clearLog = () => { if (!confirm(`Xóa toàn bộ ${(book.log || []).length} dòng lịch sử? Số liệu tiền nong không bị ảnh hưởng.`)) return; B.mutate((d) => { d.log = []; }, "Xóa lịch sử chỉnh sửa"); setLogN(15); };
  return (
    <Stack spacing={2}>
      <Card sx={{ p: 2.5 }}>
        <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 1.5 }}><Iconify icon="solar:settings-bold-duotone" sx={{ color: "text.secondary" }} /><Typography variant="subtitle1">Cài đặt</Typography></Stack>
        <TextField fullWidth label="Tên · ngân hàng · số tài khoản" defaultValue={book.note || ""} onBlur={(e) => { if (e.target.value !== (book.note || "")) B.mutate((d) => { d.note = e.target.value; }, "Sửa thông tin ngân hàng"); }} sx={{ mb: 1.5 }} />
        <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap>
          <input ref={qrRef} type="file" accept="image/*" hidden onChange={onQr} />
          <input ref={jsonRef} type="file" accept="application/json,.json" hidden onChange={onJson} />
          <Button size="small" variant="outlined" startIcon={<Iconify icon="solar:qr-code-bold" width={18} />} onClick={() => qrRef.current?.click()}>{book.qr ? "Đổi QR" : "Tải QR lên"}</Button>
          {book.qr && <Button size="small" color="error" onClick={() => B.mutate((d) => { d.qr = ""; }, "Xóa mã QR")}>Xóa QR</Button>}
          <Box flexGrow={1} />
          <Button size="small" color="inherit" startIcon={<Iconify icon="solar:upload-bold" width={18} />} onClick={() => jsonRef.current?.click()}>Nhập JSON</Button>
          <Button size="small" color="inherit" startIcon={<Iconify icon="solar:download-bold" width={18} />} onClick={exportJson}>Xuất JSON</Button>
        </Stack>
        {book.qr && <Box sx={{ textAlign: "center", mt: 2 }}><img src={book.qr} alt="QR" style={{ maxWidth: 180, borderRadius: 12 }} /></Box>}
        <Typography variant="caption" color="text.secondary" sx={{ display: "block", mt: 1.5 }}>Sổ đang ở phiên bản <Money component="span">{B.rev}</Money>. Muốn quay lại bản cũ: xuất JSON định kỳ để backup, rồi Nhập JSON khi cần.</Typography>
      </Card>

      <Card sx={{ p: 2.5 }}>
        <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 1.5 }}>
          <Iconify icon="solar:history-bold-duotone" sx={{ color: "text.secondary" }} />
          <Typography variant="subtitle1" sx={{ flexGrow: 1 }}>Lịch sử chỉnh sửa{log.length ? ` · ${log.length}` : ""}</Typography>
          {log.length > 0 && <Button size="small" color="error" onClick={clearLog}>Xóa</Button>}
        </Stack>
        {log.length === 0 ? <Typography variant="body2" color="text.secondary">Chưa ghi nhận thao tác nào. Từ giờ mọi thay đổi đều được ghi lại ở đây.</Typography> : (
          <List dense disablePadding>
            {log.slice(0, logN).map((e, i) => { const d = new Date(e.t), ok = !isNaN(d); return (
              <ListItem key={i} divider={i < Math.min(logN, log.length) - 1} sx={{ alignItems: "flex-start", px: 0 }}>
                <Money sx={{ width: 92, flexShrink: 0, fontSize: 11, color: "text.secondary", pt: 0.25 }}>{ok ? d.toLocaleDateString("vi-VN", { day: "2-digit", month: "2-digit" }) + " " + d.toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" }) : "—"}</Money>
                <Typography variant="body2" sx={{ flex: 1 }}>{e.m}</Typography>
              </ListItem>
            ); })}
          </List>
        )}
        <Stack direction="row" spacing={1} sx={{ mt: 1 }}>
          {log.length > logN && <Button size="small" onClick={() => setLogN((n) => n + 30)}>Xem thêm {Math.min(30, log.length - logN)}</Button>}
          {logN > 15 && <Button size="small" color="inherit" onClick={() => setLogN(15)}>Thu gọn</Button>}
        </Stack>
        <Typography variant="caption" color="text.secondary" sx={{ display: "block", mt: 1 }}>Giữ {M.LOG_MAX} thao tác gần nhất, nằm chung trong sổ.</Typography>
      </Card>
    </Stack>
  );
}

// ---------- shared overlays ----------
function PicBar({ ctx, pickFile }) {
  const { picFor, setPicFor, book, B, isAdmin } = ctx;
  if (!isAdmin || !picFor) return null;
  const has = picFor.k === "m" ? !!M.memById(book, picFor.id)?.av : !!M.sessionById(book, picFor.id)?.photo;
  const name = M.picName(book, picFor);
  const del = () => { B.mutate((d) => { if (picFor.k === "m") { const mm = d.members.find((x) => x.id === picFor.id); if (mm) mm.av = ""; } else { const s = d.sessions.find((x) => x.id === picFor.id); if (s) s.photo = ""; } }, `Xóa ảnh ${name}`); setPicFor(null); };
  return (
    <Paper sx={{ position: "fixed", left: "50%", transform: "translateX(-50%)", bottom: { xs: "calc(140px + env(safe-area-inset-bottom))", sm: 76 }, zIndex: 30, px: 1.5, py: 1, display: "flex", alignItems: "center", gap: 1, width: "max-content", maxWidth: "min(94vw, 520px)", borderRadius: 4, bgcolor: "grey.800", color: "common.white", boxShadow: (t) => t.customShadows.z20 }}>
      <Typography variant="body2" sx={{ flex: 1 }}>Ảnh cho <b>{name}</b> — <Box component="span" sx={{ bgcolor: "rgba(255,255,255,.16)", px: 0.6, borderRadius: 0.5, ...monoFont, fontSize: 11 }}>Ctrl+V</Box></Typography>
      <Button size="small" variant="outlined" sx={{ color: "#fff", borderColor: "rgba(255,255,255,.4)" }} onClick={pickFile}>Chọn ảnh</Button>
      {has && <Button size="small" color="error" variant="outlined" onClick={del}>Xóa</Button>}
      <Button size="small" variant="contained" onClick={() => setPicFor(null)}>Xong</Button>
    </Paper>
  );
}

function ImageDialog({ img, onClose }) {
  if (!img) return null;
  const dl = () => { const a = document.createElement("a"); a.href = img.url; a.download = img.filename; document.body.appendChild(a); a.click(); a.remove(); };
  return (
    <Dialog open onClose={onClose} fullWidth maxWidth="sm">
      <DialogTitle sx={{ display: "flex", alignItems: "center" }}><Box sx={{ flexGrow: 1 }}>Ảnh đã tạo xong</Box><IconButton onClick={onClose}><Iconify icon="solar:close-circle-bold" /></IconButton></DialogTitle>
      <DialogContent><Box component="img" src={img.url} sx={{ width: "100%", borderRadius: 1.5, display: "block" }} />
        <Typography variant="caption" color="text.secondary" sx={{ display: "block", textAlign: "center", mt: 1 }}>Trên điện thoại: nhấn giữ vào ảnh rồi chọn “Lưu ảnh”.</Typography>
      </DialogContent>
      <DialogActions><Button variant="contained" startIcon={<Iconify icon="solar:download-bold" />} onClick={dl}>Tải về máy</Button></DialogActions>
    </Dialog>
  );
}

function PhotoZoom({ photo, onClose }) {
  if (!photo) return null;
  return <Dialog open onClose={onClose} fullWidth maxWidth="sm"><Box component="img" src={photo} sx={{ width: "100%", display: "block" }} onClick={onClose} /></Dialog>;
}

// ---------- Save bar + conflict ----------
function SaveBar({ B }) {
  if (!B.isAdmin) return null;
  const { save, rev } = B;
  let color = "success", txt, icon = "solar:cloud-check-bold";
  if (save.err) { color = "error"; icon = "solar:danger-triangle-bold"; txt = "Lưu lỗi: " + save.err + (save.retries && save.retries < 3 ? ` (thử lại lần ${save.retries}…)` : ""); }
  else if (save.saving) { color = "warning"; icon = "solar:cloud-upload-bold"; txt = "Đang lưu lên web…"; }
  else if (save.dirty) { color = "warning"; icon = "solar:clock-circle-bold"; txt = "Có thay đổi chưa lưu"; }
  else txt = `Đã lưu${save.savedAt ? " lúc " + new Date(save.savedAt).toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" }) : ""}`;
  return (
    <Paper sx={{ position: "fixed", left: "50%", transform: "translateX(-50%)", bottom: { xs: "calc(76px + env(safe-area-inset-bottom))", sm: 20 }, zIndex: 20, pl: 1.5, pr: 1, py: 0.75, display: "flex", alignItems: "center", gap: 1.25, width: "max-content", maxWidth: "min(94vw, 560px)", borderRadius: 5, bgcolor: "grey.800", color: "common.white", boxShadow: (t) => t.customShadows.z20 }}>
      <Iconify icon={icon} width={20} sx={{ color: `${color}.light` }} />
      <Typography variant="body2" sx={{ flex: 1, fontWeight: 500 }}>{txt}</Typography>
      {!save.dirty && !save.err && !save.saving && <Label variant="filled" sx={{ bgcolor: "rgba(255,255,255,.14)", color: "grey.300", ...monoFont }}>v{rev}</Label>}
      {(save.dirty || save.err) && <Button size="small" variant="contained" onClick={B.saveNow} sx={{ borderRadius: 4, boxShadow: "none" }}>Lưu ngay</Button>}
    </Paper>
  );
}

function ConflictDialog({ B }) {
  const c = B.conflict; if (!c) return null;
  const lines = c.data ? M.diffSummary(B.book, c.data).slice(0, 10) : [];
  return (
    <Dialog open onClose={() => {}} fullWidth maxWidth="sm">
      <DialogTitle sx={{ display: "flex", alignItems: "center", gap: 1 }}><Iconify icon="solar:danger-triangle-bold" sx={{ color: "warning.main" }} width={26} /> Sổ đã bị sửa ở nơi khác</DialogTitle>
      <DialogContent>
        <Typography variant="body2" color="text.secondary">Trên web đang là phiên bản <Label color="info">v{c.rev}</Label>, máy này giữ phiên bản <Label>v{B.rev}</Label>. Thường do bạn mở ở tab/máy khác.</Typography>
        {lines.length > 0 && <Box sx={{ mt: 2, p: 1.5, borderRadius: 1.5, bgcolor: "background.neutral" }}>{lines.map((l, i) => <Typography key={i} variant="body2" sx={{ py: 0.25 }}>• {l}</Typography>)}</Box>}
      </DialogContent>
      <DialogActions><Button variant="contained" onClick={() => B.resolveConflict(true)}>Lấy bản trên web</Button><Button color="error" onClick={() => B.resolveConflict(false)}>Ghi đè bằng bản của tôi</Button></DialogActions>
    </Dialog>
  );
}

// ---------- image helpers ----------
function shrinkSquare(blob, size, cb) {
  const rd = new FileReader();
  rd.onload = (ev) => { const im = new Image(); im.onload = () => {
    const side = Math.min(im.width, im.height), sx = (im.width - side) / 2, sy = (im.height - side) / 2;
    const cv = document.createElement("canvas"); cv.width = cv.height = size;
    cv.getContext("2d").drawImage(im, sx, sy, side, side, 0, 0, size, size);
    try { cb(cv.toDataURL("image/jpeg", 0.8)); } catch { cb(ev.target.result); }
  }; im.src = ev.target.result; };
  rd.readAsDataURL(blob);
}
function shrinkMax(blob, max, cb) {
  const rd = new FileReader();
  rd.onload = (ev) => { const im = new Image(); im.onload = () => {
    let w = im.width, h = im.height; const r = Math.min(1, max / Math.max(w, h)); w = Math.round(w * r); h = Math.round(h * r);
    const cv = document.createElement("canvas"); cv.width = w; cv.height = h; cv.getContext("2d").drawImage(im, 0, 0, w, h);
    try { cb(cv.toDataURL("image/jpeg", 0.85)); } catch { cb(ev.target.result); }
  }; im.src = ev.target.result; };
  rd.readAsDataURL(blob);
}
