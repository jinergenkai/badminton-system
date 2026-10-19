import { useEffect, useState } from "react";
import { Alert, Box, Card, CardContent, CircularProgress, Stack, Typography } from "@mui/material";
import { api } from "../lib/api.js";

// Bước đầu: đọc /api/courts (snapshot sân trống trên Blob) và báo đã lấy được.
// Port kế tiếp: dựng lại heatmap (lưới sân × khung giờ) từ courts.html cũ.
export default function Courts() {
  const [info, setInfo] = useState(null);
  const [err, setErr] = useState("");

  useEffect(() => {
    api.getCourts().then(setInfo).catch((e) => setErr(String(e.message || e)));
  }, []);

  return (
    <Stack spacing={2}>
      <Typography variant="h5">Sân trống</Typography>
      {err && <Alert severity="warning">Chưa đọc được dữ liệu sân: {err}</Alert>}
      {!info && !err && (
        <Box sx={{ display: "grid", placeItems: "center", py: 6 }}><CircularProgress /></Box>
      )}
      {info && (
        <Card>
          <CardContent>
            <Typography color="text.secondary" gutterBottom>
              Cập nhật: {info.updatedAt ? new Date(info.updatedAt).toLocaleString("vi-VN") : "chưa có lần cào nào"}
            </Typography>
            <Typography>
              {info.data?.branches?.length
                ? `${info.data.branches.length} chi nhánh — heatmap sẽ port ở bước sau.`
                : "Chưa có snapshot sân."}
            </Typography>
          </CardContent>
        </Card>
      )}
    </Stack>
  );
}
