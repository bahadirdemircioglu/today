import { test } from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./helpers/load-qml-js.mjs";

const R = loadQmlJs("ContextRules.js");
const TODAY = "2026-10-03";
const task = (f = {}) => ({ id: "t1", project_id: "inbox", due: null, labels: [], ...f });
const st = { inboxProjectId: "inbox", labels: { L1: { name: "calls" } } };

test("contextFor", () => {
  assert.deepEqual(R.contextFor({ kind: "project", id: "w" }, st), { kind: "project", projectId: "w" });
  assert.deepEqual(R.contextFor({ kind: "inbox", id: "" }, st), { kind: "inbox", projectId: "inbox" });
  assert.deepEqual(R.contextFor({ kind: "label", id: "L1" }, st), { kind: "label", labelName: "calls" });
  assert.deepEqual(R.contextFor({ kind: "upcoming", id: "" }, st, "2026-10-05"), { kind: "upcoming", date: "2026-10-05" });
});

test("today / upcoming: undated tasks get the date; dated ones are left alone", () => {
  assert.deepEqual(R.followUps({ kind: "today" }, task(), TODAY, "inbox"), [{ kind: "update", args: { due: { date: TODAY } } }]);
  assert.deepEqual(R.followUps({ kind: "upcoming", date: "2026-10-06" }, task(), TODAY, "inbox"),
    [{ kind: "update", args: { due: { date: "2026-10-06" } } }]);
  assert.deepEqual(R.followUps({ kind: "today" }, task({ due: { date: "2026-10-09" } }), TODAY, "inbox"), []);
  assert.deepEqual(R.followUps(null, task(), TODAY, "inbox"), [{ kind: "update", args: { due: { date: TODAY } } }]);
});

test("project: moved unless the text chose a project; inbox view never moves", () => {
  assert.deepEqual(R.followUps({ kind: "project", projectId: "w" }, task(), TODAY, "inbox"), [{ kind: "move", projectId: "w" }]);
  assert.deepEqual(R.followUps({ kind: "project", projectId: "w" }, task({ project_id: "home" }), TODAY, "inbox"), []);
  assert.deepEqual(R.followUps({ kind: "inbox", projectId: "inbox" }, task(), TODAY, "inbox"), []);
});

test("label: added once; filter: nothing", () => {
  assert.deepEqual(R.followUps({ kind: "label", labelName: "calls" }, task({ labels: ["x"] }), TODAY, "inbox"),
    [{ kind: "update", args: { labels: ["x", "calls"] } }]);
  assert.deepEqual(R.followUps({ kind: "label", labelName: "calls" }, task({ labels: ["calls"] }), TODAY, "inbox"), []);
  assert.deepEqual(R.followUps({ kind: "filter" }, task(), TODAY, "inbox"), []);
});
