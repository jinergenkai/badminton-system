// Xoay người cho host: chọn NGÀY → /api/pickup?date= trả mỗi người + số trận đã đánh
// trong ngày (ít nhất trước, cùng số trận thì ai nghỉ lâu hơn trước).
// - Chạm vào một người để đánh dấu "vắng" (chỉ lưu trên máy này, theo ngày) → bị bỏ
//   khỏi gợi ý.
// - Gợi ý 4 người vào sân tiếp, chia sẵn 2 cặp Đỏ/Xanh cân Elo nhất.
// - Admin thêm khách vãng lai (tên có dấu * trên band/bảng).
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  Alert, Avatar, Box, Button, Card, CircularProgress, InputAdornment, List, ListItemButton,
  ListItemAvatar, ListItemText, Stack, TextField, Typography,
} from "@mui/material";
import { alpha, useTheme } from "@mui/material/styles";
import { api, API_BASE, balancePairs, todayVN } from "../lib/api.js";
import { useAuth } from "../lib/auth.jsx";
import WidgetSummary from "../components/WidgetSummary.jsx";
import { Iconify } from "../components/iconify/index.jsx";
import { Label } from "../components/label/index.jsx";
import Money, { SectionLabel } from "../components/Money.jsx";

const LS_AWAY = "pickup_away_"; // + YYYY-MM-DD -> ["id", ...]
const RED = "#E5484D";
const BLUE = "#1E6FD9";

const hhmm = (t) => (t ? String(t).slice(11, 16) : ""); // played_at là giờ local VN, không offset
const readAway = (day) => { try { return new Set(JSON.parse(localStorage.getItem(LS_AWAY + day) || "[]")); } catch { return new Set(); } };
const saveAway = (day, set) => { try { localStorage.setItem(LS_AWAY + day, JSON.stringify([...set])); } catch { /* */ } };

export function GuestTag({ sx }) {
  return <Label color="warning" sx={[{ ml: 0.75, height: 20, fontSize: 11 }, ...(Array.isArray(sx) ? sx : [sx])]}>khách</Label>;
}

function PairCard({ title, color, pair }) {
  return (
    <Box sx={{ p: 1.25, borderRadius: 1.5, bgcolor: alpha(color, 0.12), border: `1px solid ${alpha(color, 0.4)}`, minWidth: 0 }}>
      <Typography variant="overline" sx={{ color, fontWeight: 800, lineHeight: 1.6 }}>{title}</Typography>
      {pair.map((p) => (
        <Stack key={p.id} direction="row" alignItems="center" spacing={1} sx={{ mt: 0.75, minWidth: 0 }}>
          <Avatar src={p.avatar || undefined} sx={{ width: 30, height: 30, bgcolor: color, color: "#fff", fontSize: 14 }}>{(p.name || "?").slice(0, 1)}</Avatar>
          <Box sx={{ minWidth: 0 }}>
            <Typography variant="subtitle2" noWrap>{p.short || p.name}</Typography>
            <Typography variant="caption" color="text.secondary">{p.played} trận · Elo {Math.round(p.elo || 1000)}</Typography>
          </Box>
        </Stack>
      ))}
    </Box>
  );
}

export default function Pickup() {
  const theme = useTheme();
  const auth = useAuth();
  const [day, setDay] = useState(todayVN);
  const [data, setData] = useState(null); // {date, matches, pickup}
  const [err, setErr] = useState("");
  const [loading, setLoading] = useState(false);
  const [away, setAway] = useState(() => readAway(todayVN()));
  const [guestName, setGuestName] = useState("");
  const [guestBusy, setGuestBusy] = useState(false);
  const [guestMsg, setGuestMsg] = useState(null); // {sev, text}

  const load = useCallback((d) => {
    setLoading(true); setErr("");
    api.getPickupDay(d)
      .then((j) => setData(j && Array.isArray(j.pickup) ? j : { date: d, matches: 0, pickup: [] }))
      .catch((e) => { setErr(String(e.message || e)); setData(null); })
      .finally(() => setLoading(false));
  }, []);
  useEffect(() => { load(day); setAway(readAway(day)); }, [day, load]);

  const toggleAway = (id) => {
    setAway((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      saveAway(day, next);
      return next;
    });
  };

  const addGuest = async () => {
    const name = guestName.trim();
    if (!name || guestBusy) return;
    setGuestBusy(true); setGuestMsg(null);
    try {
      const g = await api.addGuest(auth.passRef.current, name);
      setGuestName("");
      setGuestMsg({ sev: "success", text: `Đã thêm khách ${g.name} (band: ${g.short}). Phone kéo danh bạ là thấy.` });
      load(day);
    } catch (e) {
      setGuestMsg({ sev: "error", text: String(e.message || e) });
    } finally {
      setGuestBusy(false);
    }
  };

  const list = data ? data.pickup : [];
  const here = useMemo(() => list.filter((p) => !away.has(p.id)), [list, away]);
  const min = here.length ? Math.min(...here.map((p) => p.played)) : 0;
  const max = here.length ? Math.max(...here.map((p) => p.played)) : 0;
  const zero = here.filter((p) => p.played === 0).length;
  // backend đã xếp: ít trận trước, nghỉ lâu trước → 4 người đầu trong số có mặt
  const pairs = useMemo(() => balancePairs(here.slice(0, 4)), [here]);

  return (
    <Stack spacing={3}>
      <Box>
        <Typography variant="h4" sx={{ fontFamily: theme.typography.fontSecondaryFamily, fontWeight: 800 }}>Xoay người</Typography>
        <Typography variant="body2" color="text.secondary">Ai đánh ít nhất lên trước — cùng số trận thì ai nghỉ lâu hơn. Chạm vào tên để đánh dấu vắng.</Typography>
      </Box>

      <Card sx={{ p: 2 }}>
        <Stack direction="row" spacing={1}>
          <TextField fullWidth type="date" label="Ngày" value={day} onChange={(e) => e.target.value && setDay(e.target.value)}
            InputLabelProps={{ shrink: true }}
            InputProps={{ startAdornment: <InputAdornment position="start"><Iconify icon="solar:calendar-bold-duotone" sx={{ color: "text.disabled" }} /></InputAdornment> }} />
          <Button variant="contained" onClick={() => load(day)} disabled={loading} startIcon={<Iconify icon="solar:refresh-bold" width={18} />} sx={{ flexShrink: 0 }}>Tải</Button>
        </Stack>
      </Card>

      {loading && !data && <Box sx={{ display: "grid", placeItems: "center", py: 6 }}><CircularProgress /></Box>}
      {err && (
        <Alert severity="warning">
          Không tải được danh sách: {err}
          {!API_BASE && <><br />Chưa cấu hình <code>VITE_API_BASE</code> — màn này cần backend.</>}
        </Alert>
      )}

      {data && (
        <>
          <Box sx={{ display: "grid", gap: { xs: 1.5, sm: 2.5 }, gridTemplateColumns: { xs: "repeat(2,1fr)", sm: "repeat(3,1fr)" } }}>
            <WidgetSummary color="primary" icon="solar:users-group-rounded-bold-duotone" title="Có mặt" total={here.length} caption={away.size ? `${away.size} người vắng` : "chạm tên để đánh dấu vắng"} />
            <WidgetSummary color="warning" icon="solar:pause-circle-bold" title="Chưa đánh" total={zero} caption="ưu tiên vào sân" />
            <WidgetSummary color="info" icon="solar:ranking-bold-duotone" title="Trận trong ngày" total={data.matches} caption={here.length ? `ít nhất ${min} · nhiều nhất ${max} trận/người` : "—"} sx={{ gridColumn: { xs: "1 / -1", sm: "auto" } }} />
          </Box>

          {pairs ? (
            <Card sx={{ p: 2 }}>
              <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 1.5 }}>
                <Iconify icon="solar:play-circle-bold" sx={{ color: "primary.main" }} />
                <Typography variant="subtitle1" sx={{ flexGrow: 1 }}>Gợi ý vào sân tiếp</Typography>
                <Label color={pairs.diff <= 30 ? "success" : pairs.diff <= 80 ? "info" : "warning"}>lệch {Math.round(pairs.diff)} Elo</Label>
              </Stack>
              <Box sx={{ display: "grid", gap: 1.25, gridTemplateColumns: "1fr auto 1fr", alignItems: "center" }}>
                <PairCard title="Đỏ" color={RED} pair={pairs.red} />
                <Typography variant="h6" color="text.disabled" sx={{ px: 0.5 }}>vs</Typography>
                <PairCard title="Xanh" color={BLUE} pair={pairs.blue} />
              </Box>
            </Card>
          ) : (
            here.length > 0 && <Alert severity="info">Cần ít nhất 4 người có mặt để gợi ý cặp.</Alert>
          )}

          {auth.isAdmin && API_BASE && (
            <Card sx={{ p: 2 }}>
              <SectionLabel>Thêm khách vãng lai</SectionLabel>
              <Stack direction="row" spacing={1}>
                <TextField fullWidth size="small" placeholder="Tên khách, vd: Tuấn (bạn An)" value={guestName}
                  onChange={(e) => setGuestName(e.target.value)} onKeyDown={(e) => e.key === "Enter" && addGuest()}
                  inputProps={{ maxLength: 60 }} />
                <Button variant="contained" color="warning" onClick={addGuest} disabled={!guestName.trim() || guestBusy}
                  startIcon={<Iconify icon="solar:user-plus-bold" width={18} />} sx={{ flexShrink: 0 }}>Thêm</Button>
              </Stack>
              {guestMsg && <Alert severity={guestMsg.sev} sx={{ mt: 1.5 }}>{guestMsg.text}</Alert>}
            </Card>
          )}

          <Box>
            <SectionLabel right={<Label>{data.date}</Label>}>Thứ tự lên sân</SectionLabel>
            <Card>
              <List disablePadding>
                {list.map((p, i) => {
                  const isAway = away.has(p.id);
                  return (
                    <ListItemButton key={p.id} divider={i < list.length - 1} onClick={() => toggleAway(p.id)}
                      sx={{ py: 1.25, opacity: isAway ? 0.45 : 1 }}>
                      <Money sx={{ width: 28, color: "text.disabled", fontSize: 13 }}>{String(i + 1).padStart(2, "0")}</Money>
                      <ListItemAvatar><Avatar src={p.avatar || undefined} sx={{ bgcolor: p.guest ? "warning.main" : "primary.main", color: "#fff" }}>{(p.name || "?").slice(0, 1)}</Avatar></ListItemAvatar>
                      <ListItemText
                        primary={<Box component="span" sx={{ display: "inline-flex", alignItems: "center", textDecoration: isAway ? "line-through" : "none" }}>{p.name}{p.guest && <GuestTag />}</Box>}
                        secondary={isAway ? "vắng — chạm để bỏ đánh dấu" : p.last_played ? `vào sân lần cuối ${hhmm(p.last_played)}` : "chưa vào sân"} />
                      <Stack direction="row" alignItems="center" spacing={1} sx={{ ml: 1 }}>
                        <Box sx={{ width: 64, height: 6, borderRadius: 3, bgcolor: alpha(theme.palette.grey[500], 0.16), overflow: "hidden", display: { xs: "none", sm: "block" } }}>
                          <Box sx={{ height: 1, width: `${max ? (p.played / max) * 100 : 0}%`, bgcolor: "primary.main", borderRadius: 3 }} />
                        </Box>
                        <Label color={isAway ? "default" : p.played === min ? "success" : p.played === max && max > min ? "error" : "default"}>
                          <Money sx={{ fontWeight: 700 }}>{p.played}</Money>&nbsp;trận
                        </Label>
                      </Stack>
                    </ListItemButton>
                  );
                })}
                {list.length === 0 && <Box sx={{ py: 3, textAlign: "center" }}><Typography variant="body2" color="text.secondary">Không có người chơi active.</Typography></Box>}
              </List>
            </Card>
          </Box>
        </>
      )}
    </Stack>
  );
}
