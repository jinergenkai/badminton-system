import { createTheme, alpha } from "@mui/material/styles";

// Theme theo đúng design system của material-kit-react (minimal):
// palette grey/primary chuẩn, hệ shadow mềm nhiều lớp, bo góc 8, Public Sans scale.
// Mặc định sáng — thoáng, trắng, bóng nhẹ như minimal; đổi MODE="dark" nếu muốn tối.
const MODE = "light";

const grey = {
  0: "#FFFFFF", 100: "#F9FAFB", 200: "#F4F6F8", 300: "#DFE3E8", 400: "#C4CDD5",
  500: "#919EAB", 600: "#637381", 700: "#454F5B", 800: "#1C252E", 900: "#141A21",
};
const primary = { lighter: "#C8FAD6", light: "#5BE49B", main: "#00A76F", dark: "#007867", darker: "#004B50", contrastText: "#FFFFFF" };
const secondary = { lighter: "#EFD6FF", light: "#C684FF", main: "#8E33FF", dark: "#5119B7", darker: "#27097A", contrastText: "#FFFFFF" };
const info = { lighter: "#CAFDF5", light: "#61F3F3", main: "#00B8D9", dark: "#006C9C", darker: "#003768", contrastText: "#FFFFFF" };
const success = { lighter: "#D3FCD2", light: "#77ED8B", main: "#22C55E", dark: "#118D57", darker: "#065E49", contrastText: "#ffffff" };
const warning = { lighter: "#FFF5CC", light: "#FFD666", main: "#FFAB00", dark: "#B76E00", darker: "#7A4100", contrastText: grey[800] };
const error = { lighter: "#FFE9D5", light: "#FFAC82", main: "#FF5630", dark: "#B71D18", darker: "#7A0916", contrastText: "#FFFFFF" };

const varAlpha = (c, o) => alpha(c, o);

// Hệ shadow của minimal — mềm, nhiều lớp, ăn theo grey500.
function customShadows(mode) {
  const col = mode === "light" ? grey[500] : "#000000";
  const base = mode === "light" ? 0.16 : 0.4;
  return {
    z1: `0 1px 2px 0 ${varAlpha(col, base)}`,
    z8: `0 8px 16px 0 ${varAlpha(col, base)}`,
    z12: `0 12px 24px -4px ${varAlpha(col, base)}`,
    z16: `0 16px 32px -4px ${varAlpha(col, base)}`,
    z20: `0 20px 40px -4px ${varAlpha(col, base)}`,
    card: `0 0 2px 0 ${varAlpha(col, 0.2)}, 0 12px 24px -4px ${varAlpha(col, mode === "light" ? 0.12 : 0.28)}`,
    dialog: `-40px 40px 80px -8px ${varAlpha("#000000", 0.24)}`,
    dropdown: `0 0 2px 0 ${varAlpha(col, 0.24)}, -20px 20px 40px -4px ${varAlpha(col, 0.24)}`,
    primary: `0 8px 16px 0 ${varAlpha(primary.main, 0.24)}`,
    secondary: `0 8px 16px 0 ${varAlpha(secondary.main, 0.24)}`,
    info: `0 8px 16px 0 ${varAlpha(info.main, 0.24)}`,
    success: `0 8px 16px 0 ${varAlpha(success.main, 0.24)}`,
    warning: `0 8px 16px 0 ${varAlpha(warning.main, 0.24)}`,
    error: `0 8px 16px 0 ${varAlpha(error.main, 0.24)}`,
  };
}

const light = {
  mode: "light",
  primary, secondary, info, success, warning, error,
  grey,
  common: { black: "#000000", white: "#FFFFFF" },
  text: { primary: grey[800], secondary: grey[600], disabled: grey[500] },
  background: { paper: "#FFFFFF", default: grey[100], neutral: grey[200] },
  action: {
    hover: varAlpha(grey[500], 0.08), selected: varAlpha(grey[500], 0.16),
    focus: varAlpha(grey[500], 0.24), disabled: varAlpha(grey[500], 0.8),
    disabledBackground: varAlpha(grey[500], 0.24), active: grey[600],
    hoverOpacity: 0.08, disabledOpacity: 0.48,
  },
  divider: varAlpha(grey[500], 0.2),
};
const dark = {
  mode: "dark",
  primary, secondary, info, success, warning, error,
  grey,
  common: { black: "#000000", white: "#FFFFFF" },
  text: { primary: "#FFFFFF", secondary: grey[500], disabled: grey[600] },
  background: { paper: grey[800], default: grey[900], neutral: varAlpha(grey[500], 0.12) },
  action: {
    hover: varAlpha(grey[500], 0.08), selected: varAlpha(grey[500], 0.16),
    focus: varAlpha(grey[500], 0.24), disabled: varAlpha(grey[500], 0.8),
    disabledBackground: varAlpha(grey[500], 0.24), active: grey[500],
    hoverOpacity: 0.08, disabledOpacity: 0.48,
  },
  divider: varAlpha(grey[500], 0.2),
};

const palette = MODE === "light" ? light : dark;
const shadows = customShadows(MODE);

const theme = createTheme({
  palette,
  shape: { borderRadius: 8 },
  customShadows: shadows,
  typography: {
    fontFamily: "'Be Vietnam Pro', 'Public Sans', system-ui, sans-serif",
    fontWeightRegular: 400, fontWeightMedium: 600, fontWeightBold: 700,
    h1: { fontWeight: 800, lineHeight: 1.1, fontSize: "2.5rem", letterSpacing: "-0.02em" },
    h2: { fontWeight: 800, lineHeight: 1.15, fontSize: "2rem", letterSpacing: "-0.02em" },
    h3: { fontWeight: 700, lineHeight: 1.2, fontSize: "1.5rem", letterSpacing: "-0.01em" },
    h4: { fontWeight: 700, lineHeight: 1.25, fontSize: "1.25rem" },
    h5: { fontWeight: 700, lineHeight: 1.3, fontSize: "1.125rem" },
    h6: { fontWeight: 700, lineHeight: 1.4, fontSize: "1rem" },
    subtitle1: { fontWeight: 600 }, subtitle2: { fontWeight: 600, fontSize: "0.875rem" },
    body2: { lineHeight: 1.5 },
    caption: { fontSize: "0.75rem", lineHeight: 1.5 },
    overline: { fontWeight: 700, letterSpacing: "0.08em", textTransform: "uppercase", fontSize: "0.75rem" },
    button: { fontWeight: 700, textTransform: "none" },
  },
  components: {
    MuiCssBaseline: {
      styleOverrides: {
        body: { backgroundColor: palette.background.default },
        "::selection": { background: varAlpha(primary.main, 0.24) },
      },
    },
    MuiPaper: {
      styleOverrides: {
        root: { backgroundImage: "none" },
        outlined: { borderColor: varAlpha(grey[500], 0.16) },
      },
    },
    MuiCard: {
      defaultProps: { elevation: 0 },
      styleOverrides: {
        root: { position: "relative", borderRadius: 16, zIndex: 0, boxShadow: shadows.card },
      },
    },
    MuiCardHeader: { defaultProps: { titleTypographyProps: { variant: "h6" }, subheaderTypographyProps: { variant: "body2", color: "text.secondary" } }, styleOverrides: { root: { padding: "24px 24px 0" } } },
    MuiCardContent: { styleOverrides: { root: { padding: 24 } } },
    MuiButton: {
      defaultProps: { disableElevation: true },
      styleOverrides: {
        root: { borderRadius: 8, paddingInline: 16 },
        sizeLarge: { minHeight: 48 },
        containedPrimary: { boxShadow: shadows.primary },
        containedInherit: { color: palette.mode === "light" ? "#FFFFFF" : grey[800], backgroundColor: palette.mode === "light" ? grey[800] : grey[100] },
        outlinedInherit: { borderColor: varAlpha(grey[500], 0.32) },
      },
    },
    MuiChip: {
      styleOverrides: {
        root: { fontWeight: 600, borderRadius: 8 },
        label: { paddingInline: 10 },
      },
    },
    MuiToggleButton: {
      styleOverrides: {
        root: {
          border: "none", textTransform: "none", fontWeight: 600, color: palette.text.secondary,
          "&.Mui-selected": { backgroundColor: palette.background.paper, color: palette.text.primary, boxShadow: shadows.z1 },
          "&.Mui-selected:hover": { backgroundColor: palette.background.paper },
        },
      },
    },
    MuiToggleButtonGroup: {
      styleOverrides: {
        root: { backgroundColor: palette.background.neutral, borderRadius: 10, padding: 4, gap: 2 },
        grouped: { borderRadius: "8px !important", margin: 0, border: "none" },
      },
    },
    MuiTab: { styleOverrides: { root: { textTransform: "none", fontWeight: 600, minWidth: 48, padding: "12px 12px" } } },
    MuiOutlinedInput: {
      styleOverrides: {
        root: {
          "& .MuiOutlinedInput-notchedOutline": { borderColor: varAlpha(grey[500], 0.2) },
          "&:hover .MuiOutlinedInput-notchedOutline": { borderColor: palette.text.primary },
        },
      },
    },
    MuiTextField: { defaultProps: { size: "small" } },
    MuiSelect: { defaultProps: { size: "small" } },
    MuiTableCell: {
      styleOverrides: {
        root: { borderBottomColor: varAlpha(grey[500], 0.16) },
        head: { color: palette.text.secondary, backgroundColor: palette.background.neutral, fontWeight: 700, fontSize: "0.8125rem" },
      },
    },
    MuiTooltip: { styleOverrides: { tooltip: { backgroundColor: palette.mode === "light" ? grey[800] : grey[700], borderRadius: 8, fontSize: "0.75rem", fontWeight: 600 } } },
    MuiDialog: { styleOverrides: { paper: { borderRadius: 16, boxShadow: shadows.dialog } } },
    MuiAppBar: { styleOverrides: { root: { boxShadow: "none" } } },
    MuiLinearProgress: { styleOverrides: { root: { borderRadius: 4, backgroundColor: varAlpha(primary.main, 0.16) } } },
  },
});

export default theme;
