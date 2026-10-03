import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { loadQmlJs } from "./helpers/load-qml-js.mjs";

const Q = loadQmlJs("CommandQueue.js");
const S = loadQmlJs("TaskStore.js");
let counter = 0;
const uuidFn = () => `u${++counter}`;

function queueOf(...entries) {
  return { v: 1, entries };
}
const close = (uuid, itemId, attempts = 0) => ({ kind: "close", uuid, itemId, createdAt: 0, attempts });
const qa = (localId, text, extra = {}) => ({ kind: "quick_add", localId, text, createdAt: 0, attempts: 0, state: "pending", sentAt: null, ...extra });

test("#1 enqueueClose is idempotent per item", () => {
  let q = Q.enqueueClose(Q.emptyQueue(), "a", 1, uuidFn);
  q = Q.enqueueClose(q, "a", 2, uuidFn);
  assert.equal(q.entries.length, 1);
});

test("enqueueClose does not mutate its input", () => {
  const q0 = Q.emptyQueue();
  Q.enqueueClose(q0, "a", 1, uuidFn);
  assert.equal(q0.entries.length, 0);
});

test("#2 nextSyncBatch caps at 100 item_close commands", () => {
  let q = Q.emptyQueue();
  for (let i = 0; i < 150; i++) q = Q.enqueueClose(q, `i${i}`, 0, uuidFn);
  q = Q.enqueueQuickAdd(q, "x", 0, uuidFn).queue;
  const batch = Q.nextSyncBatch(q, 100);
  assert.equal(batch.length, 100);
  assert.deepEqual(Object.keys(batch[0]).sort(), ["args", "type", "uuid"]);
  assert.equal(batch[0].type, "item_close");
  assert.deepEqual(batch[0].args, { id: "i0" });
});

test("#3 #4 #5 #6 applySyncStatus", () => {
  const status = JSON.parse(fs.readFileSync(new URL("./fixtures/sync-status-errors.json", import.meta.url), "utf8")).sync_status;
  const q = queueOf(close("u-ok", "1"), close("u-notfound", "2"), close("u-rate", "3"), close("u-server", "4"), close("u-missing", "5"), close("u-unsent", "6"));
  const r = Q.applySyncStatus(q, ["u-ok", "u-notfound", "u-rate", "u-server", "u-missing"], status);
  assert.deepEqual(r.queue.entries.map((e) => [e.uuid, e.attempts]), [["u-rate", 1], ["u-server", 1], ["u-missing", 0], ["u-unsent", 0]]);
  assert.deepEqual(r.dropped, [{ kind: "close", itemId: "2", errorTag: "ITEM_NOT_FOUND", httpCode: 404 }]);
  assert.equal(r.retryAfterSec, 30);
});

test("#7 a command failing transiently 20 times is dropped", () => {
  const q = queueOf(close("u", "1", 19));
  const r = Q.applySyncStatus(q, ["u"], { u: { http_code: 503, error_tag: "X" } });
  assert.equal(r.queue.entries.length, 0);
  assert.equal(r.dropped.length, 1);
});

test("#8 quick add validation", () => {
  const q0 = Q.emptyQueue();
  assert.equal(Q.enqueueQuickAdd(q0, "   ", 0, uuidFn).error, "empty");
  assert.equal(Q.enqueueQuickAdd(q0, "x".repeat(1001), 0, uuidFn).error, "too_long");
  assert.equal(Q.enqueueQuickAdd(q0, "x".repeat(1001), 0, uuidFn).queue, q0);
  const ok = Q.enqueueQuickAdd(q0, "  Buy milk ", 5, uuidFn);
  assert.equal(ok.error, null);
  assert.equal(ok.queue.entries[0].text, "Buy milk");
  assert.equal(ok.queue.entries[0].state, "pending");
});

test("#9 markQuickAddResult outcomes", () => {
  const base = Q.markQuickAddSent(queueOf(qa("L", "x")), "L", 100);
  assert.equal(base.entries[0].sentAt, 100);
  assert.equal(base.entries[0].attempts, 1);

  assert.equal(Q.markQuickAddResult(base, "L", "ok").queue.entries.length, 0);

  const client = Q.markQuickAddResult(base, "L", "client");
  assert.equal(client.queue.entries.length, 0);
  assert.equal(client.dropped.length, 1);

  const server = Q.markQuickAddResult(base, "L", "server").queue.entries[0];
  assert.equal(server.state, "pending");
  assert.equal(server.sentAt, null);

  assert.equal(Q.markQuickAddResult(base, "L", "network").queue.entries[0].state, "uncertain");
  assert.equal(Q.markQuickAddResult(queueOf(qa("L", "x")), "L", "network").queue.entries[0].state, "pending");
});

test("nextQuickAdd skips uncertain entries", () => {
  const q = queueOf(qa("A", "a", { state: "uncertain", sentAt: 1 }), qa("B", "b"));
  assert.equal(Q.nextQuickAdd(q).localId, "B");
});

test("#10 resolveUncertain matches the created task", () => {
  const sentAt = Date.UTC(2026, 9, 3, 9);
  const store = { ...S.emptyStore(), items: { a: { id: "a", content: "dişçi", addedAt: sentAt + 3000 } } };
  const q = queueOf(qa("L", "yarın 15:00 dişçi #Kişisel", { state: "uncertain", sentAt }));
  assert.equal(Q.resolveUncertain(q, store).entries.length, 0);
});

test("resolveUncertain also looks at recently added tasks without a due date", () => {
  const sentAt = Date.UTC(2026, 9, 3, 9);
  const store = { ...S.emptyStore(), recent: { a: { content: "Buy milk", addedAt: sentAt + 1000 } } };
  const q = queueOf(qa("L", "Buy milk @shop p2 // two litres", { state: "uncertain", sentAt }));
  assert.equal(Q.resolveUncertain(q, store).entries.length, 0);
});

test("#11 resolveUncertain without a match puts the entry back to pending", () => {
  const sentAt = Date.UTC(2026, 9, 3, 9);
  const store = { ...S.emptyStore(), items: {
    far: { id: "far", content: "dişçi", addedAt: sentAt + 3600 * 1000 },
    other: { id: "other", content: "something else", addedAt: sentAt },
  } };
  const r = Q.resolveUncertain(queueOf(qa("L", "dişçi", { state: "uncertain", sentAt })), store);
  assert.equal(r.entries[0].state, "pending");
  assert.equal(r.entries[0].sentAt, null);
});

test("#12 serialize / deserialize round trip; garbage gives an empty queue", () => {
  const q = queueOf(close("u", "1"), qa("L", "x"));
  assert.deepEqual(Q.deserialize(Q.serialize(q)), q);
  assert.deepEqual(Q.deserialize("{bad"), Q.emptyQueue());
  assert.deepEqual(Q.deserialize(JSON.stringify({ v: 2, entries: [] })), Q.emptyQueue());
});

test("#13 uuid4 format", () => {
  let i = 0;
  const seq = [0.1, 0.5, 0.9, 0.3, 0.7];
  const id = Q.uuid4(() => seq[i++ % seq.length]);
  assert.match(id, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  assert.match(Q.uuid4(() => 0.999999), /^ffffffff-ffff-4fff-bfff-ffffffffffff$/);
});

test("dropByUuids removes only the given close entries", () => {
  const r = Q.dropByUuids(queueOf(close("a", "1"), close("b", "2"), qa("L", "x")), ["a"]);
  assert.deepEqual(r.queue.entries.map((e) => e.uuid || e.localId), ["b", "L"]);
  assert.equal(r.dropped[0].itemId, "1");
});

test("stripQuickAddSyntax / normWords", () => {
  assert.deepEqual(Q.normWords(Q.stripQuickAddSyntax("Call mom today p1 #Family @phone {friday} // notes")), ["call", "mom", "today"]);
});

test("recoverAfterRestart: an in-flight Quick Add becomes uncertain, others are untouched", () => {
  const q = queueOf(qa("A", "a", { sentAt: 5, attempts: 1 }), qa("B", "b"), close("u", "1"));
  const r = Q.recoverAfterRestart(q);
  assert.deepEqual(r.entries.map((e) => e.state || e.kind), ["uncertain", "pending", "close"]);
  assert.equal(Q.recoverAfterRestart(queueOf(qa("B", "b"))).entries[0].state, "pending");
});

test("enqueueDueToday becomes an item_update with the date, in queue order", () => {
  let q = Q.enqueueClose(Q.emptyQueue(), "a", 0, uuidFn);
  q = Q.enqueueDueToday(q, "b", "2026-10-03", 0, uuidFn);
  const batch = Q.nextSyncBatch(q, 100);
  assert.deepEqual(batch.map((c) => c.type), ["item_close", "item_update"]);
  assert.deepEqual(batch[1].args, { id: "b", due: { date: "2026-10-03" } });
});

test("update entries follow the same sync_status rules as closes", () => {
  const q = Q.enqueueDueToday(Q.emptyQueue(), "b", "2026-10-03", 0, () => "d1");
  assert.equal(Q.applySyncStatus(q, ["d1"], { d1: "ok" }).queue.entries.length, 0);
  const r = Q.applySyncStatus(q, ["d1"], { d1: { http_code: 404, error_tag: "ITEM_NOT_FOUND" } });
  assert.deepEqual(r.dropped, [{ kind: "update", itemId: "b", errorTag: "ITEM_NOT_FOUND", httpCode: 404 }]);
  assert.equal(Q.dropByUuids(q, ["d1"]).queue.entries.length, 0);
  assert.deepEqual(Q.deserialize(Q.serialize(q)), q);
});

test("update / move / delete commands", () => {
  let q = Q.enqueueUpdate(Q.emptyQueue(), "a", { priority: 4 }, 0, () => "u1");
  q = Q.enqueueMove(q, "a", "P2", 0, () => "u2");
  const del = Q.enqueueDelete(q, "b", 1000, 5000, () => "u3");
  q = del.queue;
  assert.equal(del.uuid, "u3");
  assert.equal(Q.enqueueDelete(q, "b", 1000, 5000, () => "u4").uuid, null);
  assert.deepEqual(Q.nextSyncBatch(q, 100, 2000), [
    { type: "item_update", uuid: "u1", args: { id: "a", priority: 4 } },
    { type: "item_move", uuid: "u2", args: { id: "a", project_id: "P2" } },
  ]);
  assert.deepEqual(Q.nextSyncBatch(q, 100, 6000).at(-1), { type: "item_delete", uuid: "u3", args: { id: "b" } });
  assert.equal(Q.nextHeldAt(q, 2000), 6000);
  assert.equal(Q.nextHeldAt(q, 6000), 0);
  assert.equal(Q.cancelEntry(q, "u3").entries.length, 2);
  assert.deepEqual(Q.deserialize(Q.serialize(q)), q);
});

test("enqueueQuickAdd keeps the view context", () => {
  const r = Q.enqueueQuickAdd(Q.emptyQueue(), "x", 0, uuidFn, { kind: "project", projectId: "w" });
  assert.deepEqual(r.queue.entries[0].context, { kind: "project", projectId: "w" });
  assert.equal(Q.enqueueQuickAdd(Q.emptyQueue(), "x", 0, uuidFn).queue.entries[0].context, null);
});
