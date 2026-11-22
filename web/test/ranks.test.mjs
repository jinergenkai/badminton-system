import { test } from "node:test";
import assert from "node:assert/strict";
import { rankOf, RANKS } from "../src/lib/ranks.js";
import { RANK_FRAME_SVG } from "../src/components/rank/frames.gen.js";

test("hạng theo mốc Elo", () => {
  assert.equal(rankOf(800).key, "dong");
  assert.equal(rankOf(899.9).key, "dong");
  assert.equal(rankOf(900).key, "bac");
  assert.equal(rankOf(1000).key, "vang");
  assert.equal(rankOf(1050).key, "bach-kim");
  assert.equal(rankOf(1199).key, "kim-cuong");
  assert.equal(rankOf(1278).key, "cao-thu");
  assert.equal(rankOf(undefined).key, "vang"); // thiếu = 1000
});

test("mỗi hạng có khung SVG", () => {
  for (const r of RANKS) assert.ok(RANK_FRAME_SVG[r.key]?.includes("<"), r.key);
});
