import { Alert, Stack, Typography } from "@mui/material";

// Port kế tiếp: chọn buổi -> gọi /api/pickup?session=<id>, hiện danh sách người
// kèm "số trận / nghỉ mấy lượt", gợi ý người vào sân tiếp theo.
export default function Pickup() {
  return (
    <Stack spacing={2}>
      <Typography variant="h5">Xoay người (host)</Typography>
      <Alert severity="info">
        Màn này nối với <code>/api/pickup</code>: chọn buổi hôm nay → thấy ai chưa đánh / đánh ít /
        đánh nhiều để chia sân cho chuẩn. Sẽ port ở bước tiếp theo.
      </Alert>
    </Stack>
  );
}
