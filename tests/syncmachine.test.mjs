import { test } from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./helpers/load-qml-js.mjs";

const M = loadQmlJs("SyncMachine.js");
const rnd = () => 0.5; // no jitter

function run(state, ...events) {
  let s = state;
  let effects = [];
  for (const ev of events) {
    const r = M.reduce(s, { now: 0, ...ev }, rnd);
    s = r.state;
    effects = r.effects;
  }
  return { s, effects, types: effects.map((e) => e.type) };
}
const T0 = 1_000_000;
// a verified, idle, READY state with a successful sync 60 s ago
function ready(extra = {}) {
  return { ...M.initialState(), phase: "READY", hasToken: true, hasCache: true, accountVerified: true,
    lastSyncAt: T0 - 60000, lastRequestAt: T0 - 60000, ...extra };
}
const has = (effects, type) => effects.find((e) => e.type === type);

test("INIT without token -> SETUP, no effects", () => {
  const { s, types } = run(M.initialState(), { type: "INIT", hasToken: false });
  assert.equal(s.phase, "SETUP");
  assert.deepEqual(types, []);
});

test("INIT with cache -> READY + sync; without cache -> LOADING + sync", () => {
  let r = run(M.initialState(), { type: "INIT", hasToken: true, hasCache: true, now: T0 });
  assert.equal(r.s.phase, "READY");
  assert.equal(has(r.effects, "startRequest").mode, "sync");
  assert.ok(has(r.effects, "startPeriodic"));
  r = run(M.initialState(), { type: "INIT", hasToken: true, hasCache: false, now: T0 });
  assert.equal(r.s.phase, "LOADING");
  assert.equal(r.s.inFlight, "sync");
});

test("TOKEN_CLEARED -> SETUP, stop timers, clear data", () => {
  const { s, types } = run(ready({ inFlight: "sync" }), { type: "TOKEN_CLEARED" });
  assert.equal(s.phase, "SETUP");
  assert.deepEqual(types, ["abortRequest", "stopTimers", "clearData"]);
});

test("SYNC_OK -> READY, backoff reset, periodic", () => {
  const { s, types } = run(ready({ phase: "OFFLINE", inFlight: "sync", backoffStep: 3 }), { type: "REQUEST_DONE", kind: "ok", now: T0 });
  assert.equal(s.phase, "READY");
  assert.equal(s.backoffStep, 0);
  assert.equal(s.lastSyncAt, T0);
  assert.deepEqual(types, ["startPeriodic"]);
});

test("NET_FAIL -> OFFLINE + retryIn(backoff)", () => {
  const { s, effects } = run(ready({ inFlight: "sync" }), { type: "REQUEST_DONE", kind: "network" });
  assert.equal(s.phase, "OFFLINE");
  assert.deepEqual(effects, [{ type: "retryIn", ms: 30000 }]);
});

test("HTTP_SERVER -> ERROR + retryIn(retryAfter || backoff)", () => {
  let r = run(ready({ inFlight: "sync" }), { type: "REQUEST_DONE", kind: "server" });
  assert.equal(r.s.phase, "ERROR");
  assert.deepEqual(r.effects, [{ type: "retryIn", ms: 30000 }]);
  r = run(ready({ inFlight: "sync" }), { type: "REQUEST_DONE", kind: "server", retryAfterSec: 90 });
  assert.deepEqual(r.effects, [{ type: "retryIn", ms: 90000 }]);
});

test("HTTP_RATE keeps the phase and waits at least 30 s", () => {
  let r = run(ready({ inFlight: "sync" }), { type: "REQUEST_DONE", kind: "rate", retryAfterSec: 5 });
  assert.equal(r.s.phase, "READY");
  assert.equal(r.s.rateLimited, true);
  assert.deepEqual(r.effects, [{ type: "retryIn", ms: 30000 }]);
  r = run(ready({ inFlight: "sync" }), { type: "REQUEST_DONE", kind: "rate", retryAfterSec: 120 });
  assert.deepEqual(r.effects, [{ type: "retryIn", ms: 120000 }]);
});

test("HTTP_AUTH -> AUTH_INVALID, timers stopped", () => {
  const { s, types } = run(ready({ inFlight: "sync" }), { type: "REQUEST_DONE", kind: "auth" });
  assert.equal(s.phase, "AUTH_INVALID");
  assert.deepEqual(types, ["stopTimers"]);
});

test("#2 a request while in flight is coalesced into one resync", () => {
  let r = run(ready({ inFlight: "sync" }), { type: "SYNC_REQUESTED", reason: "periodic", now: T0 });
  assert.deepEqual(r.types, []);
  assert.equal(r.s.pendingResync, true);
  r = run(r.s, { type: "SYNC_REQUESTED", reason: "manual", now: T0 });
  assert.deepEqual(r.types, []);
  r = run(r.s, { type: "REQUEST_DONE", kind: "ok", now: T0 + 1000 });
  assert.equal(r.types.filter((t) => t === "startRequest").length, 1);
  assert.equal(r.s.pendingResync, false);
});

test("#3 three actions in a row -> one debounce -> one request", () => {
  let r = run(ready(), { type: "SYNC_REQUESTED", reason: "action", now: T0 });
  assert.deepEqual(r.effects, [{ type: "startDebounce", ms: 1000 }]);
  r = run(r.s, { type: "SYNC_REQUESTED", reason: "action", now: T0 + 300 });
  assert.deepEqual(r.types, []);
  r = run(r.s, { type: "SYNC_REQUESTED", reason: "action", now: T0 + 600 });
  assert.deepEqual(r.types, []);
  r = run(r.s, { type: "DEBOUNCE_FIRED", now: T0 + 1000 });
  assert.equal(r.types.filter((t) => t === "startRequest").length, 1);
});

test("#4 expanded / hover only sync when data is older than 30 s", () => {
  let r = run(ready({ lastSyncAt: T0 - 10000, lastRequestAt: T0 - 10000 }), { type: "SYNC_REQUESTED", reason: "expanded", now: T0 });
  assert.deepEqual(r.types, []);
  r = run(ready({ lastSyncAt: T0 - 40000, lastRequestAt: T0 - 40000 }), { type: "SYNC_REQUESTED", reason: "hover", now: T0 });
  assert.ok(r.types.includes("startRequest"));
});

test("#5 manual / expanded while OFFLINE do not wait for the backoff", () => {
  for (const reason of ["manual", "expanded"]) {
    const r = run(ready({ phase: "OFFLINE", backoffStep: 3 }), { type: "SYNC_REQUESTED", reason, now: T0 });
    assert.ok(r.types.includes("startRequest"), reason);
    assert.ok(r.types.includes("cancelRetry"), reason);
  }
  assert.equal(run(ready({ phase: "OFFLINE", backoffStep: 3 }), { type: "SYNC_REQUESTED", reason: "manual", now: T0 }).s.backoffStep, 0);
});

test("#6 two requests less than 5 s apart -> follow-up at 5 s", () => {
  const r = run(ready({ lastRequestAt: T0 - 2000, lastSyncAt: T0 - 40000 }), { type: "SYNC_REQUESTED", reason: "periodic", now: T0 });
  assert.deepEqual(r.effects, [{ type: "scheduleFollowUp", ms: 3000 }]);
  const f = run(r.s, { type: "SYNC_REQUESTED", reason: "followUp", now: T0 + 3000 });
  assert.ok(f.types.includes("startRequest"));
});

test("#7 #8 recovery: client error with commands -> full read -> batch dropped", () => {
  let r = run(ready({ inFlight: "sync" }), { type: "REQUEST_DONE", kind: "client", hadCommands: true, now: T0 });
  assert.equal(r.s.recovery, "readOnlyFull");
  assert.equal(has(r.effects, "startRequest").mode, "readOnlyFull");
  r = run(r.s, { type: "REQUEST_DONE", kind: "ok", fullSync: true, now: T0 + 1000 });
  assert.equal(r.s.recovery, "retryBatch");
  assert.equal(has(r.effects, "startRequest").mode, "sync");
  r = run(r.s, { type: "REQUEST_DONE", kind: "client", hadCommands: true, now: T0 + 2000 });
  assert.ok(r.types.includes("dropBatch"));
  assert.equal(r.s.phase, "READY");
  assert.equal(r.s.recovery, null);
});

test("recovery: batch accepted after the full read -> normal", () => {
  let r = run(ready({ inFlight: "sync", recovery: "retryBatch" }), { type: "REQUEST_DONE", kind: "ok", now: T0 });
  assert.equal(r.s.recovery, null);
  assert.equal(r.s.phase, "READY");
});

test("#9 recovery: the full read itself is rejected -> ERROR + retry", () => {
  let r = run(ready({ inFlight: "sync", recovery: "readOnlyFull" }), { type: "REQUEST_DONE", kind: "client", now: T0 });
  assert.equal(r.s.phase, "ERROR");
  assert.equal(r.s.recovery, null);
  assert.deepEqual(r.types, ["retryIn"]);
});

test("#10 full sync -> immediate incremental follow-up", () => {
  const r = run(ready({ inFlight: "sync" }), { type: "REQUEST_DONE", kind: "ok", fullSync: true, now: T0 });
  assert.ok(r.types.includes("scheduleFollowUp"));
});

test("#11 Quick Add rate limit stops the cycle and waits", () => {
  const r = run(ready({ inFlight: "sync" }), { type: "QUICK_ADD_DONE", kind: "rate", retryAfterSec: 30, now: T0 });
  assert.deepEqual(r.effects, [{ type: "retryIn", ms: 30000 }]);
  assert.equal(r.s.inFlight, null);
});

test("#12 AUTH_INVALID ignores sync requests", () => {
  for (const reason of ["periodic", "manual", "action", "expanded"]) {
    assert.deepEqual(run(ready({ phase: "AUTH_INVALID" }), { type: "SYNC_REQUESTED", reason, now: T0 }).types, []);
  }
});

test("#13 backoff sequence 30/60/120/300/300 s with +-20 % jitter", () => {
  assert.deepEqual([1, 2, 3, 4, 5].map((n) => M.backoffMs(n, () => 0.5)), [30000, 60000, 120000, 300000, 300000]);
  assert.equal(M.backoffMs(1, () => 0), 24000);
  assert.equal(M.backoffMs(1, () => 1), 36000);
  let r = run(ready({ inFlight: "sync" }), { type: "REQUEST_DONE", kind: "network" });
  const waits = [r.effects[0].ms];
  for (let i = 0; i < 4; i++) {
    r = run({ ...r.s, inFlight: "sync" }, { type: "REQUEST_DONE", kind: "network" });
    waits.push(r.effects[0].ms);
  }
  assert.deepEqual(waits, [30000, 60000, 120000, 300000, 300000]);
});

test("#14 TOKEN_SET only verifies the account, never sends queued commands", () => {
  const r = run(ready({ inFlight: "sync" }), { type: "TOKEN_SET", hasCache: true, now: T0 });
  assert.deepEqual(r.types, ["abortRequest", "stopTimers", "cancelRetry", "verifyAccount"]);
  assert.equal(r.s.accountVerified, false);
  assert.equal(r.s.inFlight, "verify");
  // sync requests while unverified do not start a sync
  const r2 = run(r.s, { type: "SYNC_REQUESTED", reason: "manual", now: T0 + 100 });
  assert.equal(r2.types.includes("startRequest"), false);
});

test("#15 a different account clears data and starts a fresh sync", () => {
  const r = run(ready({ inFlight: "verify", accountVerified: false }), { type: "ACCOUNT_VERIFIED", sameAccount: false, now: T0 });
  assert.deepEqual(r.types, ["clearData", "startPeriodic", "cancelRetry", "startRequest"]);
  assert.equal(r.s.phase, "LOADING");
  assert.equal(r.s.hasCache, false);
});

test("#16 the same account keeps the queue and syncs it", () => {
  const r = run(ready({ inFlight: "verify", accountVerified: false }), { type: "ACCOUNT_VERIFIED", sameAccount: true, now: T0 });
  assert.equal(r.types.includes("clearData"), false);
  assert.equal(has(r.effects, "startRequest").mode, "sync");
  assert.equal(r.s.accountVerified, true);
});

test("verification failures: auth -> AUTH_INVALID, network -> OFFLINE and retry verifies again", () => {
  const base = ready({ inFlight: "verify", accountVerified: false });
  assert.equal(run(base, { type: "VERIFY_FAILED", kind: "auth" }).s.phase, "AUTH_INVALID");
  let r = run(base, { type: "VERIFY_FAILED", kind: "network", now: T0 });
  assert.equal(r.s.phase, "OFFLINE");
  assert.deepEqual(r.types, ["retryIn"]);
  r = run(r.s, { type: "RETRY_FIRED", now: T0 + 30000 });
  assert.ok(r.types.includes("verifyAccount"));
  assert.equal(r.types.includes("startRequest"), false);
});

test("stale results (nothing in flight) are ignored", () => {
  const r = run(ready(), { type: "REQUEST_DONE", kind: "network" });
  assert.deepEqual(r.types, []);
  assert.equal(r.s.phase, "READY");
});

test("more queued work after a sync schedules a follow-up", () => {
  const r = run(ready({ inFlight: "sync" }), { type: "REQUEST_DONE", kind: "ok", moreWork: true, now: T0 });
  assert.deepEqual(r.effects.at(-1), { type: "scheduleFollowUp", ms: 1000 });
});

test("reduce never mutates the input state", () => {
  const s0 = ready({ inFlight: "sync" });
  const copy = JSON.stringify(s0);
  M.reduce(s0, { type: "REQUEST_DONE", kind: "network", now: T0 }, rnd);
  assert.equal(JSON.stringify(s0), copy);
});
