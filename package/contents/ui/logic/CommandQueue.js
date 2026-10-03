.pragma library
.import "TaskStore.js" as TaskStore

// Pure, persistent offline queue of user actions.
//   { kind: "close", uuid, itemId, createdAt, attempts }                       -> sync item_close
//   { kind: "quick_add", localId, text, createdAt, attempts, state, sentAt }   -> POST /tasks/quick
// Every function returns a new queue; inputs are never mutated.

var SCHEMA_VERSION = 1;
var MAX_ATTEMPTS = 20;
var MAX_QUICK_ADD_LENGTH = 1000;
var MAX_BATCH = 100;
// resolveUncertain: a created task must have been added within this window around sentAt
var MATCH_BEFORE_MS = 120 * 1000;
var MATCH_AFTER_MS = 600 * 1000;

function emptyQueue() {
    return { v: SCHEMA_VERSION, entries: [] };
}

function withEntries(entries) {
    return { v: SCHEMA_VERSION, entries: entries };
}

function copyEntry(e) {
    var out = {};
    for (var k in e) {
        if (Object.prototype.hasOwnProperty.call(e, k)) {
            out[k] = e[k];
        }
    }
    return out;
}

// RFC 4122 version 4 UUID from an injectable random source.
function uuid4(randomFn) {
    var rnd = randomFn || Math.random;
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
        var r = Math.floor(rnd() * 16) & 15;
        return (c === "x" ? r : ((r & 3) | 8)).toString(16);
    });
}

function hasClose(queue, itemId) {
    var entries = queue.entries;
    for (var i = 0; i < entries.length; i++) {
        if (entries[i].kind === "close" && entries[i].itemId === itemId) {
            return true;
        }
    }
    return false;
}

function enqueueClose(queue, itemId, nowMs, uuidFn) {
    var id = String(itemId);
    if (hasClose(queue, id)) {
        return queue;
    }
    var entries = queue.entries.slice();
    entries.push({ kind: "close", uuid: uuidFn(), itemId: id, createdAt: nowMs, attempts: 0 });
    return withEntries(entries);
}

// -> { queue, error: null | "empty" | "too_long", localId }
function enqueueQuickAdd(queue, text, nowMs, uuidFn) {
    var t = String(text === undefined || text === null ? "" : text).trim();
    if (!t) {
        return { queue: queue, error: "empty", localId: null };
    }
    if (t.length > MAX_QUICK_ADD_LENGTH) {
        return { queue: queue, error: "too_long", localId: null };
    }
    var localId = uuidFn();
    var entries = queue.entries.slice();
    entries.push({ kind: "quick_add", localId: localId, text: t, createdAt: nowMs, attempts: 0, state: "pending", sentAt: null });
    return { queue: withEntries(entries), error: null, localId: localId };
}

// -> [{ type: "item_close", uuid, args: { id } }, ...] (at most `max`)
function nextSyncBatch(queue, max) {
    var limit = max || MAX_BATCH;
    var out = [];
    var entries = queue.entries;
    for (var i = 0; i < entries.length && out.length < limit; i++) {
        if (entries[i].kind === "close") {
            out.push({ type: "item_close", uuid: entries[i].uuid, args: { id: entries[i].itemId } });
        }
    }
    return out;
}

function isTransientStatus(st) {
    if (!st || typeof st !== "object") {
        return false;
    }
    var code = st.http_code;
    return code === 429 || (typeof code === "number" && code >= 500)
        || !!(st.error_extra && st.error_extra.retry_after !== undefined && st.error_extra.retry_after !== null);
}

// -> { queue, dropped: [{ kind, itemId, errorTag, httpCode }], retryAfterSec: number|null }
function applySyncStatus(queue, sentUuids, syncStatus) {
    var sent = {};
    var i;
    for (i = 0; i < (sentUuids || []).length; i++) {
        sent[sentUuids[i]] = true;
    }
    var status = syncStatus || {};
    var kept = [];
    var dropped = [];
    var retryAfterSec = null;
    for (i = 0; i < queue.entries.length; i++) {
        var e = queue.entries[i];
        if (e.kind !== "close" || !sent[e.uuid] || !Object.prototype.hasOwnProperty.call(status, e.uuid)) {
            kept.push(e);
            continue;
        }
        var st = status[e.uuid];
        if (st === "ok") {
            continue;
        }
        if (isTransientStatus(st)) {
            var ra = st.error_extra && typeof st.error_extra.retry_after === "number" ? st.error_extra.retry_after : null;
            if (ra !== null && (retryAfterSec === null || ra > retryAfterSec)) {
                retryAfterSec = ra;
            }
            var next = copyEntry(e);
            next.attempts = (e.attempts || 0) + 1;
            if (next.attempts >= MAX_ATTEMPTS) {
                dropped.push({ kind: "close", itemId: e.itemId, errorTag: st.error_tag || "", httpCode: st.http_code || 0 });
            } else {
                kept.push(next);
            }
            continue;
        }
        dropped.push({
            kind: "close",
            itemId: e.itemId,
            errorTag: st && st.error_tag ? st.error_tag : "",
            httpCode: st && st.http_code ? st.http_code : 0
        });
    }
    return { queue: withEntries(kept), dropped: dropped, retryAfterSec: retryAfterSec };
}

// Removes close entries whose uuid is in `uuids` (recovery path: a batch the server keeps rejecting).
// -> { queue, dropped }
function dropByUuids(queue, uuids) {
    var set = {};
    for (var i = 0; i < (uuids || []).length; i++) {
        set[uuids[i]] = true;
    }
    var kept = [];
    var dropped = [];
    for (var j = 0; j < queue.entries.length; j++) {
        var e = queue.entries[j];
        if (e.kind === "close" && set[e.uuid]) {
            dropped.push({ kind: "close", itemId: e.itemId, errorTag: "BATCH_REJECTED", httpCode: 400 });
        } else {
            kept.push(e);
        }
    }
    return { queue: withEntries(kept), dropped: dropped };
}

function nextQuickAdd(queue) {
    for (var i = 0; i < queue.entries.length; i++) {
        var e = queue.entries[i];
        if (e.kind === "quick_add" && e.state === "pending") {
            return e;
        }
    }
    return null;
}

function mapQuickAdd(queue, localId, fn) {
    var entries = [];
    for (var i = 0; i < queue.entries.length; i++) {
        var e = queue.entries[i];
        if (e.kind === "quick_add" && e.localId === localId) {
            var r = fn(copyEntry(e));
            if (r) {
                entries.push(r);
            }
        } else {
            entries.push(e);
        }
    }
    return withEntries(entries);
}

function findQuickAdd(queue, localId) {
    for (var i = 0; i < queue.entries.length; i++) {
        if (queue.entries[i].kind === "quick_add" && queue.entries[i].localId === localId) {
            return queue.entries[i];
        }
    }
    return null;
}

function markQuickAddSent(queue, localId, nowMs) {
    return mapQuickAdd(queue, localId, function (e) {
        e.sentAt = nowMs;
        e.attempts = (e.attempts || 0) + 1;
        return e;
    });
}

// kind: TodoistClient result kind. -> { queue, dropped: [{ kind: "quick_add", text, reason }] }
function markQuickAddResult(queue, localId, kind) {
    var entry = findQuickAdd(queue, localId);
    if (!entry) {
        return { queue: queue, dropped: [] };
    }
    if (kind === "ok") {
        return { queue: mapQuickAdd(queue, localId, function () { return null; }), dropped: [] };
    }
    if (kind === "client" || (entry.attempts || 0) >= MAX_ATTEMPTS) {
        return {
            queue: mapQuickAdd(queue, localId, function () { return null; }),
            dropped: [{ kind: "quick_add", text: entry.text, reason: kind }]
        };
    }
    var q = mapQuickAdd(queue, localId, function (e) {
        if (kind === "network" && e.sentAt !== null && e.sentAt !== undefined) {
            e.state = "uncertain";   // the server may have created it before the connection dropped
        } else {
            e.state = "pending";
            e.sentAt = null;
        }
        return e;
    });
    return { queue: q, dropped: [] };
}

// Removes Quick Add syntax tokens that never appear in the created task's content.
function stripQuickAddSyntax(text) {
    var s = String(text || "");
    s = s.replace(/(^|\s)\/\/.*$/, " ");              // " // description"
    s = s.replace(/\{[^}]*\}/g, " ");                  // {deadline}
    s = s.replace(/(^|\s)[#@\/+!][^\s]*/g, " ");       // #project @label /section +assignee !reminder !!1
    s = s.replace(/(^|\s)p[1-4](?=\s|$)/gi, " ");      // p1..p4
    return s;
}

var PUNCT_RE = /[.,;:!?"'`()\[\]{}<>*_~|\\\/=+&%$^#@‘’“”«»…–—-]/g;

function normWords(text) {
    var s = String(text || "").toLowerCase().replace(PUNCT_RE, " ");
    var parts = s.split(/\s+/);
    var out = [];
    for (var i = 0; i < parts.length; i++) {
        if (parts[i]) {
            out.push(parts[i]);
        }
    }
    return out;
}

function isSubset(small, big) {
    if (!small.length) {
        return false;
    }
    var set = {};
    for (var i = 0; i < big.length; i++) {
        set[big[i]] = true;
    }
    for (var j = 0; j < small.length; j++) {
        if (!set[small[j]]) {
            return false;
        }
    }
    return true;
}

function candidatesOf(store) {
    var list = [];
    var seen = {};
    var k;
    var items = store && store.items ? store.items : {};
    var recent = store && store.recent ? store.recent : {};
    for (k in recent) {
        if (Object.prototype.hasOwnProperty.call(recent, k)) {
            seen[k] = true;
            list.push({ content: recent[k].content, addedAt: recent[k].addedAt });
        }
    }
    for (k in items) {
        if (Object.prototype.hasOwnProperty.call(items, k) && !seen[k]) {
            list.push({ content: items[k].content, addedAt: items[k].addedAt });
        }
    }
    return list;
}

// After a successful sync: an "uncertain" Quick Add whose task shows up in the store is done;
// otherwise it goes back to "pending" and will be sent again.
function resolveUncertain(queue, store) {
    var candidates = null;
    var changed = false;
    var entries = [];
    for (var i = 0; i < queue.entries.length; i++) {
        var e = queue.entries[i];
        if (e.kind !== "quick_add" || e.state !== "uncertain") {
            entries.push(e);
            continue;
        }
        changed = true;
        if (candidates === null) {
            candidates = candidatesOf(store);
        }
        var textWords = normWords(stripQuickAddSyntax(e.text));
        var best = null;
        for (var j = 0; j < candidates.length; j++) {
            var c = candidates[j];
            if (typeof c.addedAt !== "number" || c.addedAt < e.sentAt - MATCH_BEFORE_MS || c.addedAt > e.sentAt + MATCH_AFTER_MS) {
                continue;
            }
            if (!isSubset(normWords(TaskStore.plainTitle(c.content)), textWords)) {
                continue;
            }
            if (best === null || Math.abs(c.addedAt - e.sentAt) < Math.abs(best.addedAt - e.sentAt)) {
                best = c;
            }
        }
        if (best === null) {
            var back = copyEntry(e);
            back.state = "pending";
            back.sentAt = null;
            entries.push(back);
        }
    }
    return changed ? withEntries(entries) : queue;
}

// On startup: a Quick Add that was in flight when the process died may already exist on the
// server, so it is treated like a dropped connection ("uncertain") instead of being resent blindly.
function recoverAfterRestart(queue) {
    var changed = false;
    var entries = [];
    for (var i = 0; i < queue.entries.length; i++) {
        var e = queue.entries[i];
        if (e.kind === "quick_add" && e.state === "pending" && e.sentAt !== null && e.sentAt !== undefined) {
            var u = copyEntry(e);
            u.state = "uncertain";
            entries.push(u);
            changed = true;
        } else {
            entries.push(e);
        }
    }
    return changed ? withEntries(entries) : queue;
}

function countByKind(queue) {
    var c = { close: 0, quickAdd: 0, total: 0 };
    for (var i = 0; i < queue.entries.length; i++) {
        if (queue.entries[i].kind === "close") {
            c.close++;
        } else {
            c.quickAdd++;
        }
        c.total++;
    }
    return c;
}

function serialize(queue) {
    return JSON.stringify(queue);
}

function deserialize(str) {
    var obj;
    try {
        obj = JSON.parse(str);
    } catch (e) {
        return emptyQueue();
    }
    if (!obj || obj.v !== SCHEMA_VERSION || !Array.isArray(obj.entries)) {
        return emptyQueue();
    }
    var entries = [];
    for (var i = 0; i < obj.entries.length; i++) {
        var e = obj.entries[i];
        if (e && (e.kind === "close" && e.uuid && e.itemId) || (e && e.kind === "quick_add" && e.localId && e.text)) {
            entries.push(e);
        }
    }
    return withEntries(entries);
}
