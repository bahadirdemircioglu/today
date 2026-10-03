import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { loadQmlJs } from "./helpers/load-qml-js.mjs";

const S = loadQmlJs("TaskStore.js");
const fixture = (n) => JSON.parse(fs.readFileSync(new URL(`./fixtures/${n}.json`, import.meta.url), "utf8"));
const sys180 = () => 180;
// 2026-10-03 12:00 in UTC+3
const NOON = Date.UTC(2026, 9, 3, 9, 0);
const emptyQ = { v: 1, entries: [] };

function storeWith(items, extra = {}) {
  return S.applySyncResponse(S.emptyStore(), {
    full_sync: true, sync_token: "t",
    user: { id: "1", full_name: "U", inbox_project_id: "inbox", tz_info: { gmt_string: "+03:00" } },
    items, ...extra,
  }, NOON, sys180);
}
let n = 0;
function item(fields) {
  n++;
  return { id: fields.id || `i${n}`, content: fields.content || `task ${n}`, project_id: "inbox", priority: 1,
    child_order: n, day_order: -1, checked: false, is_deleted: false, added_at: "2026-09-01T00:00:00Z", ...fields };
}

test("#1 full sync keeps every open item (dated or not) and the v2 resources", () => {
  const s = S.applySyncResponse(S.emptyStore(), fixture("full-sync"), NOON, sys180);
  assert.deepEqual(Object.keys(s.items).sort(), ["6X7rM8997g3RQmvh", "6X7rfEVP8hvv25ZQ", "6X7rfFVPjhvv84XG"]);
  assert.equal(s.items["6X7rfEVP8hvv25ZQ"].sectionId, "S1");
  assert.equal(s.items["6X7rfEVP8hvv25ZQ"].description, "Line one");
  assert.deepEqual(s.items["6X7rM8997g3RQmvh"].labels, ["health"]);
  assert.deepEqual(Object.keys(s.sections), ["S1"]);
  assert.deepEqual(s.sections.S1, { name: "Ideas", projectId: "6Jf8VQXxpwv56VQ7", order: 1 });
  assert.deepEqual(s.labels.L1, { name: "health", color: "red", order: 0 });
  assert.deepEqual(s.filters.F1, { name: "Urgent", query: "today & p1", color: "red", order: 0 });
  assert.equal(s.projects["6Jf8VQXxpwv56VQ7"].isInbox, true);
  assert.equal(s.projects["6Jf8VQXxpwv56VQ8"].order, 2);
  // undated items never enter Today
  assert.equal(S.computeToday(s, emptyQ, NOON, sys180).unparsable, 0);
  assert.equal(s.syncToken, fixture("full-sync").sync_token);
  assert.equal(s.accountId, "2671355");
  assert.equal(s.accountName, "Ada Lovelace");
  assert.equal(s.inboxProjectId, "6Jf8VQXxpwv56VQ7");
});

test("#2 #4 incremental: checked item removed, new item added and visible", () => {
  let s = S.applySyncResponse(S.emptyStore(), fixture("full-sync"), NOON, sys180);
  s = S.applySyncResponse(s, fixture("incremental"), NOON, sys180);
  assert.equal(s.items["6X7rM8997g3RQmvh"], undefined);
  assert.ok(s.items["6X7rNEWITEM00001"]);
  assert.equal(s.syncToken, "Zx9-incremental-token");
  const v = S.computeToday(s, emptyQ, NOON, sys180);
  assert.deepEqual(v.today.map((r) => r.id), ["6X7rNEWITEM00001"]);
  assert.equal(v.today[0].title, "Call Ann about docs");
  assert.equal(v.today[0].projectName, "Home");
});

test("#3 incremental: deleted item removed", () => {
  const s0 = storeWith([item({ id: "a", due: { date: "2026-10-03" } })]);
  const s = S.applySyncResponse(s0, { full_sync: false, items: [{ id: "a", is_deleted: true }] }, NOON, sys180);
  assert.equal(s.items.a, undefined);
});

test("#5 item moved to tomorrow leaves Today but stays cached", () => {
  const s0 = storeWith([item({ id: "a", due: { date: "2026-10-03" } })]);
  const s = S.applySyncResponse(s0, { full_sync: false, items: [item({ id: "a", due: { date: "2026-10-04" } })] }, NOON, sys180);
  assert.ok(s.items.a);
  const v = S.computeToday(s, emptyQ, NOON, sys180);
  assert.equal(v.counts.total, 0);
});

test("#6 full sync replaces the whole cache", () => {
  const s0 = storeWith([item({ id: "old", due: { date: "2026-10-03" } })]);
  const s = S.applySyncResponse(s0, { full_sync: true, sync_token: "x", items: [item({ id: "new", due: { date: "2026-10-03" } })] }, NOON, sys180);
  assert.deepEqual(Object.keys(s.items), ["new"]);
});

test("#7 tz follows the system when offsets match", () => {
  const s = storeWith([]);
  assert.deepEqual(s.tz, { gmtOffsetMin: 180, followSystem: true, timezone: "" });
  const s2 = S.applySyncResponse(S.emptyStore(), { user: { id: "1", tz_info: { gmt_string: "+03:00" } } }, NOON, () => -240);
  assert.equal(s2.tz.followSystem, false);
});

test("#8 #8b user_item_orders: deletions and non-day scopes", () => {
  let s = storeWith([], { user_item_orders: [
    { item_id: "a", scope: "day", scope_id: 0, order_key: "a1", is_deleted: false },
    { item_id: "b", scope: "project", scope_id: 0, order_key: "zz", is_deleted: false },
    { item_id: "c", scope: "day", scope_id: 5, order_key: "zz", is_deleted: false },
  ] });
  assert.deepEqual(s.orderKeys, { a: "a1" });
  s = S.applySyncResponse(s, { user_item_orders: [
    { item_id: "a", scope: "project", scope_id: 0, order_key: null, is_deleted: true },
  ] }, NOON, sys180);
  assert.deepEqual(s.orderKeys, { a: "a1" });
  s = S.applySyncResponse(s, { user_item_orders: [
    { item_id: "a", scope: "day", scope_id: 0, order_key: null, is_deleted: true },
  ] }, NOON, sys180);
  assert.deepEqual(s.orderKeys, {});
});

test("#9 ordering: timed first by time, then by order key", () => {
  const s = storeWith([
    item({ id: "yest", due: { date: "2026-10-02" } }),
    item({ id: "t0900", due: { date: "2026-10-03T09:00:00" } }),
    item({ id: "a2", due: { date: "2026-10-03" } }),
    item({ id: "a1", due: { date: "2026-10-03" } }),
    item({ id: "t0800", due: { date: "2026-10-03T08:00:00" } }),
  ], { user_item_orders: [
    { item_id: "a2", scope: "day", scope_id: 0, order_key: "a2" },
    { item_id: "a1", scope: "day", scope_id: 0, order_key: "a1" },
  ] });
  const v = S.computeToday(s, emptyQ, NOON, sys180);
  assert.deepEqual(v.overdue.map((r) => r.id), ["yest"]);
  assert.deepEqual(v.today.map((r) => r.id), ["t0800", "t0900", "a1", "a2"]);
});

test("#10 fallback ordering: day_order, then priority", () => {
  const s = storeWith([
    item({ id: "d2", day_order: 2, due: { date: "2026-10-03" } }),
    item({ id: "d1", day_order: 1, due: { date: "2026-10-03" } }),
    item({ id: "p1", priority: 1, due: { date: "2026-10-03" } }),
    item({ id: "p4", priority: 4, due: { date: "2026-10-03" } }),
  ]);
  const v = S.computeToday(s, emptyQ, NOON, sys180);
  assert.deepEqual(v.today.map((r) => r.id), ["d1", "d2", "p4", "p1"]);
});

test("#11 a timed task whose time has passed stays in Today, flagged late", () => {
  const s = storeWith([item({ id: "a", due: { date: "2026-10-03T10:00:00" } })]);
  const v = S.computeToday(s, emptyQ, Date.UTC(2026, 9, 3, 8, 0), sys180); // 11:00 local
  assert.equal(v.today[0].isLate, true);
  assert.equal(v.overdue.length, 0);
});

test("#12 #13 queue overlay: closes hidden, quick adds pending", () => {
  const s = storeWith([item({ id: "x", due: { date: "2026-10-03" } }), item({ id: "y", due: { date: "2026-10-03" } })]);
  const q = { v: 1, entries: [
    { kind: "close", uuid: "u", itemId: "x", createdAt: 0, attempts: 0 },
    { kind: "quick_add", localId: "L1", text: "Buy milk", createdAt: 0, attempts: 0, state: "pending", sentAt: null },
  ] };
  const v = S.computeToday(s, q, NOON, sys180);
  assert.deepEqual(v.today.map((r) => r.id), ["y"]);
  assert.equal(v.counts.total, 1);
  assert.equal(v.pending.length, 1);
  assert.equal(v.pending[0].localId, "L1");
  assert.equal(v.pending[0].text, "Buy milk");
});

test("#14 next task: first upcoming timed task", () => {
  const s = storeWith([
    item({ id: "late", due: { date: "2026-10-03T10:00:00" } }),
    item({ id: "later", due: { date: "2026-10-03T15:00:00" } }),
    item({ id: "untimed", due: { date: "2026-10-03" } }),
  ]);
  assert.equal(S.computeToday(s, emptyQ, NOON, sys180).next.id, "later");
});

test("#15 plainTitle strips markdown", () => {
  assert.equal(S.plainTitle("Call **Ann** [docs](https://x)"), "Call Ann docs");
  assert.equal(S.plainTitle("*urgent* and __bold__ `code` ~~gone~~"), "urgent and bold code gone");
  assert.equal(S.plainTitle("* Header-ish task"), "Header-ish task");
  assert.equal(S.plainTitle("snake_case_name stays"), "snake_case_name stays");
  assert.equal(S.plainTitle("<b>not html</b>"), "<b>not html</b>");
});

test("v2 resources: deletions in incremental syncs", () => {
  let s = S.applySyncResponse(S.emptyStore(), fixture("full-sync"), NOON, sys180);
  s = S.applySyncResponse(s, { sections: [{ id: "S1", is_deleted: true }], labels: [{ id: "L1", is_deleted: true }],
    filters: [{ id: "F1", is_deleted: true }] }, NOON, sys180);
  assert.deepEqual([Object.keys(s.sections), Object.keys(s.labels), Object.keys(s.filters)], [[], [], []]);
});

test("#16 deserialize rejects garbage and other versions", () => {
  assert.deepEqual(S.deserialize("bozuk"), S.emptyStore());
  assert.deepEqual(S.deserialize(JSON.stringify({ v: 99 })), S.emptyStore());
  assert.deepEqual(S.deserialize(JSON.stringify({ v: 1, items: {} })), S.emptyStore());
  const s = storeWith([item({ id: "a", due: { date: "2026-10-03" } })]);
  assert.deepEqual(S.deserialize(S.serialize(s)), s);
});

test("#17 archived / deleted projects are dropped", () => {
  let s = storeWith([item({ id: "a", project_id: "P", due: { date: "2026-10-03" } })], {
    projects: [{ id: "P", name: "Work" }],
  });
  assert.equal(S.computeToday(s, emptyQ, NOON, sys180).today[0].projectName, "Work");
  s = S.applySyncResponse(s, { projects: [{ id: "P", name: "Work", is_archived: true }] }, NOON, sys180);
  assert.equal(s.projects.P, undefined);
  assert.equal(S.computeToday(s, emptyQ, NOON, sys180).today[0].projectName, "");
});

test("inbox project name is not shown", () => {
  const s = storeWith([item({ id: "a", project_id: "inbox", due: { date: "2026-10-03" } })], {
    projects: [{ id: "inbox", name: "Inbox" }],
  });
  assert.equal(S.computeToday(s, emptyQ, NOON, sys180).today[0].projectName, "");
});

test("recently added items without a due date are remembered for Quick Add matching", () => {
  const s = storeWith([item({ id: "nodue", content: "Buy milk", due: null, added_at: "2026-10-03T08:58:00Z" })]);
  assert.equal(s.items.nodue.due, null);
  assert.equal(s.recent.nodue.content, "Buy milk");
  const later = S.applySyncResponse(s, { items: [] }, NOON + 31 * 60 * 1000, sys180);
  assert.equal(later.recent.nodue, undefined);
});

test("flattenRows produces uniform rows with sections", () => {
  const s = storeWith([
    item({ id: "o", due: { date: "2026-10-01" } }),
    item({ id: "t", due: { date: "2026-10-03T13:30:00" } }),
  ]);
  const q = { v: 1, entries: [{ kind: "quick_add", localId: "L", text: "New", state: "pending" }] };
  const rows = S.flattenRows(S.computeToday(s, q, NOON, sys180));
  assert.deepEqual(rows.map((r) => [r.key, r.section, r.header, r.minutes]),
    [["t:o", "overdue", "overdue", -1], ["t:t", "today", "today", 810], ["q:L", "pending", "pending", -1]]);
  const keys = Object.keys(rows[0]).sort();
  for (const r of rows) assert.deepEqual(Object.keys(r).sort(), keys);
});

test("flattenRows: no Today label without overdue rows; one label per section", () => {
  const s = storeWith([
    item({ id: "a", due: { date: "2026-10-03" } }),
    item({ id: "b", due: { date: "2026-10-03" } }),
  ]);
  const rows = S.flattenRows(S.computeToday(s, emptyQ, NOON, sys180));
  assert.deepEqual(rows.map((r) => r.header), ["", ""]);
});

test("isValidId", () => {
  assert.equal(S.isValidId("6X7rM8997g3RQmvh"), true);
  assert.equal(S.isValidId("../x"), false);
});

test("queue overlay: update / move / delete are reflected immediately", () => {
  const s = storeWith([
    item({ id: "a", content: "Old", priority: 1, due: { date: "2026-10-03" } }),
    item({ id: "b", due: { date: "2026-10-03" } }),
    item({ id: "c", due: { date: "2026-10-03" } }),
  ], { projects: [{ id: "P", name: "Work" }] });
  const q = { v: 1, entries: [
    { kind: "update", uuid: "1", itemId: "a", args: { content: "New **title**", priority: 4 } },
    { kind: "move", uuid: "2", itemId: "a", projectId: "P" },
    { kind: "update", uuid: "3", itemId: "b", args: { due: { date: "2026-10-04" } } },
    { kind: "delete", uuid: "4", itemId: "c", sendAfter: 0 },
  ] };
  const v = S.computeToday(s, q, NOON, sys180);
  assert.deepEqual(v.today.map((r) => r.id), ["a"]);
  assert.equal(v.today[0].title, "New title");
  assert.equal(v.today[0].content, "New **title**");
  assert.equal(v.today[0].priority, 4);
  assert.equal(v.today[0].projectName, "Work");
  assert.equal(s.items.a.content, "Old");
});

test("projectList: Inbox first, then by name", () => {
  const s = storeWith([], { projects: [{ id: "z", name: "zeta" }, { id: "inbox", name: "Inbox" }, { id: "a", name: "Alpha" }] });
  assert.deepEqual(S.projectList(s).map((p) => p.id), ["inbox", "a", "z"]);
});
