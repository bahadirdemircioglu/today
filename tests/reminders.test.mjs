import { test } from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./helpers/load-qml-js.mjs";

const R = loadQmlJs("Reminders.js");
const DAY = "2026-10-03";
const rows = [
  { id: "a", title: "Dentist", dateKey: DAY, minutes: 900 },      // 15:00
  { id: "b", title: "Untimed", dateKey: DAY, minutes: null },
  { id: "c", title: "Late", dateKey: DAY, minutes: 600 },          // 10:00
  { id: "d", title: "Yesterday", dateKey: "2026-10-02", minutes: 900 },
];
const ids = (list) => list.map((x) => x.id);

test("notifies inside the lead window only, once", () => {
  assert.deepEqual(ids(R.due(rows, DAY, 880, 0, 10, {}, {})), []);
  assert.deepEqual(ids(R.due(rows, DAY, 890, 0, 10, {}, {})), ["a"]);
  assert.deepEqual(ids(R.due(rows, DAY, 890, 0, 10, { "a|2026-10-03|900": true }, {})), []);
  assert.deepEqual(ids(R.due(rows, DAY, 900, 0, 0, {}, {})), ["a"]);
});

test("off, untimed, other days and long-past tasks never notify", () => {
  assert.deepEqual(ids(R.due(rows, DAY, 895, 0, -1, {}, {})), []);
  assert.deepEqual(ids(R.due(rows, DAY, 620, 0, 10, {}, {})), []);   // 10:00 task, 20 min late
  assert.deepEqual(ids(R.due(rows, DAY, 610, 0, 10, {}, {})), ["c"]); // within the 15 min grace
});

test("snoozed reminders come back when due, with a fresh key", () => {
  const z = { "a|2026-10-03|900": 5000 };
  assert.deepEqual(R.due(rows, DAY, 905, 4000, 10, { "a|2026-10-03|900": true }, z), []);
  const back = R.due(rows, DAY, 910, 5000, -1, { "a|2026-10-03|900": true }, z);
  assert.deepEqual(back, [{ key: "a|2026-10-03|900|5000", baseKey: "a|2026-10-03|900", id: "a", title: "Dentist", minutes: 900, snoozed: true }]);
});

test("prune keeps only today's keys", () => {
  assert.deepEqual(R.prune({ "a|2026-10-03|900": true, "x|2026-10-02|60": true }, DAY), { "a|2026-10-03|900": true });
});
