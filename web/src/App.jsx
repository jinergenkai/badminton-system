import { useState } from "react";
import {
  AppBar, Box, Container, Tab, Tabs, Toolbar, Typography, useMediaQuery,
  BottomNavigation, BottomNavigationAction, Paper,
} from "@mui/material";
import { useTheme, alpha } from "@mui/material/styles";

import { Logo } from "./components/logo/index.jsx";
import { Iconify } from "./components/iconify/index.jsx";
import BillBook from "./pages/BillBook.jsx";
import Courts from "./pages/Courts.jsx";
import Ranking from "./pages/Ranking.jsx";
import Pickup from "./pages/Pickup.jsx";

// maxWidth: Tiền cầu giữ cột hẹp ~600px như bản gốc (phone-first)
const TABS = [
  { label: "Tiền cầu", icon: "solar:wallet-money-bold-duotone", el: <BillBook />, maxWidth: 600 },
  { label: "Sân trống", icon: "solar:calendar-search-bold-duotone", el: <Courts />, maxWidth: "lg" },
  { label: "Ranking", icon: "solar:cup-star-bold-duotone", el: <Ranking />, maxWidth: "md" },
  { label: "Pickup", icon: "solar:users-group-rounded-bold-duotone", el: <Pickup />, maxWidth: "md" },
];

export default function App() {
  const [tab, setTab] = useState(0);
  const theme = useTheme();
  const isMobile = useMediaQuery(theme.breakpoints.down("sm"));
  const cur = TABS[tab];

  return (
    <Box sx={{ minHeight: "100dvh", pb: isMobile ? "calc(72px + env(safe-area-inset-bottom))" : 4 }}>
      <AppBar position="sticky" color="inherit"
        sx={{
          bgcolor: alpha(theme.palette.background.default, 0.8), backdropFilter: "blur(10px)",
          WebkitBackdropFilter: "blur(10px)", borderBottom: `1px dashed ${theme.palette.divider}`,
        }}>
        <Toolbar sx={{ gap: 1.25, minHeight: { xs: 60, sm: 68 } }}>
          <Logo sx={{ width: 34, height: 34 }} />
          <Box sx={{ flexGrow: 1, minWidth: 0 }}>
            <Typography sx={{ fontFamily: theme.typography.fontSecondaryFamily, fontWeight: 800, fontSize: 21, lineHeight: 1, color: "primary.darker", letterSpacing: "-0.01em" }}>
              Sổ Cầu Lông
            </Typography>
            {isMobile && <Typography variant="caption" color="text.secondary" sx={{ lineHeight: 1 }}>{cur.label}</Typography>}
          </Box>
          {!isMobile && (
            <Tabs value={tab} onChange={(_, v) => setTab(v)}
              TabIndicatorProps={{ sx: { height: "100%", borderRadius: 1.25, bgcolor: alpha(theme.palette.primary.main, 0.1), zIndex: 0 } }}
              sx={{ minHeight: 44, "& .MuiTab-root": { minHeight: 44, px: 2, zIndex: 1, color: "text.secondary", "&.Mui-selected": { color: "primary.main" } } }}>
              {TABS.map((t, i) => <Tab key={i} label={t.label} icon={<Iconify icon={t.icon} width={22} />} iconPosition="start" />)}
            </Tabs>
          )}
        </Toolbar>
      </AppBar>

      <Container maxWidth={typeof cur.maxWidth === "string" ? cur.maxWidth : false}
        sx={{ py: { xs: 2, sm: 3 }, ...(typeof cur.maxWidth === "number" && { maxWidth: cur.maxWidth }) }}>
        {cur.el}
      </Container>

      {isMobile && (
        <Paper sx={{ position: "fixed", bottom: 0, left: 0, right: 0, zIndex: 10, pb: "env(safe-area-inset-bottom)", borderTop: `1px solid ${theme.palette.divider}`, boxShadow: theme.customShadows.z16 }}>
          <BottomNavigation showLabels value={tab} onChange={(_, v) => setTab(v)} sx={{ height: 64 }}>
            {TABS.map((t, i) => <BottomNavigationAction key={i} label={t.label} icon={<Iconify icon={t.icon} width={24} />} />)}
          </BottomNavigation>
        </Paper>
      )}
    </Box>
  );
}
