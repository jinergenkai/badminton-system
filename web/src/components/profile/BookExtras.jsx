// Phần gắn thêm vào tab Tiền cầu (chỉ đọc, không đụng tính tiền):
//  • MeProfileStrip: dải đầu tab "Của tôi" — khung hạng + Elo + huy hiệu, bấm mở Profile
//  • MonthTopCard: thẻ vinh danh "Đại gia tháng" ở tab "Cả nhóm"
import { useEffect, useMemo, useState } from "react";
import { Box, Card, Stack, Typography } from "@mui/material";
import { alpha } from "@mui/material/styles";

import { Iconify } from "../iconify/index.jsx";
import RankFrame from "../rank/RankFrame.jsx";
import Badge from "../badges/Badge.jsx";
import { api } from "../../lib/api.js";
import { rankOf } from "../../lib/ranks.js";
import { badgeByKey, badgeList, bookStats, levelOf, matchStats, monthTops, showcase } from "../../lib/badges.js";
import * as M from "../../lib/model.js";
import { fmtSpent, useProfile } from "./Profile.jsx";

export function MeProfileStrip({ book, m }) {
  const open = useProfile();
  const [prof, setProf] = useState(null);
  useEffect(() => {
    let live = true; setProf(null);
    api.getProfile(m.id).then((j) => live && setProf(j)).catch(() => {});
    return () => { live = false; };
  }, [m.id]);
  const { list, p } = useMemo(() => {
    const ms = prof ? matchStats(prof) : null;
    const bs = bookStats(book, m.id);
    return {
      list: showcase(badgeList({ ...(ms?.values || {}), ...(bs?.values || {}) }), 8),
      p: { id: m.id, name: m.name, avatar: m.av, ...(prof?.player || {}) },
    };
  }, [prof, book, m]);
  const hasElo = !!prof?.player;
  return (
    <Card onClick={() => open(p)} sx={{ p: 1.25, pr: 1.5, cursor: "pointer", display: "flex", alignItems: "center", gap: 1.25, "&:hover": { boxShadow: (t) => t.customShadows.z8 } }}>
      <RankFrame p={p} size={60} />
      <Box sx={{ flex: 1, minWidth: 0 }}>
        <Typography variant="subtitle1" noWrap>{m.name}</Typography>
        <Typography variant="caption" color="text.secondary" component="div">
          {hasElo ? `${rankOf(p.elo).label} · ${Math.round(p.elo)} Elo · ` : ""}{M.playCount(book, m.id)} buổi
        </Typography>
        {list.length > 0 && (
          <Stack direction="row" spacing={0.4} alignItems="center" sx={{ mt: 0.5 }}>
            {list.slice(0, 4).map((b) => <Badge key={b.key} k={b.key} tier={b.tier} size={24} title={b.name} />)}
            {list.length > 4 && <Typography variant="caption" color="text.disabled" sx={{ pl: 0.5 }}>+{list.length - 4}</Typography>}
          </Stack>
        )}
      </Box>
      <Typography variant="caption" color="primary.main" sx={{ fontWeight: 700, display: "flex", alignItems: "center" }}>
        Hồ sơ<Iconify icon="solar:alt-arrow-right-bold" width={16} />
      </Typography>
    </Card>
  );
}

export function MonthTopCard({ book }) {
  const open = useProfile();
  const tops = useMemo(() => monthTops(book), [book]);
  const cur = tops[tops.length - 1];
  if (!cur?.top) return null;
  const mem = M.memById(book, cur.top.mid);
  if (!mem) return null;
  const times = tops.filter((t) => t.top?.mid === cur.top.mid).length;
  const tier = levelOf(badgeByKey("dai-gia"), times).tier || "dong";
  return (
    <Card onClick={() => open({ id: mem.id, name: mem.name, avatar: mem.av })}
      sx={{ p: 1.5, cursor: "pointer", display: "flex", alignItems: "center", gap: 1.5,
        border: (t) => `1px dashed ${alpha(t.palette.warning.main, 0.6)}`,
        background: (t) => `linear-gradient(120deg, ${alpha(t.palette.warning.main, 0.12)}, ${t.palette.background.paper} 70%)` }}>
      <Badge k="dai-gia" tier={tier} size={46} title="Đại gia sân cầu" />
      <Box sx={{ flex: 1, minWidth: 0 }}>
        <Typography sx={{ fontSize: 11.5, fontWeight: 800, letterSpacing: 0.6, color: "warning.dark", textTransform: "uppercase" }}>Đại gia tháng {cur.month}</Typography>
        <Typography variant="subtitle1" noWrap>{M.fullName(book, mem)}</Typography>
        <Typography variant="caption" color="text.secondary">góp {fmtSpent(cur.top.amount)} · {cur.sessions} buổi trong tháng{times > 1 ? ` · lần thứ ${times}` : ""}</Typography>
      </Box>
      <Iconify icon="solar:alt-arrow-right-bold" width={18} sx={{ color: "text.disabled" }} />
    </Card>
  );
}
