// Trình độ host đặt cho từng người -> Elo khởi điểm. Giữ cùng khóa/điểm với
// backend/api/db.py (LEVELS). '' = chưa đặt (tính như Trung bình, 1000).
export const LEVELS = [
  { key: "newbie", label: "Newbie", short: "NB", elo: 800 },
  { key: "yeu", label: "Yếu", short: "Y", elo: 900 },
  { key: "tb-yeu", label: "TB yếu", short: "TB-", elo: 950 },
  { key: "tb", label: "Trung bình", short: "TB", elo: 1000 },
  { key: "kha", label: "Khá", short: "K", elo: 1100 },
  { key: "gioi", label: "Giỏi", short: "G", elo: 1200 },
];
export const levelOf = (key) => LEVELS.find((l) => l.key === key) || null;
