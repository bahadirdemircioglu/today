import { test } from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./helpers/load-qml-js.mjs";

const M = loadQmlJs("ModelSync.js");

class FakeModel {
  constructor(rows = []) { this.rows = rows.map((r) => ({ ...r })); this.ops = []; }
  get count() { return this.rows.length; }
  get(i) { return this.rows[i]; }
  insert(i, r) { this.ops.push("insert"); this.rows.splice(i, 0, { ...r }); }
  remove(i) { this.ops.push("remove"); this.rows.splice(i, 1); }
  move(from, to, n) { this.ops.push("move"); const m = this.rows.splice(from, n); this.rows.splice(to, 0, ...m); }
  set(i, r) { this.ops.push("set"); this.rows[i] = { ...r }; }
}
const r = (key, title = key) => ({ key, title });

test("syncs order, removals and insertions", () => {
  const m = new FakeModel([r("a"), r("b"), r("c")]);
  M.sync(m, [r("c"), r("a"), r("d")]);
  assert.deepEqual(m.rows.map((x) => x.key), ["c", "a", "d"]);
});

test("unchanged rows produce no operations", () => {
  const m = new FakeModel([r("a"), r("b")]);
  M.sync(m, [r("a"), r("b")]);
  assert.deepEqual(m.ops, []);
});

test("completing one row is a single remove", () => {
  const m = new FakeModel([r("a"), r("b"), r("c")]);
  M.sync(m, [r("a"), r("c")]);
  assert.deepEqual(m.ops, ["remove"]);
});

test("changed fields are updated in place", () => {
  const m = new FakeModel([r("a", "old")]);
  M.sync(m, [r("a", "new")]);
  assert.deepEqual(m.ops, ["set"]);
  assert.equal(m.rows[0].title, "new");
});
