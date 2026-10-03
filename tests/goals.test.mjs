import { test } from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./helpers/load-qml-js.mjs";

const G = loadQmlJs("Goals.js");
const DAY = "2026-10-03";

test("parseStats reads today's count and the daily goal", () => {
  const json = { days_items: [{ date: "2026-10-02", total_completed: 9 }, { date: DAY, total_completed: 3 }], goals: { daily_goal: 5 } };
  assert.deepEqual(G.parseStats(json, DAY), { completed: 3, goal: 5, date: DAY });
  assert.deepEqual(G.parseStats({ days_items: [] , goals: { daily_goal: 4 } }, DAY), { completed: 0, goal: 4, date: DAY });
});

test("parseStats falls back to the user's goal and rejects odd shapes", () => {
  assert.deepEqual(G.parseStats({ days_items: [{ date: DAY, total_completed: 2 }] }, DAY, 6), { completed: 2, goal: 6, date: DAY });
  assert.equal(G.parseStats({}, DAY), null);
  assert.equal(G.parseStats(null, DAY, 5), null);
  assert.equal(G.parseStats({ goals: { daily_goal: 0 } }, DAY), null);
});

test("progress adds local completions and caps the fraction", () => {
  const s = { completed: 3, goal: 5, date: DAY };
  assert.deepEqual(G.progress(s, DAY, 1), { completed: 4, goal: 5, fraction: 0.8, reached: false });
  assert.deepEqual(G.progress(s, DAY, 4), { completed: 7, goal: 5, fraction: 1, reached: true });
  assert.equal(G.progress(s, "2026-10-04", 0), null);
  assert.equal(G.progress(null, DAY, 0), null);
});

test("needsRefresh: missing, stale, or from another day", () => {
  const s = { completed: 1, goal: 5, date: DAY };
  assert.equal(G.needsRefresh(null, 0, 1000, DAY), true);
  assert.equal(G.needsRefresh(s, 1000, 1000 + 60000, DAY), false);
  assert.equal(G.needsRefresh(s, 1000, 1000 + 16 * 60000, DAY), true);
  assert.equal(G.needsRefresh(s, 1000, 2000, "2026-10-04"), true);
});
