// Hồ sơ người chơi: phần đầu theo màu hạng, chỉ số, Elo theo trận, phong độ,
// huy hiệu (trận + sổ tiền), đồng đội ăn ý / khắc tinh, sổ tiền (công khai, không có nợ), trận gần đây.
// Mở ở bất cứ đâu: const open = useProfile(); open(p)  (p = {id, name?, elo?, avatar?...})
import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import {
  Box, Button, Card, CircularProgress, Dialog, IconButton, Stack, Typography, useMediaQuery,
} from "@mui/material";
import { alpha, useTheme } from "@mui/material/styles";

import { Iconify } from "../iconify/index.jsx";
import RankFrame from "../rank/RankFrame.jsx";
import Badge from "../badges/Badge.jsx";
import { api, todayVN } from "../../lib/api.js";
import { loadBookRO } from "../../lib/bookRO.js";
import { RANKS, rankOf } from "../../lib/ranks.js";
import { badgeList, bookStats, matchStats, showcase, upcoming, TIER_LABEL } from "../../lib/badges.js";
import * as M from "../../lib/model.js";

// màu phần đầu theo hạng: [nền tối, nền giữa, nhấn]
export const HERO = {
  dong: ["#1E1006", "#6B3E1C", "#E3A26B"],
  bac: ["#11161D", "#4E5968", "#DDE3EA"],
  vang: ["#2B1E02", "#7A5200", "#F2C94C"],
  "bach-kim": ["#04211C", "#0D5E50", "#6FE3C8"],
  "kim-cuong": ["#0B1640", "#1C3A94", "#7FA6FF"],
  "cao-thu": ["#2A0508", "#8A1A22", "#FF8A8A"],
};
const WIN = "#22C55E", LOSS = "#FF5630";

export const fmtSpent = (k) => (k >= 1000 ? (k / 1000).toFixed(2).replace(/\.?0+$/, "").replace(".", ",") + "tr" : M.numStr(Math.round(k)) + "k");

const Ctx = createContext(() => {});
export const useProfile = () => useContext(Ctx);

export function ProfileProvider({ children }) {
  const [who, setWho] = useState(null);
  const theme = useTheme();
  const full = useMediaQuery(theme.breakpoints.down("sm"));
  const open = useCallback((p) => p?.id && setWho(p), []);
  return (
    <Ctx.Provider value={open}>
      {children}
      <Dialog open={!!who} onClose={() => setWho(null)} fullScreen={full} fullWidth maxWidth="xs"
        PaperProps={{ sx: { bgcolor: "background.default", ...(full ? {} : { borderRadius: 3 }) } }}>
        {who && <ProfileView key={who.id} seed={who} onClose={() => setWho(null)} />}
      </Dialog>
    </Ctx.Provider>
  );
}

/** Dữ liệu hồ sơ: trận (backend) + sổ tiền (đọc-chỉ). Mỗi nguồn lỗi riêng, không kéo nhau chết. */
export function useProfileData(id) {
  const [prof, setProf] = useState(undefined); // undefined = đang tải, null = không có
  const [book, setBook] = useState(undefined);
  useEffect(() => {
    let live = true;
    api.getProfile(id).then((j) => live && setProf(j)).catch(() => live && setProf(null));
    loadBookRO().then((b) => live && setBook(b || null)).catch(() => live && setBook(null));
    return () => { live = false; };
  }, [id]);
  return useMemo(() => {
    const ms = prof ? matchStats(prof) : null;
    const bs = book ? bookStats(book, id) : null;
    const list = badgeList({ ...(ms?.values || {}), ...(bs?.values || {}) });
    return { prof, book, ms, bs, list, loading: prof === undefined || book === undefined };
  }, [prof, book, id]);
}

function ProfileView({ seed, onClose }) {
  const { prof, book, ms, bs, list, loading } = useProfileData(seed.id);
  const mem = book ? M.memById(book, seed.id) : null;
  const p = { ...seed, ...(mem ? { name: mem.name, avatar: seed.avatar || mem.av } : {}), ...(prof?.player || {}) };
  if (!p.avatar && mem?.av) p.avatar = mem.av;
  const people = prof?.people || {};
  const nameOf = (id) => people[id]?.short || people[id]?.name || (book && M.memById(book, id)?.name) || "?";
  const [allMatches, setAllMatches] = useState(false);
  const [allBadges, setAllBadges] = useState(false);
  const top = showcase(list, 4), soon = upcoming(list, 2);
  const nEarned = list.filter((b) => b.level > 0).length;
  const recent = (prof?.matches || []).slice().reverse();

  return (
    <Box sx={{ p: { xs: 1.5, sm: 2 }, pb: 4 }}>
      <Hero p={p} ms={ms} onClose={onClose} />
      {loading && <Box sx={{ display: "grid", placeItems: "center", py: 4 }}><CircularProgress size={28} /></Box>}

      {ms && ms.played > 0 && (
        <Sec>
          <Stack direction="row">
            <Stat v={ms.played} l="Trận" />
            <Stat v={ms.winRate + "%"} l="Thắng" c="primary.main" />
            <Stat v={ms.streak ? <><Iconify icon="solar:fire-bold" width={18} sx={{ color: "#FF7A1A", mr: 0.25 }} />{ms.streak}</> : "–"} l="Chuỗi thắng" c="warning.dark" />
            <Stat v={Math.round(ms.peak)} l="Đỉnh Elo" />
          </Stack>
        </Sec>
      )}

      {ms && ms.elo.length > 2 && <Sec title="Elo theo trận" sub={`${ms.played} trận`}><EloChart elo={ms.elo} /></Sec>}

      {ms && ms.form.length > 0 && (
        <Sec title="Phong độ" sub={`${ms.form.length} trận gần nhất`}>
          <Stack direction="row" spacing={0.6}>
            {ms.form.map((w, i) => (
              <Box key={i} sx={{ flex: 1, maxWidth: 40, height: 28, borderRadius: 0.9, display: "grid", placeItems: "center", fontSize: 11, fontWeight: 800, color: "#fff", bgcolor: w ? WIN : LOSS }}>{w ? "T" : "B"}</Box>
            ))}
          </Stack>
        </Sec>
      )}

      {!loading && (
        <Sec title="Huy hiệu" sub={<Box component="span" onClick={() => setAllBadges((v) => !v)} sx={{ cursor: "pointer", color: "primary.main", fontWeight: 600 }}>{nEarned}/{list.length} · {allBadges ? "Thu gọn" : "Xem tất cả"}</Box>}>
          {allBadges ? <BadgeGrid list={list} /> : (<>
            {top.length > 0 ? (
              <Stack direction="row" justifyContent={top.length < 4 ? "flex-start" : "space-between"} spacing={top.length < 4 ? 2 : 0}>
                {top.map((b) => (
                  <Box key={b.key} sx={{ width: 74, textAlign: "center" }}>
                    <Badge k={b.key} tier={b.tier} size={60} title={`${b.name} · ${TIER_LABEL[b.tier]}`} sx={{ mx: "auto" }} />
                    <Typography sx={{ fontSize: 11.5, fontWeight: 700, lineHeight: 1.2, mt: 0.25 }}>{b.name}</Typography>
                    <Typography sx={{ fontSize: 10.5, color: "text.disabled" }}>{b.value} {b.unit}</Typography>
                  </Box>
                ))}
              </Stack>
            ) : <Typography variant="body2" color="text.secondary">Chưa có huy hiệu nào — đánh thêm vài trận nhé.</Typography>}
            {soon.map((b) => (
              <Stack key={b.key} direction="row" alignItems="center" spacing={1.25} sx={{ pt: 1.25, mt: 1.25, borderTop: (t) => `1px dashed ${t.palette.divider}` }}>
                <Badge k={b.key} tier={b.tier || "dong"} locked={!b.tier} size={40} />
                <Box sx={{ flex: 1, minWidth: 0 }}>
                  <Typography variant="subtitle2">{b.name}</Typography>
                  <Box sx={{ height: 6, borderRadius: 1, bgcolor: (t) => alpha(t.palette.grey[500], 0.16), my: 0.5, overflow: "hidden" }}>
                    <Box sx={{ width: `${Math.min(100, (b.value / b.next) * 100)}%`, height: 1, borderRadius: 1, bgcolor: "primary.main" }} />
                  </Box>
                  <Typography variant="caption" color="text.secondary">{b.value}/{b.next} {b.unit} → {TIER_LABEL[["dong", "bac", "vang", "kim-cuong"][b.level]]}</Typography>
                </Box>
              </Stack>
            ))}
          </>)}
        </Sec>
      )}

      {ms && (ms.bestPartner || ms.nemesis) && (
        <Sec>
          <Stack direction="row" spacing={1.25}>
            {ms.bestPartner && <Duo title="Đồng đội ăn ý" color="primary" pid={ms.bestPartner.id} people={people} name={nameOf(ms.bestPartner.id)}
              line={`${ms.bestPartner.n} trận · thắng ${Math.round((ms.bestPartner.w / ms.bestPartner.n) * 100)}%`} />}
            {ms.nemesis && <Duo title="Khắc tinh" color="error" pid={ms.nemesis.id} people={people} name={nameOf(ms.nemesis.id)}
              line={`thua ${ms.nemesis.l}/${ms.nemesis.n} lần gặp`} />}
          </Stack>
        </Sec>
      )}

      {bs && (bs.plays > 0 || bs.meals > 0) && (
        <Sec title="Sổ tiền" sub={bs.recentOf ? `có mặt ${bs.recentIn}/${bs.recentOf} buổi gần nhất` : ""}>
          <Stack direction="row" spacing={1}>
            <Tile l="Buổi cầu" v={bs.plays} />
            <Tile l="Kèo ăn" v={bs.meals} />
            <Tile l="Đã chi" v={fmtSpent(bs.spent)} color="warning" />
          </Stack>
        </Sec>
      )}

      {recent.length > 0 && (
        <Sec title="Trận gần đây" sub={recent.length > 5 && <Box component="span" onClick={() => setAllMatches((v) => !v)} sx={{ cursor: "pointer", color: "primary.main", fontWeight: 600 }}>{allMatches ? "Thu gọn" : `Xem tất cả ${recent.length}`}</Box>}>
          {(allMatches ? recent : recent.slice(0, 5)).map((m) => (
            <Stack key={m.id} direction="row" alignItems="center" spacing={1.25} sx={{ py: 1.1, borderTop: (t) => `1px dashed ${t.palette.divider}`, "&:first-of-type": { borderTop: 0, pt: 0 } }}>
              <Box sx={{ width: 4, alignSelf: "stretch", borderRadius: 1, bgcolor: m.won ? WIN : LOSS }} />
              <Box sx={{ flex: 1, minWidth: 0 }}>
                <Typography variant="body2" fontWeight={600} noWrap>
                  {m.partners.length ? <>cùng {m.partners.map(nameOf).join(" · ")} </> : null}
                  <Box component="span" sx={{ color: "text.disabled", fontWeight: 400 }}>vs</Box> {m.opponents.map(nameOf).join(" · ")}
                </Typography>
                <Typography variant="caption" color="text.disabled">{whenLabel(m.played_at)}</Typography>
              </Box>
              <Box sx={{ textAlign: "right" }}>
                <Typography sx={{ fontFamily: (t) => t.typography.fontSecondaryFamily, fontWeight: 800, fontSize: 15 }}>{m.score}–{m.opp_score}</Typography>
                <Typography sx={{ fontSize: 12, fontWeight: 700, color: m.won ? WIN : LOSS }}>{m.delta > 0 ? "+" : ""}{Math.round(m.delta)}</Typography>
              </Box>
            </Stack>
          ))}
        </Sec>
      )}

      {!loading && prof === null && !bs && <Typography variant="body2" color="text.secondary" sx={{ textAlign: "center", mt: 3 }}>Chưa có dữ liệu của người này.</Typography>}
    </Box>
  );
}

function Hero({ p, ms, onClose }) {
  const rank = rankOf(p.elo);
  const [c0, c1, acc] = HERO[rank.key];
  const i = RANKS.findIndex((r) => r.key === rank.key);
  const next = RANKS[i + 1];
  const lo = Number.isFinite(rank.min) ? rank.min : (next ? next.min - 100 : 0);
  const elo = Math.round(Number(p.elo) || 1000);
  return (
    <Box sx={{ position: "relative", overflow: "hidden", borderRadius: 2.5, color: "#fff", px: 2.25, pt: 2.5, pb: 2.25,
      background: `radial-gradient(circle at 50% 28%, ${c1} 0%, ${c0} 68%)`, boxShadow: `0 12px 28px -8px ${alpha(c1, 0.6)}` }}>
      <Box component="svg" viewBox="0 0 360 300" preserveAspectRatio="none" aria-hidden sx={{ position: "absolute", inset: 0, width: 1, height: 1, opacity: 0.16 }}>
        <rect x="14" y="14" width="332" height="272" rx="6" fill="none" stroke="#fff" strokeWidth="1.5" strokeDasharray="6 6" />
        <line x1="180" y1="14" x2="180" y2="286" stroke="#fff" strokeWidth="1.5" strokeDasharray="6 6" />
        <line x1="14" y1="150" x2="346" y2="150" stroke="#fff" strokeWidth="1" strokeDasharray="3 6" />
      </Box>
      <Box sx={{ position: "absolute", left: "50%", top: 22, width: 190, height: 190, transform: "translateX(-50%)", borderRadius: "50%", background: `radial-gradient(${alpha(acc, 0.4)}, transparent 65%)`, filter: "blur(6px)" }} />
      <IconButton onClick={onClose} sx={{ position: "absolute", top: 8, right: 8, color: "#fff", bgcolor: "rgba(255,255,255,.12)", "&:hover": { bgcolor: "rgba(255,255,255,.22)" } }}>
        <Iconify icon="mingcute:close-line" width={20} />
      </IconButton>
      <Stack alignItems="center" sx={{ position: "relative" }}>
        <RankFrame p={p} size={140} />
        <Typography sx={{ fontWeight: 800, fontSize: 22, mt: 0.5, textAlign: "center", lineHeight: 1.25 }}>{p.name || "?"}</Typography>
        <Stack direction="row" spacing={0.75} alignItems="center" sx={{ mt: 0.75 }}>
          <Typography sx={{ fontSize: 11, fontWeight: 800, letterSpacing: 1.5, color: acc, textTransform: "uppercase" }}>{rank.label}</Typography>
          {p.host && <Box sx={{ fontSize: 11, fontWeight: 700, px: 1, py: 0.1, borderRadius: 2, bgcolor: "#256E4E", border: "1px solid #F2C94C", color: "#FFE8A3" }}>Host sân</Box>}
          {p.guest && <Box sx={{ fontSize: 11, fontWeight: 700, px: 1, py: 0.1, borderRadius: 2, bgcolor: "rgba(255,255,255,.14)" }}>Khách</Box>}
        </Stack>
        <Stack direction="row" alignItems="baseline" spacing={0.75} sx={{ mt: 0.5 }}>
          <Typography sx={{ fontFamily: (t) => t.typography.fontSecondaryFamily, fontWeight: 800, fontSize: 44, lineHeight: 1, textShadow: `0 2px 12px ${alpha(acc, 0.5)}` }}>{elo}</Typography>
          <Typography sx={{ fontSize: 12, opacity: 0.7 }}>Elo</Typography>
        </Stack>
      </Stack>
      <Box sx={{ position: "relative", mt: 1.75 }}>
        {next ? (<>
          <Stack direction="row" justifyContent="space-between" sx={{ fontSize: 12, opacity: 0.85 }}>
            <span>{rank.label}</span><span>còn <b>{Math.max(1, Math.ceil(next.min - (Number(p.elo) || 1000)))}</b> Elo lên {next.label}</span>
          </Stack>
          <Box sx={{ height: 6, borderRadius: 1, bgcolor: "rgba(255,255,255,.15)", mt: 0.75, overflow: "hidden" }}>
            <Box sx={{ width: `${Math.max(4, Math.min(100, ((elo - lo) / (next.min - lo)) * 100))}%`, height: 1, borderRadius: 1, background: `linear-gradient(90deg, ${alpha(acc, 0.65)}, ${acc})` }} />
          </Box>
        </>) : <Typography sx={{ fontSize: 12, opacity: 0.85 }}>Hạng cao nhất · giữ vững phong độ</Typography>}
        {ms && ms.played === 0 && <Typography sx={{ fontSize: 12, opacity: 0.75, mt: 0.75 }}>Chưa có trận nào được ghi.</Typography>}
      </Box>
    </Box>
  );
}

function Sec({ title, sub, children }) {
  return (
    <Card sx={{ p: 2, mt: 1.5 }}>
      {title && (
        <Stack direction="row" justifyContent="space-between" alignItems="baseline" sx={{ mb: 1.5 }}>
          <Typography variant="subtitle1">{title}</Typography>
          <Typography variant="caption" color="text.disabled" component="div">{sub}</Typography>
        </Stack>
      )}
      {children}
    </Card>
  );
}
function Stat({ v, l, c = "text.primary" }) {
  return (
    <Box sx={{ flex: 1, textAlign: "center" }}>
      <Typography component="div" sx={{ fontFamily: (t) => t.typography.fontSecondaryFamily, fontWeight: 800, fontSize: 20, color: c, display: "flex", justifyContent: "center", alignItems: "center" }}>{v}</Typography>
      <Typography variant="caption" color="text.secondary">{l}</Typography>
    </Box>
  );
}
function Tile({ l, v, color }) {
  return (
    <Box sx={{ flex: 1, borderRadius: 1.5, px: 1.25, py: 1, bgcolor: (t) => (color ? alpha(t.palette[color].main, 0.12) : t.palette.background.neutral || alpha(t.palette.grey[500], 0.08)) }}>
      <Typography variant="caption" color="text.secondary">{l}</Typography>
      <Typography sx={{ fontFamily: (t) => t.typography.fontSecondaryFamily, fontWeight: 800, fontSize: 18, color: color ? `${color}.dark` : "text.primary" }}>{v}</Typography>
    </Box>
  );
}
function Duo({ title, color, pid, people, name, line }) {
  const open = useProfile();
  const pp = people[pid] || { id: pid, name };
  return (
    <Box onClick={() => open(pp)} sx={{ flex: 1, cursor: "pointer", textAlign: "center", p: 1.25, borderRadius: 1.5,
      bgcolor: (t) => alpha(t.palette[color].main, 0.08), border: (t) => `1px dashed ${alpha(t.palette[color].main, 0.4)}` }}>
      <Typography sx={{ fontSize: 10, fontWeight: 800, letterSpacing: 1, textTransform: "uppercase", color: `${color}.main` }}>{title}</Typography>
      <RankFrame p={pp} size={60} sx={{ mx: "auto", my: 0.25 }} />
      <Typography variant="subtitle2" noWrap>{name}</Typography>
      <Typography variant="caption" color="text.secondary">{line}</Typography>
    </Box>
  );
}
function BadgeGrid({ list }) {
  return (
    <Box sx={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 1.5 }}>
      {list.map((b) => (
        <Box key={b.key} sx={{ textAlign: "center" }}>
          <Badge k={b.key} tier={b.tier || "dong"} locked={!b.tier} size={54} sx={{ mx: "auto" }} />
          <Typography sx={{ fontSize: 11.5, fontWeight: 700, lineHeight: 1.2, mt: 0.25 }}>{b.name}</Typography>
          <Typography sx={{ fontSize: 10.5, color: "text.secondary", lineHeight: 1.3 }}>
            {b.tier ? TIER_LABEL[b.tier] + " · " : ""}{b.known ? `${b.value}${b.next ? "/" + b.next : ""} ${b.unit}` : "chưa có dữ liệu"}
          </Typography>
          <Typography sx={{ fontSize: 10, color: "text.disabled", lineHeight: 1.3 }}>{b.desc}</Typography>
        </Box>
      ))}
    </Box>
  );
}

function EloChart({ elo }) {
  const theme = useTheme();
  const col = theme.palette.primary.main;
  const W = 330, H = 96;
  const lo = Math.min(...elo) - 8, hi = Math.max(...elo) + 8;
  const pts = elo.map((v, i) => [(i * W) / (elo.length - 1), H - ((v - lo) / (hi - lo)) * H]);
  const d = "M" + pts.map(([x, y]) => `${x.toFixed(1)} ${y.toFixed(1)}`).join(" L");
  const [lx, ly] = pts[pts.length - 1];
  const marks = RANKS.filter((r) => Number.isFinite(r.min) && r.min > lo && r.min < hi);
  const gid = "eg" + elo.length;
  return (
    <Box component="svg" viewBox={`0 0 ${W} ${H}`} sx={{ width: 1, height: H, overflow: "visible", display: "block" }}>
      <defs><linearGradient id={gid} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor={col} stopOpacity=".28" /><stop offset="1" stopColor={col} stopOpacity="0" /></linearGradient></defs>
      {marks.map((r) => { const y = H - ((r.min - lo) / (hi - lo)) * H; return (
        <g key={r.key}><line x1="0" x2={W} y1={y} y2={y} stroke={theme.palette.text.disabled} strokeDasharray="4 4" strokeWidth="1" />
          <text x="2" y={y - 4} fontSize="10" fill={theme.palette.text.disabled}>{r.label} {r.min}</text></g>); })}
      <path d={`${d} L${W} ${H} L0 ${H} Z`} fill={`url(#${gid})`} />
      <path d={d} fill="none" stroke={col} strokeWidth="2.5" strokeLinejoin="round" />
      <circle cx={lx} cy={ly} r="5" fill="#fff" stroke={col} strokeWidth="2.5" />
    </Box>
  );
}

const WD = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"];
function whenLabel(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(iso || "");
  if (!m) return "";
  const d = new Date(+m[1], +m[2] - 1, +m[3]);
  const same = `${m[1]}-${m[2]}-${m[3]}` === todayVN(); // giờ trận là giờ VN của điện thoại
  return `${same ? "Hôm nay" : `${WD[d.getDay()]} ${+m[3]}/${+m[2]}`} · ${m[4]}:${m[5]}`;
}
