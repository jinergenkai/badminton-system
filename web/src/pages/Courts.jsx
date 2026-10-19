// Sân trống — port bản xem công khai từ _legacy/courts.html sang MUI.
// 3 view: Theo ngày (sân × giờ), Tổng quan (sân × ngày, mini-timeline), Tìm slot (đa sân).
// Dữ liệu do crawler đẩy lên /api/courts (nén occ theo sân×ngày) → giải nén về shape viz.
import { useEffect, useMemo, useRef, useState } from "react";
import {
  Box, Card, CardContent, Stack, Typography, Select, MenuItem, FormControl,
  ToggleButton, ToggleButtonGroup, Switch, FormControlLabel, Chip, Tooltip,
  CircularProgress, Alert, useMediaQuery,
} from "@mui/material";
import { useTheme, alpha } from "@mui/material/styles";
import { api } from "../lib/api.js";

const WD_FULL = { T2: "Thứ 2", T3: "Thứ 3", T4: "Thứ 4", T5: "Thứ 5", T6: "Thứ 6", T7: "Thứ 7", CN: "Chủ nhật" };
const WDX = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"];
const SPORT_LABEL = { badminton: "Cầu lông", pickleball: "Pickleball", all: "Tất cả" };
const STLABEL = { free: "Trống", booked: "Đã đặt", locked: "Khoá (chờ mở)", event: "Sự kiện" };
const LS_KEY = "alobo_prefs_mui";

const fmtDate = (iso) => { const [, m, d] = iso.split("-"); return `${d}/${m}`; };
const addMin = (t, m) => { let [a, b] = t.split(":").map(Number); let x = a * 60 + b + m; return String(Math.floor(x / 60)).padStart(2, "0") + ":" + String(x % 60).padStart(2, "0"); };
function fmtPrice(n) { if (n == null) return ""; if (n >= 1e6) return (n / 1e6).toFixed(n % 1e6 ? 1 : 0) + "tr"; if (n >= 1000) return Math.round(n / 1000) + "k"; return "" + n; }

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

  useEffect(() => {
    api.getCourts().then((j) => {
      setUpdatedAt(j.updatedAt || null);
      setData(expandCourts(j.data || { branches: [], monitored: [] }));
    }).catch((e) => setErr(e.message || String(e)));
  }, []);

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
  if (!branches.length) return <Alert severity="info" sx={{ mt: 2 }}>Chưa có dữ liệu sân — máy cào chưa gửi lên lần nào.</Alert>;

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
  const stamp = updatedAt ? (() => { const t = new Date(updatedAt), mins = Math.max(0, Math.round((Date.now() - t) / 60000)); return mins < 1 ? "vừa xong" : mins < 60 ? mins + "′ trước" : mins < 2880 ? Math.round(mins / 60) + "h trước" : Math.round(mins / 1440) + " ngày trước"; })() : "chưa có dữ liệu";

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
      {/* KPIs */}
      <Box sx={{ display: "grid", gap: 1.5, gridTemplateColumns: { xs: "repeat(2,1fr)", sm: "repeat(4,1fr)" } }}>
        <Stat big={free} label={`ô trống ${range.start}–${range.end} (T2–T6)`} color="success.main" />
        <Stat big={`${daysFree}/${kdays.length}`} label="ngày T2–T6 có chỗ" />
        <Stat big={courts.length} label="sân" />
        <Stat big={bmp != null ? fmtPrice(bmp) : g.days.length} label={bmp != null ? "giá trần / giờ" : "ngày theo dõi"} color={bmp != null ? "primary.main" : undefined} />
      </Box>

      {/* Controls */}
      <Card>
        <CardContent sx={{ py: 2, "&:last-child": { pb: 2 } }}>
          <Stack direction="row" flexWrap="wrap" gap={1.5} alignItems="center">
            <Box sx={{ flexGrow: 1, minWidth: 0 }}>
              <Typography variant="h5" sx={{ lineHeight: 1 }}>{g.branch_name}</Typography>
              <Typography variant="caption" color="text.secondary">{g.days.length} ngày · {g.courts.length} sân · cào {stamp}</Typography>
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
            <ToggleButtonGroup exclusive size="small" value={view} onChange={(_, v) => v && setView(v)}>
              <ToggleButton value="day">Theo ngày</ToggleButton>
              <ToggleButton value="overview">Tổng quan</ToggleButton>
              <ToggleButton value="finder">🔍 Tìm slot</ToggleButton>
            </ToggleButtonGroup>

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

function Stat({ big, label, color }) {
  return (
    <Card sx={{ borderRadius: 2 }}>
      <CardContent sx={{ p: 2, "&:last-child": { pb: 2 } }}>
        <Typography variant="h3" sx={{ color: color || "text.primary", lineHeight: 1 }}>{big}</Typography>
        <Typography variant="caption" color="text.secondary">{label}</Typography>
      </CardContent>
    </Card>
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
              {head && <Typography variant="subtitle2" sx={{ mt: 2 }}>{WD_FULL[r.weekday] || r.weekday} · {fmtDate(r.date)}</Typography>}
              <Stack direction="row" gap={1.25} alignItems="center" flexWrap="wrap" sx={{ mt: 0.75, cursor: "pointer", py: 0.5 }} onClick={() => onOpen(r.branch, r.date, { start: finder.start, end: finder.end })}>
                <Typography sx={{ minWidth: 170, fontWeight: 600 }} variant="body2">{r.name}</Typography>
                <Stack direction="row" gap={0.75} flexWrap="wrap">{r.freeSlots.map((s) => <Chip key={s} label={s} size="small" color="success" variant="outlined" />)}</Stack>
                <Typography variant="caption" color="text.secondary">tối đa {r.maxFree} sân</Typography>
              </Stack>
            </Box>
          );
        })}
      </Box>
    </Box>
  );
}
