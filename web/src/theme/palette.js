// Port JS từ material-kit-react: src/theme/theme-config.ts + core/palette.ts
// Khác template: primary = xanh sân cầu #256E4E (nhận diện gốc của Sổ Cầu Lông).
import { alpha } from "@mui/material/styles";

export const varAlpha = (color, opacity) => alpha(color, opacity);

export const grey = {
  50: "#FCFDFD", 100: "#F9FAFB", 200: "#F4F6F8", 300: "#DFE3E8", 400: "#C4CDD5",
  500: "#919EAB", 600: "#637381", 700: "#454F5B", 800: "#1C252E", 900: "#141A21",
};

export const primary = { lighter: "#D5EDE1", light: "#62A886", main: "#256E4E", dark: "#1A5139", darker: "#0E3324", contrastText: "#FFFFFF" };
export const secondary = { lighter: "#EFD6FF", light: "#C684FF", main: "#8E33FF", dark: "#5119B7", darker: "#27097A", contrastText: "#FFFFFF" };
export const info = { lighter: "#CAFDF5", light: "#61F3F3", main: "#00B8D9", dark: "#006C9C", darker: "#003768", contrastText: "#FFFFFF" };
export const success = { lighter: "#D3FCD2", light: "#77ED8B", main: "#22C55E", dark: "#118D57", darker: "#065E49", contrastText: "#FFFFFF" };
export const warning = { lighter: "#FFF5CC", light: "#FFD666", main: "#FFAB00", dark: "#B76E00", darker: "#7A4100", contrastText: grey[800] };
export const error = { lighter: "#FFE9D5", light: "#FFAC82", main: "#FF5630", dark: "#B71D18", darker: "#7A0916", contrastText: "#FFFFFF" };
export const common = { black: "#000000", white: "#FFFFFF" };

export const palette = {
  mode: "light",
  primary, secondary, info, success, warning, error, grey, common,
  text: { primary: grey[800], secondary: grey[600], disabled: grey[500] },
  // nền hơi ngả xanh sân — giữ chất bản gốc
  background: { paper: "#FFFFFF", default: "#F5F8F6", neutral: grey[200], tint: varAlpha(primary.main, 0.08) },
  action: {
    hover: varAlpha(grey[500], 0.08), selected: varAlpha(grey[500], 0.16),
    focus: varAlpha(grey[500], 0.24), disabled: varAlpha(grey[500], 0.8),
    disabledBackground: varAlpha(grey[500], 0.24), active: grey[600],
    hoverOpacity: 0.08, disabledOpacity: 0.48,
  },
  divider: varAlpha(grey[500], 0.2),
};
