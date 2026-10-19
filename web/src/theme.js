import { createTheme } from "@mui/material/styles";

// Theme kiểu material-kit: nền tối mềm, bo góc lớn, bóng nhẹ, xanh ngọc nhấn.
const theme = createTheme({
  palette: {
    mode: "dark",
    primary: { main: "#2dd4bf", contrastText: "#06201c" },
    secondary: { main: "#f59e0b" },
    background: { default: "#0f1216", paper: "#171b21" },
    success: { main: "#34d399" },
    error: { main: "#f87171" },
    text: { primary: "#e7ebf0", secondary: "#9aa4b2" },
    divider: "rgba(255,255,255,0.08)",
  },
  shape: { borderRadius: 16 },
  typography: {
    fontFamily: "'Be Vietnam Pro', system-ui, -apple-system, sans-serif",
    h5: { fontWeight: 700 },
    h6: { fontWeight: 700 },
    button: { textTransform: "none", fontWeight: 600 },
  },
  components: {
    MuiPaper: {
      styleOverrides: {
        root: { backgroundImage: "none", border: "1px solid rgba(255,255,255,0.06)" },
      },
    },
    MuiCard: {
      styleOverrides: {
        root: { boxShadow: "0 8px 24px rgba(0,0,0,0.28)" },
      },
    },
    MuiButton: { defaultProps: { disableElevation: true } },
  },
});

export default theme;
