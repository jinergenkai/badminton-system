// Xếp sân cho host (điện thoại thứ 3, mở web).
//   1. "Hôm nay ai tới": tick người có mặt (Dialog giống chọn người của Tiền cầu).
//   2. Các sân: chọn bằng thanh trên hoặc vuốt trái/phải. Mỗi sân 4 ô Đỏ 1-2 / Xanh 1-2.
//   3. Khay "Đang chờ": card từng người, xếp chờ lâu nhất trước (chưa đánh = chờ lâu nhất),
//      rồi ít trận hơn. Chạm card → vào ô đang chọn (hoặc ô trống đầu tiên).
//      Chạm người trên sân → về khay. "Tự xếp" lấy 4 người ưu tiên, chia cặp lệch Elo ít nhất.
// Bảng lưu ở backend theo ngày (rev chống ghi đè) → máy khác cùng thấy; sau này phone
// đọc bảng này để gửi cặp xuống band. Logic thuần ở lib/courts.js (có test).
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Alert, Avatar, Box, Button, Card, Checkbox, CircularProgress, Dialog, DialogActions,
  DialogContent, DialogTitle, IconButton, InputAdornment, List, ListItem, ListItemAvatar,
  ListItemText, Paper, Snackbar, Stack, TextField, ToggleButton, ToggleButtonGroup, Typography,
} from "@mui/material";
import { alpha, useTheme } from "@mui/material/styles";
import { api, API_BASE, todayVN } from "../lib/api.js";
import * as C from "../lib/courts.js";
import { useAuth } from "../lib/auth.jsx";
import WidgetSummary from "../components/WidgetSummary.jsx";
import { Iconify } from "../components/iconify/index.jsx";
import { Label } from "../components/label/index.jsx";
import Money, { SectionLabel } from "../components/Money.jsx";

const SAVE_DELAY = 600;
const POLL_BOARD = 15000;
const POLL_COUNTS = 60000;

function GuestTag() {
  return <Label color="warning" sx={{ ml: 0.75, height: 18, fontSize: 10, px: 0.6 }}>khách</Label>;
}

function PAvatar({ p, size = 32, color }) {
  return (
    <Avatar src={p.avatar || undefined}
      sx={{ width: size, height: size, fontSize: size * 0.45, color: "#fff", bgcolor: color || (p.guest ? "warning.main" : "primary.main") }}>
      {(p.name || "?").slice(0, 1)}
    </Avatar>
  );
}

// ---------- một ô trên sân ----------
function Slot({ p, side, selected, onClick, now, disabled }) {
  return (
    <Box component="button" type="button" onClick={onClick} disabled={disabled}
      sx={(t) => {
        const c = t.palette[side];
        return {
          display: "flex", alignItems: "center", gap: 1, width: 1, minHeight: 56, px: 1, py: 0.75, borderRadius: 1.5,
          font: "inherit", textAlign: "left", cursor: disabled ? "default" : "pointer", transition: "all .15s",
          bgcolor: p ? alpha(c.main, 0.1) : selected ? alpha(c.main, 0.16) : "transparent",
          border: `${selected ? 2 : 1}px ${p ? "solid" : "dashed"} ${selected ? c.main : alpha(p ? c.main : t.palette.grey[500], p ? 0.4 : 0.48)}`,
          color: "text.primary",
        };
      }}>
      {p ? (
        <>
          <PAvatar p={p} size={30} color={`${side}.main`} />
          <Box sx={{ minWidth: 0 }}>
            <Typography variant="subtitle2" noWrap sx={{ lineHeight: 1.3 }}>{p.short || p.name}</Typography>
            <Typography variant="caption" color="text.secondary" noWrap component="div">{p.played} trận · <Money sx={{ fontSize: 11, fontWeight: 500 }}>{Math.round(p.elo || 1000)}</Money></Typography>
          </Box>
        </>
      ) : (
        <Typography variant="caption" sx={{ color: selected ? `${side}.dark` : "text.disabled", fontWeight: 600, mx: "auto" }}>
          {selected ? "Chạm người bên dưới" : "Trống"}
        </Typography>
      )}
    </Box>
  );
}

// ---------- một sân ----------
function CourtCard({ court, ci, people, sel, setSel, isAdmin, onSlot, onAuto, onClear, onRemove, canRemove, now }) {
  const ps = court.slots.map((id) => (id ? people.get(id) || { id, name: id, elo: 1000, played: 0 } : null));
  const full = ps.every(Boolean);
  const diff = full ? Math.abs((ps[0].elo || 1000) + (ps[1].elo || 1000) - (ps[2].elo || 1000) - (ps[3].elo || 1000)) : null;
  const side = (label, color, idx) => (
    <Box sx={{ minWidth: 0 }}>
      <Typography variant="overline" sx={{ color: `${color}.main`, fontWeight: 800, display: "block", mb: 0.5 }}>{label}</Typography>
      <Stack spacing={1}>
        {idx.map((si) => (
          <Slot key={si} p={ps[si]} side={color} now={now} disabled={!isAdmin}
            selected={isAdmin && sel && sel.ci === ci && sel.si === si}
            onClick={() => onSlot(ci, si)} />
        ))}
      </Stack>
    </Box>
  );
  return (
    <Card sx={{ p: 2 }}>
      <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 1.5 }}>
        <Typography variant="h6" sx={{ flexGrow: 1 }}>{court.name}</Typography>
        {diff != null && <Label color={diff <= 30 ? "success" : diff <= 80 ? "info" : "warning"}>lệch {Math.round(diff)} Elo</Label>}
        {/* chỉ xoá được sân TRỐNG — tránh một chạm mất cả 4 người đang đánh */}
        {isAdmin && canRemove && !ps.some(Boolean) && (
          <IconButton size="small" onClick={() => onRemove(ci)} sx={{ color: "text.disabled" }}><Iconify icon="solar:trash-bin-trash-bold" width={18} /></IconButton>
        )}
      </Stack>
      <Box sx={{ display: "grid", gridTemplateColumns: "1fr auto 1fr", gap: 1, alignItems: "center" }}>
        {side("Đỏ", "error", C.RED)}
        <Typography variant="subtitle2" color="text.disabled" sx={{ pt: 3 }}>vs</Typography>
        {side("Xanh", "info", C.BLUE)}
      </Box>
      {isAdmin && (
        <Stack direction="row" spacing={1} sx={{ mt: 2 }}>
          <Button fullWidth variant="contained" onClick={() => onAuto(ci)} disabled={full} startIcon={<Iconify icon="solar:shuffle-bold" width={18} />}>Tự xếp</Button>
          <Button fullWidth variant="outlined" color="inherit" onClick={() => onClear(ci)} disabled={!ps.some(Boolean)} startIcon={<Iconify icon="solar:check-circle-bold" width={18} />}>Xong trận</Button>
        </Stack>
      )}
    </Card>
  );
}

// ---------- card người chờ ----------
function WaitCard({ p, rank, onClick, disabled, now }) {
  const first = rank < 4;
  return (
    <Card component="button" type="button" onClick={onClick} disabled={disabled}
      sx={(t) => ({
        p: 1.25, display: "flex", alignItems: "center", gap: 1, width: 1, font: "inherit", textAlign: "left",
        cursor: disabled ? "default" : "pointer", boxShadow: "none",
        border: `1px solid ${first ? alpha(t.palette.primary.main, 0.4) : alpha(t.palette.grey[500], 0.2)}`,
        bgcolor: first ? alpha(t.palette.primary.main, 0.04) : "background.paper",
        "&:hover": disabled ? undefined : { borderColor: "primary.main" },
      })}>
      <PAvatar p={p} size={36} />
      <Box sx={{ minWidth: 0, flexGrow: 1 }}>
        <Typography variant="subtitle2" noWrap sx={{ display: "flex", alignItems: "center" }}>
          <Box component="span" sx={{ overflow: "hidden", textOverflow: "ellipsis" }}>{p.name}</Box>{p.guest && <GuestTag />}
        </Typography>
        <Typography variant="caption" color="text.secondary" component="div" noWrap>
          {p.played} trận · {C.waitLabel(p, now)} · <Money sx={{ fontSize: 11, fontWeight: 500 }}>{Math.round(p.elo || 1000)}</Money>
        </Typography>
      </Box>
      {first && <Label color="primary" sx={{ flexShrink: 0 }}>#{rank + 1}</Label>}
    </Card>
  );
}

// ---------- dialog "hôm nay ai tới" ----------
function PresentDialog({ open, onClose, list, present, onToggle, isAdmin, onAddGuest }) {
  const [q, setQ] = useState("");
  const [guest, setGuest] = useState("");
  const [busy, setBusy] = useState(false);
  const shown = useMemo(() => {
    const k = q.trim().toLowerCase();
    const arr = list.filter((p) => !k || (p.name || "").toLowerCase().includes(k) || (p.short || "").toLowerCase().includes(k));
    // người đã tick lên đầu; còn lại ai đánh nhiều hôm nay / tên
    return arr.sort((a, b) => (present.has(b.id) - present.has(a.id)) || String(a.name).localeCompare(String(b.name), "vi"));
  }, [list, present, q]);
  const add = async () => {
    const n = guest.trim();
    if (!n || busy) return;
    setBusy(true);
    try { await onAddGuest(n); setGuest(""); } finally { setBusy(false); }
  };
  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="sm">
      <DialogTitle>Hôm nay ai tới</DialogTitle>
      <DialogContent>
        <SectionLabel>Người chơi · {present.size} đã chọn</SectionLabel>
        <TextField size="small" fullWidth placeholder="Tìm tên…" value={q} onChange={(e) => setQ(e.target.value)} sx={{ mb: 1 }}
          InputProps={{ startAdornment: <InputAdornment position="start"><Iconify icon="solar:magnifer-linear" width={18} sx={{ color: "text.disabled" }} /></InputAdornment> }} />
        <Paper variant="outlined" sx={{ maxHeight: 360, overflow: "auto", borderRadius: 1.5 }}>
          <List dense disablePadding>
            {shown.map((p) => {
              const on = present.has(p.id);
              return (
                <ListItem key={p.id} divider sx={{ bgcolor: (t) => (on ? alpha(t.palette.primary.main, 0.05) : undefined) }}>
                  <Checkbox edge="start" checked={on} disabled={!isAdmin} onChange={() => onToggle(p.id)} />
                  <ListItemAvatar sx={{ minWidth: 40 }}><PAvatar p={p} size={28} /></ListItemAvatar>
                  <ListItemText onClick={() => isAdmin && onToggle(p.id)} sx={{ cursor: isAdmin ? "pointer" : "default" }}
                    primary={<Box component="span" sx={{ display: "inline-flex", alignItems: "center" }}>{p.name}{p.guest && <GuestTag />}</Box>}
                    secondary={`${p.played} trận hôm nay · Elo ${Math.round(p.elo || 1000)}`} />
                </ListItem>
              );
            })}
            {shown.length === 0 && <Box sx={{ py: 3, textAlign: "center" }}><Typography variant="body2" color="text.secondary">Không tìm thấy ai.</Typography></Box>}
          </List>
        </Paper>
        {isAdmin && (
          <Stack direction="row" spacing={1} sx={{ mt: 1.5 }}>
            <TextField fullWidth placeholder="Thêm khách vãng lai" value={guest} onChange={(e) => setGuest(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && add()} inputProps={{ maxLength: 60 }}
              InputProps={{ startAdornment: <InputAdornment position="start"><Iconify icon="solar:user-plus-bold" sx={{ color: "text.disabled" }} /></InputAdornment> }} />
            <Button variant="outlined" onClick={add} disabled={!guest.trim() || busy}>Thêm</Button>
          </Stack>
        )}
        <Typography variant="caption" color="text.secondary" sx={{ display: "block", mt: 1 }}>
          Thành viên thêm ở Tiền cầu. Khách có dấu * trên band.
        </Typography>
      </DialogContent>
      <DialogActions><Button variant="contained" onClick={onClose}>Xong</Button></DialogActions>
    </Dialog>
  );
}

export default function Pickup() {
  const theme = useTheme();
  const auth = useAuth();
  const isAdmin = auth.isAdmin;
  const [day, setDay] = useState(todayVN);
  const [counts, setCounts] = useState(null); // {date, matches, pickup:[...]}
  const [board, setBoard] = useState(null);
  const [err, setErr] = useState("");
  const [ci, setCi] = useState(0);
  const [sel, setSel] = useState(null); // {ci, si} ô đang chọn
  const [openPresent, setOpenPresent] = useState(false);
  const [toast, setToast] = useState("");
  const [saving, setSaving] = useState(false);
  const [now, setNow] = useState(Date.now());
  const st = useRef({ rev: 0, dirty: false, timer: null, saving: false, board: null, day: null });

  // ----- tải -----
  const loadCounts = useCallback((d) => api.getPickupDay(d).then((j) => { if (st.current.day === d) setCounts(j); }), []);
  const loadBoard = useCallback((d, force) => api.getBoard(d).then((j) => {
    const s = st.current;
    if (s.day !== d || (!force && (s.dirty || s.saving))) return; // đang sửa thì không đè
    s.rev = j.rev; s.board = j.board;
    setBoard(j.board);
  }), []);
  const loadAll = useCallback((d) => {
    setErr("");
    return Promise.all([loadCounts(d), loadBoard(d, true)]).catch((e) => setErr(String(e.message || e)));
  }, [loadCounts, loadBoard]);

  useEffect(() => {
    const s = st.current;
    clearTimeout(s.timer); s.dirty = false; s.day = day; s.rev = 0; s.board = null;
    setBoard(null); setCounts(null); setSel(null); setCi(0);
    loadAll(day);
  }, [day, loadAll]);

  useEffect(() => {
    const a = setInterval(() => { loadBoard(st.current.day).catch(() => {}); }, POLL_BOARD);
    const b = setInterval(() => { setNow(Date.now()); loadCounts(st.current.day).catch(() => {}); }, POLL_COUNTS);
    const onFocus = () => { setNow(Date.now()); loadAll(st.current.day); };
    window.addEventListener("focus", onFocus);
    return () => { clearInterval(a); clearInterval(b); window.removeEventListener("focus", onFocus); };
  }, [loadBoard, loadCounts, loadAll]);

  // ----- lưu (debounce, chống ghi đè bằng rev) -----
  const flush = useCallback(async () => {
    const s = st.current;
    if (!s.dirty || s.saving) return;
    s.saving = true; s.dirty = false; setSaving(true);
    const d = s.day;
    try {
      const r = await api.saveBoard(auth.passRef.current, d, s.rev, s.board);
      if (s.day !== d) return;
      if (r.conflict) {
        s.rev = r.server.rev; s.board = r.server.board; setBoard(r.server.board);
        setToast("Máy khác vừa sửa bảng — đã tải bản mới, bạn làm lại thao tác vừa rồi.");
      } else {
        s.rev = r.rev;
        if (!s.dirty) { s.board = r.board; setBoard(r.board); }
      }
    } catch (e) {
      s.dirty = true;
      setToast("Chưa lưu được: " + (e.message || e));
    } finally {
      s.saving = false; setSaving(false);
      if (s.dirty) { clearTimeout(s.timer); s.timer = setTimeout(flush, 3000); }
    }
  }, [auth.passRef]);

  const update = useCallback((fn) => {
    const s = st.current;
    if (!s.board) return;
    const next = fn(s.board);
    if (next === s.board) return;
    s.board = next; s.dirty = true; setBoard(next);
    clearTimeout(s.timer); s.timer = setTimeout(flush, SAVE_DELAY);
  }, [flush]);

  // ----- dữ liệu dẫn xuất -----
  const people = useMemo(() => new Map((counts?.pickup || []).map((p) => [p.id, p])), [counts]);
  const present = useMemo(() => new Set(board?.present || []), [board]);
  const busy = useMemo(() => (board ? C.onCourtIds(board) : new Set()), [board]);
  const tray = useMemo(() => C.byPriority((counts?.pickup || []).filter((p) => present.has(p.id) && !busy.has(p.id)), now),
    [counts, present, busy, now]);
  const courtIdx = board ? Math.min(ci, board.courts.length - 1) : 0;

  // ----- thao tác -----
  const onSlot = (c, si) => {
    const id = st.current.board?.courts[c]?.slots[si];
    if (id) { update((b) => C.removeEverywhere(b, id)); setSel({ ci: c, si }); return; }
    setSel((cur) => (cur && cur.ci === c && cur.si === si ? null : { ci: c, si }));
  };
  const pick = (p) => {
    const cur = st.current.board; // bản mới nhất (state có thể chưa kịp render khi bấm nhanh)
    if (!isAdmin || !cur) return;
    const c = Math.min(sel ? sel.ci : courtIdx, cur.courts.length - 1);
    const si = C.firstEmpty(cur.courts[c], sel && sel.ci === c ? sel.si : -1);
    if (si < 0) { setToast(`${cur.courts[c].name} đã đủ 4 người — bấm "Xong trận" hoặc chạm một ô để gỡ.`); return; }
    const next = C.place(cur, c, si, p.id);
    update(() => next);
    // chọn sẵn ô trống kế tiếp của sân đó cho nhanh
    const nx = C.firstEmpty(next.courts[c]);
    setSel(nx >= 0 ? { ci: c, si: nx } : null);
    setCi(c);
  };
  const onAuto = (c) => {
    if (tray.length === 0) { setToast("Không còn ai đang chờ — tick thêm người ở \"Hôm nay ai tới\"."); return; }
    update((b) => C.autoFill(b, c, counts?.pickup || [], Date.now()));
    setSel(null);
  };
  const onAddGuest = async (name) => {
    try {
      const g = await api.addGuest(auth.passRef.current, name);
      await loadCounts(day);
      update((b) => (b.present.includes(g.id) ? b : { ...b, present: [...b.present, g.id] }));
      setToast(`Đã thêm khách ${g.name} — trên band là ${g.short}`);
    } catch (e) { setToast(String(e.message || e)); }
  };

  // vuốt trái/phải giữa các sân
  const touch = useRef(null);
  const onTouchStart = (e) => { const t = e.touches[0]; touch.current = { x: t.clientX, y: t.clientY, lx: t.clientX, ly: t.clientY }; };
  const onTouchMove = (e) => { const s = touch.current, t = e.touches[0]; if (s && t) { s.lx = t.clientX; s.ly = t.clientY; } };
  const onTouchEnd = () => {
    const s = touch.current; touch.current = null;
    if (!s || !board) return;
    const dx = s.lx - s.x, dy = s.ly - s.y;
    if (Math.abs(dx) < 60 || Math.abs(dx) < Math.abs(dy) * 1.5) return;
    setCi((i) => Math.max(0, Math.min(board.courts.length - 1, i + (dx < 0 ? 1 : -1))));
    setSel(null);
  };

  const isToday = day === todayVN();

  return (
    <Stack spacing={2.5}>
      <Stack direction="row" alignItems="center" spacing={1}>
        <Box sx={{ flexGrow: 1 }}>
          <Typography variant="h4" sx={{ fontFamily: theme.typography.fontSecondaryFamily, fontWeight: 800, lineHeight: 1.1 }}>Xếp sân</Typography>
          <Typography variant="caption" color="text.secondary">Chờ lâu nhất vào trước · cặp chia cân Elo</Typography>
        </Box>
        {saving ? <Label color="info" variant="soft" startIcon={<Iconify icon="solar:cloud-upload-bold" />}>Đang lưu</Label>
          : isAdmin && <Label color="primary" variant="soft" startIcon={<Iconify icon="solar:verified-check-bold" />}>Quản trị</Label>}
      </Stack>

      <Card sx={{ px: 1, py: 0.75 }}>
        <Stack direction="row" alignItems="center">
          <IconButton onClick={() => setDay((d) => C.shiftDay(d, -1))}><Iconify icon="solar:alt-arrow-left-bold" /></IconButton>
          <Stack alignItems="center" sx={{ flexGrow: 1 }}>
            <Typography variant="subtitle1">{C.dayLabel(day)}</Typography>
            {isToday ? <Label color="success" sx={{ height: 18, fontSize: 10 }}>Hôm nay</Label>
              : <Button size="small" onClick={() => setDay(todayVN())} sx={{ py: 0, minHeight: 0, fontSize: 12 }}>Về hôm nay</Button>}
          </Stack>
          <IconButton onClick={() => setDay((d) => C.shiftDay(d, 1))}><Iconify icon="solar:alt-arrow-right-bold" /></IconButton>
          <IconButton onClick={() => { setNow(Date.now()); loadAll(day); }} sx={{ color: "text.secondary" }}><Iconify icon="solar:refresh-bold" /></IconButton>
        </Stack>
      </Card>

      {err && (
        <Alert severity="warning">
          Không tải được: {err}
          {!API_BASE && <><br />Chưa cấu hình <code>VITE_API_BASE</code> — màn này cần backend.</>}
        </Alert>
      )}
      {!err && (!board || !counts) && <Box sx={{ display: "grid", placeItems: "center", py: 6 }}><CircularProgress /></Box>}

      {board && counts && (
        <>
          <Box sx={{ display: "grid", gap: 1.5, gridTemplateColumns: "repeat(2,1fr)" }}>
            <WidgetSummary color="primary" icon="solar:users-group-rounded-bold-duotone" title="Có mặt" total={present.size} caption={`${tray.length} đang chờ · ${busy.size} trên sân`} />
            <WidgetSummary color="info" icon="solar:ranking-bold-duotone" title="Trận hôm nay" total={counts.matches} caption="đồng bộ từ phone" />
          </Box>

          <Button variant={present.size ? "outlined" : "contained"} color={present.size ? "inherit" : "primary"} onClick={() => setOpenPresent(true)}
            startIcon={<Iconify icon="solar:user-plus-bold" width={18} />} sx={{ alignSelf: "stretch" }}>
            Hôm nay ai tới · {present.size} người
          </Button>

          {!isAdmin && <Alert severity="info">Đang xem. Mở khoá <b>Quản trị</b> (góc trên) để xếp sân.</Alert>}

          <Stack direction="row" spacing={1} alignItems="center">
            <ToggleButtonGroup exclusive value={courtIdx} onChange={(_, v) => { if (v != null) { setCi(v); setSel(null); } }}
              sx={{ flexGrow: 1, overflowX: "auto", flexWrap: "nowrap" }}>
              {board.courts.map((c, i) => {
                const n = c.slots.filter(Boolean).length;
                return (
                  <ToggleButton key={i} value={i} sx={{ py: 0.6, px: 1.5, whiteSpace: "nowrap", flexShrink: 0 }}>
                    {c.name}<Box component="span" sx={{ ml: 0.75, fontSize: 11, opacity: 0.7 }}>{n}/4</Box>
                  </ToggleButton>
                );
              })}
            </ToggleButtonGroup>
            {isAdmin && board.courts.length < C.MAX_COURTS && (
              <IconButton onClick={() => { update((b) => C.addCourt(b)); setCi(board.courts.length); setSel(null); }}
                sx={{ border: (t) => `1px dashed ${alpha(t.palette.grey[500], 0.4)}`, borderRadius: 1.25 }}>
                <Iconify icon="mingcute:add-line" />
              </IconButton>
            )}
          </Stack>

          {/* pan-y: trình duyệt chỉ tự cuộn dọc, vuốt ngang để đổi sân. overscroll none: chặn
              Chrome Android hiểu vuốt ngang là "quay lại trang trước" (thoát khỏi web). */}
          <Box onTouchStart={onTouchStart} onTouchMove={onTouchMove} onTouchEnd={onTouchEnd} onTouchCancel={() => { touch.current = null; }}
            sx={{ touchAction: "pan-y", overscrollBehaviorX: "none" }}>
            <CourtCard court={board.courts[courtIdx]} ci={courtIdx} people={people} sel={sel} setSel={setSel} isAdmin={isAdmin} now={now}
              onSlot={onSlot} onAuto={onAuto} onClear={(c) => { update((b) => C.clearCourt(b, c)); setSel(null); }}
              onRemove={(c) => { update((b) => C.removeCourt(b, c)); setCi(Math.max(0, c - 1)); setSel(null); }}
              canRemove={board.courts.length > 1} />
            {board.courts.length > 1 && (
              <Stack direction="row" justifyContent="center" spacing={0.75} sx={{ mt: 1.25 }}>
                {board.courts.map((_, i) => (
                  <Box key={i} sx={{ width: i === courtIdx ? 16 : 6, height: 6, borderRadius: 3, transition: "all .2s",
                    bgcolor: i === courtIdx ? "primary.main" : (t) => alpha(t.palette.grey[500], 0.32) }} />
                ))}
              </Stack>
            )}
          </Box>

          <Box>
            <SectionLabel right={sel && isAdmin ? <Label color={sel.si < 2 ? "error" : "info"}>→ {board.courts[sel.ci]?.name} · {sel.si < 2 ? "Đỏ" : "Xanh"} {sel.si % 2 + 1}</Label> : null}>
              Đang chờ · {tray.length}
            </SectionLabel>
            {tray.length === 0 ? (
              <Card sx={{ p: 3, textAlign: "center" }}>
                <Typography variant="body2" color="text.secondary">
                  {present.size === 0 ? "Chưa ai có mặt — bấm \"Hôm nay ai tới\"." : "Ai có mặt cũng đang trên sân."}
                </Typography>
              </Card>
            ) : (
              <Box sx={{ display: "grid", gap: 1, gridTemplateColumns: { xs: "1fr", sm: "repeat(2,1fr)" } }}>
                {tray.map((p, i) => <WaitCard key={p.id} p={p} rank={i} now={now} disabled={!isAdmin} onClick={() => pick(p)} />)}
              </Box>
            )}
          </Box>

          <PresentDialog open={openPresent} onClose={() => setOpenPresent(false)} list={counts.pickup} present={present}
            isAdmin={isAdmin} onToggle={(id) => update((b) => C.togglePresent(b, id))} onAddGuest={onAddGuest} />
        </>
      )}

      <Snackbar open={!!toast} autoHideDuration={3200} onClose={() => setToast("")} message={toast}
        anchorOrigin={{ vertical: "bottom", horizontal: "center" }} sx={{ bottom: { xs: 90, sm: 24 } }} />
    </Stack>
  );
}
