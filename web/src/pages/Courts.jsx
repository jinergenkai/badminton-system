// Sân trống — port bản xem công khai từ _legacy/courts.html sang MUI.
// 3 view: Theo ngày (sân × giờ), Tổng quan (sân × ngày, mini-timeline), Tìm slot (đa sân).
// Dữ liệu do crawler đẩy lên /api/courts (nén occ theo sân×ngày) → giải nén về shape viz.
import { useEffect, useMemo, useRef, useState } from "react";
import {
  Box, Card, CardContent, Stack, Typography, Select, MenuItem, FormControl,
  ToggleButton, ToggleButtonGroup, Switch, FormControlLabel, Chip, Tooltip,
  CircularProgress, Alert, useMediaQuery,
} from "@mui/material";
import { Button, Collapse, Snackbar, TextField, IconButton } from "@mui/material";
import { useTheme, alpha } from "@mui/material/styles";
import { api } from "../lib/api.js";
import { useAuth } from "../lib/auth.jsx";
import WidgetSummary from "../components/WidgetSummary.jsx";
import { Iconify } from "../components/iconify/index.jsx";
import { Label } from "../components/label/index.jsx";

const WD_FULL = { T2: "Thứ 2", T3: "Thứ 3", T4: "Thứ 4", T5: "Thứ 5", T6: "Thứ 6", T7: "Thứ 7", CN: "Chủ nhật" };
const WDX = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"];
const SPORT_LABEL = { badminton: "Cầu lông", pickleball: "Pickleball", all: "Tất cả" };
const STLABEL = { free: "Trống", booked: "Đã đặt", locked: "Khoá (chờ mở)", event: "Sự kiện" };
const LS_KEY = "alobo_prefs_mui";

const fmtDate = (iso) => { const [, m, d] = iso.split("-"); return `${d}/${m}`; };
const addMin = (t, m) => { let [a, b] = t.split(":").map(Number); let x = a * 60 + b + m; return String(Math.floor(x / 60)).padStart(2, "0") + ":" + String(x % 60).padStart(2, "0"); };
function fmtPrice(n) { if (n == null) return ""; if (n >= 1e6) return (n / 1e6).toFixed(n % 1e6 ? 1 : 0) + "tr"; if (n >= 1000) return Math.round(n / 1000) + "k"; return "" + n; }
function fmtStamp(updatedAt) { if (!updatedAt) return "chưa có dữ liệu"; const t = new Date(updatedAt), mins = Math.max(0, Math.round((Date.now() - t) / 60000)); return mins < 1 ? "vừa xong" : mins < 60 ? mins + "′ trước" : mins < 2880 ? Math.round(mins / 60) + "h trước" : Math.round(mins / 1440) + " ngày trước"; }

// push_web.py nén occupied thành chuỗi theo sân×ngày — giải nén về shape viz cần.
function expandCourts(p) {
  (p.branches || []).forEach((g) => {
    if (!g.occ) return;
    const occ = [...(g.occ_extra || [])], codes = g.occ_codes || [];
    Object.entries(g.occ).forEach(([court, ds]) => Object.entries(ds).forEach(([date, row]) => {
      for (let i = 0; i < row.length; i++) { const ch = row[i]; if (ch === ".") continue; occ.push({ court, date, slot: g.slots[i], status: codes[ch.charCodeAt(0) - 97] || "booked" }); }
    }));
    g.occupied = occ; delete g.occ; delete g.occ_extra;
  });
  return p;
}
function buildOcc(g) {
  if (!g.__occ) { g.__occ = new Set(g.occupied.map((c) => c.court + "|" + c.date + "|" + c.slot)); g.__stat = {}; g.occupied.forEach((c) => (g.__stat[c.court + "|" + c.date + "|" + c.slot] = c.status)); }
  return g;
}
function statusG(g, court, date, slot) { buildOcc(g); const k = court + "|" + date + "|" + slot; return g.__occ.has(k) ? g.__stat[k] || "booked" : "free"; }
function priceAt(g, court, date, slot) {
  const P = g.prices; if (!P) return null;
  const jsw = new Date(date + "T00:00:00").getDay(); const w = (jsw + 6) % 7;
  for (const key of [court, "*"]) for (const r of P[key] || []) if ((r.days === null || r.days.includes(w)) && r.start <= slot && slot < r.end) return r.price;
  return null;
}
function priceRange(g, courts, date, slots) {
  const set = new Set(); courts.forEach((c) => slots.forEach((s) => { const p = priceAt(g, c, date, s); if (p != null) set.add(p); }));
  const a = [...set].sort((x, y) => x - y); if (!a.length) return null;
  return a.length === 1 ? fmtPrice(a[0]) : `${fmtPrice(a[0])}–${fmtPrice(a[a.length - 1])}`;
}
function branchMaxPrice(g, courts) {
  if (!g.prices) return null; let mx = null;
  for (const c of courts) for (const key of [c, "*"]) for (const r of g.prices[key] || []) if (mx == null || r.price > mx) mx = r.price;
  return mx;
}
function courtsOf(g, sport) { if (!sport || sport === "all") return g.courts; const m = g.court_sport || {}; return g.courts.filter((c) => (m[c] || "badminton") === sport); }
function sportsOf(g) { const m = g.court_sport || {}; return [...new Set(g.courts.map((c) => m[c] || "badminton"))]; }

function loadPrefs() { try { return JSON.parse(localStorage.getItem(LS_KEY) || "{}"); } catch { return {}; } }
function savePrefs(p) { try { localStorage.setItem(LS_KEY, JSON.stringify(p)); } catch { /* */ } }

// ---- màu trạng thái theo theme ----
function useStatusStyles() {
  const t = useTheme();
  const s = {
    free: { bg: alpha(t.palette.success.main, 0.14), ring: `inset 0 0 0 1.5px ${t.palette.success.main}`, dot: t.palette.success.main },
    booked: { bg: alpha(t.palette.error.main, 0.16), fill: alpha(t.palette.error.main, 0.55) },
    locked: { bg: alpha(t.palette.text.disabled, 0.12), hatch: `repeating-linear-gradient(45deg,transparent,transparent 4px,${alpha(t.palette.text.disabled, 0.4)} 4px,${alpha(t.palette.text.disabled, 0.4)} 5px)` },
    event: { bg: alpha(t.palette.secondary.main, 0.14), mark: t.palette.secondary.main },
  };
  return s;
}

export default function Courts() {
  const theme = useTheme();
  const isMobile = useMediaQuery(theme.breakpoints.down("sm"));
  const ST = useStatusStyles();
  const auth = useAuth();
  const [data, setData] = useState(null);
  const [err, setErr] = useState("");
  const [updatedAt, setUpdatedAt] = useState(null);
  const pref = useRef(loadPrefs());
  const [bi, setBi] = useState(0);
  const [view, setView] = useState(pref.current.view || "day");
  const [range, setRange] = useState(pref.current.range || { start: "18:00", end: "22:00" });
  const [wd, setWd] = useState(pref.current.wd ?? true);
  const [sport, setSport] = useState("all");
  const [date, setDate] = useState(null);
  const [finder, setFinder] = useState(pref.current.finder || { days: [0, 1, 2, 3, 4], start: "18:00", end: "20:00" });

  const reload = () => api.getCourts().then((j) => {
    setUpdatedAt(j.updatedAt || null);
    setData(expandCourts(j.data || { branches: [], monitored: [] }));
    return j.updatedAt || null;
  });
  useEffect(() => { reload().catch((e) => setErr(e.message || String(e))); }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const branches = useMemo(() => {
    if (!data) return [];
    const mon = new Set(data.monitored || []);
    let b = data.branches.filter((g) => g.branch !== "demo" && (mon.size ? mon.has(g.branch) : true));
    if (!b.length) b = data.branches.filter((g) => g.branch !== "demo");
    return b;
  }, [data]);

  const g = branches[bi] || null;

  // khôi phục sân đã chọn
  useEffect(() => {
    if (!branches.length) return;
    const j = branches.findIndex((x) => x.branch === pref.current.branch);
    if (j > 0) setBi(j);
  }, [branches]);

  // mỗi lần đổi sân: chọn môn + ngày mặc định
  useEffect(() => {
    if (!g) return;
    const av = sportsOf(g);
    setSport(av.length <= 1 ? "all" : av.includes("badminton") ? "badminton" : av[0]);
    setDate((prev) => (g.days.some((d) => d.date === prev) ? prev : (g.days.find((d) => !d.is_weekend) || g.days[0] || {}).date));
  }, [g]);

  useEffect(() => { savePrefs({ view, range, wd, finder, branch: g?.branch }); }, [view, range, wd, finder, g]);

  if (err) return <Alert severity="error" sx={{ mt: 2 }}>Không tải được dữ liệu sân: {err}</Alert>;
  if (!data) return <Box sx={{ display: "flex", justifyContent: "center", py: 8 }}><CircularProgress /></Box>;

  const isAdmin = auth.isAdmin;
  if (!isAdmin && (view === "crawl" || view === "config")) setView("day");
  const tabsEl = (
    <ToggleButtonGroup exclusive size="small" value={view} onChange={(_, v) => v && setView(v)} sx={{ flexWrap: "wrap" }}>
      <ToggleButton value="day">Theo ngày</ToggleButton>
      <ToggleButton value="overview">Tổng quan</ToggleButton>
      <ToggleButton value="finder"><Iconify icon="solar:magnifer-linear" width={16} sx={{ mr: 0.5 }} />Tìm slot</ToggleButton>
      {isAdmin && <ToggleButton value="crawl"><Iconify icon="solar:refresh-bold" width={16} sx={{ mr: 0.5 }} />Cào</ToggleButton>}
      {isAdmin && <ToggleButton value="config"><Iconify icon="solar:settings-bold" width={16} sx={{ mr: 0.5 }} />Cấu hình</ToggleButton>}
    </ToggleButtonGroup>
  );

  // Tab quản trị — không cần dữ liệu sân (dùng được cả khi chưa cào gì).
  if (isAdmin && view === "crawl") return <Stack spacing={2.5} sx={{ mt: 1 }}>{tabsEl}<CrawlPanel pass={auth.passRef} stamp={fmtStamp(updatedAt)} reload={reload} /></Stack>;
  if (isAdmin && view === "config") return <Stack spacing={2.5} sx={{ mt: 1 }}>{tabsEl}<CourtsSettings pass={auth.passRef} /></Stack>;

  if (!branches.length) return (
    <Stack spacing={2.5} sx={{ mt: 1 }}>{tabsEl}
      <Alert severity="info">Chưa có dữ liệu sân{isAdmin ? " — mở tab “Cào” để lấy dữ liệu mới." : " — máy cào chưa gửi lên lần nào."}</Alert>
    </Stack>
  );

  const courts = courtsOf(g, sport);
  const slots = g.slots.filter((s) => s >= range.start && s < range.end);
  const days = (() => { const f = g.days.filter((d) => !(wd && d.is_weekend)); return f.length ? f : g.days; })();
  const av = sportsOf(g);
  const timeOpts = (() => { const h = g.hours || { start: "06:00", end: "22:00" }; const out = []; let t = h.start; const step = g.slot_minutes || 30; while (t <= h.end) { out.push(t); t = addMin(t, step); } return out; })();

  // KPIs (khung đã chọn, T2–T6)
  const kdays = g.days.filter((d) => !d.is_weekend);
  let free = 0, total = 0;
  kdays.forEach((d) => courts.forEach((c) => slots.forEach((s) => { total++; if (statusG(g, c, d.date, s) === "free") free++; })));
  const daysFree = kdays.filter((d) => courts.some((c) => slots.some((s) => statusG(g, c, d.date, s) === "free"))).length;
  const bmp = branchMaxPrice(g, courts);
  const stamp = fmtStamp(updatedAt);

  const cell = (st) => {
    const base = { width: 30, height: 26, borderRadius: 1, position: "relative", flex: "0 0 auto" };
    if (st === "free") return { ...base, bgcolor: ST.free.bg, boxShadow: ST.free.ring };
    if (st === "booked") return { ...base, bgcolor: ST.booked.bg };
    if (st === "locked") return { ...base, bgcolor: ST.locked.bg, backgroundImage: ST.locked.hatch };
    if (st === "event") return { ...base, bgcolor: ST.event.bg };
    return base;
  };

  return (
    <Stack spacing={2.5} sx={{ mt: 1 }}>
      {tabsEl}
      {/* KPIs */}
      <Box sx={{ display: "grid", gap: { xs: 1.5, sm: 2.5 }, gridTemplateColumns: { xs: "repeat(2,1fr)", md: "repeat(4,1fr)" } }}>
        <WidgetSummary color="success" icon="solar:calendar-search-bold-duotone" title="Ô trống (T2–T6)" total={free} caption={`khung ${range.start}–${range.end} · ${total} ô`} />
        <WidgetSummary color="primary" icon="solar:calendar-bold-duotone" title="Ngày có chỗ" total={`${daysFree}/${kdays.length}`} caption="T2–T6 còn ít nhất 1 ô" />
        <WidgetSummary color="info" icon="solar:widget-bold-duotone" title="Số sân" total={courts.length} caption={SPORT_LABEL[sport] || sport} />
        <WidgetSummary color="warning" icon="solar:tag-price-bold" title={bmp != null ? "Giá trần / giờ" : "Ngày theo dõi"} total={bmp != null ? fmtPrice(bmp) : g.days.length} caption={bmp != null ? "mức cao nhất bảng giá" : "ngày đã cào"} />
      </Box>

      {/* Controls */}
      <Card>
        <CardContent sx={{ py: 2, "&:last-child": { pb: 2 } }}>
          <Stack direction="row" flexWrap="wrap" gap={1.5} alignItems="center">
            <Box sx={{ flexGrow: 1, minWidth: 0 }}>
              <Stack direction="row" alignItems="center" spacing={1}>
                <Iconify icon="solar:map-point-bold" width={22} sx={{ color: "primary.main" }} />
                <Typography variant="h5" sx={{ lineHeight: 1.2 }}>{g.branch_name}</Typography>
              </Stack>
              <Stack direction="row" alignItems="center" spacing={1} sx={{ mt: 0.75 }} flexWrap="wrap" useFlexGap>
                <Label color="primary">{g.days.length} ngày</Label>
                <Label color="info">{g.courts.length} sân</Label>
                <Label startIcon={<Iconify icon="solar:refresh-bold" />}>cào {stamp}</Label>
              </Stack>
            </Box>
            {branches.length > 1 && (
              <FormControl sx={{ minWidth: 180 }}>
                <Select value={bi} onChange={(e) => setBi(e.target.value)}>
                  {branches.map((b, i) => <MenuItem key={b.branch} value={i}>{b.branch_name}</MenuItem>)}
                </Select>
              </FormControl>
            )}
          </Stack>

          <Stack direction="row" flexWrap="wrap" gap={1.5} alignItems="center" sx={{ mt: 2 }}>
            {view !== "finder" && (
              <Stack direction="row" gap={1} alignItems="center">
                <Typography variant="body2" color="text.secondary">Giờ</Typography>
                <Select size="small" value={range.start} onChange={(e) => { let s = e.target.value, en = range.end; if (en <= s) en = addMin(s, g.slot_minutes || 30); setRange({ start: s, end: en }); }}>
                  {timeOpts.slice(0, -1).map((t) => <MenuItem key={t} value={t}>{t}</MenuItem>)}
                </Select>
                <Typography variant="body2" color="text.secondary">–</Typography>
                <Select size="small" value={range.end} onChange={(e) => setRange({ ...range, end: e.target.value })}>
                  {timeOpts.slice(1).map((t) => <MenuItem key={t} value={t}>{t}</MenuItem>)}
                </Select>
              </Stack>
            )}

            {view === "overview" && g.days.some((d) => d.is_weekend) && (
              <FormControlLabel control={<Switch size="small" checked={wd} onChange={(e) => setWd(e.target.checked)} />} label="Chỉ T2–T6" />
            )}
            {view === "day" && (
              <FormControl size="small" sx={{ minWidth: 150 }}>
                <Select value={date || ""} onChange={(e) => setDate(e.target.value)}>
                  {g.days.map((d) => <MenuItem key={d.date} value={d.date}>{WD_FULL[d.weekday]} · {fmtDate(d.date)}</MenuItem>)}
                </Select>
              </FormControl>
            )}
            {view !== "finder" && av.length > 1 && (
              <FormControl size="small" sx={{ minWidth: 120 }}>
                <Select value={sport} onChange={(e) => setSport(e.target.value)}>
                  {[...av, "all"].map((x) => <MenuItem key={x} value={x}>{SPORT_LABEL[x] || x}</MenuItem>)}
                </Select>
              </FormControl>
            )}
          </Stack>

          {view !== "finder" && (
            <Stack direction="row" flexWrap="wrap" gap={2} sx={{ mt: 1.5 }}>
              {[["free", "Trống"], ["booked", "Đã đặt"], ["locked", "Khoá"], ["event", "Sự kiện"]].map(([k, l]) => (
                <Stack key={k} direction="row" gap={0.75} alignItems="center">
                  <Box sx={{ ...cell(k), width: 15, height: 15 }} />
                  <Typography variant="caption" color="text.secondary">{l}</Typography>
                </Stack>
              ))}
            </Stack>
          )}
        </CardContent>
      </Card>

      {/* Board */}
      <Card>
        <CardContent>
          {view === "day" && <DayView {...{ g, date, slots, courts, range, cell, theme }} />}
          {view === "overview" && <OverView {...{ g, slots, courts, days, cell, onPick: (dt) => { setDate(dt); setView("day"); }, theme }} />}
          {view === "finder" && <Finder {...{ branches, finder, setFinder, timeOpts, onOpen: (branch, dt, r) => { const i = branches.findIndex((x) => x.branch === branch); if (i >= 0) setBi(i); setDate(dt); setRange(r); setView("day"); } }} />}
        </CardContent>
      </Card>
    </Stack>
  );
}

function DayView({ g, date, slots, courts, range, cell, theme }) {
  const onHour = (t) => t.endsWith(":00");
  const step = g.slot_minutes || 30;
  return (
    <Box sx={{ overflowX: "auto" }}>
      <Box sx={{ display: "inline-block", minWidth: "100%" }}>
        {/* trục giờ */}
        <Stack direction="row" sx={{ pl: "80px", mb: 0.5 }}>
          {slots.map((s, i) => (
            <Box key={s} sx={{ width: 33, position: "relative", height: 16 }}>
              {onHour(s) && <Typography variant="caption" sx={{ position: "absolute", bottom: 0, left: 0, transform: i === 0 ? "none" : "translateX(-50%)", fontSize: 11, color: "text.secondary", fontWeight: 600 }}>{s}</Typography>}
              {i === slots.length - 1 && onHour(addMin(s, step)) && <Typography variant="caption" sx={{ position: "absolute", bottom: 0, right: 0, fontSize: 11, color: "text.secondary", fontWeight: 600 }}>{addMin(s, step)}</Typography>}
            </Box>
          ))}
        </Stack>
        {courts.map((c) => (
          <Stack key={c} direction="row" alignItems="center" sx={{ mb: "3px" }}>
            <Typography sx={{ width: 76, pr: 1, textAlign: "right", fontSize: 12, fontWeight: 600, color: "text.secondary", flex: "0 0 auto" }}>{c}</Typography>
            <Stack direction="row" gap="3px">
              {slots.map((s) => {
                const st = statusG(g, c, date, s);
                const pr = priceAt(g, c, date, s);
                return (
                  <Tooltip key={s} arrow title={<span><b>{c}</b> · {s}<br />{STLABEL[st]}{pr != null ? ` · ${fmtPrice(pr)}/giờ` : ""}</span>}>
                    <Box sx={{ ...cell(st), cursor: "default", "&::after": st === "free" ? { content: '""', position: "absolute", inset: 0, margin: "auto", width: 7, height: 7, borderRadius: "50%", bgcolor: theme.palette.success.main } : st === "booked" ? { content: '""', position: "absolute", inset: "6px", borderRadius: "3px", bgcolor: theme.palette.error.main, opacity: 0.55 } : st === "event" ? { content: '"★"', position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center", color: theme.palette.secondary.main, fontSize: 12 } : {} }} />
                  </Tooltip>
                );
              })}
            </Stack>
          </Stack>
        ))}
        {/* hàng trống/khung */}
        <Stack direction="row" alignItems="center" sx={{ mt: "3px" }}>
          <Typography sx={{ width: 76, pr: 1, textAlign: "right", fontSize: 12, fontWeight: 700, color: "success.main", flex: "0 0 auto" }}>Trống</Typography>
          <Stack direction="row" gap="3px">
            {slots.map((s) => { const n = courts.filter((c) => statusG(g, c, date, s) === "free").length; return <Box key={s} sx={{ width: 30, textAlign: "center", fontSize: 12, fontWeight: 700, color: n ? "success.main" : "text.disabled" }}>{n || "·"}</Box>; })}
          </Stack>
        </Stack>
      </Box>
      {(() => { const rng = priceRange(g, courts, date, slots); return rng ? <Typography variant="body2" color="text.secondary" sx={{ mt: 1.5 }}>💵 Giá {range.start}–{range.end}: <b>{rng}/giờ</b>{rng.includes("–") ? " (nhiều mức — rê chuột từng ô)" : ""}</Typography> : null; })()}
    </Box>
  );
}

function OverView({ g, slots, courts, days, onPick, theme }) {
  const hours = [...new Set(slots.map((s) => s.slice(0, 2)))].map((h) => ({ h, slots: slots.filter((s) => s.slice(0, 2) === h) }));
  const segColor = (st) => st === "free" ? theme.palette.success.main : st === "booked" ? theme.palette.error.main : st === "event" ? theme.palette.secondary.main : theme.palette.text.disabled;
  return (
    <Box sx={{ overflowX: "auto" }}>
      <Box sx={{ display: "inline-block", minWidth: "100%" }}>
        <Stack direction="row" sx={{ pl: "80px", mb: 0.5 }}>
          {days.map((d) => <Box key={d.date} sx={{ width: 64, textAlign: "center", flex: "0 0 auto" }}><Typography variant="caption" sx={{ fontWeight: 600, color: d.is_weekend ? "text.disabled" : "text.secondary", display: "block", lineHeight: 1.1 }}>{d.weekday}<br /><span style={{ opacity: 0.7 }}>{fmtDate(d.date)}</span></Typography></Box>)}
        </Stack>
        {courts.map((c) => (
          <Stack key={c} direction="row" alignItems="center" sx={{ mb: "4px" }}>
            <Typography sx={{ width: 76, pr: 1, textAlign: "right", fontSize: 12, fontWeight: 600, color: "text.secondary", flex: "0 0 auto" }}>{c}</Typography>
            {days.map((d) => {
              const segs = hours.map((hb) => { const sts = hb.slots.map((s) => statusG(g, c, d.date, s)); return sts.includes("booked") ? "booked" : sts.includes("locked") ? "locked" : sts.includes("event") ? "event" : sts.every((x) => x === "free") ? "free" : "booked"; });
              const freeH = segs.filter((x) => x === "free").length;
              return (
                <Tooltip key={d.date} arrow title={<span><b>{c}</b> · {WD_FULL[d.weekday]} {fmtDate(d.date)}<br />{freeH}/{hours.length} giờ trống</span>}>
                  <Box onClick={() => onPick(d.date)} sx={{ width: 64, px: 0.5, flex: "0 0 auto", cursor: "pointer" }}>
                    <Stack direction="row" gap="1.5px" sx={{ height: 15, borderRadius: 1, overflow: "hidden" }}>
                      {segs.map((st, i) => <Box key={i} sx={{ flex: 1, minWidth: 3, bgcolor: segColor(st) }} />)}
                    </Stack>
                    <Typography sx={{ textAlign: "center", fontSize: 10.5, fontWeight: 700, color: freeH ? "success.main" : "text.secondary", mt: "2px", lineHeight: 1 }}>{freeH}<span style={{ fontWeight: 500, opacity: 0.6 }}>/{hours.length}</span></Typography>
                  </Box>
                </Tooltip>
              );
            })}
          </Stack>
        ))}
      </Box>
      <Typography variant="body2" color="text.secondary" sx={{ mt: 1.5 }}>Mỗi ô = buổi tối một sân, chia theo <b>giờ</b>: xanh = trống, đỏ = đã đặt, xám = khoá. Số = <b>giờ trống/tổng</b>. Bấm ô để xem chi tiết ngày.</Typography>
    </Box>
  );
}

function Finder({ branches, finder, setFinder, timeOpts, onOpen }) {
  const toggleDay = (i) => setFinder((f) => ({ ...f, days: f.days.includes(i) ? f.days.filter((x) => x !== i) : [...f.days, i] }));
  const found = [];
  branches.forEach((g) => {
    const m = g.court_sport || {}; const bad = g.courts.filter((c) => (m[c] || "badminton") === "badminton"); const courts = bad.length ? bad : g.courts;
    const slots = g.slots.filter((s) => s >= finder.start && s < finder.end);
    g.days.forEach((d) => {
      if (!finder.days.includes(WDX.indexOf(d.weekday))) return;
      const freeSlots = slots.filter((s) => courts.some((c) => statusG(g, c, d.date, s) === "free"));
      if (!freeSlots.length) return;
      let mx = 0; freeSlots.forEach((s) => { const n = courts.filter((c) => statusG(g, c, d.date, s) === "free").length; if (n > mx) mx = n; });
      found.push({ date: d.date, weekday: d.weekday, branch: g.branch, name: g.branch_name, freeSlots, maxFree: mx });
    });
  });
  found.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : a.name.localeCompare(b.name)));
  const nDays = [...new Set(found.map((r) => r.date))].length;
  let cur = "";
  return (
    <Box>
      <Typography variant="subtitle1">Tìm slot theo khung yêu thích</Typography>
      <Typography variant="body2" color="text.secondary">Chọn thứ + khung giờ → mọi ngày sắp tới còn sân trống (mọi sân theo dõi), để đặt sớm.</Typography>
      <Stack direction="row" flexWrap="wrap" gap={2} alignItems="flex-end" sx={{ mt: 2 }}>
        <Box>
          <Typography variant="caption" color="text.secondary">Thứ</Typography>
          <Stack direction="row" gap={0.75} flexWrap="wrap" sx={{ mt: 0.5 }}>
            {WDX.map((w, i) => <Chip key={w} label={w} color={finder.days.includes(i) ? "primary" : "default"} variant={finder.days.includes(i) ? "filled" : "outlined"} onClick={() => toggleDay(i)} size="small" />)}
          </Stack>
        </Box>
        <Box>
          <Typography variant="caption" color="text.secondary" sx={{ display: "block" }}>Khung giờ</Typography>
          <Stack direction="row" gap={1} alignItems="center" sx={{ mt: 0.5 }}>
            <Select size="small" value={finder.start} onChange={(e) => setFinder({ ...finder, start: e.target.value })}>{timeOpts.slice(0, -1).map((t) => <MenuItem key={t} value={t}>{t}</MenuItem>)}</Select>
            <Typography variant="body2">–</Typography>
            <Select size="small" value={finder.end} onChange={(e) => setFinder({ ...finder, end: e.target.value })}>{timeOpts.slice(1).map((t) => <MenuItem key={t} value={t}>{t}</MenuItem>)}</Select>
          </Stack>
        </Box>
      </Stack>
      <Box sx={{ mt: 2 }}>
        {!found.length && <Typography variant="body2" color="text.secondary">Không có slot trống trong khung đã chọn — thử nới khung giờ hoặc thêm thứ.</Typography>}
        {found.length > 0 && <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>Có chỗ trong <b>{nDays}</b> ngày · khung {finder.start}–{finder.end}. Bấm một dòng để mở chi tiết.</Typography>}
        {found.map((r) => {
          const head = r.date !== cur ? (cur = r.date, true) : false;
          return (
            <Box key={r.branch + r.date}>
              {head && <Typography variant="overline" color="text.secondary" sx={{ display: "block", mt: 2.5 }}>{WD_FULL[r.weekday] || r.weekday} · {fmtDate(r.date)}</Typography>}
              <Stack direction="row" gap={1.25} alignItems="center" flexWrap="wrap" sx={{ mt: 0.75, cursor: "pointer", py: 1, px: 1.5, borderRadius: 1.5, border: (t) => `1px dashed ${t.palette.divider}`, transition: "all .15s", "&:hover": { bgcolor: "action.hover", borderColor: "primary.main" } }} onClick={() => onOpen(r.branch, r.date, { start: finder.start, end: finder.end })}>
                <Typography sx={{ minWidth: 170, fontWeight: 600 }} variant="body2">{r.name}</Typography>
                <Stack direction="row" gap={0.75} flexWrap="wrap">{r.freeSlots.map((s) => <Label key={s} color="success" sx={{ fontFamily: "'Roboto Mono', monospace" }}>{s}</Label>)}</Stack>
                <Label color={r.maxFree > 1 ? "primary" : "warning"} variant="inverted">tối đa {r.maxFree} sân</Label>
              </Stack>
            </Box>
          );
        })}
      </Box>
    </Box>
  );
}

// Bảng quản trị: cào lại dữ liệu sân (gửi lệnh qua Vercel → server cào).
function CrawlPanel({ pass, stamp, reload }) {
  const theme = useTheme();
  const [st, setSt] = useState(null);
  const [busy, setBusy] = useState(false);
  const [toast, setToast] = useState("");
  const [logOpen, setLogOpen] = useState(false);
  const wasRunning = useRef(false);

  // Poll trạng thái cào: 2s khi đang chạy, 15s khi nghỉ. Xong thì nạp lại data.
  useEffect(() => {
    let alive = true, tid;
    const tick = async () => {
      let s = null; try { s = await api.getCourtsStatus(); } catch { /* */ }
      if (!alive) return;
      if (s) setSt(s);
      if (s && !s.running && wasRunning.current) { wasRunning.current = false; reload().catch(() => {}); setToast("Cào xong — dữ liệu mới."); }
      if (s) wasRunning.current = s.running;
      tid = setTimeout(tick, s && s.running ? 2000 : 15000);
    };
    tick();
    return () => { alive = false; clearTimeout(tid); };
  }, [reload]);

  const run = async () => {
    setBusy(true);
    try { await api.triggerCrawl(pass.current); wasRunning.current = true; setToast("Đã gửi lệnh cào…"); setTimeout(async () => { try { setSt(await api.getCourtsStatus()); } catch { /* */ } }, 800); }
    catch (e) { setToast("Lỗi cào: " + (e.message || e)); }
    finally { setBusy(false); }
  };

  const cov = st?.coverage, running = !!st?.running, tracking = !!cov?.tracking;
  const bcov = cov?.branches || [];
  const cellTot = bcov.reduce((n, b) => n + b.total, 0);
  const haveTot = bcov.reduce((n, b) => n + b.have, 0);
  const freshTot = bcov.reduce((n, b) => n + (b.fresh || 0), 0);
  const auto = st?.auto || {};
  const dayCell = (d) => {
    if (!d.has) return { bgcolor: alpha(theme.palette.error.main, 0.14), color: theme.palette.error.dark };
    if (tracking && d.fresh) return { bgcolor: alpha(theme.palette.success.main, 0.2), color: theme.palette.success.dark, boxShadow: `inset 0 0 0 1.5px ${theme.palette.success.main}` };
    if (tracking) return { bgcolor: alpha(theme.palette.text.disabled, 0.14), color: theme.palette.text.secondary, opacity: 0.6 };
    return { bgcolor: alpha(theme.palette.success.main, 0.14), color: theme.palette.success.dark };
  };
  const legendItem = (bg, ring, label) => (
    <Stack direction="row" spacing={0.5} alignItems="center"><Box sx={{ width: 14, height: 14, borderRadius: 0.5, bgcolor: bg, boxShadow: ring }} /><Typography variant="caption" color="text.secondary">{label}</Typography></Stack>
  );

  return (
    <Stack spacing={2}>
      <Card sx={{ p: 2 }}>
        <Stack direction="row" alignItems="center" spacing={1.5} flexWrap="wrap" useFlexGap>
          <Box sx={{ width: 40, height: 40, borderRadius: 1.5, display: "grid", placeItems: "center", bgcolor: (t) => alpha(t.palette.primary.main, 0.1), color: "primary.main", flexShrink: 0 }}>
            {running ? <CircularProgress size={22} /> : <Iconify icon="solar:refresh-circle-bold-duotone" width={24} />}
          </Box>
          <Box sx={{ flexGrow: 1, minWidth: 0 }}>
            <Typography variant="subtitle1" sx={{ lineHeight: 1.2 }}>Cào dữ liệu sân</Typography>
            <Typography variant="caption" color="text.secondary">
              Lần gần nhất: {cov?.last_data_age || stamp} · {auto.enabled ? <Box component="span" sx={{ color: "success.main" }}>tự động mỗi {auto.interval_min}′</Box> : "cào tay"}
            </Typography>
          </Box>
          <Button variant="contained" disabled={busy || running} onClick={run} startIcon={<Iconify icon="solar:refresh-bold" width={18} />}>{running ? "Đang cào…" : "Cào lại ngay"}</Button>
        </Stack>

        {cellTot > 0 && (
          <Box sx={{ mt: 2 }}>
            <Stack direction="row" spacing={1.5} alignItems="center" flexWrap="wrap" useFlexGap sx={{ mb: 1 }}>
              {running && <Typography variant="body2" sx={{ color: "primary.main", fontWeight: 600 }}>Đang cào…</Typography>}
              <Typography variant="body2" color="text.secondary">
                {tracking ? <>Lượt này cập nhật <Box component="b" sx={{ color: "success.main" }}>{freshTot}</Box>/{cellTot} ô</> : <>{haveTot}/{cellTot} ô có dữ liệu</>}
              </Typography>
              <Box flexGrow={1} />
              {tracking && (<Stack direction="row" spacing={1.5}>
                {legendItem(alpha(theme.palette.success.main, 0.2), `inset 0 0 0 1.5px ${theme.palette.success.main}`, "vừa cào")}
                {legendItem(alpha(theme.palette.text.disabled, 0.14), "none", "data cũ")}
                {legendItem(alpha(theme.palette.error.main, 0.14), "none", "chưa có")}
              </Stack>)}
            </Stack>
            <Box sx={{ overflowX: "auto" }}>
              {bcov.map((b) => (
                <Box key={b.branch} sx={{ mb: 1.5 }}>
                  <Typography variant="caption" sx={{ fontWeight: 600 }}>{b.branch}</Typography>
                  <Typography component="span" variant="caption" color="text.secondary"> — {b.have}/{b.total} ngày{tracking && b.fresh ? ` · ${b.fresh} vừa cào` : ""} · khoá {b.aux?.locks?.has ? b.aux.locks.age : "chưa"} · sân {b.aux?.cores?.has ? b.aux.cores.age : "chưa"}</Typography>
                  <Stack direction="row" gap="4px" sx={{ mt: 0.5 }}>
                    {(b.days || []).map((d) => (
                      <Tooltip key={d.date} arrow title={`${d.date} · ${d.has ? (tracking && d.fresh ? "vừa cào " + d.age : "data cũ · " + d.age) : "chưa có"}`}>
                        <Box sx={{ width: 42, height: 34, borderRadius: 0.75, display: "grid", placeItems: "center", textAlign: "center", lineHeight: 1, flexShrink: 0, ...dayCell(d) }}>
                          <Box><Typography sx={{ fontSize: 10, fontWeight: 600 }}>{d.weekday}</Typography><Typography sx={{ fontSize: 10 }}>{d.date.slice(8)}</Typography></Box>
                        </Box>
                      </Tooltip>
                    ))}
                  </Stack>
                </Box>
              ))}
            </Box>
          </Box>
        )}

        {st?.log_tail && (<Box sx={{ mt: 1.5 }}>
          <Button size="small" color="inherit" onClick={() => setLogOpen((v) => !v)} startIcon={<Iconify icon={logOpen ? "solar:alt-arrow-up-bold" : "solar:alt-arrow-down-bold"} width={16} />}>Log lần cào gần nhất{st.finished ? ` · xong ${st.finished.slice(11, 16)}${st.returncode ? " (lỗi " + st.returncode + ")" : " ✓"}` : ""}</Button>
          <Collapse in={logOpen}><Box component="pre" sx={{ mt: 1, p: 1.5, borderRadius: 1.5, bgcolor: "background.neutral", fontSize: 11, lineHeight: 1.6, overflow: "auto", maxHeight: 300, whiteSpace: "pre-wrap", fontFamily: "'Roboto Mono', monospace" }}>{st.log_tail}</Box></Collapse>
        </Box>)}

        {!cellTot && !running && <Typography variant="caption" color="text.secondary" sx={{ display: "block", mt: 1.5 }}>Chưa có sân nào được cấu hình để cào — vào tab Cấu hình để thêm.</Typography>}
      </Card>
      <Snackbar open={!!toast} autoHideDuration={3500} onClose={() => setToast("")} message={toast} anchorOrigin={{ vertical: "bottom", horizontal: "center" }} />
    </Stack>
  );
}

// Cấu hình sân cho admin: số ngày cào + chọn sân theo dõi (ghi vào config.json của crawler).
function CourtsSettings({ pass }) {
  const [dir, setDir] = useState(null);
  const [days, setDays] = useState(21);
  const [sel, setSel] = useState(() => new Set());
  const [extra, setExtra] = useState([]);   // sân nhập tay chưa có trong danh bạ
  const [newId, setNewId] = useState("");
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState("");
  useEffect(() => {
    Promise.all([api.getCourtsDirectory().catch(() => null), api.getCourtsConfig().catch(() => null)])
      .then(([d, c]) => {
        if (d) { setDir(d); setSel(new Set((d.branches || []).filter((b) => b.monitored).map((b) => b.id))); }
        else setErr("Không đọc được danh bạ sân — backend/crawler chưa sẵn sàng hoặc chưa set VITE_API_BASE.");
        if (c) setDays(c.days_window || c.days_ahead || 21);
      });
  }, []);
  const toggle = (id) => setSel((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n; });
  const addBranch = () => {
    const id = newId.trim().toLowerCase();
    if (!/^[a-z0-9_-]{2,80}$/.test(id)) { setMsg('branchId không hợp lệ (vd sport_xyz_badminton)'); return; }
    const known = (dir?.branches || []).some((b) => b.id === id) || extra.some((b) => b.id === id);
    if (!known) setExtra((e) => [{ id, name: id, sport: "", has_data: false, custom: true }, ...e]);
    setSel((s) => new Set(s).add(id)); setNewId(""); setMsg("");
  };
  const removeExtra = (id) => { setExtra((e) => e.filter((b) => b.id !== id)); setSel((s) => { const n = new Set(s); n.delete(id); return n; }); };
  const save = async () => {
    setBusy(true); setMsg("Đang lưu…");
    try { const r = await api.saveCourtsConfig(pass.current, [...sel], Math.max(1, Math.min(60, +days || 21))); setMsg(`✓ Đã lưu ${(r.branches || []).length} sân · ${r.days_window} ngày. Vào tab Cào để chạy.`); }
    catch (e) { setMsg("Lỗi: " + (e.message || e)); }
    finally { setBusy(false); }
  };
  const list = [...extra, ...(dir?.branches || [])];
  return (
    <Card sx={{ p: 2.5 }}>
      <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 2 }}>
        <Iconify icon="solar:settings-bold-duotone" sx={{ color: "text.secondary" }} />
        <Typography variant="subtitle1">Cấu hình sân theo dõi</Typography>
      </Stack>
      <Stack direction="row" spacing={1} alignItems="center" sx={{ mb: 2 }}>
        <Typography variant="body2" color="text.secondary">Số ngày cào từ hôm nay:</Typography>
        <Select size="small" value={days} onChange={(e) => setDays(e.target.value)} sx={{ width: 90 }}>
          {[7, 10, 14, 21, 30, 45, 60].map((n) => <MenuItem key={n} value={n}>{n}</MenuItem>)}
        </Select>
        <Typography variant="caption" color="text.secondary">gồm cả T7/CN</Typography>
      </Stack>
      {err && <Alert severity="warning" sx={{ mb: 2 }}>{err}</Alert>}
      {!dir && !err ? <Box sx={{ display: "grid", placeItems: "center", py: 3 }}><CircularProgress size={24} /></Box> : (<>
        <Typography variant="caption" color="text.secondary" sx={{ display: "block", mb: 1 }}>Bật = theo dõi &amp; cào. Tắt = ngừng cào sân đó.</Typography>
        <Stack divider={<Box sx={{ borderBottom: (t) => `1px solid ${t.palette.divider}` }} />}>
          {list.map((b) => (
            <Stack key={b.id} direction="row" alignItems="center" spacing={1} sx={{ py: 0.75 }}>
              <Switch size="small" checked={sel.has(b.id)} onChange={() => toggle(b.id)} />
              <Box sx={{ flexGrow: 1, minWidth: 0 }}>
                <Typography variant="body2" sx={{ fontWeight: 600, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{b.name}</Typography>
                <Typography variant="caption" color="text.secondary">{b.id}{b.sport ? " · " + b.sport : ""}</Typography>
              </Box>
              <Label color={b.has_data ? "success" : "default"} variant={b.has_data ? "soft" : "outlined"}>{b.has_data ? "có dữ liệu" : "chưa có"}</Label>
              {b.custom && <Tooltip title="Bỏ khỏi danh sách"><IconButton size="small" color="error" onClick={() => removeExtra(b.id)}><Iconify icon="solar:close-circle-bold" width={18} /></IconButton></Tooltip>}
            </Stack>
          ))}
          {list.length === 0 && <Typography variant="body2" color="text.secondary" sx={{ py: 2 }}>Danh bạ trống — thêm branchId bên dưới.</Typography>}
        </Stack>
        <Stack direction="row" spacing={1} sx={{ mt: 2 }}>
          <TextField size="small" fullWidth placeholder="Thêm branchId (vd sport_xyz_badminton)" value={newId}
            onChange={(e) => setNewId(e.target.value)} onKeyDown={(e) => e.key === "Enter" && addBranch()} />
          <Button variant="outlined" onClick={addBranch} sx={{ flexShrink: 0 }}>Thêm</Button>
        </Stack>
      </>)}
      <Stack direction="row" spacing={1.5} alignItems="center" sx={{ mt: 2 }}>
        <Button variant="contained" disabled={busy || !dir} onClick={save}>Lưu cấu hình</Button>
        {msg && <Typography variant="caption" color={/Lỗi|hợp lệ/.test(msg) ? "error" : "text.secondary"}>{msg}</Typography>}
      </Stack>
    </Card>
  );
}
