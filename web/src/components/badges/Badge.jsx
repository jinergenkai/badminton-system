// Huy hiệu khiên lục giác (SVG sinh sẵn ở badges.gen.js).
// tier: dong | bac | vang | kim-cuong ; locked -> xám mờ (chưa đạt).
import { useId } from "react";
import { Box } from "@mui/material";
import { BADGE_ICON, BADGE_SHELL, BADGE_VIEWBOX } from "./badges.gen.js";

export default function Badge({ k, tier, size = 48, locked = false, title, sx }) {
  const uid = "b" + useId().replace(/[^a-zA-Z0-9]/g, "");
  const shell = (BADGE_SHELL[tier || "dong"] || "").replaceAll("__ID__", uid);
  return (
    <Box component="svg" viewBox={BADGE_VIEWBOX} role="img" aria-label={title}
      sx={[{ width: size, height: (size * 98) / 96, flexShrink: 0, display: "block", overflow: "visible",
        ...(locked && { filter: "grayscale(1)", opacity: 0.4 }) }, ...(Array.isArray(sx) ? sx : [sx])]}
      dangerouslySetInnerHTML={{ __html: (title ? `<title>${title}</title>` : "") + shell + (BADGE_ICON[k] || "") }} />
  );
}
