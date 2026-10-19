import { useEffect, useMemo, useState } from "react";
import {
  Avatar, Box, Card, CardContent, Chip, CircularProgress, InputAdornment, List, ListItem,
  ListItemAvatar, ListItemText, Stack, TextField, Typography,
} from "@mui/material";
import SearchIcon from "@mui/icons-material/Search";
import { api } from "../lib/api.js";

const DEFAULT_PRICE = 25000;
const EPS = 1;

// Bước đầu: đọc sổ (read-only) và tính nợ mỗi người — logic lấy từ index.html cũ.
// Port kế tiếp: quản trị (thêm buổi, tick đã trả, thành viên, ảnh), QR, lịch sử.
function computeDue(book) {
  const sessions = book?.sessions || [];
  const members = book?.members || [];
  const total = (s) => s.court + s.shuttles * (s.price || DEFAULT_PRICE);
  const weight = (s) => s.parts.reduce((a, p) => a + (+p.weight || 0), 0);
  const perUnit = (s) => { const w = weight(s); return w > 0 ? total(s) / w : 0; };
  const due = new Map(members.map((m) => [m.id, 0]));
  for (const s of sessions) {
    const u = perUnit(s);
    for (const p of s.parts) {
      const paid = !!(s.paid && s.paid[p.mid]);
      if (!paid) due.set(p.mid, (due.get(p.mid) || 0) + p.weight * u);
    }
  }
  return members.map((m) => ({ ...m, due: Math.round(due.get(m.id) || 0) }))
    .sort((a, b) => b.due - a.due);
}

const vnd = (n) => n.toLocaleString("vi-VN") + "₫";

export default function BillBook() {
  const [book, setBook] = useState(null);
  const [err, setErr] = useState("");
  const [q, setQ] = useState("");

  useEffect(() => {
    api.getBook().then((r) => setBook(r.data)).catch((e) => setErr(String(e.message || e)));
  }, []);

  const rows = useMemo(() => (book ? computeDue(book) : []), [book]);
  const shown = rows.filter((m) => m.name.toLowerCase().includes(q.trim().toLowerCase()));

  if (err) return <Typography color="error">Không tải được sổ: {err}</Typography>;
  if (!book) return <Box sx={{ display: "grid", placeItems: "center", py: 8 }}><CircularProgress /></Box>;

  return (
    <Stack spacing={2}>
      <Typography variant="h5">Tiền cầu</Typography>
      <TextField size="small" placeholder="Tìm tên mình…" value={q} onChange={(e) => setQ(e.target.value)}
        InputProps={{ startAdornment: <InputAdornment position="start"><SearchIcon /></InputAdornment> }} />
      <Card>
        <CardContent sx={{ p: 0 }}>
          <List disablePadding>
            {shown.map((m, i) => (
              <ListItem key={m.id} divider={i < shown.length - 1}
                secondaryAction={
                  <Chip label={m.due > EPS ? vnd(m.due) : "đã xong"}
                    color={m.due > EPS ? "error" : "success"}
                    variant={m.due > EPS ? "filled" : "outlined"} sx={{ fontWeight: 700 }} />
                }>
                <ListItemAvatar>
                  <Avatar src={m.av || undefined}>{(m.name || "?").slice(0, 1)}</Avatar>
                </ListItemAvatar>
                <ListItemText primary={m.name} />
              </ListItem>
            ))}
            {shown.length === 0 && (
              <ListItem><ListItemText secondary="Không tìm thấy ai." /></ListItem>
            )}
          </List>
        </CardContent>
      </Card>
      <Typography variant="caption" color="text.secondary">
        Bản xem (read-only). Quản trị — thêm buổi, tick đã trả, thành viên, QR — sẽ port tiếp,
        giữ nguyên UX sổ cũ.
      </Typography>
    </Stack>
  );
}
