// Chuyển từ material-kit-react: sections/overview/analytics-widget-summary.tsx
// Thẻ KPI nền gradient theo màu palette + hình vuông chìm + sparkline (tuỳ chọn).
import Box from "@mui/material/Box";
import Card from "@mui/material/Card";
import { useTheme, alpha } from "@mui/material/styles";
import { Iconify } from "./iconify/index.jsx";
import { Chart, useChart } from "./chart/index.jsx";

export default function WidgetSummary({ sx, icon, title, total, caption, chart, percent, color = "primary", mono = false, ...other }) {
  const theme = useTheme();
  const c = theme.palette[color];
  const chartOptions = useChart({
    chart: { sparkline: { enabled: true } },
    colors: [c.dark],
    xaxis: { categories: chart?.categories || [] },
    grid: { padding: { top: 6, left: 6, right: 6, bottom: 6 } },
    tooltip: { y: { formatter: (v) => String(v), title: { formatter: () => "" } } },
    markers: { strokeWidth: 0 },
    ...chart?.options,
  });
  return (
    <Card sx={[{
      p: { xs: 2, sm: 2.5 }, boxShadow: "none", position: "relative", overflow: "hidden",
      color: c.darker, backgroundColor: "common.white",
      backgroundImage: `linear-gradient(135deg, ${alpha(c.lighter, 0.48)}, ${alpha(c.light, 0.48)})`,
    }, ...(Array.isArray(sx) ? sx : [sx])]} {...other}>
      {icon && <Box sx={{ width: 40, height: 40, mb: 2, display: "grid", placeItems: "center", color: c.main }}>
        {typeof icon === "string" ? <Iconify icon={icon} width={40} /> : icon}
      </Box>}
      {percent != null && (
        <Box sx={{ top: 16, gap: 0.5, right: 16, display: "flex", position: "absolute", alignItems: "center" }}>
          <Iconify width={20} icon="eva:trending-up-fill" sx={percent < 0 ? { transform: "scaleY(-1)" } : undefined} />
          <Box component="span" sx={{ typography: "subtitle2" }}>{percent > 0 && "+"}{percent}%</Box>
        </Box>
      )}
      <Box sx={{ display: "flex", flexWrap: "wrap", alignItems: "flex-end", justifyContent: "flex-end" }}>
        <Box sx={{ flexGrow: 1, minWidth: 0 }}>
          <Box sx={{ mb: 0.5, typography: "subtitle2", opacity: 0.88 }}>{title}</Box>
          <Box sx={{
            typography: "h3", lineHeight: 1.15,
            ...(mono && { fontFamily: theme.typography.fontMonoFamily, fontVariantNumeric: "tabular-nums", fontWeight: 700, letterSpacing: "-0.02em", fontSize: { xs: "1.35rem", sm: "1.6rem" } }),
          }}>{total}</Box>
          {caption && <Box sx={{ mt: 0.5, typography: "caption", opacity: 0.72 }}>{caption}</Box>}
        </Box>
        {chart?.series?.length > 1 && (
          <Chart type="line" series={[{ data: chart.series }]} options={chartOptions} sx={{ width: 84, height: 56 }} />
        )}
      </Box>
      <Box sx={{
        top: 0, left: -20, width: 240, height: 240, zIndex: -1, opacity: 0.24, position: "absolute", bgcolor: c.main,
        mask: "url(/assets/background/shape-square.svg) no-repeat center / contain",
        WebkitMask: "url(/assets/background/shape-square.svg) no-repeat center / contain",
      }} />
    </Card>
  );
}
