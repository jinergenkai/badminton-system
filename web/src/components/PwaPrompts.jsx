// Gợi ý cài app (Android/desktop Chrome) + báo có bản mới + báo đang offline.
import { useEffect, useState } from "react";
import { Box, Button, IconButton, Paper, Snackbar, Stack, Typography } from "@mui/material";
import { onPwa, promptInstall, applyUpdate } from "../lib/pwa.js";
import { Logo } from "./logo/index.jsx";
import { Iconify } from "./iconify/index.jsx";

const DISMISS_KEY = "pwa_install_dismissed";

export default function PwaPrompts() {
  const [pwa, setPwa] = useState({});
  const [online, setOnline] = useState(() => navigator.onLine);
  const [hide, setHide] = useState(() => { try { return !!localStorage.getItem(DISMISS_KEY); } catch { return false; } });
  useEffect(() => onPwa(setPwa), []);
  useEffect(() => {
    const on = () => setOnline(true), off = () => setOnline(false);
    window.addEventListener("online", on); window.addEventListener("offline", off);
    return () => { window.removeEventListener("online", on); window.removeEventListener("offline", off); };
  }, []);
  const dismiss = () => { setHide(true); try { localStorage.setItem(DISMISS_KEY, "1"); } catch { /* */ } };

  return (
    <>
      {pwa.installEvt && !hide && (
        <Paper sx={{ position: "fixed", zIndex: 30, left: 16, right: 16, mx: "auto", maxWidth: 420, top: { xs: 72, sm: 80 },
          p: 1.5, pl: 2, borderRadius: 2, boxShadow: (t) => t.customShadows.dropdown }}>
          <Stack direction="row" alignItems="center" spacing={1.5}>
            <Logo sx={{ width: 36, height: 36 }} />
            <Box sx={{ flexGrow: 1, minWidth: 0 }}>
              <Typography variant="subtitle2">Cài Sổ Cầu Lông</Typography>
              <Typography variant="caption" color="text.secondary">Mở nhanh từ màn hình chính, xem được khi mất mạng.</Typography>
            </Box>
            <Button variant="contained" size="small" onClick={promptInstall}>Cài</Button>
            <IconButton size="small" onClick={dismiss}><Iconify icon="solar:close-circle-bold" width={18} /></IconButton>
          </Stack>
        </Paper>
      )}
      <Snackbar open={!!pwa.update} anchorOrigin={{ vertical: "top", horizontal: "center" }}
        message="Đã có bản mới của app"
        action={<Button size="small" color="primary" variant="contained" onClick={applyUpdate}>Cập nhật</Button>} />
      <Snackbar open={!online} anchorOrigin={{ vertical: "top", horizontal: "center" }}
        message={<Stack direction="row" spacing={1} alignItems="center"><Iconify icon="solar:danger-triangle-bold" width={18} /><span>Đang offline — xem số đã lưu trong máy</span></Stack>} />
    </>
  );
}
