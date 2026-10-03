.pragma library

// Pure sync state machine: reduce(state, event, randomFn) -> { state, effects }.
// All concurrency / retry / recovery decisions live here so they can be unit-tested in Node.
// SyncController.qml only executes the effects (timers, XHR, storage) and feeds results back.
//
// Events (every event carries `now` in ms):
//   INIT{hasToken, hasCache}            TOKEN_SET{hasCache}        TOKEN_CLEARED
//   SYNC_REQUESTED{reason}              reason: periodic|expanded|hover|action|dayChanged|manual|retry|followUp|view
//   DEBOUNCE_FIRED                      RETRY_FIRED
//   REQUEST_DONE{kind, retryAfterSec, hadCommands, fullSync, moreWork}
//   QUICK_ADD_DONE{kind, retryAfterSec} (a Quick Add failure that ends the cycle)
//   ACCOUNT_VERIFIED{sameAccount}       VERIFY_FAILED{kind, retryAfterSec}
// Effects:
//   startRequest{mode: "sync"|"readOnlyFull"}  verifyAccount  abortRequest  cancelRetry
//   startDebounce{ms}  retryIn{ms}  scheduleFollowUp{ms}  startPeriodic  stopTimers
//   clearData  dropBatch

var PHASE_SETUP = "SETUP";
var PHASE_LOADING = "LOADING";
var PHASE_READY = "READY";
var PHASE_OFFLINE = "OFFLINE";
var PHASE_ERROR = "ERROR";
var PHASE_AUTH_INVALID = "AUTH_INVALID";

var DEBOUNCE_MS = 1000;
var MIN_GAP_MS = 5000;
var STALE_MS = 30000;
var FOLLOW_UP_MS = 1000;
var MIN_RATE_WAIT_SEC = 30;
var BACKOFF_SEC = [30, 60, 120, 300];

function initialState() {
    return {
        phase: PHASE_SETUP,
        hasToken: false,
        hasCache: false,
        accountVerified: false,
        inFlight: null,          // null | "sync" | "verify"
        pendingResync: false,
        lastSyncAt: 0,           // last successful sync
        lastRequestAt: 0,        // last request start
        backoffStep: 0,
        recovery: null,          // null | "readOnlyFull" | "retryBatch"
        debouncing: false,
        rateLimited: false
    };
}

function copy(state) {
    var s = {};
    for (var k in state) {
        if (Object.prototype.hasOwnProperty.call(state, k)) {
            s[k] = state[k];
        }
    }
    return s;
}

// step >= 1 -> 30/60/120/300/300... seconds, +-20% jitter, in ms
function backoffMs(step, randomFn) {
    var rnd = randomFn || Math.random;
    var idx = Math.max(0, Math.min(step, BACKOFF_SEC.length) - 1);
    var base = BACKOFF_SEC[idx] * 1000;
    return Math.round(base * (0.8 + 0.4 * rnd()));
}

function startSync(s, now, effects) {
    s.inFlight = "sync";
    s.pendingResync = false;
    s.lastRequestAt = now;
    effects.push({ type: "cancelRetry" });
    effects.push({ type: "startRequest", mode: s.recovery === "readOnlyFull" ? "readOnlyFull" : "sync" });
}

function startVerify(s, now, effects) {
    s.inFlight = "verify";
    s.lastRequestAt = now;
    effects.push({ type: "cancelRetry" });
    effects.push({ type: "verifyAccount" });
}

function canSync(s) {
    return s.hasToken && s.phase !== PHASE_SETUP && s.phase !== PHASE_AUTH_INVALID;
}

// gapExempt: retries, follow-ups, coalesced resyncs and debounced user actions
function requestSync(s, now, effects, gapExempt) {
    if (!canSync(s)) {
        return;
    }
    if (!s.accountVerified) {
        if (s.inFlight === null) {
            startVerify(s, now, effects);
        }
        return;
    }
    if (s.inFlight !== null) {
        s.pendingResync = true;
        return;
    }
    if (!gapExempt && s.lastRequestAt > 0 && now - s.lastRequestAt < MIN_GAP_MS) {
        effects.push({ type: "scheduleFollowUp", ms: MIN_GAP_MS - (now - s.lastRequestAt) });
        return;
    }
    startSync(s, now, effects);
}

// Shared failure handling for sync, Quick Add and verification requests.
function fail(s, ev, effects, randomFn) {
    s.pendingResync = false;
    var kind = ev.kind;
    var ra = typeof ev.retryAfterSec === "number" && ev.retryAfterSec > 0 ? ev.retryAfterSec : null;
    if (kind === "auth") {
        s.phase = PHASE_AUTH_INVALID;
        s.recovery = null;
        effects.push({ type: "stopTimers" });
        return;
    }
    if (kind === "rate") {
        s.rateLimited = true;
        effects.push({ type: "retryIn", ms: Math.max(ra || 0, MIN_RATE_WAIT_SEC) * 1000 });
        return;
    }
    s.backoffStep = s.backoffStep + 1;
    var wait = backoffMs(s.backoffStep, randomFn);
    if (kind === "network") {
        s.phase = PHASE_OFFLINE;
        s.recovery = null;
        effects.push({ type: "retryIn", ms: wait });
        return;
    }
    // server, client (outside the recovery path) and anything unexpected
    s.phase = PHASE_ERROR;
    effects.push({ type: "retryIn", ms: ra !== null ? ra * 1000 : wait });
}

function succeed(s, ev, effects) {
    s.phase = PHASE_READY;
    s.hasCache = true;
    s.backoffStep = 0;
    s.rateLimited = false;
    s.lastSyncAt = ev.now;
    effects.push({ type: "startPeriodic" });
}

function reduce(state, ev, randomFn) {
    var s = copy(state || initialState());
    var effects = [];
    var now = ev.now || 0;

    switch (ev.type) {
    case "INIT":
        s.hasToken = !!ev.hasToken;
        s.hasCache = !!ev.hasCache;
        if (!s.hasToken) {
            s.phase = PHASE_SETUP;
            break;
        }
        // the cache was built with this very token: no account verification needed
        s.accountVerified = true;
        s.phase = s.hasCache ? PHASE_READY : PHASE_LOADING;
        effects.push({ type: "startPeriodic" });
        startSync(s, now, effects);
        break;

    case "TOKEN_CLEARED":
        s = initialState();
        effects.push({ type: "abortRequest" });
        effects.push({ type: "stopTimers" });
        effects.push({ type: "clearData" });
        break;

    case "TOKEN_SET":
        if (s.inFlight !== null) {
            effects.push({ type: "abortRequest" });
        }
        s.hasToken = true;
        s.hasCache = !!ev.hasCache;
        s.phase = s.hasCache ? PHASE_READY : PHASE_LOADING;
        s.accountVerified = false;
        s.inFlight = null;
        s.pendingResync = false;
        s.recovery = null;
        s.backoffStep = 0;
        s.rateLimited = false;
        s.debouncing = false;
        effects.push({ type: "stopTimers" });
        // no queued command may reach the server before we know whose account this is
        startVerify(s, now, effects);
        break;

    case "ACCOUNT_VERIFIED":
        if (s.inFlight !== "verify") {
            break;
        }
        s.inFlight = null;
        s.accountVerified = true;
        s.backoffStep = 0;
        if (!ev.sameAccount) {
            effects.push({ type: "clearData" });
            s.hasCache = false;
            s.phase = PHASE_LOADING;
        }
        effects.push({ type: "startPeriodic" });
        startSync(s, now, effects);
        break;

    case "VERIFY_FAILED":
        if (s.inFlight !== "verify") {
            break;
        }
        s.inFlight = null;
        fail(s, ev, effects, randomFn);
        break;

    case "SYNC_REQUESTED": {
        var reason = ev.reason;
        if (!canSync(s)) {
            break;
        }
        if (reason === "action") {
            if (!s.debouncing) {
                s.debouncing = true;
                effects.push({ type: "startDebounce", ms: DEBOUNCE_MS });
            }
            break;
        }
        if ((reason === "expanded" || reason === "hover") && s.lastSyncAt > 0 && now - s.lastSyncAt < STALE_MS) {
            break;
        }
        if (reason === "manual") {
            s.backoffStep = 0;
        }
        // "view": the user switched to a view that needs fresh server data (a filter)
        requestSync(s, now, effects, reason === "retry" || reason === "followUp" || reason === "view");
        break;
    }

    case "DEBOUNCE_FIRED":
        s.debouncing = false;
        requestSync(s, now, effects, true);
        break;

    case "RETRY_FIRED":
        requestSync(s, now, effects, true);
        break;

    case "REQUEST_DONE":
        if (s.inFlight !== "sync") {
            break;
        }
        s.inFlight = null;
        if (ev.kind === "ok") {
            if (s.recovery === "readOnlyFull") {
                // fresh state from a full read; now try the batch once more
                s.recovery = "retryBatch";
                succeed(s, ev, effects);
                startSync(s, now, effects);
                break;
            }
            s.recovery = null;
            succeed(s, ev, effects);
            if (ev.fullSync || ev.moreWork) {
                s.pendingResync = false;
                effects.push({ type: "scheduleFollowUp", ms: FOLLOW_UP_MS });
            } else if (s.pendingResync) {
                requestSync(s, now, effects, true);
            }
            break;
        }
        if (ev.kind === "client") {
            if (s.recovery === null) {
                // invalid sync_token or a bad command: isolate with a command-less full read
                s.recovery = "readOnlyFull";
                startSync(s, now, effects);
                break;
            }
            if (s.recovery === "retryBatch") {
                // the read works, the batch does not: drop it so the queue never gets stuck
                s.recovery = null;
                effects.push({ type: "dropBatch" });
                succeed(s, ev, effects);
                effects.push({ type: "scheduleFollowUp", ms: FOLLOW_UP_MS });
                break;
            }
            // even the full read is rejected
            s.recovery = null;
            s.phase = PHASE_ERROR;
            s.backoffStep = s.backoffStep + 1;
            s.pendingResync = false;
            effects.push({ type: "retryIn", ms: backoffMs(s.backoffStep, randomFn) });
            break;
        }
        fail(s, ev, effects, randomFn);
        break;

    case "QUICK_ADD_DONE":
        if (s.inFlight !== "sync") {
            break;
        }
        s.inFlight = null;
        fail(s, ev, effects, randomFn);
        break;

    default:
        break;
    }
    return { state: s, effects: effects };
}
