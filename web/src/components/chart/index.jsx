// Port JS từ material-kit-react: components/chart (Chart lazy + useChart base options).
import { lazy, Suspense } from "react";
import { styled, useTheme, alpha } from "@mui/material/styles";
import Skeleton from "@mui/material/Skeleton";

const LazyChart = lazy(() => import("react-apexcharts"));

const ChartRoot = styled("div")(({ theme }) => ({
  width: "100%", flexShrink: 0, position: "relative", borderRadius: theme.shape.borderRadius * 1.5,
}));

export function Chart({ type, series, options, sx, ...other }) {
  return (
    <ChartRoot dir="ltr" sx={sx} {...other}>
      <Suspense fallback={<Skeleton variant="rounded" sx={{ width: 1, height: 1, minHeight: 40 }} />}>
        <LazyChart type={type} series={series} options={options} width="100%" height="100%" />
      </Suspense>
    </ChartRoot>
  );
}

const isObj = (v) => v && typeof v === "object" && !Array.isArray(v);
function merge(a, b) {
  const out = { ...a };
  Object.keys(b || {}).forEach((k) => { out[k] = isObj(a[k]) && isObj(b[k]) ? merge(a[k], b[k]) : b[k]; });
  return out;
}

export function useChart(updatedOptions) {
  const theme = useTheme();
  return merge(baseChartOptions(theme), updatedOptions || {});
}

function baseChartOptions(theme) {
  const p = theme.palette;
  const LABEL_TOTAL = { show: true, label: "Tổng", color: p.text.secondary, fontSize: theme.typography.subtitle2.fontSize, fontWeight: theme.typography.subtitle2.fontWeight };
  const LABEL_VALUE = { offsetY: 8, color: p.text.primary, fontSize: "1.5rem", fontWeight: theme.typography.h4.fontWeight };
  return {
    chart: {
      toolbar: { show: false }, zoom: { enabled: false }, parentHeightOffset: 0,
      fontFamily: theme.typography.fontFamily, foreColor: p.text.disabled,
      animations: { enabled: true, speed: 360, animateGradually: { enabled: true, delay: 120 }, dynamicAnimation: { enabled: true, speed: 360 } },
    },
    colors: [p.primary.main, p.warning.main, p.info.main, p.error.main, p.success.main, p.warning.dark, p.success.darker, p.info.dark, p.info.darker],
    states: { hover: { filter: { type: "darken" } }, active: { filter: { type: "darken" } } },
    fill: { opacity: 1, gradient: { type: "vertical", shadeIntensity: 0, opacityFrom: 0.4, opacityTo: 0, stops: [0, 100] } },
    dataLabels: { enabled: false },
    stroke: { width: 2.5, curve: "smooth", lineCap: "round" },
    grid: { strokeDashArray: 3, borderColor: p.divider, padding: { top: 0, right: 0, bottom: 0 }, xaxis: { lines: { show: false } } },
    xaxis: { axisBorder: { show: false }, axisTicks: { show: false } },
    yaxis: { tickAmount: 5 },
    markers: { size: 0, strokeColors: p.background.paper },
    tooltip: { theme: "false", fillSeriesColor: false, x: { show: true } },
    legend: {
      show: false, position: "top", fontWeight: 500, fontSize: "13px", horizontalAlign: "right",
      markers: { shape: "circle" }, labels: { colors: p.text.primary }, itemMargin: { horizontal: 8, vertical: 8 },
    },
    plotOptions: {
      bar: { borderRadius: 4, columnWidth: "48%", borderRadiusApplication: "end" },
      pie: { donut: { labels: { show: true, value: { ...LABEL_VALUE }, total: { ...LABEL_TOTAL } } } },
      radialBar: {
        hollow: { margin: -8, size: "100%" },
        track: { margin: -8, strokeWidth: "50%", background: alpha(p.grey[500], 0.16) },
        dataLabels: { value: { ...LABEL_VALUE }, total: { ...LABEL_TOTAL } },
      },
    },
    responsive: [
      { breakpoint: theme.breakpoints.values.sm, options: { plotOptions: { bar: { borderRadius: 3, columnWidth: "80%" } } } },
      { breakpoint: theme.breakpoints.values.md, options: { plotOptions: { bar: { columnWidth: "60%" } } } },
    ],
  };
}
