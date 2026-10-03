import { test } from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./helpers/load-qml-js.mjs";

const V = loadQmlJs("ViewModel.js");
const S = loadQmlJs("TaskStore.js");
const sys180 = () => 180;
const NOON = Date.UTC(2026, 9, 3, 9, 0); // Sat 2026-10-03 12:00 (+03:00)
const emptyQ = { v: 1, entries: [] };

let n = 0;
function item(fields) {
  n++;
  return { id: fields.id || `i${n}`, content: fields.content || `task ${n}`, project_id: "inbox", priority: 1,
    child_order: n, day_order: -1, checked: false, is_deleted: false, added_at: "2026-09-01T00:00:00Z", due: null, ...fields };
}
function store(items, extra = {}) {
  return S.applySyncResponse(S.emptyStore(), {
    full_sync: true, sync_token: "t",
    user: { id: "1", full_name: "U", inbox_project_id: "inbox", tz_info: { gmt_string: "+03:00" } },
    projects: [
      { id: "inbox", name: "Inbox", inbox_project: true, child_order: 0 },
      { id: "work", name: "Work", child_order: 2 },
      { id: "home", name: "Home", child_order: 1 },
      { id: "sub", name: "Sub", parent_id: "work", child_order: 0 },
    ],
    sections: [
      { id: "s2", name: "Later", project_id: "work", section_order: 2 },
      { id: "s1", name: "Now", project_id: "work", section_order: 1 },
    ],
    labels: [{ id: "L1", name: "health", item_order: 0 }, { id: "L2", name: "calls", item_order: 1 }],
    filters: [{ id: "F1", name: "Urgent", query: "p1", item_order: 0 }],
    items, ...extra,
  }, NOON, sys180);
}
const view = (st, key, q = emptyQ, fr) => V.computeView(st, q, V.parseSpec(key), NOON, sys180, fr);
const ids = (v) => v.groups.map((g) => [g.key, g.rows.map((r) => r.id)]);

test("parseSpec / specKey round trip and fallback", () => {
  for (const k of ["today", "upcoming", "inbox", "query", "project:abc", "label:L1", "filter:F1"]) {
    assert.equal(V.specKey(V.parseSpec(k)), k);
  }
  assert.deepEqual(V.parseSpec("project:../x"), { kind: "today", id: "" });
  assert.deepEqual(V.parseSpec(""), { kind: "today", id: "" });
});

test("today view equals computeToday", () => {
  const st = store([
    item({ id: "o", due: { date: "2026-10-01" } }),
    item({ id: "t", due: { date: "2026-10-03T15:00:00" } }),
    item({ id: "f", due: { date: "2026-10-05" } }),
    item({ id: "u" }),
  ]);
  const v = view(st, "today");
  const t = S.computeToday(st, emptyQ, NOON, sys180);
  assert.deepEqual(ids(v), [["overdue", t.overdue.map((r) => r.id)], ["today", t.today.map((r) => r.id)]]);
  assert.equal(v.counts.total, 2);
  assert.equal(v.counts.overdue, 1);
});

test("inbox: undated and dated inbox tasks in manual order", () => {
  const st = store([
    item({ id: "b", child_order: 2 }),
    item({ id: "a", child_order: 1, due: { date: "2026-12-01" } }),
    item({ id: "w", project_id: "work" }),
  ]);
  assert.deepEqual(ids(view(st, "inbox")), [["s:none", ["a", "b"]]]);
});

test("project: sections in order, sub-tasks under their parent with depth", () => {
  const st = store([
    item({ id: "p1", project_id: "work", child_order: 1 }),
    item({ id: "c1", project_id: "work", parent_id: "p1", child_order: 2 }),
    item({ id: "c0", project_id: "work", parent_id: "p1", child_order: 1 }),
    item({ id: "g1", project_id: "work", parent_id: "c0", child_order: 1 }),
    item({ id: "n1", project_id: "work", section_id: "s1", child_order: 1 }),
    item({ id: "l1", project_id: "work", section_id: "s2", child_order: 1 }),
    item({ id: "orphan", project_id: "work", parent_id: "gone", child_order: 9 }),
  ]);
  const v = view(st, "project:work");
  assert.equal(v.title, "Work");
  assert.deepEqual(ids(v), [["s:none", ["p1", "c0", "g1", "c1", "orphan"]], ["s:s1", ["n1"]], ["s:s2", ["l1"]]]);
  assert.deepEqual(v.groups[0].rows.map((r) => r.depth), [0, 1, 2, 1, 0]);
  assert.equal(v.groups[1].label, "Now");
});

test("upcoming: overdue first, then seven day groups including empty days", () => {
  const st = store([
    item({ id: "old", due: { date: "2026-09-30" } }),
    item({ id: "d0", due: { date: "2026-10-03" } }),
    item({ id: "d2", due: { date: "2026-10-05T09:00:00" } }),
    item({ id: "d6", due: { date: "2026-10-09" } }),
    item({ id: "d7", due: { date: "2026-10-10" } }),
  ]);
  const v = view(st, "upcoming");
  assert.equal(v.groups.length, 8);
  assert.deepEqual(v.groups[0].rows.map((r) => r.id), ["old"]);
  assert.deepEqual(v.groups.slice(1).map((g) => g.dateKey), ["2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09"]);
  assert.deepEqual(v.groups.slice(1).map((g) => g.rows.length), [1, 0, 1, 0, 0, 0, 1]);
  const rows = V.flattenView(v);
  assert.equal(rows.filter((r) => r.kind === "header").length, 4);
  assert.equal(rows.find((r) => r.itemId === "d2").header, "day");
});

test("label: tasks carrying the label, dated first", () => {
  const st = store([
    item({ id: "x", labels: ["health"], priority: 4 }),
    item({ id: "y", labels: ["health", "calls"], due: { date: "2026-10-04" } }),
    item({ id: "z", labels: ["calls"] }),
  ]);
  const v = view(st, "label:L1");
  assert.equal(v.title, "health");
  assert.deepEqual(ids(v), [["all", ["y", "x"]]]);
});

test("filter: server result order, overlay applied, missing ids counted", () => {
  const st = store([item({ id: "a" }), item({ id: "b" }), item({ id: "c" })]);
  const q = { v: 1, entries: [{ kind: "close", uuid: "u", itemId: "b" }] };
  const v = view(st, "filter:F1", q, { F1: { ids: ["c", "b", "zzz", "a"], fetchedAt: 5 } });
  assert.deepEqual(ids(v), [["all", ["c", "a"]]]);
  assert.equal(v.filterMissing, 1);
  assert.equal(v.filterFetchedAt, 5);
  assert.equal(view(st, "filter:F1").hasFilterResult, false);
});

test("views of a vanished project or label report exists=false", () => {
  const st = store([]);
  assert.equal(view(st, "project:nope").exists, false);
  assert.equal(view(st, "label:nope").exists, false);
  assert.equal(view(st, "inbox").exists, true);
});

test("overlay works in every view (move, update, close)", () => {
  const st = store([item({ id: "a", project_id: "inbox" }), item({ id: "b", project_id: "inbox" })]);
  const q = { v: 1, entries: [
    { kind: "move", uuid: "1", itemId: "a", projectId: "work" },
    { kind: "update", uuid: "2", itemId: "b", args: { labels: ["calls"] } },
  ] };
  assert.deepEqual(ids(view(st, "project:work", q)), [["s:none", ["a"]]]);
  assert.deepEqual(ids(view(st, "label:L2", q)), [["all", ["b"]]]);
  assert.deepEqual(ids(view(st, "inbox", q)), [["s:none", ["b"]]]);
});

test("flattenView: uniform roles, headers, pending rows", () => {
  const st = store([
    item({ id: "n1", project_id: "work", section_id: "s1" }),
    item({ id: "p", project_id: "work" }),
  ]);
  const q = { v: 1, entries: [{ kind: "quick_add", localId: "L", text: "New", state: "pending" }] };
  const rows = V.flattenView(view(st, "project:work", q));
  assert.deepEqual(rows.map((r) => [r.key, r.header, r.headerText]),
    [["t:p", "", ""], ["t:n1", "section", "Now"], ["q:L", "pending", ""]]);
  const keys = Object.keys(rows[0]).sort();
  for (const r of rows) assert.deepEqual(Object.keys(r).sort(), keys);
  const today = V.flattenView(view(store([item({ id: "t", due: { date: "2026-10-03" } })]), "today"));
  assert.equal(today[0].header, "");
  assert.equal(today[0].showDate, false);
});

test("navList: fixed views, project tree, labels, filters with counts", () => {
  const st = store([
    item({ id: "a" }),
    item({ id: "b", project_id: "work", labels: ["health"], due: { date: "2026-10-03" } }),
    item({ id: "c", project_id: "sub", due: { date: "2026-10-06" } }),
  ]);
  const nav = V.navList(st, emptyQ, NOON, sys180, { F1: { ids: ["a", "x"], fetchedAt: 1 } });
  assert.deepEqual(nav.map((e) => [e.key, e.count, e.depth]), [
    ["inbox", 1, 0], ["today", 1, 0], ["upcoming", 2, 0],
    ["project:home", 0, 0], ["project:work", 1, 0], ["project:sub", 1, 1],
    ["label:L1", 1, 0], ["label:L2", 0, 0],
    ["filter:F1", 1, 0],
  ]);
  assert.equal(V.navList(st, emptyQ, NOON, sys180, {}).at(-1).count, -1);
});

test("deadline and description roles", () => {
  const st = store([
    item({ id: "d", project_id: "work", deadline: { date: "2026-10-03", lang: "en" }, description: "First line\nSecond line" }),
    item({ id: "e", project_id: "work", deadline: { date: "2026-10-20" } }),
  ]);
  const rows = V.flattenView(view(st, "project:work"));
  const d = rows.find((r) => r.itemId === "d");
  const e = rows.find((r) => r.itemId === "e");
  assert.deepEqual([d.deadlineKey, d.deadlineDue, d.description, d.descriptionFull],
    ["2026-10-03", true, "First line", "First line\nSecond line"]);
  assert.deepEqual([e.deadlineKey, e.deadlineDue], ["2026-10-20", false]);
});

test("collapsed parents hide their sub-tasks and report childCount", () => {
  const st = store([
    item({ id: "p", project_id: "work", child_order: 1 }),
    item({ id: "c1", project_id: "work", parent_id: "p", child_order: 1 }),
    item({ id: "c2", project_id: "work", parent_id: "p", child_order: 2 }),
  ]);
  const open = V.computeView(st, emptyQ, V.parseSpec("project:work"), NOON, sys180, {}, {});
  assert.deepEqual(ids(open), [["s:none", ["p", "c1", "c2"]]]);
  assert.equal(open.groups[0].rows[0].childCount, 2);
  assert.equal(open.groups[0].rows[0].collapsed, false);
  const closed = V.computeView(st, emptyQ, V.parseSpec("project:work"), NOON, sys180, {}, { collapsed: { p: true } });
  assert.deepEqual(ids(closed), [["s:none", ["p"]]]);
  const row = V.flattenView(closed)[0];
  assert.deepEqual([row.childCount, row.collapsed], [2, true]);
});

test("custom query view and nav entry", () => {
  const st = store([item({ id: "a" }), item({ id: "b" })]);
  const opts = { customQuery: { name: "Focus", query: "today & p1" } };
  const results = { __query: { ids: ["b", "a"], fetchedAt: 9 } };
  const v = V.computeView(st, emptyQ, V.parseSpec("query"), NOON, sys180, results, opts);
  assert.equal(v.title, "Focus");
  assert.equal(v.exists, true);
  assert.deepEqual(ids(v), [["all", ["b", "a"]]]);
  assert.equal(V.computeView(st, emptyQ, V.parseSpec("query"), NOON, sys180, {}, opts).hasFilterResult, false);
  assert.equal(V.computeView(st, emptyQ, V.parseSpec("query"), NOON, sys180, results, {}).exists, false);
  const nav = V.navList(st, emptyQ, NOON, sys180, results, opts);
  assert.deepEqual(nav[3], { key: "query", kind: "query", id: "", name: "Focus", count: 2, depth: 0 });
  assert.equal(V.navList(st, emptyQ, NOON, sys180, results, {}).some((e) => e.kind === "query"), false);
});
