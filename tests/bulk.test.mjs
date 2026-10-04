import { test } from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./helpers/load-qml-js.mjs";

const Bulk = loadQmlJs("Bulk.js");

test("rescheduleOverdue: keeps times, skips recurring tasks", () => {
  const rows = [
    { id: "a1", minutes: null, isRecurring: false },
    { id: "b2", minutes: 15 * 60 + 30, isRecurring: false },
    { id: "c3", minutes: null, isRecurring: true },
  ];
  const r = Bulk.rescheduleOverdue(rows, "2026-10-04");
  assert.deepEqual(JSON.parse(JSON.stringify(r)), {
    changes: [
      { itemId: "a1", due: { date: "2026-10-04" } },
      { itemId: "b2", due: { date: "2026-10-04T15:30:00" } },
    ],
    skipped: 1,
  });
});

test("rescheduleOverdue: nothing to do for a bad target or no rows", () => {
  assert.deepEqual(JSON.parse(JSON.stringify(Bulk.rescheduleOverdue([{ id: "a1", minutes: null }], null))), { changes: [], skipped: 0 });
  assert.deepEqual(JSON.parse(JSON.stringify(Bulk.rescheduleOverdue([], "2026-10-04"))), { changes: [], skipped: 0 });
});
