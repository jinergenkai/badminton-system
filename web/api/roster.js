/* Danh bạ người chơi — mirror luôn-online của backend SQLite.
 *
 *   GET  /api/roster   → { updatedAt, players }   (players = [] nếu chưa đẩy lần nào)
 *   POST /api/roster   header Authorization: Bearer <ROSTER_TOKEN>
 *                      body   { players: [...] }   (backend đẩy sau mỗi thay đổi)
 *
 * Nguồn GHI duy nhất là backend. Web/Flutter chỉ ĐỌC — nên vẫn xem được danh
 * bạ (tên, ảnh) kể cả khi home server tắt. Không chứa tiền/QR, tách khỏi sổ.
 */
import { put, get } from "@vercel/blob";
import { timingSafeEqual } from "crypto";

const BLOB_NAME = "roster.json";
const ACCESS = process.env.BLOB_ACCESS === "public" ? "public" : "private";
const MAX_BYTES = 4 * 1024 * 1024;     // ảnh đại diện base64 có thể nặng

function tokenOk(header) {
  const want = process.env.ROSTER_TOKEN || process.env.CRAWLER_TOKEN || "";
  if (!want) return false;
  const given = String(header || "").replace(/^Bearer\s+/i, "");
  const a = Buffer.from(given, "utf8"), b = Buffer.from(want, "utf8");
  return a.length === b.length && timingSafeEqual(a, b);
}

export default async function handler(req, res) {
  res.setHeader("Cache-Control", "no-store");
  try {
    if (req.method === "GET") {
      const r = await get(BLOB_NAME, { access: ACCESS, useCache: false });
      if (!r || !r.stream) return res.status(200).json({ updatedAt: null, players: [] });
      return res.status(200).json(await new Response(r.stream).json());
    }

    if (req.method === "POST") {
      if (!(process.env.ROSTER_TOKEN || process.env.CRAWLER_TOKEN)) {
        return res.status(503).json({ error: "Vercel chưa có ROSTER_TOKEN (đặt xong phải Redeploy)." });
      }
      if (!tokenOk(req.headers.authorization)) {
        return res.status(401).json({ error: "Sai token." });
      }
      const body = typeof req.body === "string" ? JSON.parse(req.body) : req.body || {};
      if (!body || !Array.isArray(body.players)) {
        return res.status(400).json({ error: "Thiếu players — gửi { players: [...] }." });
      }
      const json = JSON.stringify({ updatedAt: new Date().toISOString(), players: body.players });
      if (Buffer.byteLength(json, "utf8") > MAX_BYTES) {
        return res.status(413).json({ error: "Danh bạ quá nặng (>4MB). Bớt ảnh đại diện." });
      }
      await put(BLOB_NAME, json, {
        access: ACCESS, contentType: "application/json",
        addRandomSuffix: false, allowOverwrite: true,
      });
      return res.status(200).json({ ok: true, players: body.players.length });
    }

    res.setHeader("Allow", "GET, POST");
    return res.status(405).json({ error: "Method không hỗ trợ." });
  } catch (e) {
    return res.status(500).json({ error: String((e && e.message) || e) });
  }
}
