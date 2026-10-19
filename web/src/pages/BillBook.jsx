import { useEffect, useMemo, useState } from "react";
import {
  Avatar, Box, Card, CardContent, Chip, CircularProgress, InputAdornment, LinearProgress,
  List, ListItem, ListItemAvatar, ListItemText, Stack, TextField, Typography,
} from "@mui/material";
import SearchIcon from "@mui/icons-material/Search";
import { api } from "../lib/api.js";
import * as M from "../lib/model.js";

const vndK = (x) => M.fmt(x);

// Bước đầu (read-only): đọc sổ qua /api/data, migrate, tính nợ bằng model VERBATIM.
// Port kế tiếp: viewMe/picker/sessions chi tiết, rồi quản trị (thêm buổi, tick trả,
// thành viên, QR, xuất ảnh) + lưu chống-đè theo rev.
export default function BillBook() {
  const [book, setBook] = useState(null);
  const [err, setErr] = useState("");
  const [q, setQ] = useState("");

  useEffect(() => {
    api.getBook()
      .then((r) => setBook(M.migrate(r.data || M.EMPTY_BOOK())))
      .catch((e) => setErr(String(e.message || e)));
  }, []);

  const stats = useMemo(() => {
    if (!book) return null;
    const due = M.totalDue(book), got = M.totalCollected(book);
    const rows = book.members
      .map((m) => ({ m, due: M.memberDue(book, m.id), tot: M.memberSessions(book, m.id).length }))
      .filter((r) => r.tot > 0)
      .sort((a, b) => b.due - a.due || a.m.name.localeCompare(b.m.name, "vi"));
    return { due, got, all: due + got, rows, nDue: rows.filter((r) => r.due > M.EPS).length };
  }, [book]);

  if (err) return <Typography color="error">Không tải được sổ: {err}</Typography>;
  if (!book || !stats) return <Box sx={{ display: "grid", placeItems: "center", py: 8 }}><CircularProgress /></Box>;

  const shown = stats.rows.filter((r) => M.norm(r.m.name).includes(M.norm(q)));
  const pct = stats.all > M.EPS ? Math.round((stats.got / stats.all) * 100) : 0;

  return (
    <Stack spacing={2}>
      <Typography variant="h5">Tiền cầu</Typography>

      <Card>
        <CardContent>
          <Stack direction="row" justifyContent="space-between" alignItems="flex-start">
            <Box>
              <Typography variant="caption" color="text.secondary" fontWeight={700}>CÒN THIẾU</Typography>
              <Typography variant="h4" color={stats.due > M.EPS ? "error" : "success.main"} fontWeight={700}>
                {stats.due > M.EPS ? vndK(stats.due) : "Xong hết 🎉"}
              </Typography>
            </Box>
            <Box textAlign="right">
              <Typography variant="caption" color="text.secondary" fontWeight={700}>ĐÃ THU</Typography>
              <Typography variant="h6" color="success.main" fontWeight={700}>{vndK(stats.got)}</Typography>
              <Typography variant="caption" color="text.secondary">/ {vndK(stats.all)}</Typography>
            </Box>
          </Stack>
          <LinearProgress variant="determinate" value={pct} sx={{ my: 1.5, height: 6, borderRadius: 3 }} />
          <Typography variant="caption" color="text.secondary">
            {stats.nDue} người còn nợ · {book.sessions.length} buổi đã chơi
          </Typography>
        </CardContent>
      </Card>

      <TextField size="small" placeholder="Tìm tên mình…" value={q} onChange={(e) => setQ(e.target.value)}
        InputProps={{ startAdornment: <InputAdornment position="start"><SearchIcon /></InputAdornment> }} />

      <Card>
        <CardContent sx={{ p: 0 }}>
          <List disablePadding>
            {shown.map((r, i) => (
              <ListItem key={r.m.id} divider={i < shown.length - 1}
                secondaryAction={
                  <Chip label={r.due > M.EPS ? vndK(r.due) : "✓"}
                    color={r.due > M.EPS ? "error" : "success"}
                    variant={r.due > M.EPS ? "filled" : "outlined"} sx={{ fontWeight: 700 }} />
                }>
                <ListItemAvatar>
                  <Avatar src={r.m.av || undefined} sx={{ bgcolor: M.hue(r.m.id) }}>
                    {M.initials(r.m.name)}
                  </Avatar>
                </ListItemAvatar>
                <ListItemText primary={M.fullName(book, r.m)}
                  secondary={r.due > M.EPS ? `${M.memberDueSessions(book, r.m.id).length} buổi chưa trả` : `${r.tot} buổi · đã trả đủ`} />
              </ListItem>
            ))}
            {shown.length === 0 && <ListItem><ListItemText secondary="Không tìm thấy ai." /></ListItem>}
          </List>
        </CardContent>
      </Card>

      <Typography variant="caption" color="text.secondary">
        Bản xem (read-only), tính tiền dùng đúng công thức sổ cũ. Quản trị — thêm buổi, tick đã trả,
        thành viên, QR, xuất ảnh — sẽ port tiếp.
      </Typography>
    </Stack>
  );
}
