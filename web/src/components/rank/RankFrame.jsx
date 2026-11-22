// Avatar đeo khung hạng (SVG sinh sẵn ở frames.gen.js). `size` = bề rộng cả khung;
// avatar nằm giữa, đường kính = 60/136 bề rộng (khung vẽ quanh avatar r=30).
import { Avatar, Box } from "@mui/material";
import { RANK_FRAME_SVG, RANK_VIEWBOX } from "./frames.gen.js";
import { rankOf } from "../../lib/ranks.js";

const VB_W = 136, VB_H = 152, CX = 68, CY = 82, AV = 72; // avatar lớn hơn vòng trong một chút: mép nằm dưới viền

export default function RankFrame({ p, size = 48, sx }) {
  const rank = rankOf(p?.elo);
  const h = (size * VB_H) / VB_W;
  const d = (size * AV) / VB_W;
  return (
    <Box title={rank.label} sx={[{ position: "relative", width: size, height: h, flexShrink: 0 }, ...(Array.isArray(sx) ? sx : [sx])]}>
      <Avatar src={p?.avatar || undefined}
        sx={{ position: "absolute", width: d, height: d, left: (size * CX) / VB_W - d / 2, top: (h * CY) / VB_H - d / 2,
          fontSize: d * 0.45, color: "#fff", bgcolor: p?.guest ? "warning.main" : "primary.main" }}>
        {(p?.name || "?").slice(0, 1)}
      </Avatar>
      <Box component="svg" viewBox={RANK_VIEWBOX} aria-hidden
        sx={{ position: "absolute", inset: 0, width: 1, height: 1, pointerEvents: "none", overflow: "visible" }}
        dangerouslySetInnerHTML={{ __html: RANK_FRAME_SVG[rank.key] }} />
    </Box>
  );
}
