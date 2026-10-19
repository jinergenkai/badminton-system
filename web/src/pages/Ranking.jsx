import { useEffect, useState } from "react";
import {
  Avatar, Box, Card, CardContent, Chip, CircularProgress, List, ListItem,
  ListItemAvatar, ListItemText, Stack, Typography,
} from "@mui/material";
import EmojiEventsIcon from "@mui/icons-material/EmojiEvents";
import { api } from "../lib/api.js";

const medal = ["#f5c518", "#c0c7d0", "#cd7f45"];

export default function Ranking() {
  const [rows, setRows] = useState(null);
  const [err, setErr] = useState("");

  useEffect(() => {
    api.getRanking().then(setRows).catch((e) => setErr(String(e.message || e)));
  }, []);

  if (err) return <Typography color="error">Không tải được ranking: {err}</Typography>;
  if (!rows) return <Box sx={{ display: "grid", placeItems: "center", py: 8 }}><CircularProgress /></Box>;

  return (
    <Stack spacing={2}>
      <Stack direction="row" alignItems="center" spacing={1}>
        <EmojiEventsIcon color="secondary" />
        <Typography variant="h5">Bảng xếp hạng</Typography>
      </Stack>
      {rows.length === 0 ? (
        <Typography color="text.secondary">Chưa có trận nào được đồng bộ từ app.</Typography>
      ) : (
        <Card>
          <CardContent sx={{ p: 0 }}>
            <List disablePadding>
              {rows.map((p, i) => (
                <ListItem key={p.id} divider={i < rows.length - 1}
                  secondaryAction={
                    <Stack direction="row" spacing={1} alignItems="center">
                      <Chip size="small" label={`${Math.round(p.elo)}`} color="primary"
                        variant="outlined" sx={{ fontWeight: 700, minWidth: 56 }} />
                      <Typography variant="body2" color="text.secondary" sx={{ minWidth: 64, textAlign: "right" }}>
                        {p.wins}T · {p.losses}B
                      </Typography>
                    </Stack>
                  }>
                  <ListItemAvatar>
                    <Avatar src={p.avatar || undefined}
                      sx={{ bgcolor: medal[i] || "primary.dark", color: "#111", fontWeight: 700 }}>
                      {i < 3 ? i + 1 : (p.name || "?").slice(0, 1)}
                    </Avatar>
                  </ListItemAvatar>
                  <ListItemText primary={p.name}
                    secondary={`${p.played} trận`} />
                </ListItem>
              ))}
            </List>
          </CardContent>
        </Card>
      )}
    </Stack>
  );
}
