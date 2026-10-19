import { useMemo, useRef, useState } from "react";
import {
  Alert, AppBar, Avatar, Box, Button, Checkbox, Chip, CircularProgress, Dialog, DialogActions,
  DialogContent, DialogTitle, Divider, Fab, IconButton, InputAdornment, LinearProgress, List,
  ListItem, ListItemAvatar, ListItemButton, ListItemText, Paper, Snackbar, Stack, Tab, Tabs,
  TextField, ToggleButton, ToggleButtonGroup, Typography,
} from "@mui/material";
import SearchIcon from "@mui/icons-material/Search";
import AddIcon from "@mui/icons-material/Add";
import DeleteOutlineIcon from "@mui/icons-material/DeleteOutline";
import LockOpenIcon from "@mui/icons-material/LockOpen";
import * as M from "../lib/model.js";
import { useBook } from "../lib/useBook.js";

const money = (x) => M.fmt(x);
const ME_KEY = "bmw_me";

export default function BillBook() {
  const B = useBook();
  const { book } = B;
  const [isAdmin, setAdmin] = useState(B.isAdmin);
  const [sub, setSub] = useState("all");
  const [toast, setToast] = useState("");

  // đồng bộ trạng thái admin từ hook (sau login)
  if (B.isAdmin && !isAdmin) { setAdmin(true); setSub("sessions"); }

  if (B.loadErr && !book) return <Alert severity="error">Không tải được sổ: {B.loadErr}</Alert>;
  if (!book) return <Box sx={{ display: "grid", placeItems: "center", py: 8 }}><CircularProgress /></Box>;

  const viewerTabs = [["me", "Của tôi"], ["all", "Cả nhóm"], ["sessions", "Các buổi"]];
  const adminTabs = [["sessions", "Buổi chơi"], ["members", "Thành viên"], ["collect", "Thu tiền"]];
  const tabs = isAdmin ? adminTabs : viewerTabs;
  if (!tabs.some(([k]) => k === sub)) setSub(tabs[0][0]);

  const ctx = { B, book, setToast, isAdmin };

  return (
    <Box sx={{ pb: 10 }}>
      <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 1 }}>
        <Typography variant="h5" sx={{ flexGrow: 1 }}>Tiền cầu</Typography>
        {isAdmin
          ? <Button size="small" onClick={() => { B.logout(); setAdmin(false); setSub("all"); }}>Thoát quản trị</Button>
          : <LoginButton B={B} />}
      </Stack>

      {B.loadErr && !B.online && (
        <Alert severity="warning" sx={{ mb: 2 }}>Mất kết nối máy chủ — đang xem số đã lưu trong máy.</Alert>
      )}

      <Tabs value={sub} onChange={(_, v) => setSub(v)} variant="scrollable" allowScrollButtonsMobile sx={{ mb: 2 }}>
        {tabs.map(([k, label]) => <Tab key={k} value={k} label={label} />)}
      </Tabs>

      {!isAdmin && sub === "me" && <ViewMe {...ctx} />}
      {!isAdmin && sub === "all" && <ViewAll {...ctx} />}
      {(sub === "sessions") && (isAdmin ? <AdminSessions {...ctx} /> : <ViewSessions {...ctx} />)}
      {isAdmin && sub === "members" && <AdminMembers {...ctx} />}
      {isAdmin && sub === "collect" && <AdminCollect {...ctx} />}

      <SaveBar B={B} />
      <ConflictDialog B={B} />
      <Snackbar open={!!toast} autoHideDuration={2600} onClose={() => setToast("")}
        message={toast} anchorOrigin={{ vertical: "bottom", horizontal: "center" }} />
    </Box>
  );
}

function MemAvatar({ book, m, size = 40 }) {
  return <Avatar src={m.av || undefined} sx={{ width: size, height: size, bgcolor: M.hue(m.id), fontSize: size * 0.4 }}>
    {M.initials(m.name)}
  </Avatar>;
}

// ---------- Viewer ----------
function ViewAll({ book, setToast }) {
  const [q, setQ] = useState("");
  const [filter, setFilter] = useState("due");
  const due = M.totalDue(book), got = M.totalCollected(book), all = due + got;
  let rows = book.members
    .map((m) => ({ m, due: M.memberDue(book, m.id), n: M.memberDueSessions(book, m.id).length, tot: M.memberSessions(book, m.id).length }))
    .filter((r) => r.tot > 0);
  const nDue = rows.filter((r) => r.due > M.EPS).length;
  rows = rows.filter((r) => filter === "all" || (filter === "due" ? r.due > M.EPS : r.due <= M.EPS))
    .filter((r) => !q || M.norm(r.m.name).includes(M.norm(q)))
    .sort((a, b) => b.due - a.due || a.m.name.localeCompare(b.m.name, "vi"));
  const pct = all > M.EPS ? Math.round((got / all) * 100) : 0;
  return (
    <Stack spacing={2}>
      <StatCard due={due} got={got} all={all} pct={pct} sub={`${nDue} người còn nợ · ${book.sessions.length} buổi đã chơi`} />
      <TextField size="small" placeholder="Tìm tên…" value={q} onChange={(e) => setQ(e.target.value)}
        InputProps={{ startAdornment: <InputAdornment position="start"><SearchIcon /></InputAdornment> }} />
      <ToggleButtonGroup size="small" exclusive value={filter} onChange={(_, v) => v && setFilter(v)}>
        <ToggleButton value="due">Còn nợ · {nDue}</ToggleButton>
        <ToggleButton value="ok">Đã xong</ToggleButton>
        <ToggleButton value="all">Tất cả</ToggleButton>
      </ToggleButtonGroup>
      <Paper>
        <List disablePadding>
          {rows.map((r, i) => (
            <ListItem key={r.m.id} divider={i < rows.length - 1}
              secondaryAction={<Typography fontWeight={700} color={r.due > M.EPS ? "error" : "success.main"}>{r.due > M.EPS ? money(r.due) : "✓"}</Typography>}>
              <ListItemAvatar><MemAvatar book={book} m={r.m} size={34} /></ListItemAvatar>
              <ListItemText primary={M.fullName(book, r.m)}
                secondary={r.due > M.EPS ? `${r.n} buổi chưa trả` : `${r.tot} buổi · đã trả đủ`} />
            </ListItem>
          ))}
          {rows.length === 0 && <ListItem><ListItemText secondary="Không có ai trong mục này." /></ListItem>}
        </List>
      </Paper>
    </Stack>
  );
}

function ViewMe({ book }) {
  const [meId, setMeId] = useState(() => { try { return localStorage.getItem(ME_KEY); } catch { return null; } });
  const [q, setQ] = useState("");
  const m = meId ? M.memById(book, meId) : null;
  const pick = (id) => { setMeId(id); try { localStorage.setItem(ME_KEY, id); } catch { /* */ } };
  if (!m) {
    const rows = book.members.map((x) => ({ m: x, due: M.memberDue(book, x.id) }))
      .filter((r) => !q || M.norm(r.m.name).includes(M.norm(q)))
      .sort((a, b) => b.due - a.due || a.m.name.localeCompare(b.m.name, "vi"));
    return (
      <Stack spacing={2}>
        <Alert severity="info">Bấm vào tên bạn để xem mình nợ bao nhiêu, gồm những buổi nào.</Alert>
        <TextField size="small" placeholder="Gõ tên để tìm…" value={q} onChange={(e) => setQ(e.target.value)} />
        <Paper><List disablePadding>
          {rows.map((r, i) => (
            <ListItemButton key={r.m.id} divider={i < rows.length - 1} onClick={() => pick(r.m.id)}>
              <ListItemAvatar><MemAvatar book={book} m={r.m} size={34} /></ListItemAvatar>
              <ListItemText primary={M.fullName(book, r.m)} />
              <Typography fontWeight={700} color={r.due > M.EPS ? "error" : "success.main"}>{r.due > M.EPS ? money(r.due) : "✓"}</Typography>
            </ListItemButton>
          ))}
          {rows.length === 0 && <ListItem><ListItemText secondary="Không tìm thấy ai." /></ListItem>}
        </List></Paper>
      </Stack>
    );
  }
  const due = M.memberDue(book, m.id), paidSum = M.memberPaidSum(book, m.id);
  const dueSes = M.memberDueSessions(book, m.id);
  return (
    <Stack spacing={2}>
      <Paper sx={{ p: 3, textAlign: "center" }}>
        <MemAvatar book={book} m={m} size={72} />
        <Typography variant="h6" sx={{ mt: 1 }}>{M.fullName(book, m)}</Typography>
        {due > M.EPS ? (
          <>
            <Typography variant="overline" color="text.secondary">Cần chuyển</Typography>
            <Typography variant="h3" color="error" fontWeight={800}>{money(due)}</Typography>
            <Typography variant="body2" color="text.secondary">{M.vnd(due)} · {dueSes.length} buổi</Typography>
            <Paper variant="outlined" sx={{ mt: 2, p: 1.5, display: "inline-block" }}>
              <Typography variant="caption" color="text.secondary">Nội dung chuyển khoản</Typography>
              <Typography fontFamily="monospace" fontWeight={700}>{M.payRef(m)}</Typography>
            </Paper>
            {book.note && <Typography fontWeight={700} sx={{ mt: 1 }}>{book.note}</Typography>}
            {book.qr && <Box sx={{ mt: 1 }}><img src={book.qr} alt="QR" style={{ maxWidth: 210, borderRadius: 12 }} /></Box>}
          </>
        ) : (
          <Typography variant="h4" color="success.main" sx={{ mt: 1 }}>Không nợ gì 🎉</Typography>
        )}
      </Paper>
      {dueSes.length > 0 && (
        <Paper><List disablePadding>
          {dueSes.map((s, i) => (
            <ListItem key={s.id} divider={i < dueSes.length - 1}
              secondaryAction={<Typography fontWeight={700} color="error">{money(M.shareIn(s, m.id))}</Typography>}>
              <ListItemText primary={s.date || "—"}
                secondary={`(${s.court} + ${s.shuttles}×${s.price || M.DEFAULT_PRICE}) / ${M.wStr(M.sWeight(s))} suất`} />
            </ListItem>
          ))}
        </List></Paper>
      )}
      <Button size="small" onClick={() => { setMeId(null); try { localStorage.removeItem(ME_KEY); } catch { /* */ } }}>
        Tôi không phải {m.name}
      </Button>
    </Stack>
  );
}

function ViewSessions({ book }) {
  const list = M.orderedSessions(book);
  return (
    <Stack spacing={1.5}>
      {list.map((s) => <SessionCard key={s.id} book={book} s={s} />)}
      {list.length === 0 && <Alert severity="info">Chưa có buổi nào.</Alert>}
    </Stack>
  );
}

function SessionCard({ book, s }) {
  const settled = M.sSettled(s), got = M.sCollected(s), tot = M.sTotal(s);
  return (
    <Paper sx={{ p: 2 }}>
      <Stack direction="row" justifyContent="space-between">
        <Typography fontWeight={700}>{s.date || "—"} <Typography component="span" variant="body2" color="text.secondary">· {s.parts.length} người</Typography></Typography>
        <Typography fontWeight={700}>{money(tot)}</Typography>
      </Stack>
      <Typography variant="caption" color="text.secondary">
        ({s.court} + {s.shuttles}×{s.price || M.DEFAULT_PRICE}) / {M.wStr(M.sWeight(s))} suất = {money(M.sPerUnit(s))}/suất
      </Typography>
      <LinearProgress variant="determinate" value={tot > M.EPS ? Math.round((got / tot) * 100) : 0} sx={{ my: 1, height: 6, borderRadius: 3 }} />
      <Typography variant="body2">{settled ? <b style={{ color: "#34d399" }}>✓ Đã thu đủ</b> : `Đã thu ${money(got)} / ${money(tot)} · còn ${M.sUnpaid(s).length} người`}</Typography>
      <Box sx={{ display: "flex", flexWrap: "wrap", gap: 0.5, mt: 1 }}>
        {s.parts.map((p) => {
          const m = M.memById(book, p.mid); if (!m) return null;
          const on = M.isPaid(s, p.mid);
          return <Chip key={p.mid} size="small" avatar={<MemAvatar book={book} m={m} size={18} />}
            label={M.fullName(book, m) + (p.weight !== 1 ? ` ×${M.wStr(p.weight)}` : "")}
            color={on ? "success" : "default"} variant={on ? "filled" : "outlined"}
            sx={on ? { textDecoration: "line-through", opacity: 0.8 } : undefined} />;
        })}
      </Box>
    </Paper>
  );
}

function StatCard({ due, got, all, pct, sub }) {
  return (
    <Paper sx={{ p: 2 }}>
      <Stack direction="row" justifyContent="space-between" alignItems="flex-start">
        <Box>
          <Typography variant="caption" color="text.secondary" fontWeight={700}>CÒN THIẾU</Typography>
          <Typography variant="h4" color={due > M.EPS ? "error" : "success.main"} fontWeight={700}>{due > M.EPS ? money(due) : "Xong hết 🎉"}</Typography>
        </Box>
        <Box textAlign="right">
          <Typography variant="caption" color="text.secondary" fontWeight={700}>ĐÃ THU</Typography>
          <Typography variant="h6" color="success.main" fontWeight={700}>{money(got)}</Typography>
          <Typography variant="caption" color="text.secondary">/ {money(all)}</Typography>
        </Box>
      </Stack>
      <LinearProgress variant="determinate" value={pct} sx={{ my: 1.5, height: 6, borderRadius: 3 }} />
      <Typography variant="caption" color="text.secondary">{sub}</Typography>
    </Paper>
  );
}

// ---------- Admin ----------
function LoginButton({ B }) {
  const [open, setOpen] = useState(false);
  const [pw, setPw] = useState("");
  const [err, setErr] = useState("");
  const go = async () => { try { await B.login(pw); setOpen(false); setPw(""); setErr(""); } catch (e) { setErr(String(e.message || e)); } };
  return (
    <>
      <Button size="small" startIcon={<LockOpenIcon />} onClick={() => setOpen(true)}>Quản trị</Button>
      <Dialog open={open} onClose={() => setOpen(false)} fullWidth maxWidth="xs">
        <DialogTitle>Đăng nhập quản trị</DialogTitle>
        <DialogContent>
          <TextField autoFocus type="password" fullWidth label="Mật khẩu" value={pw}
            onChange={(e) => setPw(e.target.value)} onKeyDown={(e) => e.key === "Enter" && go()} sx={{ mt: 1 }} />
          {err && <Typography color="error" variant="body2" sx={{ mt: 1 }}>{err}</Typography>}
        </DialogContent>
        <DialogActions><Button onClick={() => setOpen(false)}>Đóng</Button><Button variant="contained" onClick={go}>Mở khóa</Button></DialogActions>
      </Dialog>
    </>
  );
}

function AdminSessions({ B, book, setToast }) {
  const [filter, setFilter] = useState("open");
  const [edit, setEdit] = useState(null); // session draft or null
  const due = M.totalDue(book), got = M.totalCollected(book), all = due + got;
  const openN = book.sessions.filter((s) => !M.sSettled(s)).length;
  const list = M.orderedSessions(book).filter((s) => filter === "all" || (filter === "open" ? !M.sSettled(s) : M.sSettled(s)));

  const togglePaid = (s, mid) => {
    const on = M.isPaid(s, mid);
    B.mutate((d) => { const ss = d.sessions.find((x) => x.id === s.id); M.setPaid(ss, mid, !on); },
      `${on ? "Bỏ dấu đã trả" : "Đánh dấu đã trả"}: ${M.memById(book, mid)?.name || "?"} · buổi ${s.date || "?"}`);
    if (!on) setToast(`${M.memById(book, mid)?.name} đã trả · buổi ${s.date || "?"}`);
  };
  const payAll = (s) => {
    const mids = M.sUnpaid(s); if (!mids.length) return;
    B.mutate((d) => { const ss = d.sessions.find((x) => x.id === s.id); mids.forEach((mid) => M.setPaid(ss, mid, true)); }, `Thu hết buổi ${s.date || "?"}`);
    setToast(`Đã thu ${mids.length} người · buổi ${s.date || "?"}`);
  };
  const del = (s) => { if (!confirm(`Xóa buổi ${s.date || "?"}?`)) return; B.mutate((d) => { d.sessions = d.sessions.filter((x) => x.id !== s.id); }, `Xóa buổi ${s.date || "?"}`); };

  return (
    <Stack spacing={2}>
      <StatCard due={due} got={got} all={all} pct={all > M.EPS ? Math.round(got / all * 100) : 0}
        sub={`${M.debtors(book).length} người còn nợ · ${openN}/${book.sessions.length} buổi chưa thu xong`} />
      <Button variant="contained" startIcon={<AddIcon />} onClick={() => setEdit(newSession())}>Thêm buổi chơi</Button>
      <ToggleButtonGroup size="small" exclusive value={filter} onChange={(_, v) => v && setFilter(v)}>
        <ToggleButton value="open">Chưa xong · {openN}</ToggleButton>
        <ToggleButton value="done">Đã xong · {book.sessions.length - openN}</ToggleButton>
        <ToggleButton value="all">Tất cả · {book.sessions.length}</ToggleButton>
      </ToggleButtonGroup>
      {list.map((s) => (
        <Paper key={s.id} sx={{ p: 2 }}>
          <Stack direction="row" justifyContent="space-between">
            <Typography fontWeight={700}>{s.date || "(chưa đặt ngày)"} <Typography component="span" variant="body2" color="text.secondary">· {s.parts.length} người</Typography></Typography>
            <Typography fontWeight={700}>{money(M.sTotal(s))}</Typography>
          </Stack>
          <Typography variant="caption" color="text.secondary">({s.court} + {s.shuttles}×{s.price || M.DEFAULT_PRICE}) / {M.wStr(M.sWeight(s))} suất = {money(M.sPerUnit(s))}/suất</Typography>
          <Box sx={{ display: "flex", flexWrap: "wrap", gap: 0.5, my: 1 }}>
            {s.parts.map((p) => {
              const m = M.memById(book, p.mid); if (!m) return null;
              const on = M.isPaid(s, p.mid);
              return <Chip key={p.mid} size="small" clickable onClick={() => togglePaid(s, p.mid)}
                avatar={<MemAvatar book={book} m={m} size={18} />}
                label={(on ? "✓ " : "") + M.fullName(book, m) + (p.weight !== 1 ? ` ×${M.wStr(p.weight)}` : "")}
                color={on ? "success" : "default"} variant={on ? "filled" : "outlined"} />;
            })}
          </Box>
          <Stack direction="row" spacing={1} flexWrap="wrap">
            {!M.sSettled(s) && <Button size="small" variant="outlined" onClick={() => payAll(s)}>Thu hết {money(M.sDue(s))}</Button>}
            <Box flexGrow={1} />
            <Button size="small" onClick={() => setEdit(clone(s))}>Sửa</Button>
            <Button size="small" color="error" onClick={() => del(s)}>Xóa</Button>
          </Stack>
        </Paper>
      ))}
      {list.length === 0 && <Alert severity="info">{book.sessions.length === 0 ? "Chưa có buổi nào." : "Không có buổi nào ở mục này."}</Alert>}
      {edit && <SessionDialog B={B} book={book} draft={edit} onClose={() => setEdit(null)} setToast={setToast} />}
    </Stack>
  );
}

const newSession = () => ({ id: M.id(), date: "", court: 0, price: M.DEFAULT_PRICE, shuttles: 0, parts: [], paid: {} });
const clone = (o) => JSON.parse(JSON.stringify(o));

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
    // thêm vào sổ (qua mutate) + chọn luôn
    B.mutate((bk) => { bk.members.push(m); }, `Thêm thành viên: ${nm}`);
    setD((cur) => ({ ...cur, parts: [...cur.parts, { mid: m.id, weight: 1 }] }));
    setNewMem("");
  };
  const save = () => {
    if (!d.parts.length) { alert("Chọn ít nhất 1 người chơi."); return; }
    if (M.sWeight(d) <= 0) { alert("Tổng hệ số đang bằng 0 — không chia được tiền."); return; }
    const fixed = clone(d);
    Object.keys(fixed.paid).forEach((k) => { if (!fixed.parts.some((p) => p.mid === k)) delete fixed.paid[k]; });
    B.mutate((bk) => { const i = bk.sessions.findIndex((s) => s.id === fixed.id); if (i < 0) bk.sessions.push(fixed); else bk.sessions[i] = fixed; },
      `${editing ? "Sửa" : "Thêm"} buổi ${fixed.date || "?"} · ${money(M.sTotal(fixed))} · ${fixed.parts.length} người`);
    setToast(editing ? "Đã lưu buổi" : "Đã thêm buổi");
    onClose();
  };
  return (
    <Dialog open onClose={onClose} fullWidth maxWidth="sm">
      <DialogTitle>{editing ? "Sửa buổi" : "Buổi mới"}</DialogTitle>
      <DialogContent>
        <Stack direction="row" spacing={1.5} sx={{ mt: 1 }}>
          <TextField label="Ngày" placeholder="vd: 20/6" value={d.date} onChange={(e) => upd({ date: e.target.value })} fullWidth />
          <TextField label="Tiền sân" type="number" value={d.court || ""} onChange={(e) => upd({ court: +e.target.value || 0 })} fullWidth />
        </Stack>
        <Stack direction="row" spacing={1.5} sx={{ mt: 1.5 }}>
          <TextField label="Số cầu" type="number" value={d.shuttles || ""} onChange={(e) => upd({ shuttles: +e.target.value || 0 })} fullWidth />
          <TextField label="Giá 1 cầu" type="number" value={d.price} onChange={(e) => upd({ price: +e.target.value || M.DEFAULT_PRICE })} fullWidth />
        </Stack>
        <Typography variant="caption" color="text.secondary" sx={{ display: "block", mt: 2 }}>Người chơi & hệ số</Typography>
        <Paper variant="outlined" sx={{ maxHeight: 280, overflow: "auto", mt: 0.5 }}>
          <List dense disablePadding>
            {book.members.map((m) => {
              const on = chosen.has(m.id), wt = on ? chosen.get(m.id) : 1;
              return (
                <ListItem key={m.id} divider
                  secondaryAction={on &&
                    <ToggleButtonGroup size="small" exclusive value={wt} onChange={(_, v) => v != null && setW(m.id, v)}>
                      {[0.5, 1, 2].map((q) => <ToggleButton key={q} value={q} sx={{ px: 1, py: 0.2 }}>{q === 0.5 ? "½" : q}</ToggleButton>)}
                    </ToggleButtonGroup>}>
                  <Checkbox edge="start" checked={on} onChange={() => toggle(m.id)} />
                  <ListItemAvatar sx={{ minWidth: 40 }}><MemAvatar book={book} m={m} size={28} /></ListItemAvatar>
                  <ListItemText primary={M.fullName(book, m)} />
                </ListItem>
              );
            })}
          </List>
        </Paper>
        <Stack direction="row" spacing={1} sx={{ mt: 1 }}>
          <TextField size="small" placeholder="Thêm người mới" value={newMem} onChange={(e) => setNewMem(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && addMem()} fullWidth />
          <Button onClick={addMem}>Thêm</Button>
        </Stack>
        <Paper variant="outlined" sx={{ mt: 2, p: 1.5, bgcolor: "action.hover" }}>
          <Typography variant="body2">Tổng {money(M.sTotal(d))} · {M.wStr(M.sWeight(d))} suất · <b>{money(M.sPerUnit(d))}</b>/suất</Typography>
        </Paper>
      </DialogContent>
      <DialogActions><Button onClick={onClose}>Đóng</Button><Button variant="contained" onClick={save}>Lưu buổi</Button></DialogActions>
    </Dialog>
  );
}

function AdminMembers({ B, book, setToast }) {
  const [filter, setFilter] = useState("all");
  const [newName, setNewName] = useState("");
  const fileRef = useRef(null);
  const [picFor, setPicFor] = useState(null);
  const rows = book.members.map((m) => ({ m, due: M.memberDue(book, m.id), n: M.memberSessions(book, m.id).length }))
    .sort((a, b) => b.due - a.due || a.m.name.localeCompare(b.m.name, "vi"));
  const list = rows.filter((r) => filter === "all" || r.due > M.EPS);
  const add = () => { const nm = newName.trim(); if (!nm) return; B.mutate((d) => d.members.push({ id: M.id(), name: nm, av: "" }), `Thêm thành viên: ${nm}`); setNewName(""); };
  const rename = (m) => { const nw = (prompt("Đổi tên:", m.name) || "").trim(); if (!nw || nw === m.name) return; B.mutate((d) => { const mm = d.members.find((x) => x.id === m.id); mm.name = nw; }, `Đổi tên: "${m.name}" → "${nw}"`); };
  const del = (m) => {
    const used = M.memberSessions(book, m.id).length;
    if (used > 0 && !confirm(`${m.name} có mặt trong ${used} buổi. Xóa khỏi cả các buổi đó?`)) return;
    B.mutate((d) => { d.members = d.members.filter((x) => x.id !== m.id); d.sessions.forEach((s) => { s.parts = s.parts.filter((p) => p.mid !== m.id); delete s.paid[m.id]; }); delete d.flags[m.id]; }, `Xóa thành viên ${m.name}`);
  };
  const payAll = (m) => { const ses = M.memberDueSessions(book, m.id); if (!ses.length) return; B.mutate((d) => { ses.forEach((s) => M.setPaid(d.sessions.find((x) => x.id === s.id), m.id, true)); }, `Thu của ${m.name}: ${money(M.memberDue(book, m.id))}`); setToast(`${m.name} đã trả ${money(M.memberDue(book, m.id))}`); };
  const onFile = (e) => {
    const f = e.target.files[0]; e.target.value = ""; if (!f || !picFor) return;
    shrinkSquare(f, 96, (dataUrl) => { B.mutate((d) => { const mm = d.members.find((x) => x.id === picFor); if (mm) mm.av = dataUrl; }, `Đổi ảnh đại diện: ${M.memById(book, picFor)?.name}`); });
    setPicFor(null);
  };
  return (
    <Stack spacing={2}>
      <Stack direction="row" spacing={1}>
        <TextField size="small" placeholder="Tên thành viên mới" value={newName} onChange={(e) => setNewName(e.target.value)} onKeyDown={(e) => e.key === "Enter" && add()} fullWidth />
        <Button onClick={add}>Thêm</Button>
      </Stack>
      <ToggleButtonGroup size="small" exclusive value={filter} onChange={(_, v) => v && setFilter(v)}>
        <ToggleButton value="due">Còn nợ · {rows.filter((r) => r.due > M.EPS).length}</ToggleButton>
        <ToggleButton value="all">Tất cả · {rows.length}</ToggleButton>
      </ToggleButtonGroup>
      <input ref={fileRef} type="file" accept="image/*" hidden onChange={onFile} />
      <Paper><List disablePadding>
        {list.map((r, i) => (
          <ListItem key={r.m.id} divider={i < list.length - 1}
            secondaryAction={
              <Stack direction="row" spacing={0.5}>
                {r.due > M.EPS && <Button size="small" onClick={() => payAll(r.m)}>Thu {money(r.due)}</Button>}
                <Button size="small" onClick={() => rename(r.m)}>Đổi tên</Button>
                <IconButton size="small" color="error" onClick={() => del(r.m)}><DeleteOutlineIcon fontSize="small" /></IconButton>
              </Stack>}>
            <ListItemAvatar>
              <IconButton onClick={() => { setPicFor(r.m.id); fileRef.current?.click(); }} sx={{ p: 0 }}><MemAvatar book={book} m={r.m} size={40} /></IconButton>
            </ListItemAvatar>
            <ListItemText primary={M.fullName(book, r.m)}
              secondary={r.due > M.EPS ? `nợ ${money(r.due)} · ${r.n} buổi` : `${r.n} buổi · đã trả đủ`} />
          </ListItem>
        ))}
        {list.length === 0 && <ListItem><ListItemText secondary={rows.length ? "Không ai còn nợ 🎉" : "Chưa có thành viên nào."} /></ListItem>}
      </List></Paper>
      <Typography variant="caption" color="text.secondary">Bấm ảnh đại diện để đổi ảnh (chọn file). QR / xuất ảnh hoá đơn sẽ port tiếp.</Typography>
    </Stack>
  );
}

function AdminCollect({ B, book, setToast }) {
  const [sel, setSel] = useState(() => new Set());
  const owing = M.debtors(book).map((m) => ({ m, due: M.memberDue(book, m.id), n: M.memberDueSessions(book, m.id).length })).sort((a, b) => b.due - a.due);
  const chosen = owing.filter((r) => sel.has(r.m.id));
  const grand = chosen.reduce((a, r) => a + r.due, 0);
  const toggle = (id) => setSel((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n; });
  const go = () => {
    if (!chosen.length) return;
    if (!confirm(`Ghi nhận đã thu ${money(grand)} từ ${chosen.length} người?`)) return;
    B.mutate((d) => { chosen.forEach((r) => M.memberDueSessions(book, r.m.id).forEach((s) => M.setPaid(d.sessions.find((x) => x.id === s.id), r.m.id, true))); }, `Thu ${money(grand)} từ ${chosen.length} người`);
    setToast(`Đã ghi nhận ${money(grand)} từ ${chosen.length} người`); setSel(new Set());
  };
  return (
    <Stack spacing={2}>
      <Alert severity="info">Tick người vừa chuyển khoản rồi bấm Đã nhận tiền. Sổ tự lưu lên web.</Alert>
      <Stack direction="row" spacing={1}>
        <Button size="small" onClick={() => setSel(new Set(owing.map((r) => r.m.id)))}>Chọn hết</Button>
        <Button size="small" onClick={() => setSel(new Set())}>Bỏ chọn</Button>
      </Stack>
      <Typography variant="overline" color="text.secondary">Đang nợ · {owing.length} người · {money(owing.reduce((a, r) => a + r.due, 0))}</Typography>
      <Paper><List disablePadding>
        {owing.map((r, i) => (
          <ListItemButton key={r.m.id} divider={i < owing.length - 1} selected={sel.has(r.m.id)} onClick={() => toggle(r.m.id)}>
            <Checkbox edge="start" checked={sel.has(r.m.id)} tabIndex={-1} />
            <ListItemAvatar><MemAvatar book={book} m={r.m} size={32} /></ListItemAvatar>
            <ListItemText primary={M.fullName(book, r.m)} secondary={`${r.n} buổi chưa trả`} />
            <Typography fontWeight={700} color="error">{money(r.due)}</Typography>
          </ListItemButton>
        ))}
        {owing.length === 0 && <ListItem><ListItemText secondary="Không ai còn nợ 🎉" /></ListItem>}
      </List></Paper>
      <Button variant="contained" disabled={!chosen.length} onClick={go}>
        ✓ Đã nhận tiền{chosen.length ? ` · ${money(grand)} · ${chosen.length} người` : ""}
      </Button>
      <SettingsCard B={B} book={book} setToast={setToast} />
    </Stack>
  );
}

function SettingsCard({ B, book, setToast }) {
  const qrRef = useRef(null), jsonRef = useRef(null);
  const onQr = (e) => { const f = e.target.files[0]; e.target.value = ""; if (!f) return; shrinkMax(f, 480, (d) => B.mutate((bk) => { bk.qr = d; }, "Cập nhật mã QR")); };
  const onJson = (e) => {
    const f = e.target.files[0]; e.target.value = ""; if (!f) return;
    const rd = new FileReader();
    rd.onload = (ev) => {
      let next; try { next = M.migrate(JSON.parse(ev.target.result)); } catch (err) { alert("File không hợp lệ: " + err.message); return; }
      if (!confirm(`Nhập ${next.sessions.length} buổi / ${next.members.length} người? Sổ trên web sẽ bị ghi đè.`)) return;
      B.mutate(() => {}, `Nhập JSON: ${next.sessions.length} buổi / ${next.members.length} người`);
      B.mutate((bk) => { Object.keys(bk).forEach((k) => delete bk[k]); Object.assign(bk, next); }, "");
      setToast("Đã nhập — đang lưu lên web…");
    };
    rd.readAsText(f);
  };
  const exportJson = () => { const b = new Blob([JSON.stringify(book, null, 2)], { type: "application/json" }); const a = document.createElement("a"); a.href = URL.createObjectURL(b); a.download = "so-cau-long-" + new Date().toISOString().slice(0, 10) + ".json"; a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 4000); };
  return (
    <Paper sx={{ p: 2 }}>
      <Typography variant="overline" color="text.secondary">Cài đặt</Typography>
      <TextField fullWidth size="small" label="Tên · ngân hàng · số tài khoản" defaultValue={book.note || ""}
        onBlur={(e) => { if (e.target.value !== (book.note || "")) B.mutate((d) => { d.note = e.target.value; }, "Sửa thông tin ngân hàng"); }} sx={{ my: 1 }} />
      <Stack direction="row" spacing={1} flexWrap="wrap">
        <input ref={qrRef} type="file" accept="image/*" hidden onChange={onQr} />
        <input ref={jsonRef} type="file" accept="application/json,.json" hidden onChange={onJson} />
        <Button size="small" onClick={() => qrRef.current?.click()}>{book.qr ? "Đổi QR" : "Tải QR lên"}</Button>
        {book.qr && <Button size="small" color="error" onClick={() => B.mutate((d) => { d.qr = ""; }, "Xóa mã QR")}>Xóa QR</Button>}
        <Box flexGrow={1} />
        <Button size="small" onClick={() => jsonRef.current?.click()}>Nhập JSON</Button>
        <Button size="small" onClick={exportJson}>Xuất JSON</Button>
      </Stack>
      {book.qr && <Box sx={{ textAlign: "center", mt: 1 }}><img src={book.qr} alt="QR" style={{ maxWidth: 180, borderRadius: 12 }} /></Box>}
    </Paper>
  );
}

// ---------- Save bar + conflict ----------
function SaveBar({ B }) {
  if (!B.isAdmin) return null;
  const { save, rev } = B;
  let color = "#8FD3AE", txt;
  if (save.err) { color = "#F2A0A0"; txt = "Lưu lỗi: " + save.err + (save.retries && save.retries < 3 ? ` (thử lại lần ${save.retries}…)` : ""); }
  else if (save.saving) { color = "#E8C07A"; txt = "Đang lưu lên web…"; }
  else if (save.dirty) { color = "#E8C07A"; txt = "Có thay đổi chưa lưu"; }
  else txt = `Đã lưu${save.savedAt ? " lúc " + new Date(save.savedAt).toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" }) : ""} · phiên bản ${rev}`;
  return (
    <Paper elevation={8} sx={{ position: "fixed", left: "50%", transform: "translateX(-50%)", bottom: { xs: 72, sm: 16 }, zIndex: 20, px: 2, py: 1, display: "flex", alignItems: "center", gap: 1.5, maxWidth: "94vw" }}>
      <Box sx={{ width: 8, height: 8, borderRadius: "50%", bgcolor: color }} />
      <Typography variant="body2" sx={{ flex: 1 }}>{txt}</Typography>
      {(save.dirty || save.err) && <Button size="small" onClick={B.saveNow}>Lưu ngay</Button>}
    </Paper>
  );
}

function ConflictDialog({ B }) {
  const c = B.conflict; if (!c) return null;
  const lines = c.data ? M.diffSummary(B.book, c.data).slice(0, 10) : [];
  return (
    <Dialog open onClose={() => {}} fullWidth maxWidth="sm">
      <DialogTitle>Sổ đã bị sửa ở nơi khác</DialogTitle>
      <DialogContent>
        <Typography variant="body2" color="text.secondary">Trên web đang là phiên bản {c.rev}, máy này giữ phiên bản {B.rev}. Thường do bạn mở ở tab/máy khác.</Typography>
        {lines.length > 0 && <Paper variant="outlined" sx={{ mt: 1.5, p: 1.5 }}>
          {lines.map((l, i) => <Typography key={i} variant="body2">• {l}</Typography>)}
        </Paper>}
      </DialogContent>
      <DialogActions>
        <Button onClick={() => B.resolveConflict(true)}>Lấy bản trên web</Button>
        <Button color="error" onClick={() => B.resolveConflict(false)}>Ghi đè bằng bản của tôi</Button>
      </DialogActions>
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
