// Số tiền: font mono + tabular-nums — chữ ký của bản HTML gốc.
import Box from "@mui/material/Box";

export default function Money({ children, sx, ...other }) {
  return (
    <Box component="span" sx={[{ fontFamily: (t) => t.typography.fontMonoFamily, fontVariantNumeric: "tabular-nums", fontWeight: 600, letterSpacing: "-0.01em", whiteSpace: "nowrap" }, ...(Array.isArray(sx) ? sx : [sx])]} {...other}>
      {children}
    </Box>
  );
}

// Nhãn mục viết hoa (giống .sec-label của bản gốc)
export function SectionLabel({ children, sx, right }) {
  return (
    <Box sx={[{ display: "flex", alignItems: "center", gap: 1, px: 0.5, mb: 1, mt: 0.5 }, ...(Array.isArray(sx) ? sx : [sx])]}>
      <Box sx={{ typography: "overline", color: "text.secondary", flexGrow: 1 }}>{children}</Box>
      {right}
    </Box>
  );
}
