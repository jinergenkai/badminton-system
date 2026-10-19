// Nút quản trị dùng chung cả app (header). Mở khoá = bật admin cho mọi tab.
import { useState } from "react";
import {
  Button, Dialog, DialogActions, DialogContent, DialogTitle, IconButton, TextField, Tooltip,
} from "@mui/material";
import { Iconify } from "./iconify/index.jsx";
import { Label } from "./label/index.jsx";
import { useAuth } from "../lib/auth.jsx";

export default function AdminButton({ compact }) {
  const auth = useAuth();
  const [open, setOpen] = useState(false);
  const [pw, setPw] = useState("");
  const [err, setErr] = useState("");
  const go = async () => { try { await auth.login(pw); setOpen(false); setPw(""); setErr(""); } catch (e) { setErr(String(e.message || e)); } };

  if (auth.isAdmin) {
    return (
      <Tooltip title="Thoát quản trị">
        {compact
          ? <IconButton size="small" color="primary" onClick={auth.logout}><Iconify icon="solar:lock-keyhole-minimalistic-unlocked-bold" /></IconButton>
          : <Button size="small" variant="contained" color="primary" onClick={auth.logout}
              startIcon={<Iconify icon="solar:lock-keyhole-minimalistic-unlocked-bold" width={18} />}>Quản trị</Button>}
      </Tooltip>
    );
  }
  return (
    <>
      {compact
        ? <Tooltip title="Đăng nhập quản trị"><IconButton size="small" onClick={() => setOpen(true)} sx={{ color: "text.secondary" }}><Iconify icon="solar:lock-keyhole-bold" /></IconButton></Tooltip>
        : <Button size="small" variant="outlined" color="inherit" onClick={() => setOpen(true)}
            startIcon={<Iconify icon="solar:lock-keyhole-bold" width={18} />}>Quản trị</Button>}
      <Dialog open={open} onClose={() => setOpen(false)} fullWidth maxWidth="xs">
        <DialogTitle>Đăng nhập quản trị</DialogTitle>
        <DialogContent>
          <TextField autoFocus type="password" fullWidth label="Mật khẩu" value={pw}
            onChange={(e) => setPw(e.target.value)} onKeyDown={(e) => e.key === "Enter" && go()}
            sx={{ mt: 1 }} error={!!err} helperText={err || "Mở khoá cho cả Tiền cầu, Sân trống, Pickup."} />
        </DialogContent>
        <DialogActions>
          <Button color="inherit" onClick={() => setOpen(false)}>Đóng</Button>
          <Button variant="contained" onClick={go}>Mở khoá</Button>
        </DialogActions>
      </Dialog>
    </>
  );
}
