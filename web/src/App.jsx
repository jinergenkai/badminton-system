import { useState } from "react";
import {
  AppBar, Box, Container, Tab, Tabs, Toolbar, Typography, useMediaQuery,
  BottomNavigation, BottomNavigationAction, Paper,
} from "@mui/material";
import PaymentsIcon from "@mui/icons-material/Payments";
import SportsTennisIcon from "@mui/icons-material/SportsTennis";
import LeaderboardIcon from "@mui/icons-material/Leaderboard";
import GroupsIcon from "@mui/icons-material/Groups";
import { useTheme } from "@mui/material/styles";

import BillBook from "./pages/BillBook.jsx";
import Courts from "./pages/Courts.jsx";
import Ranking from "./pages/Ranking.jsx";
import Pickup from "./pages/Pickup.jsx";

const TABS = [
  { label: "Tiền cầu", icon: <PaymentsIcon />, el: <BillBook /> },
  { label: "Sân trống", icon: <SportsTennisIcon />, el: <Courts /> },
  { label: "Ranking", icon: <LeaderboardIcon />, el: <Ranking /> },
  { label: "Pickup", icon: <GroupsIcon />, el: <Pickup /> },
];

export default function App() {
  const [tab, setTab] = useState(0);
  const theme = useTheme();
  const isMobile = useMediaQuery(theme.breakpoints.down("sm"));

  return (
    <Box sx={{ minHeight: "100dvh", pb: isMobile ? 9 : 0 }}>
      <AppBar position="sticky" elevation={0}
        sx={{ bgcolor: (t) => t.palette.background.paper, color: "text.primary",
          borderBottom: 1, borderColor: "divider",
          backdropFilter: "blur(8px)", backgroundImage: "none" }}>
        <Toolbar sx={{ gap: 1 }}>
          <Box sx={{ display: "flex", alignItems: "center", justifyContent: "center", width: 36, height: 36, borderRadius: 2, bgcolor: "primary.main", color: "primary.contrastText", boxShadow: (t) => t.customShadows?.primary }}>
            <SportsTennisIcon fontSize="small" />
          </Box>
          <Typography variant="h6" sx={{ flexGrow: 1 }}>Sổ Cầu Lông</Typography>
          {!isMobile && (
            <Tabs value={tab} onChange={(_, v) => setTab(v)} textColor="primary"
              indicatorColor="primary">
              {TABS.map((t, i) => <Tab key={i} label={t.label} icon={t.icon} iconPosition="start" />)}
            </Tabs>
          )}
        </Toolbar>
      </AppBar>

      <Container maxWidth="lg" sx={{ py: { xs: 2, sm: 3 } }}>
        {TABS[tab].el}
      </Container>

      {isMobile && (
        <Paper elevation={8} sx={{ position: "fixed", bottom: 0, left: 0, right: 0, zIndex: 10 }}>
          <BottomNavigation showLabels value={tab} onChange={(_, v) => setTab(v)}>
            {TABS.map((t, i) => <BottomNavigationAction key={i} label={t.label} icon={t.icon} />)}
          </BottomNavigation>
        </Paper>
      )}
    </Box>
  );
}
