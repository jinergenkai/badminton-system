import { useRef, useState } from "react";
import {
  Alert, Avatar, Box, Button, Card, Checkbox, CircularProgress, Dialog, DialogActions,
  DialogContent, DialogTitle, IconButton, InputAdornment, LinearProgress, List,
  ListItem, ListItemAvatar, ListItemButton, ListItemText, Paper, Snackbar, Stack,
  TextField, ToggleButton, ToggleButtonGroup, Tooltip, Typography,
} from "@mui/material";
import { alpha } from "@mui/material/styles";
import * as M from "../lib/model.js";
import { useBook } from "../lib/useBook.js";
import { Iconify } from "../components/iconify/index.jsx";
import { Label } from "../components/label/index.jsx";
import WidgetSummary from "../components/WidgetSummary.jsx";
import Money, { SectionLabel } from "../components/Money.jsx";

const money = (x) => M.fmt(x);
const ME_KEY = "bmw_me";
const DUE = "warning.dark"; // màu hổ phách cho số còn nợ (như bản gốc)

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
    <Box sx={{ pb: isAdmin ? 10 : 2 }}>
      <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 2 }}>
        <Box sx={{ flexGrow: 1 }}>
          <Typography variant="h4" sx={{ fontFamily: (t) => t.typography.fontSecondaryFamily, fontWeight: 800, lineHeight: 1.1 }}>Tiền cầu</Typography>
          <Typography variant="caption" color="text.secondary">
            {book.members.length} thành viên · {book.sessions.length} buổi
          </Typography>
        </Box>
        {isAdmin
          ? <Stack direction="row" spacing={1} alignItems="center">
              <Label color="primary" variant="soft" startIcon={<Iconify icon="solar:verified-check-bold" />}>Quản trị</Label>
              <Tooltip title="Thoát quản trị">
                <IconButton size="small" onClick={() => { B.logout(); setAdmin(false); setSub("all"); }}><Iconify icon="solar:logout-2-bold" /></IconButton>
              </Tooltip>
            </Stack>
          : <LoginButton B={B} />}
      </Stack>

      {B.loadErr && !B.online && (
        <Alert severity="warning" sx={{ mb: 2 }}>Mất kết nối máy chủ — đang xem số đã lưu trong máy.</Alert>
      )}

      <ToggleButtonGroup exclusive fullWidth value={sub} onChange={(_, v) => v && setSub(v)} sx={{ mb: 2.5 }}>
        {tabs.map(([k, label]) => <ToggleButton key={k} value={k} sx={{ py: 0.9 }}>{label}</ToggleButton>)}
      </ToggleButtonGroup>

      {!isAdmin && sub === "me" && <ViewMe {...ctx} />}
      {!isAdmin && sub === "all" && <ViewAll {...ctx} />}
      {(sub === "sessions") && (isAdmin ? <AdminSessions {...ctx} /> : <ViewSessions {...ctx} />)}
      {isAdmin && sub === "members" && <AdminMembers {...ctx} />}
      {isAdmin && sub === "collect" && <AdminCollect {...ctx} />}

      <SaveBar B={B} />
      <ConflictDialog B={B} />
      <Snackbar open={!!toast} autoHideDuration={2600} onClose={() => setToast("")}
        message={toast} anchorOrigin={{ vertical: "bottom", horizontal: "center" }}
        sx={{ bottom: { xs: 140, sm: 80 } }} />
    </Box>
  );
}

function MemAvatar({ m, size = 40 }) {
  return <Avatar src={m.av || undefined} sx={{ width: size, height: size, bgcolor: M.hue(m.id), fontSize: size * 0.4, color: "#fff" }}>
    {M.initials(m.name)}
  </Avatar>;
}

// trạng thái tiền một người: số hổ phách nếu còn nợ, nhãn xanh nếu đã xong
function DueTag({ due }) {
  return due > M.EPS
    ? <Money sx={{ color: DUE, fontWeight: 700, fontSize: 15 }}>{money(due)}</Money>
    : <Label color="success" startIcon={<Iconify icon="solar:check-circle-bold" />}>Đã trả</Label>;
}

function SearchBox({ value, onChange, placeholder }) {
  return (
    <TextField fullWidth placeholder={placeholder} value={value} onChange={(e) => onChange(e.target.value)}
      sx={{ "& .MuiOutlinedInput-root": { bgcolor: "background.paper" } }}
      InputProps={{ startAdornment: <InputAdornment position="start"><Iconify icon="solar:magnifer-linear" sx={{ color: "text.disabled" }} /></InputAdornment> }} />
  );
}

function EmptyRow({ children }) {
  return <ListItem sx={{ py: 3, justifyContent: "center" }}><Typography variant="body2" color="text.secondary">{children}</Typography></ListItem>;
}

// ---------- Viewer ----------
function ViewAll({ book }) {
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
      <SearchBox placeholder="Tìm tên…" value={q} onChange={setQ} />
      <ToggleButtonGroup size="small" exclusive value={filter} onChange={(_, v) => v && setFilter(v)} sx={{ alignSelf: "flex-start" }}>
        <ToggleButton value="due">Còn nợ · {nDue}</ToggleButton>
        <ToggleButton value="ok">Đã xong</ToggleButton>
        <ToggleButton value="all">Tất cả</ToggleButton>
      </ToggleButtonGroup>
      <Card>
        <List disablePadding>
          {rows.map((r, i) => (
            <ListItem key={r.m.id} divider={i < rows.length - 1} secondaryAction={<DueTag due={r.due} />} sx={{ py: 1.25 }}>
              <ListItemAvatar><MemAvatar m={r.m} size={38} /></ListItemAvatar>
              <ListItemText primary={M.fullName(book, r.m)}
                secondary={r.due > M.EPS ? `${r.n} buổi chưa trả` : `${r.tot} buổi · đã trả đủ`} />
            </ListItem>
          ))}
          {rows.length === 0 && <EmptyRow>Không có ai trong mục này.</EmptyRow>}
        </List>
      </Card>
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
        <Alert severity="info" icon={<Iconify icon="solar:user-rounded-bold-duotone" />}>Bấm vào tên bạn để xem mình nợ bao nhiêu, gồm những buổi nào.</Alert>
        <SearchBox placeholder="Gõ tên để tìm…" value={q} onChange={setQ} />
        <Card><List disablePadding>
          {rows.map((r, i) => (
            <ListItemButton key={r.m.id} divider={i < rows.length - 1} onClick={() => pick(r.m.id)} sx={{ py: 1.25 }}>
              <ListItemAvatar><MemAvatar m={r.m} size={38} /></ListItemAvatar>
              <ListItemText primary={M.fullName(book, r.m)} />
              <DueTag due={r.due} />
            </ListItemButton>
          ))}
          {rows.length === 0 && <EmptyRow>Không tìm thấy ai.</EmptyRow>}
        </List></Card>
      </Stack>
    );
  }
  const due = M.memberDue(book, m.id);
  const dueSes = M.memberDueSessions(book, m.id);
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
                <IconButton size="small" onClick={() => { try { navigator.clipboard.writeText(M.payRef(m)); } catch { /* */ } }}><Iconify icon="solar:copy-bold" width={16} /></IconButton>
              </Stack>
            </Box>
            {book.note && <Typography fontWeight={700} sx={{ mt: 1.5 }}>{book.note}</Typography>}
            {book.qr && <Box sx={{ mt: 1.5 }}><img src={book.qr} alt="QR" style={{ maxWidth: 210, borderRadius: 12, boxShadow: "0 8px 16px rgba(145,158,171,.24)" }} /></Box>}
          </>
        ) : (
          <Stack alignItems="center" spacing={1} sx={{ mt: 2 }}>
            <Iconify icon="solar:check-circle-bold" width={48} sx={{ color: "success.main" }} />
            <Typography variant="h5" color="success.dark">Không nợ gì 🎉</Typography>
          </Stack>
        )}
      </Card>
      {dueSes.length > 0 && (
        <>
          <SectionLabel>Các buổi chưa trả</SectionLabel>
          <Card><List disablePadding>
            {dueSes.map((s, i) => (
              <ListItem key={s.id} divider={i < dueSes.length - 1}
                secondaryAction={<Money sx={{ color: DUE, fontWeight: 700 }}>{money(M.shareIn(s, m.id))}</Money>}>
                <ListItemText primary={s.date || "—"}
                  secondary={<Money sx={{ fontWeight: 400, fontSize: 12 }}>({s.court} + {s.shuttles}×{s.price || M.DEFAULT_PRICE}) / {M.wStr(M.sWeight(s))} suất</Money>} />
              </ListItem>
            ))}
          </List></Card>
        </>
      )}
      <Button color="inherit" variant="text" sx={{ color: "text.secondary" }} onClick={() => { setMeId(null); try { localStorage.removeItem(ME_KEY); } catch { /* */ } }}>
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

// phần đầu thẻ buổi — dùng chung viewer/admin
function SessionHead({ s }) {
  const settled = M.sSettled(s);
  return (
    <>
      <Stack direction="row" alignItems="center" spacing={1}>
        <Box sx={{ width: 40, height: 40, borderRadius: 1.5, display: "grid", placeItems: "center", flexShrink: 0, bgcolor: (t) => alpha(t.palette.primary.main, 0.1), color: "primary.main" }}>
          <Iconify icon="solar:calendar-bold-duotone" width={22} />
        </Box>
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
      sx={{
        display: "inline-flex", alignItems: "center", gap: 0.75, pl: 0.4, pr: 1.1, py: 0.4, borderRadius: 5, font: "inherit",
        fontSize: 13, fontWeight: 600, cursor: onClick ? "pointer" : "default", transition: "all .15s",
        border: (t) => `1px solid ${on ? "transparent" : alpha(t.palette.grey[500], 0.32)}`,
        bgcolor: (t) => on ? alpha(t.palette.success.main, 0.16) : t.palette.background.paper,
        color: on ? "success.dark" : "text.primary",
        "&:hover": onClick ? { borderColor: "primary.main" } : undefined,
      }}>
      <MemAvatar m={m} size={22} />
      <span style={on ? { textDecoration: "line-through", textDecorationThickness: 1 } : undefined}>{M.fullName(book, m)}</span>
      {p.weight !== 1 && <Money sx={{ fontSize: 11, opacity: 0.7 }}>×{M.wStr(p.weight)}</Money>}
      {on && <Iconify icon="solar:check-circle-bold" width={16} />}
    </Box>
  );
}

function SessionCard({ book, s }) {
  const got = M.sCollected(s), tot = M.sTotal(s);
  return (
    <Card sx={{ p: 2 }}>
      <SessionHead s={s} />
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
        <WidgetSummary color="warning" mono title="Còn thiếu" icon="solar:hand-money-bold-duotone"
          total={due > M.EPS ? money(due) : "0k"} caption={due > M.EPS ? M.vnd(due) : "Xong hết 🎉"} />
        <WidgetSummary color="primary" mono title="Đã thu" icon="solar:wallet-money-bold-duotone"
          total={money(got)} caption={<>trên <Money sx={{ fontWeight: 600 }}>{money(all)}</Money></>} />
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
function LoginButton({ B }) {
  const [open, setOpen] = useState(false);
  const [pw, setPw] = useState("");
  const [err, setErr] = useState("");
  const go = async () => { try { await B.login(pw); setOpen(false); setPw(""); setErr(""); } catch (e) { setErr(String(e.message || e)); } };
  return (
    <>
      <Button size="small" variant="outlined" color="inherit" startIcon={<Iconify icon="solar:lock-keyhole-unlocked-bold" width={18} />} onClick={() => setOpen(true)}>Quản trị</Button>
      <Dialog open={open} onClose={() => setOpen(false)} fullWidth maxWidth="xs">
        <DialogTitle>Đăng nhập quản trị</DialogTitle>
        <DialogContent>
          <TextField autoFocus type="password" fullWidth label="Mật khẩu" value={pw}
            onChange={(e) => setPw(e.target.value)} onKeyDown={(e) => e.key === "Enter" && go()} sx={{ mt: 1 }} error={!!err} helperText={err || " "} />
        </DialogContent>
        <DialogActions><Button color="inherit" onClick={() => setOpen(false)}>Đóng</Button><Button variant="contained" onClick={go}>Mở khóa</Button></DialogActions>
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
      <Button variant="contained" size="large" startIcon={<Iconify icon="mingcute:add-line" />} onClick={() => setEdit(newSession())}>Thêm buổi chơi</Button>
      <ToggleButtonGroup size="small" exclusive value={filter} onChange={(_, v) => v && setFilter(v)} sx={{ alignSelf: "flex-start" }}>
        <ToggleButton value="open">Chưa xong · {openN}</ToggleButton>
        <ToggleButton value="done">Đã xong · {book.sessions.length - openN}</ToggleButton>
        <ToggleButton value="all">Tất cả · {book.sessions.length}</ToggleButton>
      </ToggleButtonGroup>
      {list.map((s) => (
        <Card key={s.id} sx={{ p: 2 }}>
          <SessionHead s={s} />
          <Typography variant="caption" color="text.disabled" sx={{ display: "block", mt: 1.5, mb: 0.75 }}>Bấm tên để đánh dấu đã trả</Typography>
          <Box sx={{ display: "flex", flexWrap: "wrap", gap: 0.75 }}>
            {s.parts.map((p) => <PartChip key={p.mid} book={book} s={s} p={p} onClick={() => togglePaid(s, p.mid)} />)}
          </Box>
          <Stack direction="row" spacing={1} alignItems="center" sx={{ mt: 2, pt: 1.5, borderTop: (t) => `1px dashed ${t.palette.divider}` }}>
            {!M.sSettled(s) && <Button size="small" variant="contained" color="inherit" onClick={() => payAll(s)}>Thu hết <Money sx={{ ml: 0.75 }}>{money(M.sDue(s))}</Money></Button>}
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
const numInput = { inputProps: { inputMode: "numeric", style: { fontFamily: "'Roboto Mono', monospace", fontVariantNumeric: "tabular-nums" } } };

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
        <Box sx={{ display: "grid", gap: 1.5, gridTemplateColumns: "1fr 1fr", mt: 1 }}>
          <TextField label="Ngày" placeholder="vd: 20/6" value={d.date} onChange={(e) => upd({ date: e.target.value })} />
          <TextField label="Tiền sân (k)" type="number" value={d.court || ""} onChange={(e) => upd({ court: +e.target.value || 0 })} {...numInput} />
          <TextField label="Số cầu" type="number" value={d.shuttles || ""} onChange={(e) => upd({ shuttles: +e.target.value || 0 })} {...numInput} />
          <TextField label="Giá 1 cầu (k)" type="number" value={d.price} onChange={(e) => upd({ price: +e.target.value || M.DEFAULT_PRICE })} {...numInput} />
        </Box>
        <SectionLabel sx={{ mt: 2.5 }} right={<Typography variant="caption" color="text.secondary">{d.parts.length} đã chọn</Typography>}>Người chơi & hệ số</SectionLabel>
        <Paper variant="outlined" sx={{ maxHeight: 300, overflow: "auto", borderRadius: 1.5 }}>
          <List dense disablePadding>
            {book.members.map((m) => {
              const on = chosen.has(m.id), wt = on ? chosen.get(m.id) : 1;
              return (
                <ListItem key={m.id} divider sx={{ bgcolor: (t) => on ? alpha(t.palette.primary.main, 0.05) : undefined }}
                  secondaryAction={on &&
                    <ToggleButtonGroup size="small" exclusive value={wt} onChange={(_, v) => v != null && setW(m.id, v)} sx={{ p: 0.4, gap: 0.4 }}>
                      {[0.5, 1, 2].map((q) => <ToggleButton key={q} value={q} sx={{ px: 1.1, py: 0.1, minWidth: 30, fontFamily: "'Roboto Mono', monospace" }}>{q === 0.5 ? "½" : q}</ToggleButton>)}
                    </ToggleButtonGroup>}>
                  <Checkbox edge="start" checked={on} onChange={() => toggle(m.id)} />
                  <ListItemAvatar sx={{ minWidth: 40 }}><MemAvatar m={m} size={28} /></ListItemAvatar>
                  <ListItemText primary={M.fullName(book, m)} onClick={() => toggle(m.id)} sx={{ cursor: "pointer" }} />
                </ListItem>
              );
            })}
          </List>
        </Paper>
        <Stack direction="row" spacing={1} sx={{ mt: 1.5 }}>
          <TextField placeholder="Thêm người mới" value={newMem} onChange={(e) => setNewMem(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && addMem()} fullWidth
            InputProps={{ startAdornment: <InputAdornment position="start"><Iconify icon="solar:user-plus-bold" sx={{ color: "text.disabled" }} /></InputAdornment> }} />
          <Button variant="outlined" onClick={addMem}>Thêm</Button>
        </Stack>
        <Stack direction="row" alignItems="center" sx={{ mt: 2, p: 1.5, borderRadius: 1.5, bgcolor: (t) => alpha(t.palette.primary.main, 0.08), color: "primary.darker" }}>
          <Typography variant="body2" sx={{ flexGrow: 1 }}>
            Tổng <Money sx={{ fontWeight: 700 }}>{money(M.sTotal(d))}</Money> · <Money>{M.wStr(M.sWeight(d))}</Money> suất
          </Typography>
          <Money sx={{ fontWeight: 700, fontSize: 18 }}>{money(M.sPerUnit(d))}<Typography component="span" variant="caption">/suất</Typography></Money>
        </Stack>
      </DialogContent>
      <DialogActions><Button color="inherit" onClick={onClose}>Đóng</Button><Button variant="contained" onClick={save}>Lưu buổi</Button></DialogActions>
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
        <TextField placeholder="Tên thành viên mới" value={newName} onChange={(e) => setNewName(e.target.value)} onKeyDown={(e) => e.key === "Enter" && add()} fullWidth
          sx={{ "& .MuiOutlinedInput-root": { bgcolor: "background.paper" } }}
          InputProps={{ startAdornment: <InputAdornment position="start"><Iconify icon="solar:user-plus-bold" sx={{ color: "text.disabled" }} /></InputAdornment> }} />
        <Button variant="contained" onClick={add}>Thêm</Button>
      </Stack>
      <ToggleButtonGroup size="small" exclusive value={filter} onChange={(_, v) => v && setFilter(v)} sx={{ alignSelf: "flex-start" }}>
        <ToggleButton value="due">Còn nợ · {rows.filter((r) => r.due > M.EPS).length}</ToggleButton>
        <ToggleButton value="all">Tất cả · {rows.length}</ToggleButton>
      </ToggleButtonGroup>
      <input ref={fileRef} type="file" accept="image/*" hidden onChange={onFile} />
      <Card><List disablePadding>
        {list.map((r, i) => (
          <ListItem key={r.m.id} divider={i < list.length - 1} sx={{ py: 1.25, pr: 1, flexWrap: "wrap" }}>
            <ListItemAvatar>
              <Tooltip title="Đổi ảnh">
                <IconButton onClick={() => { setPicFor(r.m.id); fileRef.current?.click(); }} sx={{ p: 0 }}><MemAvatar m={r.m} size={40} /></IconButton>
              </Tooltip>
            </ListItemAvatar>
            <ListItemText sx={{ minWidth: 0 }} primary={M.fullName(book, r.m)}
              secondary={r.due > M.EPS ? <>nợ <Money sx={{ color: DUE }}>{money(r.due)}</Money> · {r.n} buổi</> : `${r.n} buổi · đã trả đủ`} />
            <Stack direction="row" spacing={0.25} alignItems="center">
              {r.due > M.EPS && <Button size="small" color="warning" onClick={() => payAll(r.m)} sx={{ bgcolor: (t) => alpha(t.palette.warning.main, 0.16), color: "warning.dark", "&:hover": { bgcolor: (t) => alpha(t.palette.warning.main, 0.28) } }}>Thu <Money sx={{ ml: 0.5 }}>{money(r.due)}</Money></Button>}
              <Tooltip title="Đổi tên"><IconButton size="small" onClick={() => rename(r.m)}><Iconify icon="solar:pen-bold" width={18} /></IconButton></Tooltip>
              <Tooltip title="Xóa"><IconButton size="small" color="error" onClick={() => del(r.m)}><Iconify icon="solar:trash-bin-trash-bold" width={18} /></IconButton></Tooltip>
            </Stack>
          </ListItem>
        ))}
        {list.length === 0 && <EmptyRow>{rows.length ? "Không ai còn nợ 🎉" : "Chưa có thành viên nào."}</EmptyRow>}
      </List></Card>
      <Typography variant="caption" color="text.secondary">Bấm ảnh đại diện để đổi ảnh (chọn file).</Typography>
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
      <Alert severity="info" icon={<Iconify icon="solar:card-transfer-bold-duotone" />}>Tick người vừa chuyển khoản rồi bấm Đã nhận tiền. Sổ tự lưu lên web.</Alert>
      <SectionLabel right={
        <Stack direction="row" spacing={0.5}>
          <Button size="small" onClick={() => setSel(new Set(owing.map((r) => r.m.id)))}>Chọn hết</Button>
          <Button size="small" color="inherit" onClick={() => setSel(new Set())}>Bỏ chọn</Button>
        </Stack>}>
        Đang nợ · {owing.length} người · <Money>{money(owing.reduce((a, r) => a + r.due, 0))}</Money>
      </SectionLabel>
      <Card><List disablePadding>
        {owing.map((r, i) => (
          <ListItemButton key={r.m.id} divider={i < owing.length - 1} selected={sel.has(r.m.id)} onClick={() => toggle(r.m.id)}
            sx={{ py: 1, "&.Mui-selected": { bgcolor: (t) => alpha(t.palette.primary.main, 0.08) } }}>
            <Checkbox edge="start" checked={sel.has(r.m.id)} tabIndex={-1} />
            <ListItemAvatar><MemAvatar m={r.m} size={34} /></ListItemAvatar>
            <ListItemText primary={M.fullName(book, r.m)} secondary={`${r.n} buổi chưa trả`} />
            <Money sx={{ color: DUE, fontWeight: 700 }}>{money(r.due)}</Money>
          </ListItemButton>
        ))}
        {owing.length === 0 && <EmptyRow>Không ai còn nợ 🎉</EmptyRow>}
      </List></Card>
      <Button variant="contained" size="large" disabled={!chosen.length} onClick={go} startIcon={<Iconify icon="solar:check-circle-bold" />}>
        Đã nhận tiền{chosen.length ? <>&nbsp;· <Money sx={{ mx: 0.5 }}>{money(grand)}</Money> · {chosen.length} người</> : ""}
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
    <Card sx={{ p: 2.5 }}>
      <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 1.5 }}>
        <Iconify icon="solar:settings-bold-duotone" sx={{ color: "text.secondary" }} />
        <Typography variant="subtitle1">Cài đặt</Typography>
      </Stack>
      <TextField fullWidth label="Tên · ngân hàng · số tài khoản" defaultValue={book.note || ""}
        onBlur={(e) => { if (e.target.value !== (book.note || "")) B.mutate((d) => { d.note = e.target.value; }, "Sửa thông tin ngân hàng"); }} sx={{ mb: 1.5 }} />
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
    </Card>
  );
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
    <Paper sx={{
      position: "fixed", left: "50%", transform: "translateX(-50%)", bottom: { xs: "calc(76px + env(safe-area-inset-bottom))", sm: 20 }, zIndex: 20,
      pl: 1.5, pr: 1, py: 0.75, display: "flex", alignItems: "center", gap: 1.25, width: "max-content", maxWidth: "min(94vw, 560px)",
      borderRadius: 5, bgcolor: "grey.800", color: "common.white", boxShadow: (t) => t.customShadows.z20,
    }}>
      <Iconify icon={icon} width={20} sx={{ color: `${color}.light` }} />
      <Typography variant="body2" sx={{ flex: 1, fontWeight: 500 }}>{txt}</Typography>
      {!save.dirty && !save.err && !save.saving && <Label variant="filled" sx={{ bgcolor: "rgba(255,255,255,.14)", color: "grey.300", fontFamily: "'Roboto Mono', monospace" }}>v{rev}</Label>}
      {(save.dirty || save.err) && <Button size="small" variant="contained" onClick={B.saveNow} sx={{ borderRadius: 4, boxShadow: "none" }}>Lưu ngay</Button>}
    </Paper>
  );
}

function ConflictDialog({ B }) {
  const c = B.conflict; if (!c) return null;
  const lines = c.data ? M.diffSummary(B.book, c.data).slice(0, 10) : [];
  return (
    <Dialog open onClose={() => {}} fullWidth maxWidth="sm">
      <DialogTitle sx={{ display: "flex", alignItems: "center", gap: 1 }}>
        <Iconify icon="solar:danger-triangle-bold" sx={{ color: "warning.main" }} width={26} /> Sổ đã bị sửa ở nơi khác
      </DialogTitle>
      <DialogContent>
        <Typography variant="body2" color="text.secondary">
          Trên web đang là phiên bản <Label color="info">v{c.rev}</Label>, máy này giữ phiên bản <Label>v{B.rev}</Label>. Thường do bạn mở ở tab/máy khác.
        </Typography>
        {lines.length > 0 && <Box sx={{ mt: 2, p: 1.5, borderRadius: 1.5, bgcolor: "background.neutral" }}>
          {lines.map((l, i) => <Typography key={i} variant="body2" sx={{ py: 0.25 }}>• {l}</Typography>)}
        </Box>}
      </DialogContent>
      <DialogActions>
        <Button variant="contained" onClick={() => B.resolveConflict(true)}>Lấy bản trên web</Button>
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
