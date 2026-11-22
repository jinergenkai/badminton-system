// Hạng theo Elo HIỆN TẠI (lên xuống theo trận) — không gắn với "trình độ" host đặt.
// Mốc tạm, chỉnh lại khi có dữ liệu thật (xem phân bố Elo trên Ranking).
export const RANKS = [
  { key: "dong", label: "Đồng", min: -Infinity },
  { key: "bac", label: "Bạc", min: 900 },
  { key: "vang", label: "Vàng", min: 975 },
  { key: "bach-kim", label: "Bạch kim", min: 1050 },
  { key: "kim-cuong", label: "Kim cương", min: 1125 },
  { key: "cao-thu", label: "Cao thủ", min: 1200 },
];

/** Hạng của một mức Elo (thiếu/hỏng -> như 1000). */
export function rankOf(elo) {
  const e = Number.isFinite(Number(elo)) && elo !== null && elo !== "" ? Number(elo) : 1000;
  let r = RANKS[0];
  for (const x of RANKS) if (e >= x.min) r = x;
  return r;
}
