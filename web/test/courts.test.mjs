// node --test test/  (không cần cài gì thêm)
import { test } from "node:test";
import assert from "node:assert/strict";
import * as C from "../src/lib/courts.js";

const NOW = Date.parse("2026-11-23T20:00:00+07:00");
const P = (id, elo, played, ended) => ({ id, name: id, elo, played, last_ended: ended || "", last_played: ended || "" });
const people = [
  P("a", 1100, 2, "2026-11-23T19:50:00"), // chờ 10'
  P("b", 1000, 1, "2026-11-23T19:20:00"), // chờ 40'
  P("c", 900, 0),                          // chưa đánh
  P("d", 1050, 2, "2026-11-23T19:30:00"), // chờ 30'
  P("e", 950, 1, "2026-11-23T19:30:00"),  // chờ 30', ít trận hơn d
  P("f", 1200, 3, "2026-11-23T19:59:00"), // chờ 1'
];
const all = people.map((p) => p.id);

test("ưu tiên: chưa đánh > chờ lâu > ít trận", () => {
  assert.deepEqual(C.byPriority(people, NOW).map((p) => p.id), ["c", "b", "e", "d", "a", "f"]);
  assert.equal(C.waitLabel(people[1], NOW), "chờ 40'");
  assert.equal(C.waitLabel(people[2], NOW), "chưa đánh");
  assert.equal(C.waitLabel(P("x", 1000, 1, "2026-11-23T18:55:00"), NOW), "chờ 1h05");
});

test("tự xếp sân trống: 4 người ưu tiên, chia cặp lệch Elo ít nhất", () => {
  const b = C.autoFill({ present: all, courts: [C.emptyCourt(0)] }, 0, people, NOW);
  const s = b.courts[0].slots;
  assert.deepEqual([...s].sort(), ["b", "c", "d", "e"]);
  const elo = Object.fromEntries(people.map((p) => [p.id, p.elo]));
  const diff = Math.abs(elo[s[0]] + elo[s[1]] - elo[s[2]] - elo[s[3]]);
  assert.equal(diff, 0); // c+d = 1950 = b+e
});

test("tự xếp không lấy người vắng hoặc đang ở sân khác", () => {
  let b = { present: all.filter((x) => x !== "c"), courts: [C.emptyCourt(0), C.emptyCourt(1)] };
  b = C.place(b, 1, 0, "b");
  b = C.autoFill(b, 0, people, NOW);
  assert.ok(!b.courts[0].slots.includes("c"));
  assert.ok(!b.courts[0].slots.includes("b"));
  assert.deepEqual([...b.courts[0].slots].sort(), ["a", "d", "e", "f"]);
});

test("tự xếp sân đã có người: chỉ lấp ô trống, giữ người cũ", () => {
  let b = { present: all, courts: [C.emptyCourt(0)] };
  b = C.place(b, 0, 2, "f");
  b = C.autoFill(b, 0, people, NOW);
  assert.equal(b.courts[0].slots[2], "f");
  assert.deepEqual(b.courts[0].slots.filter((x) => x !== "f").sort(), ["b", "c", "e"]);
});

test("place: một người không bao giờ ở 2 ô; ô có người thì người cũ về khay", () => {
  let b = { present: all, courts: [C.emptyCourt(0), C.emptyCourt(1)] };
  b = C.place(b, 0, 0, "a");
  b = C.place(b, 1, 3, "a");
  assert.deepEqual(b.courts[0].slots, [null, null, null, null]);
  assert.equal(b.courts[1].slots[3], "a");
  b = C.place(b, 1, 3, "b");
  assert.equal(C.courtOf(b, "a"), -1);
  assert.equal(C.onCourtIds(b).size, 1);
});

test("bỏ có mặt thì gỡ khỏi sân; xoá sân giữ tối thiểu 1 và đánh số lại", () => {
  let b = C.place({ present: all, courts: [C.emptyCourt(0)] }, 0, 1, "d");
  b = C.togglePresent(b, "d");
  assert.ok(!b.present.includes("d"));
  assert.equal(C.courtOf(b, "d"), -1);
  b = C.addCourt(C.addCourt(b));
  b = C.removeCourt(b, 0);
  assert.deepEqual(b.courts.map((c) => c.name), ["Sân 1", "Sân 2"]);
  assert.equal(C.removeCourt(C.removeCourt(b, 0), 0).courts.length, 1);
});

test("ngày", () => {
  assert.equal(C.shiftDay("2026-11-30", 1), "2026-12-01");
  assert.equal(C.shiftDay("2026-03-01", -1), "2026-02-28");
  assert.equal(C.dayLabel("2026-11-23"), "T2 · 23/11");
});
