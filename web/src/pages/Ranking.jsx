import { useEffect, useState } from "react";
import {
  Avatar, Box, Card, CardHeader, CircularProgress, Stack, Table, TableBody, TableCell,
  TableContainer, TableHead, TableRow, Typography,
} from "@mui/material";
import { alpha, useTheme } from "@mui/material/styles";
import { api } from "../lib/api.js";
import WidgetSummary from "../components/WidgetSummary.jsx";
import { Iconify } from "../components/iconify/index.jsx";
import { Label } from "../components/label/index.jsx";
import { Chart, useChart } from "../components/chart/index.jsx";
import Money from "../components/Money.jsx";

const MEDAL = ["#F5B70A", "#A9B4C0", "#CD7F45"];

export default function Ranking() {
  const theme = useTheme();
  const [rows, setRows] = useState(null);
  const [err, setErr] = useState("");

  useEffect(() => {
    api.getRanking().then(setRows).catch((e) => setErr(String(e.message || e)));
  }, []);

  const top = (rows || []).slice(0, 10);
  const chartOptions = useChart({
    xaxis: { categories: top.map((p) => p.short || p.name), labels: { style: { fontWeight: 600 } } },
    plotOptions: { bar: { horizontal: true, borderRadius: 4, barHeight: "56%" } },
    colors: [theme.palette.primary.main],
    tooltip: { y: { formatter: (v) => `${v} Elo`, title: { formatter: () => "" } } },
    grid: { padding: { left: 8, right: 16 } },
  });

  if (err) return <Typography color="error">Không tải được ranking: {err}</Typography>;
  if (!rows) return <Box sx={{ display: "grid", placeItems: "center", py: 8 }}><CircularProgress /></Box>;

  const matches = Math.round(rows.reduce((a, p) => a + (p.played || 0), 0) / 4);
  const best = rows[0];

  return (
    <Stack spacing={3}>
      <Box>
        <Typography variant="h4" sx={{ fontFamily: theme.typography.fontSecondaryFamily, fontWeight: 800 }}>Bảng xếp hạng</Typography>
        <Typography variant="body2" color="text.secondary">Elo tính từ các trận đồng bộ từ app đồng hồ.</Typography>
      </Box>

      <Box sx={{ display: "grid", gap: { xs: 1.5, sm: 2.5 }, gridTemplateColumns: { xs: "repeat(2,1fr)", sm: "repeat(3,1fr)" } }}>
        <WidgetSummary color="primary" icon="solar:users-group-rounded-bold-duotone" title="Người chơi" total={rows.length} caption="đã có trận" />
        <WidgetSummary color="info" icon="solar:ranking-bold-duotone" title="Số trận (ước)" total={matches} caption="tổng lượt / 4" />
        <WidgetSummary color="warning" icon="solar:cup-star-bold-duotone" title="Dẫn đầu" total={best ? Math.round(best.elo) : "—"} caption={best?.name || "chưa có"}
          sx={{ gridColumn: { xs: "1 / -1", sm: "auto" } }} mono />
      </Box>

      {rows.length === 0 ? (
        <Card sx={{ p: 4, textAlign: "center" }}>
          <Iconify icon="solar:cup-star-bold-duotone" width={48} sx={{ color: "text.disabled" }} />
          <Typography color="text.secondary" sx={{ mt: 1 }}>Chưa có trận nào được đồng bộ từ app.</Typography>
        </Card>
      ) : (
        <>
          {top.length > 1 && (
            <Card>
              <CardHeader title="Top Elo" subheader={`${top.length} người cao nhất`} />
              <Chart type="bar" series={[{ name: "Elo", data: top.map((p) => Math.round(p.elo)) }]} options={chartOptions}
                sx={{ px: 1.5, pb: 1, height: 44 * top.length + 40 }} />
            </Card>
          )}
          <Card>
            <TableContainer>
              <Table size="small">
                <TableHead>
                  <TableRow>
                    <TableCell sx={{ width: 56 }}>#</TableCell>
                    <TableCell>Người chơi</TableCell>
                    <TableCell align="right">Elo</TableCell>
                    <TableCell align="right" sx={{ display: { xs: "none", sm: "table-cell" } }}>Thắng · Thua</TableCell>
                    <TableCell align="right">Tỉ lệ</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {rows.map((p, i) => {
                    const rate = p.played ? Math.round((p.wins / p.played) * 100) : 0;
                    return (
                      <TableRow key={p.id} hover>
                        <TableCell>
                          {i < 3
                            ? <Box sx={{ width: 28, height: 28, borderRadius: "50%", display: "grid", placeItems: "center", bgcolor: alpha(MEDAL[i], 0.2), color: MEDAL[i] }}><Iconify icon="solar:medal-ribbons-star-bold-duotone" width={20} /></Box>
                            : <Money sx={{ color: "text.secondary", pl: 1 }}>{i + 1}</Money>}
                        </TableCell>
                        <TableCell>
                          <Stack direction="row" alignItems="center" spacing={1.5} sx={{ py: 0.75 }}>
                            <Avatar src={p.avatar || undefined} sx={{ width: 36, height: 36, bgcolor: "primary.main", color: "#fff" }}>{(p.name || "?").slice(0, 1)}</Avatar>
                            <Box sx={{ minWidth: 0 }}>
                              <Typography variant="subtitle2" noWrap>{p.name}</Typography>
                              <Typography variant="caption" color="text.secondary">{p.played} trận<Box component="span" sx={{ display: { sm: "none" } }}> · {p.wins}T {p.losses}B</Box></Typography>
                            </Box>
                          </Stack>
                        </TableCell>
                        <TableCell align="right"><Money sx={{ fontWeight: 700, fontSize: 15 }}>{Math.round(p.elo)}</Money></TableCell>
                        <TableCell align="right" sx={{ display: { xs: "none", sm: "table-cell" } }}>
                          <Money sx={{ color: "success.dark" }}>{p.wins}</Money> · <Money sx={{ color: "error.dark" }}>{p.losses}</Money>
                        </TableCell>
                        <TableCell align="right"><Label color={rate >= 60 ? "success" : rate >= 40 ? "info" : "error"}>{rate}%</Label></TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </TableContainer>
          </Card>
        </>
      )}
    </Stack>
  );
}
