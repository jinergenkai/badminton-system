// Theme JS chuyển từ material-kit-react (core/custom-shadows, typography, components)
// sang MUI v5 createTheme (không dùng CSS variables).
import { createTheme } from "@mui/material/styles";
import SvgIcon from "@mui/material/SvgIcon";
import { palette, grey, primary, secondary, info, success, warning, error, common, varAlpha } from "./palette.js";

// ---- custom shadows (core/custom-shadows.ts) ----
const shadowColor = (c) => `0 8px 16px 0 ${varAlpha(c, 0.24)}`;
export const customShadows = {
  z1: `0 1px 2px 0 ${varAlpha(grey[500], 0.16)}`,
  z4: `0 4px 8px 0 ${varAlpha(grey[500], 0.16)}`,
  z8: `0 8px 16px 0 ${varAlpha(grey[500], 0.16)}`,
  z12: `0 12px 24px -4px ${varAlpha(grey[500], 0.16)}`,
  z16: `0 16px 32px -4px ${varAlpha(grey[500], 0.16)}`,
  z20: `0 20px 40px -4px ${varAlpha(grey[500], 0.16)}`,
  z24: `0 24px 48px 0 ${varAlpha(grey[500], 0.16)}`,
  dialog: `-40px 40px 80px -8px ${varAlpha(common.black, 0.24)}`,
  card: `0 0 2px 0 ${varAlpha(grey[500], 0.2)}, 0 12px 24px -4px ${varAlpha(grey[500], 0.12)}`,
  dropdown: `0 0 2px 0 ${varAlpha(grey[500], 0.24)}, -20px 20px 40px -4px ${varAlpha(grey[500], 0.24)}`,
  primary: shadowColor(primary.main), secondary: shadowColor(secondary.main), info: shadowColor(info.main),
  success: shadowColor(success.main), warning: shadowColor(warning.main), error: shadowColor(error.main),
};

// ---- typography (core/typography.ts) ----
// DM Sans không có subset tiếng Việt → chữ thường dùng Be Vietnam Pro,
// tiêu đề/KPI dùng Barlow (font phụ của template, có tiếng Việt), số tiền dùng Roboto Mono.
const FONT_PRIMARY = "'Be Vietnam Pro', 'DM Sans', system-ui, -apple-system, sans-serif";
const FONT_SECONDARY = "'Barlow', 'Be Vietnam Pro', sans-serif";
export const FONT_MONO = "'Roboto Mono', ui-monospace, 'SF Mono', Menlo, monospace";
const pxToRem = (px) => `${px / 16}rem`;
const up = (bp) => `@media (min-width:${{ sm: 600, md: 900, lg: 1200 }[bp]}px)`;
const responsive = (o) => Object.fromEntries(Object.entries(o).map(([bp, v]) => [up(bp), { fontSize: pxToRem(v) }]));

const typography = {
  fontFamily: FONT_PRIMARY,
  fontSecondaryFamily: FONT_SECONDARY,
  fontMonoFamily: FONT_MONO,
  fontWeightLight: 300, fontWeightRegular: 400, fontWeightMedium: 500, fontWeightSemiBold: 600, fontWeightBold: 700,
  h1: { fontFamily: FONT_SECONDARY, fontWeight: 800, lineHeight: 80 / 64, fontSize: pxToRem(40), ...responsive({ sm: 52, md: 58, lg: 64 }) },
  h2: { fontFamily: FONT_SECONDARY, fontWeight: 800, lineHeight: 64 / 48, fontSize: pxToRem(32), ...responsive({ sm: 40, md: 44, lg: 48 }) },
  h3: { fontFamily: FONT_SECONDARY, fontWeight: 700, lineHeight: 1.5, fontSize: pxToRem(24), ...responsive({ sm: 26, md: 30, lg: 32 }) },
  h4: { fontWeight: 700, lineHeight: 1.5, fontSize: pxToRem(20), ...responsive({ md: 24 }) },
  h5: { fontWeight: 700, lineHeight: 1.5, fontSize: pxToRem(18), ...responsive({ sm: 19 }) },
  h6: { fontWeight: 600, lineHeight: 28 / 18, fontSize: pxToRem(17), ...responsive({ sm: 18 }) },
  subtitle1: { fontWeight: 600, lineHeight: 1.5, fontSize: pxToRem(16) },
  subtitle2: { fontWeight: 600, lineHeight: 22 / 14, fontSize: pxToRem(14) },
  body1: { lineHeight: 1.5, fontSize: pxToRem(16) },
  body2: { lineHeight: 22 / 14, fontSize: pxToRem(14) },
  caption: { lineHeight: 1.5, fontSize: pxToRem(12) },
  overline: { fontWeight: 700, lineHeight: 1.5, fontSize: pxToRem(12), textTransform: "uppercase", letterSpacing: "0.06em" },
  button: { fontWeight: 700, lineHeight: 24 / 14, fontSize: pxToRem(14), textTransform: "unset" },
};

// ---- components (core/components.tsx) ----
const components = {
  MuiCssBaseline: {
    styleOverrides: {
      body: { backgroundColor: palette.background.default },
      "::selection": { background: varAlpha(primary.main, 0.24) },
      ".num, .money": { fontFamily: FONT_MONO, fontVariantNumeric: "tabular-nums" },
    },
  },
  MuiBackdrop: { styleOverrides: { root: { backgroundColor: varAlpha(grey[900], 0.6) }, invisible: { background: "transparent" } } },
  MuiButton: {
    defaultProps: { disableElevation: true },
    styleOverrides: {
      root: { borderRadius: 10 },
      containedPrimary: { boxShadow: customShadows.primary, "&:hover": { boxShadow: "none" } },
      containedInherit: { color: common.white, backgroundColor: grey[800], "&:hover": { color: common.white, backgroundColor: grey[700] } },
      outlinedInherit: { borderColor: varAlpha(grey[500], 0.32) },
      sizeLarge: { minHeight: 48 },
    },
  },
  MuiPaper: {
    defaultProps: { elevation: 0 },
    styleOverrides: { root: { backgroundImage: "none" }, outlined: { borderColor: varAlpha(grey[500], 0.16) } },
  },
  MuiCard: { styleOverrides: { root: { zIndex: 0, position: "relative", boxShadow: customShadows.card, borderRadius: 16 } } },
  MuiCardHeader: {
    defaultProps: { titleTypographyProps: { variant: "h6" }, subheaderTypographyProps: { variant: "body2" } },
    styleOverrides: { root: { padding: "24px 24px 0" } },
  },
  MuiOutlinedInput: { styleOverrides: { root: { borderRadius: 10 }, notchedOutline: { borderColor: varAlpha(grey[500], 0.2) } } },
  MuiTableCell: { styleOverrides: { head: { fontSize: pxToRem(14), color: palette.text.secondary, fontWeight: 600, backgroundColor: palette.background.neutral }, root: { borderBottomStyle: "dashed", borderBottomColor: varAlpha(grey[500], 0.2) } } },
  MuiMenuItem: { styleOverrides: { root: { ...typography.body2, borderRadius: 6, margin: "0 4px" } } },
  MuiMenu: { styleOverrides: { paper: { boxShadow: customShadows.dropdown, borderRadius: 10 } } },
  MuiPopover: { styleOverrides: { paper: { boxShadow: customShadows.dropdown, borderRadius: 10 } } },
  MuiLink: { defaultProps: { underline: "hover" } },
  MuiFormControlLabel: { styleOverrides: { label: { ...typography.body2 } } },
  MuiCheckbox: {
    defaultProps: {
      size: "small",
      icon: <SvgIcon><path d="M17.9 2.318A5 5 0 0 1 22.895 7.1l.005.217v10a5 5 0 0 1-4.783 4.995l-.217.005h-10a5 5 0 0 1-4.995-4.783l-.005-.217v-10a5 5 0 0 1 4.783-4.996l.217-.004h10Zm-.5 1.5h-9a4 4 0 0 0-4 4v9a4 4 0 0 0 4 4h9a4 4 0 0 0 4-4v-9a4 4 0 0 0-4-4Z" /></SvgIcon>,
      checkedIcon: <SvgIcon><path d="M17 2a5 5 0 0 1 5 5v10a5 5 0 0 1-5 5H7a5 5 0 0 1-5-5V7a5 5 0 0 1 5-5Zm-1.625 7.255-4.13 4.13-1.75-1.75a.881.881 0 0 0-1.24 0c-.34.34-.34.89 0 1.24l2.38 2.37c.17.17.39.25.61.25.23 0 .45-.08.62-.25l4.75-4.75c.34-.34.34-.89 0-1.24a.881.881 0 0 0-1.24 0Z" /></SvgIcon>,
    },
  },
  MuiChip: { styleOverrides: { root: { fontWeight: 600, borderRadius: 8 } } },
  MuiAvatar: { styleOverrides: { root: { fontWeight: 600 } } },
  MuiTooltip: { styleOverrides: { tooltip: { backgroundColor: grey[800], borderRadius: 8, fontSize: pxToRem(12), fontWeight: 500 }, arrow: { color: grey[800] } } },
  MuiDialog: { styleOverrides: { paper: { borderRadius: 16, boxShadow: customShadows.dialog } } },
  MuiDialogTitle: { styleOverrides: { root: { ...typography.h6, padding: 24 } } },
  MuiDialogContent: { styleOverrides: { root: { padding: "0 24px" } } },
  MuiDialogActions: { styleOverrides: { root: { padding: 24, gap: 8 } } },
  MuiAppBar: { styleOverrides: { root: { boxShadow: "none" } } },
  MuiTab: { styleOverrides: { root: { textTransform: "none", fontWeight: 600, minWidth: 48, minHeight: 48 } } },
  MuiTextField: { defaultProps: { size: "small" } },
  MuiSelect: { defaultProps: { size: "small" } },
  MuiLinearProgress: { styleOverrides: { root: { borderRadius: 4, backgroundColor: varAlpha(primary.main, 0.12) }, bar: { borderRadius: 4 } } },
  MuiListItemText: { styleOverrides: { primary: { fontWeight: 600, fontSize: pxToRem(14) }, secondary: { fontSize: pxToRem(12.5) } } },
  // toggle "pill" giống sub-tab của bản gốc: nền xanh nhạt, mục chọn là viên trắng nổi
  MuiToggleButtonGroup: {
    styleOverrides: {
      root: { backgroundColor: varAlpha(primary.main, 0.08), borderRadius: 12, padding: 4, gap: 4 },
      grouped: { borderRadius: "9px !important", margin: 0, border: "none !important" },
    },
  },
  MuiToggleButton: {
    styleOverrides: {
      root: {
        border: "none", textTransform: "none", fontWeight: 600, color: primary.dark, padding: "5px 12px",
        "&:hover": { backgroundColor: varAlpha(primary.main, 0.08) },
        "&.Mui-selected, &.Mui-selected:hover": { backgroundColor: common.white, color: primary.main, boxShadow: customShadows.z8 },
      },
    },
  },
  MuiBottomNavigationAction: { styleOverrides: { root: { color: grey[500], "&.Mui-selected": { color: primary.main } }, label: { fontWeight: 600, fontSize: pxToRem(11), "&.Mui-selected": { fontSize: pxToRem(11) } } } },
};

const theme = createTheme({
  palette,
  shape: { borderRadius: 8 },
  typography,
  components,
});
theme.customShadows = customShadows;

export default theme;
