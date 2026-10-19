// Xoay người cho host: chọn buổi → /api/pickup trả danh sách người, ít trận nhất trước
// (cùng số trận thì ai nghỉ lâu hơn trước) để chia sân công bằng.
import { useCallback, useEffect, useState } from "react";
import {
  Alert, Avatar, Box, Button, Card, CircularProgress, InputAdornment, List, ListItem,
  ListItemAvatar, ListItemText, Stack, TextField, Typography,
} from "@mui/material";
import { alpha, useTheme } from "@mui/material/styles";
import { api, API_BASE } from "../lib/api.js";
import WidgetSummary from "../components/WidgetSummary.jsx";
import { Iconify } from "../components/iconify/index.jsx";
import { Label } from "../components/label/index.jsx";
import Money, { SectionLabel } from "../components/Money.jsx";

const LS_KEY = "pickup_session";
const today = () => new Date().toISOString().slice(0, 10);
const hhmm = (t) => { if (!t) return ""; const d = new Date(t); return isNaN(d) ? String(t).slice(11, 16) : d.toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" }); };

export default function Pickup() {
  const theme = useTheme();
  const [sid, setSid] = useState(() => { try { return localStorage.getItem(LS_KEY) || today(); } catch { return today(); } });
  const [input, setInput] = useState(sid);
  const [rows, setRows] = useState(null);
  const [err, setErr] = useState("");
  const [loading, setLoading] = useState(false);

  const load = useCallback((id) => {
    setLoading(true); setErr("");
    api.getPickup(id).then((r) => setRows(r)).catch((e) => { setErr(String(e.message || e)); setRows(null); }).finally(() => setLoading(false));
  }, []);
  useEffect(() => { load(sid); }, [sid, load]);

  const go = () => { const v = input.trim(); if (!v) return; try { localStorage.setItem(LS_KEY, v); } catch { /* */ } if (v === sid) load(v); else setSid(v); };

  const list = rows || [];
  const min = list.length ? Math.min(...list.map((p) => p.played)) : 0;
  const max = list.length ? Math.max(...list.map((p) => p.played)) : 0;
  const zero = list.filter((p) => p.played === 0).length;
  const next = list.slice(0, 4);

  return (
    <Stack spacing={3}>
      <Box>
        <Typography variant="h4" sx={{ fontFamily: theme.typography.fontSecondaryFamily, fontWeight: 800 }}>Xoay người</Typography>
        <Typography variant="body2" color="text.secondary">Ai đánh ít nhất lên trước — cùng số trận thì ai nghỉ lâu hơn được ưu tiên.</Typography>
      </Box>

      <Card sx={{ p: 2 }}>
        <Stack direction="row" spacing={1}>
          <TextField fullWidth label="Mã buổi" value={input} onChange={(e) => setInput(e.target.value)} onKeyDown={(e) => e.key === "Enter" && go()}
            InputProps={{ startAdornment: <InputAdornment position="start"><Iconify icon="solar:calendar-bold-duotone" sx={{ color: "text.disabled" }} /></InputAdornment> }} />
          <Button variant="contained" onClick={go} startIcon={<Iconify icon="solar:refresh-bold" width={18} />} sx={{ flexShrink: 0 }}>Tải</Button>
        </Stack>
      </Card>

      {loading && !rows && <Box sx={{ display: "grid", placeItems: "center", py: 6 }}><CircularProgress /></Box>}
      {err && (
        <Alert severity="warning">
          Không tải được danh sách: {err}
          {!API_BASE && <><br />Chưa cấu hình <code>VITE_API_BASE</code> — màn này cần backend ranking/pickup.</>}
        </Alert>
      )}

      {rows && (
        <>
          <Box sx={{ display: "grid", gap: { xs: 1.5, sm: 2.5 }, gridTemplateColumns: { xs: "repeat(2,1fr)", sm: "repeat(3,1fr)" } }}>
            <WidgetSummary color="primary" icon="solar:users-group-rounded-bold-duotone" title="Có mặt" total={list.length} caption="người đang active" />
            <WidgetSummary color="warning" icon="solar:pause-circle-bold" title="Chưa đánh" total={zero} caption="ưu tiên vào sân" />
            <WidgetSummary color="info" icon="solar:shuffle-bold" title="Chênh lệch" total={max - min} caption={`ít nhất ${min} · nhiều nhất ${max} trận`} sx={{ gridColumn: { xs: "1 / -1", sm: "auto" } }} />
          </Box>

          {next.length > 0 && (
            <Card sx={{ p: 2.5, color: "common.white", background: `linear-gradient(135deg, ${theme.palette.primary.main}, ${theme.palette.primary.darker})` }}>
              <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 1.5 }}>
                <Iconify icon="solar:play-circle-bold" />
                <Typography variant="subtitle1">Gợi ý vào sân tiếp</Typography>
              </Stack>
              <Box sx={{ display: "grid", gap: 1, gridTemplateColumns: { xs: "repeat(2,1fr)", sm: "repeat(4,1fr)" } }}>
                {next.map((p) => (
                  <Stack key={p.id} direction="row" alignItems="center" spacing={1} sx={{ p: 1, borderRadius: 1.5, bgcolor: alpha("#fff", 0.12), minWidth: 0 }}>
                    <Avatar src={p.avatar || undefined} sx={{ width: 32, height: 32, bgcolor: alpha("#fff", 0.24) }}>{(p.short || p.name || "?").slice(0, 1)}</Avatar>
                    <Box sx={{ minWidth: 0 }}>
                      <Typography variant="subtitle2" noWrap>{p.short || p.name}</Typography>
                      <Typography variant="caption" sx={{ opacity: 0.8 }}>{p.played} trận</Typography>
                    </Box>
                  </Stack>
                ))}
              </Box>
            </Card>
          )}

          <Box>
            <SectionLabel right={<Label>{sid}</Label>}>Thứ tự lên sân</SectionLabel>
            <Card>
              <List disablePadding>
                {list.map((p, i) => (
                  <ListItem key={p.id} divider={i < list.length - 1} sx={{ py: 1.25 }}
                    secondaryAction={
                      <Stack direction="row" alignItems="center" spacing={1}>
                        <Box sx={{ width: 64, height: 6, borderRadius: 3, bgcolor: alpha(theme.palette.grey[500], 0.16), overflow: "hidden", display: { xs: "none", sm: "block" } }}>
                          <Box sx={{ height: 1, width: `${max ? (p.played / max) * 100 : 0}%`, bgcolor: "primary.main", borderRadius: 3 }} />
                        </Box>
                        <Label color={p.played === min ? "success" : p.played === max && max > min ? "error" : "default"}>
                          <Money sx={{ fontWeight: 700 }}>{p.played}</Money>&nbsp;trận
                        </Label>
                      </Stack>
                    }>
                    <Money sx={{ width: 28, color: "text.disabled", fontSize: 13 }}>{String(i + 1).padStart(2, "0")}</Money>
                    <ListItemAvatar><Avatar src={p.avatar || undefined} sx={{ bgcolor: "primary.main", color: "#fff" }}>{(p.short || p.name || "?").slice(0, 1)}</Avatar></ListItemAvatar>
                    <ListItemText primary={p.name} secondary={p.last_played ? `vào sân lần cuối ${hhmm(p.last_played)}` : "chưa vào sân"} />
                  </ListItem>
                ))}
                {list.length === 0 && <ListItem sx={{ py: 3, justifyContent: "center" }}><Typography variant="body2" color="text.secondary">Không có người chơi active.</Typography></ListItem>}
              </List>
            </Card>
          </Box>
        </>
      )}
    </Stack>
  );
}
