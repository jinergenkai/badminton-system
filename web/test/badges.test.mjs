import { test } from "node:test";
import assert from "node:assert/strict";
import { badgeList, bookStats, levelOf, BADGES, matchStats, monthTops, showcase, upcoming } from "../src/lib/badges.js";
import { BADGE_ICON, BADGE_SHELL } from "../src/components/badges/badges.gen.js";

const mk = (won, o = {}) => ({ won, partners: ["p1"], opponents: ["o1", "o2"], score: won ? 21 : 15, opp_score: won ? 15 : 21,
  elo_before: 1000, delta: won ? 16 : -16, team_elo: 1000, opp_elo: 1000, rallies: "", played_at: "2026-11-20T19:00:00.000", ...o });

test("mỗi huy hiệu có hình + 4 ngưỡng tăng dần", () => {
  for (const b of BADGES) {
    assert.ok(BADGE_ICON[b.key], b.key);
    assert.equal(b.steps.length, 4);
    assert.ok(b.steps.every((x, i) => i === 0 || x > b.steps[i - 1]), b.key);
  }
  for (const t of ["dong", "bac", "vang", "kim-cuong"]) assert.ok(BADGE_SHELL[t].includes("__ID__"));
});

test("cấp theo ngưỡng", () => {
  const b = BADGES.find((x) => x.key === "chuoi-thang");
  assert.deepEqual(levelOf(b, 2), { level: 0, tier: null, next: 3 });
  assert.deepEqual(levelOf(b, 5), { level: 2, tier: "bac", next: 8 });
  assert.deepEqual(levelOf(b, 99), { level: 4, tier: "kim-cuong", next: null });
});

test("thống kê trận: chuỗi thắng, ngược dòng, hạ khổng lồ, deuce, cú đêm, đồng đội/khắc tinh", () => {
  const ms = [
    mk(true, { rallies: "LLLLLW" + "W".repeat(20) }),            // bị dẫn 0-5 rồi thắng
    mk(true, { opp_elo: 1120, team_elo: 1010 }),                  // hạ đội Elo cao hơn 110
    mk(true, { score: 22, opp_score: 20, played_at: "2026-11-20T22:15:00.000" }),
    mk(false, { opponents: ["o1", "o3"] }),
    mk(true, { partners: ["p2"] }),
    mk(false, { opponents: ["o1", "o3"] }),
    mk(false, { opponents: ["o1", "o3"] }),
  ];
  const s = matchStats({ player: { elo: 1000 }, matches: ms });
  assert.equal(s.played, 7); assert.equal(s.wins, 4); assert.equal(s.winRate, 57);
  assert.equal(s.bestStreak, 3); assert.equal(s.streak, 0);
  assert.equal(s.values["nguoc-dong"], 1);
  assert.equal(s.values["ha-guc"], 1);
  assert.equal(s.values["marathon"], 1);
  assert.equal(s.values["cu-dem"], 1);
  assert.equal(s.values["xa-giao"], 2);
  assert.equal(s.values["cap-bai-trung"], 3);
  assert.equal(s.bestPartner.id, "p1");
  assert.equal(s.nemesis.id, "o3");            // gặp 3 thua 3
  assert.equal(s.elo.length, 8);
  assert.equal(s.form.length, 7);
});

test("hồ sơ trống không vỡ", () => {
  const s = matchStats({ player: { elo: 1042 }, matches: [] });
  assert.equal(s.played, 0); assert.equal(s.peak, 1042); assert.equal(s.bestPartner, null);
});

const ses = (date, mids, o = {}) => ({ id: date + mids.join(""), date, court: 0, shuttles: 0, price: 30, photo: "", paid: {}, parts: mids.map((mid) => ({ mid, weight: 1 })), ...o });

test("sổ tiền: chuyên cần, kèo ăn, sòng phẳng, đại gia tháng (không lộ nợ)", () => {
  const book = { members: [{ id: "a", name: "A" }, { id: "b", name: "B" }], sessions: [
    ses("28/10", ["a", "b"], { court: 100, paid: { a: "x", b: "x" } }),
    ses("30/10", ["a"], { court: 60, paid: { a: "x" } }),
    ses("2/11", ["a", "b"], { court: 100, paid: { a: "x" } }),
    ses("5/11 kèo ăn", ["b"], { court: 300, kind: "meal" }),
    ses("6/11", ["b"], { court: 40 }),
  ] };
  const a = bookStats(book, "a"), b = bookStats(book, "b");
  assert.equal(a.plays, 3); assert.equal(a.values["chuyen-can"], 3);
  assert.equal(b.values["chuyen-can"], 2);             // 2/11 + 6/11 (kèo ăn không tính)
  assert.equal(b.meals, 1); assert.equal(b.values["keo-an"], 1);
  assert.equal(a.values["song-phang"], 3); assert.equal(b.values["song-phang"], 1);
  assert.equal(a.spent, 50 + 60 + 50);
  assert.equal(b.spent, 50 + 50 + 300 + 40);
  assert.equal("due" in a, false);
  const tops = monthTops(book);
  assert.deepEqual(tops.map((t) => [t.month, t.top?.mid]), [[10, "a"], [11, "b"]]);
  assert.equal(a.values["dai-gia"], 1); assert.equal(b.values["dai-gia"], 1);
});

test("tháng: hoà thì không ai; ngày không đọc được thì bỏ qua", () => {
  const book = { members: [], sessions: [ses("1/12", ["a", "b"], { court: 100 }), ses("hôm qua", ["a"], { court: 999 })] };
  assert.equal(monthTops(book)[0].top, null);
  assert.equal(monthTops(book).length, 1);
});

test("nổi bật + sắp lên cấp", () => {
  const list = badgeList({ "chuoi-thang": 5, "bach-thang": 38, "cu-dem": 1, "keo-an": 0 });
  assert.deepEqual(showcase(list).map((b) => b.key), ["chuoi-thang", "bach-thang"]);
  assert.deepEqual(upcoming(list).map((b) => b.key), ["bach-thang", "chuoi-thang"]);
  assert.equal(list.find((b) => b.key === "marathon").known, false);
});
