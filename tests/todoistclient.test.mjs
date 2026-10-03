import { test } from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./helpers/load-qml-js.mjs";

class FakeXHR {
  static last = null;
  static respond = { status: 200, body: "{}", headers: {} };
  constructor() { this.headers = {}; this.readyState = 0; FakeXHR.last = this; }
  open(method, url) { this.method = method; this.url = url; }
  setRequestHeader(k, v) { this.headers[k] = v; }
  getResponseHeader(k) { return FakeXHR.respond.headers[k] ?? null; }
  send(body) {
    this.body = body;
    this.readyState = 4;
    this.status = FakeXHR.respond.status;
    this.responseText = FakeXHR.respond.body;
    this.onreadystatechange();
  }
}
const C = loadQmlJs("TodoistClient.js", { globals: { XMLHttpRequest: FakeXHR } });

function call(fn, status, body = "{}", headers = {}) {
  FakeXHR.respond = { status, body, headers };
  let result;
  fn((r) => { result = r; });
  return result;
}

test("#1 sync request shape; commands omitted when empty", () => {
  call((cb) => C.sync("t", { syncToken: "abc", commands: [] }, cb), 200);
  const x = FakeXHR.last;
  assert.equal(x.method, "POST");
  assert.equal(x.url, "https://api.todoist.com/api/v1/sync");
  assert.equal(x.headers.Authorization, "Bearer t");
  assert.equal(x.headers["Content-Type"], "application/x-www-form-urlencoded");
  const form = new URLSearchParams(x.body);
  assert.equal(form.get("sync_token"), "abc");
  assert.deepEqual(JSON.parse(form.get("resource_types")), ["items", "projects", "sections", "labels", "filters", "user", "user_item_orders"]);
  assert.equal(form.has("commands"), false);

  const cmds = [{ type: "item_close", uuid: "u", args: { id: "1" } }];
  call((cb) => C.sync("t", { syncToken: "*", commands: cmds }, cb), 200);
  assert.deepEqual(JSON.parse(new URLSearchParams(FakeXHR.last.body).get("commands")), cmds);
});

test("#2 quickAdd sends JSON", () => {
  call((cb) => C.quickAdd("t", "a & b", cb), 200);
  assert.equal(FakeXHR.last.url, "https://api.todoist.com/api/v1/tasks/quick");
  assert.equal(FakeXHR.last.headers["Content-Type"], "application/json");
  assert.equal(FakeXHR.last.body, '{"text":"a & b","meta":false}');
});

test("getUser is a GET", () => {
  const r = call((cb) => C.getUser("t", cb), 200, '{"id":"1"}');
  assert.equal(FakeXHR.last.method, "GET");
  assert.equal(FakeXHR.last.url, "https://api.todoist.com/api/v1/user");
  assert.equal(r.json.id, "1");
});

test("#3-#9 classification", () => {
  const kind = (status, body, headers) => call((cb) => C.getUser("t", cb), status, body, headers);
  assert.equal(kind(200, '{"a":1}').kind, "ok");
  assert.equal(kind(0, "").kind, "network");
  assert.equal(kind(401, "{}").kind, "auth");
  assert.equal(kind(403, "").kind, "auth");
  assert.deepEqual([kind(429, "{}", { "Retry-After": "12" }).kind, kind(429, "{}", { "Retry-After": "12" }).retryAfterSec], ["rate", 12]);
  assert.equal(kind(429, '{"error_extra":{"retry_after":7}}').retryAfterSec, 7);
  assert.equal(kind(429, "not json").retryAfterSec, 60);
  assert.equal(kind(502, "").kind, "server");
  assert.equal(kind(400, '{"error_tag":"INVALID_ARGUMENT"}').kind, "client");
  assert.equal(kind(200, "{broken").kind, "server");
});

test("results never contain the token", () => {
  const r = call((cb) => C.getUser("secret-token", cb), 401, '{"error":"x"}');
  assert.equal(JSON.stringify(r).includes("secret-token"), false);
});
