// Đọc sổ tiền CHỈ ĐỌC cho profile / huy hiệu (không đụng logic lưu của useBook).
// Gọi GET /api/data công khai; lỗi -> dùng cache localStorage mà tab Tiền cầu đã lưu.
import { migrate } from "./model.js";

const CACHE_KEY = "bmw_book_cache"; // trùng key của useBook — chỉ ĐỌC, không ghi
const TTL = 60_000;
let memo = { at: 0, p: null };

function fromCache() {
  try { const c = JSON.parse(localStorage.getItem(CACHE_KEY) || "null"); return c?.data ? migrate(JSON.parse(JSON.stringify(c.data))) : null; }
  catch { return null; }
}

export function loadBookRO() {
  if (memo.p && Date.now() - memo.at < TTL) return memo.p;
  memo = {
    at: Date.now(),
    p: fetch("/api/data", { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error("HTTP " + r.status))))
      .then((j) => migrate(j.data))
      .catch(() => fromCache()),
  };
  return memo.p;
}
