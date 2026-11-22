// Xếp sân cho host (điện thoại thứ 3, mở web).
//   1. "Hôm nay ai tới": tick người có mặt (Dialog giống chọn người của Tiền cầu).
//   2. Các sân: chọn bằng thanh trên hoặc vuốt trái/phải. Mỗi sân 4 ô Đỏ 1-2 / Xanh 1-2.
//   3. Khay "Đang chờ": card từng người, xếp chờ lâu nhất trước (chưa đánh = chờ lâu nhất),
//      rồi ít trận hơn. Chạm card → vào ô đang chọn (hoặc ô trống đầu tiên).
//      Chạm người trên sân → về khay. "Tự xếp" lấy 4 người ưu tiên, chia cặp lệch Elo ít nhất.
//      Kéo-thả (giữ ~0.2s trên điện thoại): card → ô, ô → ô (đổi chỗ), ô → khay (gỡ ra).
// Bảng lưu ở backend theo ngày (rev chống ghi đè) → máy khác cùng thấy; sau này phone
// đọc bảng này để gửi cặp xuống band. Logic thuần ở lib/courts.js (có test).
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Alert, Avatar, Box, Button, Card, Checkbox, CircularProgress, Dialog, DialogActions,
  DialogContent, DialogTitle, IconButton, InputAdornment, List, ListItem, ListItemAvatar,
  ListItemText, Menu, MenuItem, Paper, Snackbar, Stack, TextField, ToggleButton, ToggleButtonGroup, Typography,
} from "@mui/material";
import {
  DndContext, DragOverlay, MouseSensor, TouchSensor, pointerWithin, rectIntersection,
  useDraggable, useDroppable, useSensor, useSensors,
} from "@dnd-kit/core";

// Ô đích = ô nằm DƯỚI NGÓN TAY (không phải ô chồng nhiều nhất với chip đang kéo — chip nhỏ,
// lệch trái so với ngón tay nên hay rơi nhầm sang cột Đỏ). Ngoài mọi ô thì mới xét chồng hình.
const collide = (args) => {
  const hits = pointerWithin(args);
  return hits.length ? hits : rectIntersection(args);
};
import { alpha } from "@mui/material/styles";
import { api, API_BASE, todayVN } from "../lib/api.js";
import * as C from "../lib/courts.js";
import { useAuth } from "../lib/auth.jsx";
import { LEVELS, levelOf } from "../lib/levels.js";
import RankFrame from "../components/rank/RankFrame.jsx";
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

// ---------- một ô trên sân (thả vào được; có người thì kéo đi được) ----------
function Slot({ ci, si, p, side, selected, onClick, disabled }) {
  const drop = useDroppable({ id: `d:${ci}:${si}`, data: { ci, si }, disabled });
  const drag = useDraggable({ id: `s:${ci}:${si}`, data: { pid: p?.id }, disabled: disabled || !p });
  const setRef = (el) => { drop.setNodeRef(el); drag.setNodeRef(el); };
  const dnd = p && !disabled ? { ...drag.attributes, ...drag.listeners } : {};
  return (
    <Box ref={setRef} component="button" type="button" onClick={onClick} disabled={disabled} {...dnd}
      sx={(t) => {
        const c = t.palette[side];
        const hot = drop.isOver || selected;
        return {
          display: "flex", alignItems: "center", gap: 1, width: 1, minHeight: 52, px: 1, py: 0.5, borderRadius: 1.25,
          font: "inherit", textAlign: "left", cursor: disabled ? "default" : "pointer", transition: "all .15s",
          touchAction: "manipulation", userSelect: "none", WebkitTouchCallout: "none",
          opacity: drag.isDragging ? 0.35 : 1,
          bgcolor: drop.isOver ? alpha(c.main, 0.24) : p ? alpha(c.main, 0.1) : selected ? alpha(c.main, 0.14) : t.palette.background.paper,
          border: `${hot ? 2 : 1}px ${p ? "solid" : "dashed"} ${hot ? c.main : alpha(p ? c.main : t.palette.grey[500], p ? 0.4 : 0.48)}`,
          color: "text.primary",
        };
      }}>
      {p ? (
        <>
          <RankFrame p={p} size={42} sx={{ my: -0.5 }} />
          <Box sx={{ minWidth: 0 }}>
            <Typography variant="subtitle2" noWrap sx={{ lineHeight: 1.3 }}>{p.short || p.name}</Typography>
            <Typography variant="caption" color="text.secondary" noWrap component="div">{p.played} trận · <Money sx={{ fontSize: 11, fontWeight: 500 }}>{Math.round(p.elo || 1000)}</Money></Typography>
          </Box>
        </>
      ) : (
        <Typography variant="caption" sx={{ color: selected ? `${side}.dark` : "text.disabled", fontWeight: 600, mx: "auto" }}>
          {selected ? "Chạm / thả người vào" : "Trống"}
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
  const slot = (si, color, row, col) => (
    <Box sx={{ gridRow: row, gridColumn: col, minWidth: 0, position: "relative", zIndex: 1 }}>
      <Slot ci={ci} si={si} p={ps[si]} side={color} disabled={!isAdmin}
        selected={isAdmin && sel && sel.ci === ci && sel.si === si}
        onClick={() => onSlot(ci, si)} />
    </Box>
  );
  return (
    <Card sx={{ p: 1.5 }}>
      {/* tên sân đã có trên thanh chọn sân — ở đây chỉ Đỏ | độ lệch Elo | Xanh */}
      <Box sx={{ display: "grid", gridTemplateColumns: "1fr auto 1fr", alignItems: "center", columnGap: 1, px: 0.5, mb: 0.75, minHeight: 30 }}>
        <Typography variant="overline" sx={{ color: "error.main", fontWeight: 800 }}>Đỏ</Typography>
        <Stack direction="row" alignItems="center" spacing={0.5}>
          {diff != null && <Label color={diff <= 30 ? "success" : diff <= 80 ? "info" : "warning"}>lệch {Math.round(diff)} Elo</Label>}
          {/* chỉ xoá được sân TRỐNG — tránh một chạm mất cả 4 người đang đánh */}
          {isAdmin && canRemove && !ps.some(Boolean) && (
            <IconButton size="small" onClick={() => onRemove(ci)} sx={{ color: "text.disabled" }} aria-label={`Xoá ${court.name}`}><Iconify icon="solar:trash-bin-trash-bold" width={18} /></IconButton>
          )}
        </Stack>
        <Typography variant="overline" sx={{ color: "info.main", fontWeight: 800, textAlign: "right" }}>Xanh</Typography>
      </Box>
      {/* mặt sân: viền nét đứt, lưới (dọc, giữa) và vạch giữa (ngang) — chỉ gợi ý kiểu vạch sân */}
      <Box sx={(t) => ({
        position: "relative", display: "grid", gridTemplateColumns: "1fr 1fr", gridTemplateRows: "auto auto",
        columnGap: 3, rowGap: 1.5, p: 1, borderRadius: 1.5,
        border: `1.5px dashed ${alpha(t.palette.grey[500], 0.36)}`, bgcolor: alpha(t.palette.primary.main, 0.03),
        "&::before": { content: '""', position: "absolute", top: 6, bottom: 6, left: "50%", borderLeft: `2px dashed ${alpha(t.palette.primary.main, 0.36)}` },
        "&::after": { content: '""', position: "absolute", left: 6, right: 6, top: "50%", borderTop: `1px dashed ${alpha(t.palette.grey[500], 0.32)}` },
      })}>
        {slot(0, "error", 1, 1)}{slot(1, "error", 2, 1)}
        {slot(2, "info", 1, 2)}{slot(3, "info", 2, 2)}
        <Box sx={(t) => ({ position: "absolute", left: "50%", top: "50%", transform: "translate(-50%,-50%)", zIndex: 2,
          px: 0.75, py: 0.1, borderRadius: 1, bgcolor: "background.paper", border: `1px solid ${alpha(t.palette.grey[500], 0.24)}`,
          typography: "caption", fontWeight: 700, color: "text.disabled" })}>vs</Box>
      </Box>
      {isAdmin && (
        <Stack direction="row" spacing={1} sx={{ mt: 1.5 }}>
          <Button fullWidth size="small" variant="contained" onClick={() => onAuto(ci)} disabled={full} startIcon={<Iconify icon="solar:shuffle-bold" width={18} />}>Tự xếp</Button>
          <Button fullWidth size="small" variant="outlined" color="inherit" onClick={() => onClear(ci)} disabled={!ps.some(Boolean)} startIcon={<Iconify icon="solar:check-circle-bold" width={18} />}>Xong trận</Button>
        </Stack>
      )}
    </Card>
  );
}

// ---------- card người chờ (gọn, 2 cột trên điện thoại) ----------
function WaitCard({ p, rank, onClick, disabled, now }) {
  const first = rank < 4;
  const drag = useDraggable({ id: `p:${p.id}`, data: { pid: p.id }, disabled });
  return (
    <Card ref={drag.setNodeRef} component="button" type="button" onClick={onClick} disabled={disabled}
      {...(disabled ? {} : { ...drag.attributes, ...drag.listeners })}
      sx={(t) => ({
        position: "relative", p: 0.75, pr: first ? 3 : 0.75, display: "flex", alignItems: "center", gap: 0.75, width: 1, minWidth: 0,
        font: "inherit", textAlign: "left", cursor: disabled ? "default" : "grab", boxShadow: "none", borderRadius: 1.25,
        touchAction: "manipulation", userSelect: "none", WebkitTouchCallout: "none", opacity: drag.isDragging ? 0.35 : 1,
        border: `1px solid ${first ? alpha(t.palette.primary.main, 0.4) : alpha(t.palette.grey[500], 0.2)}`,
        bgcolor: first ? alpha(t.palette.primary.main, 0.04) : "background.paper",
        "&:hover": disabled ? undefined : { borderColor: "primary.main" },
      })}>
      <RankFrame p={p} size={44} sx={{ my: -0.5, ml: -0.25 }} />
      <Box sx={{ minWidth: 0, flexGrow: 1 }}>
        <Typography variant="subtitle2" noWrap sx={{ fontSize: 13, lineHeight: 1.35 }}>
          {p.name}{p.guest && " *"}
        </Typography>
        <Typography variant="caption" color="text.secondary" component="div" noWrap sx={{ fontSize: 11 }}>
          {p.played}tr · {C.waitLabel(p, now)} · <Money sx={{ fontSize: 11, fontWeight: 500 }}>{Math.round(p.elo || 1000)}</Money>
        </Typography>
      </Box>
      {first && <Money sx={{ position: "absolute", top: 4, right: 6, fontSize: 11, color: "primary.main" }}>#{rank + 1}</Money>}
    </Card>
  );
}

// ---------- khay: thả người từ sân về đây để gỡ ----------
function TrayZone({ children, sx }) {
  const drop = useDroppable({ id: "tray" });
  return (
    <Box ref={drop.setNodeRef} sx={[(t) => ({ borderRadius: 2, transition: "all .15s", outline: drop.isOver ? `2px dashed ${t.palette.primary.main}` : "none", outlineOffset: 2 }), ...(Array.isArray(sx) ? sx : [sx])]}>
      {children}
    </Box>
  );
}

// ---------- chip đi theo ngón tay khi kéo ----------
function DragChip({ p }) {
  if (!p) return null;
  return (
    <Stack direction="row" alignItems="center" spacing={1} sx={(t) => ({ px: 1, py: 0.75, pr: 1.5, borderRadius: 5, width: "max-content",
      bgcolor: "background.paper", boxShadow: t.customShadows?.z16 || 8, border: `1px solid ${t.palette.primary.main}` })}>
      <RankFrame p={p} size={40} sx={{ my: -0.5 }} />
      <Typography variant="subtitle2">{p.short || p.name}</Typography>
    </Stack>
  );
}

// ---------- dialog "hôm nay ai tới" ----------
function PresentDialog({ open, onClose, list, present, onToggle, isAdmin, onAddGuest, onLevel }) {
  const [q, setQ] = useState("");
  const [lvMenu, setLvMenu] = useState(null); // {el, p}
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
                    secondary={`${p.played} trận hôm nay · ${Math.round(p.elo || 1000)}`} secondaryTypographyProps={{ noWrap: true }} />
                  {(isAdmin || p.level) && (
                    <Label role={isAdmin ? "button" : undefined} color={p.level ? "primary" : "default"} variant={p.level ? "soft" : "outlined"}
                      onClick={isAdmin ? (e) => setLvMenu({ el: e.currentTarget, p }) : undefined}
                      sx={{ flexShrink: 0, cursor: isAdmin ? "pointer" : "default", border: p.level ? undefined : "1px dashed", font: "inherit", fontSize: 11 }}>
                      {levelOf(p.level)?.label || "Trình?"}
                    </Label>
                  )}
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
          Thành viên thêm ở Tiền cầu. Khách có dấu * trên band. Trình độ = Elo khởi điểm
          (Newbie 800 → Giỏi 1200); 10 trận đầu Elo thay đổi nhanh hơn.
        </Typography>
        <Menu anchorEl={lvMenu?.el} open={!!lvMenu} onClose={() => setLvMenu(null)}>
          {LEVELS.map((l) => (
            <MenuItem key={l.key} selected={lvMenu?.p.level === l.key} onClick={() => { onLevel(lvMenu.p, l.key); setLvMenu(null); }}>
              <ListItemText primary={l.label} secondary={`bắt đầu ${l.elo}`} />
            </MenuItem>
          ))}
          <MenuItem onClick={() => { onLevel(lvMenu.p, ""); setLvMenu(null); }}><ListItemText primary="Chưa đặt" secondary="như Trung bình (1000)" /></MenuItem>
        </Menu>
      </DialogContent>
      <DialogActions><Button variant="contained" onClick={onClose}>Xong</Button></DialogActions>
    </Dialog>
  );
}

export default function Pickup() {
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
  const onLevel = async (p, level) => {
    try {
      await api.setLevel(auth.passRef.current, p.id, level);
      await loadCounts(st.current.day);
      setToast(`${p.name}: ${levelOf(level)?.label || "chưa đặt trình"} — Elo đã tính lại`);
    } catch (e) { setToast(String(e.message || e)); }
  };
  const onAddGuest = async (name) => {
    try {
      const g = await api.addGuest(auth.passRef.current, name);
      await loadCounts(day);
      update((b) => (b.present.includes(g.id) ? b : { ...b, present: [...b.present, g.id] }));
      setToast(`Đã thêm khách ${g.name} — trên band là ${g.short}`);
    } catch (e) { setToast(String(e.message || e)); }
  };

  // kéo-thả. Điện thoại: giữ 0.2s mới kéo (chạm nhanh vẫn là chạm, vuốt vẫn là vuốt/cuộn).
  const sensors = useSensors(
    useSensor(MouseSensor, { activationConstraint: { distance: 6 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 150, tolerance: 8 } }),
  );
  const [dragPid, setDragPid] = useState(null);
  const dragged = useRef(false); // có kéo trong lần chạm này -> đừng hiểu là vuốt đổi sân
  const onDragStart = ({ active }) => {
    dragged.current = true;
    setDragPid(active.data.current?.pid || null);
    try { navigator.vibrate?.(12); } catch { /* */ }
  };
  const onDragEnd = ({ active, over }) => {
    setDragPid(null);
    const pid = active.data.current?.pid;
    if (!pid || !over || !isAdmin) return;
    if (over.id === "tray") {
      if (String(active.id).startsWith("s:")) update((b) => C.removeEverywhere(b, pid));
    } else if (over.data.current && over.data.current.si != null) {
      const { ci: c, si } = over.data.current;
      update((b) => C.moveTo(b, c, si, pid));
    }
    setSel(null);
  };

  // vuốt trái/phải giữa các sân
  const touch = useRef(null);
  const onTouchStart = (e) => { const t = e.touches[0]; dragged.current = false; touch.current = { x: t.clientX, y: t.clientY, lx: t.clientX, ly: t.clientY }; };
  const onTouchMove = (e) => { const s = touch.current, t = e.touches[0]; if (s && t) { s.lx = t.clientX; s.ly = t.clientY; } };
  const onTouchEnd = () => {
    const s = touch.current; touch.current = null;
    if (!s || !board || dragged.current) return;
    const dx = s.lx - s.x, dy = s.ly - s.y;
    if (Math.abs(dx) < 60 || Math.abs(dx) < Math.abs(dy) * 1.5) return;
    setCi((i) => Math.max(0, Math.min(board.courts.length - 1, i + (dx < 0 ? 1 : -1))));
    setSel(null);
  };

  const isToday = day === todayVN();
  const ready = board && counts;

  // Điện thoại: cả màn vừa khít 1 màn hình (trừ thanh trên 60 + thanh dưới 64 + lề),
  // KHÔNG cuộn trang -> kéo thả không bị lẫn với cuộn. Chỉ khay người chờ tự cuộn bên trong.
  // Máy tính: chảy bình thường.
  const FIT = { xs: "calc(100dvh - 166px - env(safe-area-inset-bottom))", sm: "auto" };

  return (
    <Stack spacing={1.25} sx={{ height: FIT, minHeight: { xs: 480, sm: 0 }, overflow: { xs: "hidden", sm: "visible" } }}>
      {/* thanh trên: ngày + ai tới + trạng thái, 1 dòng */}
      <Card sx={{ px: 0.5, py: 0.5, flexShrink: 0 }}>
        <Stack direction="row" alignItems="center" spacing={0.25}>
          <IconButton size="small" onClick={() => setDay((d) => C.shiftDay(d, -1))}><Iconify icon="solar:alt-arrow-left-bold" /></IconButton>
          <Box sx={{ textAlign: "center", minWidth: 0 }} onClick={() => !isToday && setDay(todayVN())}>
            <Typography variant="subtitle2" noWrap sx={{ lineHeight: 1.2 }}>{C.dayLabel(day)}</Typography>
            <Typography variant="caption" noWrap sx={{ color: isToday ? "success.main" : "primary.main", fontWeight: 600, lineHeight: 1.2, display: "block", cursor: isToday ? "default" : "pointer" }}>
              {isToday ? "Hôm nay" : "Về hôm nay"}
            </Typography>
          </Box>
          <IconButton size="small" onClick={() => setDay((d) => C.shiftDay(d, 1))}><Iconify icon="solar:alt-arrow-right-bold" /></IconButton>
          <Box sx={{ flexGrow: 1 }} />
          {ready && (
            <Button size="small" variant={present.size ? "outlined" : "contained"} color={present.size ? "inherit" : "primary"}
              onClick={() => setOpenPresent(true)} startIcon={<Iconify icon="solar:user-plus-bold" width={16} />} sx={{ whiteSpace: "nowrap", px: 1 }}>
              Ai tới · {present.size}
            </Button>
          )}
          <IconButton size="small" onClick={() => { setNow(Date.now()); loadAll(day); }} sx={{ color: saving ? "info.main" : "text.secondary" }}>
            <Iconify icon={saving ? "solar:cloud-upload-bold" : "solar:refresh-bold"} />
          </IconButton>
        </Stack>
      </Card>

      {err && (
        <Alert severity="warning">
          Không tải được: {err}
          {!API_BASE && <><br />Chưa cấu hình <code>VITE_API_BASE</code> — màn này cần backend.</>}
        </Alert>
      )}
      {!err && !ready && <Box sx={{ display: "grid", placeItems: "center", py: 6 }}><CircularProgress /></Box>}

      {ready && (
        <DndContext sensors={sensors} collisionDetection={collide} onDragStart={onDragStart} onDragEnd={onDragEnd} onDragCancel={() => setDragPid(null)}
          autoScroll={false}>
          {!isAdmin && <Alert severity="info" sx={{ py: 0, flexShrink: 0 }}>Đang xem. Mở khoá <b>Quản trị</b> để xếp sân.</Alert>}

          <Stack direction="row" spacing={1} alignItems="center" sx={{ flexShrink: 0 }}>
            <ToggleButtonGroup size="small" exclusive value={courtIdx} onChange={(_, v) => { if (v != null) { setCi(v); setSel(null); } }}
              sx={{ flexGrow: 1, overflowX: "auto", flexWrap: "nowrap" }}>
              {board.courts.map((c, i) => {
                const n = c.slots.filter(Boolean).length;
                return (
                  <ToggleButton key={i} value={i} sx={{ py: 0.4, px: 1.25, whiteSpace: "nowrap", flexShrink: 0 }}>
                    {c.name}<Box component="span" sx={{ ml: 0.75, fontSize: 11, opacity: 0.7 }}>{n}/4</Box>
                  </ToggleButton>
                );
              })}
            </ToggleButtonGroup>
            {isAdmin && board.courts.length < C.MAX_COURTS && (
              <IconButton size="small" onClick={() => { update((b) => C.addCourt(b)); setCi(board.courts.length); setSel(null); }}
                sx={{ border: (t) => `1px dashed ${alpha(t.palette.grey[500], 0.4)}`, borderRadius: 1.25 }} aria-label="Thêm sân">
                <Iconify icon="mingcute:add-line" />
              </IconButton>
            )}
          </Stack>

          {/* pan-y: trình duyệt chỉ tự cuộn dọc, vuốt ngang để đổi sân. overscroll none: chặn
              Chrome Android hiểu vuốt ngang là "quay lại trang trước" (thoát khỏi web). */}
          <Box onTouchStart={onTouchStart} onTouchMove={onTouchMove} onTouchEnd={onTouchEnd} onTouchCancel={() => { touch.current = null; }}
            sx={{ touchAction: "pan-y", overscrollBehaviorX: "none", flexShrink: 0, position: "relative" }}>
            <CourtCard court={board.courts[courtIdx]} ci={courtIdx} people={people} sel={sel} setSel={setSel} isAdmin={isAdmin} now={now}
              onSlot={onSlot} onAuto={onAuto} onClear={(c) => { update((b) => C.clearCourt(b, c)); setSel(null); }}
              onRemove={(c) => { update((b) => C.removeCourt(b, c)); setCi(Math.max(0, c - 1)); setSel(null); }}
              canRemove={board.courts.length > 1} />
            {board.courts.length > 1 && (
              <Stack direction="row" justifyContent="center" spacing={0.75} sx={{ position: "absolute", left: 0, right: 0, bottom: -9 }}>
                {board.courts.map((_, i) => (
                  <Box key={i} sx={{ width: i === courtIdx ? 14 : 5, height: 5, borderRadius: 3, transition: "all .2s",
                    bgcolor: i === courtIdx ? "primary.main" : (t) => alpha(t.palette.grey[500], 0.32) }} />
                ))}
              </Stack>
            )}
          </Box>

          {/* khay: chiếm phần còn lại, tự cuộn bên trong; thả người từ sân vào đây để gỡ */}
          <TrayZone sx={{ flex: { xs: "1 1 0", sm: "0 0 auto" }, minHeight: 0, display: "flex", flexDirection: "column" }}>
            <Stack direction="row" alignItems="center" sx={{ px: 0.5, mb: 0.5, flexShrink: 0 }}>
              <Box sx={{ typography: "overline", color: "text.secondary", flexGrow: 1 }}>
                Đang chờ · {tray.length}
                <Box component="span" sx={{ textTransform: "none", fontWeight: 500, ml: 0.75 }}>· {busy.size} trên sân · {counts.matches} trận hôm nay</Box>
              </Box>
              {sel && isAdmin && <Label color={sel.si < 2 ? "error" : "info"}>→ {sel.si < 2 ? "Đỏ" : "Xanh"} {sel.si % 2 + 1}</Label>}
            </Stack>
            <Box sx={{ flex: 1, minHeight: 0, overflowY: { xs: "auto", sm: "visible" }, overscrollBehavior: "contain", pb: 0.5 }}>
              {tray.length === 0 ? (
                <Card sx={{ p: 2.5, textAlign: "center" }}>
                  <Typography variant="body2" color="text.secondary">
                    {present.size === 0 ? "Chưa ai có mặt — bấm \"Ai tới\"." : "Ai có mặt cũng đang trên sân."}
                  </Typography>
                </Card>
              ) : (
                <Box sx={{ display: "grid", gap: 0.75, gridTemplateColumns: { xs: "repeat(2, minmax(0,1fr))", sm: "repeat(3, minmax(0,1fr))" } }}>
                  {tray.map((p, i) => <WaitCard key={p.id} p={p} rank={i} now={now} disabled={!isAdmin} onClick={() => pick(p)} />)}
                </Box>
              )}
            </Box>
          </TrayZone>

          <DragOverlay dropAnimation={null}>{dragPid ? <DragChip p={people.get(dragPid)} /> : null}</DragOverlay>

          <PresentDialog open={openPresent} onClose={() => setOpenPresent(false)} list={counts.pickup} present={present}
            isAdmin={isAdmin} onToggle={(id) => update((b) => C.togglePresent(b, id))} onAddGuest={onAddGuest} onLevel={onLevel} />
        </DndContext>
      )}

      <Snackbar open={!!toast} autoHideDuration={3200} onClose={() => setToast("")} message={toast}
        anchorOrigin={{ vertical: "bottom", horizontal: "center" }} sx={{ bottom: { xs: 90, sm: 24 } }} />
    </Stack>
  );
}
