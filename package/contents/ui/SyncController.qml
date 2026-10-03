import QtQuick

import "logic/DateUtil.js" as DateUtil
import "logic/TaskStore.js" as TaskStore
import "logic/CommandQueue.js" as CommandQueue
import "logic/SyncMachine.js" as SyncMachine
import "logic/TodoistClient.js" as TodoistClient
import "logic/Storage.js" as Storage

// Thin effect runner around SyncMachine: owns timers, XHRs and LocalStorage I/O.
// It makes no sync decisions of its own; branches here only dispatch on effect type
// or on a request's result kind.
Item {
    id: controller
    visible: false

    // inputs
    property string token: ""
    property string appletId: ""

    // state for the views
    property var machine: SyncMachine.initialState()
    readonly property string phase: machine.phase
    readonly property bool hasCache: machine.hasCache
    readonly property bool syncing: machine.inFlight !== null
    readonly property bool rateLimited: machine.rateLimited
    readonly property double lastSyncAt: machine.lastSyncAt
    property var store: TaskStore.emptyStore()
    property var queue: CommandQueue.emptyQueue()
    property var view: ({ overdue: [], today: [], pending: [], next: null, todayKey: "", nowMinutes: 0, unparsable: 0,
                          counts: { overdue: 0, today: 0, total: 0, pending: 0 } })
    property var rows: []
    readonly property int count: view.counts.total
    readonly property int overdueCount: view.counts.overdue
    readonly property int queuedCount: queue.entries.length
    property double nowMs: Date.now()
    property string infoText: ""
    property bool infoIsError: false

    signal accountVerified(string name)

    QtObject {
        id: priv
        property bool started: false
        property string activeToken: ""
        property var xhr: null
        property var finish: null
        property int reqGen: 0
        property double reqStartedAt: 0
        property var lastBatchUuids: []
        property int lastUnparsable: 0
    }

    function log() {
        var args = ["[todoist-today]"];
        for (var i = 0; i < arguments.length; i++) {
            args.push(arguments[i]);
        }
        console.log.apply(console, args);
    }

    function warn() {
        var args = ["[todoist-today]"];
        for (var i = 0; i < arguments.length; i++) {
            args.push(arguments[i]);
        }
        console.warn.apply(console, args);
    }

    // ---- public API -------------------------------------------------------

    function requestSync(reason) {
        dispatch({ type: "SYNC_REQUESTED", reason: reason });
    }

    function complete(itemId) {
        if (!TaskStore.isValidId(itemId)) {
            return;
        }
        queue = CommandQueue.enqueueClose(queue, itemId, Date.now(), newUuid);
        saveQueue();
        recompute();
        requestSync("action");
    }

    // -> "" on success, otherwise "empty" | "too_long"
    function addTask(text) {
        var r = CommandQueue.enqueueQuickAdd(queue, text, Date.now(), newUuid);
        if (r.error) {
            return r.error;
        }
        queue = r.queue;
        saveQueue();
        recompute();
        requestSync("action");
        return "";
    }

    function showInfo(text, isError) {
        infoText = text;
        infoIsError = !!isError;
        infoTimer.interval = isError ? 6000 : 4000;
        infoTimer.restart();
    }

    function timeText(minutes) {
        if (minutes === undefined || minutes === null || minutes < 0) {
            return "";
        }
        var d = new Date(2000, 0, 1, Math.floor(minutes / 60), minutes % 60);
        return Qt.formatTime(d, Qt.locale().timeFormat(Locale.ShortFormat));
    }

    function dateText(dateKey) {
        var p = DateUtil.splitDateKey(dateKey);
        if (!p) {
            return "";
        }
        var days = DateUtil.daysBetween(dateKey, view.todayKey);
        if (days === 1) {
            return i18n("Yesterday");
        }
        return Qt.formatDate(new Date(p.y, p.m - 1, p.d), "d MMM");
    }

    // ---- machine plumbing -------------------------------------------------

    function dispatch(ev) {
        ev.now = Date.now();
        var before = machine.phase;
        var r = SyncMachine.reduce(machine, ev, Math.random);
        machine = r.state;
        if (before !== machine.phase) {
            log("state", before, "→", machine.phase);
        }
        for (var i = 0; i < r.effects.length; i++) {
            runEffect(r.effects[i]);
        }
    }

    function runEffect(e) {
        switch (e.type) {
        case "startRequest":
            runCycle(e.mode);
            break;
        case "verifyAccount":
            verifyAccount();
            break;
        case "abortRequest":
            abortCurrent();
            break;
        case "cancelRetry":
            retryTimer.stop();
            break;
        case "startDebounce":
            debounceTimer.interval = Math.max(1, e.ms);
            debounceTimer.restart();
            break;
        case "retryIn":
            log("retry in", Math.round(e.ms / 1000), "s");
            retryTimer.interval = Math.max(1, e.ms);
            retryTimer.restart();
            break;
        case "scheduleFollowUp":
            followUpTimer.interval = Math.max(1, e.ms);
            followUpTimer.restart();
            break;
        case "startPeriodic":
            periodicTimer.restart();
            break;
        case "stopTimers":
            periodicTimer.stop();
            retryTimer.stop();
            followUpTimer.stop();
            debounceTimer.stop();
            break;
        case "clearData":
            store = TaskStore.emptyStore();
            queue = CommandQueue.emptyQueue();
            Storage.clear(appletId);
            recompute();
            break;
        case "dropBatch": {
            var r = CommandQueue.dropByUuids(queue, priv.lastBatchUuids);
            queue = r.queue;
            saveQueue();
            reportDropped(r.dropped, {});
            recompute();
            break;
        }
        default:
            warn("unknown effect", e.type);
        }
    }

    // ---- requests ---------------------------------------------------------

    function send(startFn, handler) {
        var gen = ++priv.reqGen;
        var finished = false;
        priv.reqStartedAt = Date.now();
        var finish = function (res) {
            if (finished || gen !== priv.reqGen) {
                return;
            }
            finished = true;
            timeoutTimer.stop();
            priv.xhr = null;
            priv.finish = null;
            log("request", res.kind, res.status, (Date.now() - priv.reqStartedAt) + "ms");
            handler(res);
        };
        priv.finish = finish;
        priv.xhr = startFn(finish);
        timeoutTimer.restart();
    }

    function abortCurrent() {
        priv.reqGen++;
        timeoutTimer.stop();
        var x = priv.xhr;
        priv.xhr = null;
        priv.finish = null;
        if (x) {
            try {
                x.abort();
            } catch (err) {
                // already finished
            }
        }
    }

    function runCycle(mode) {
        if (mode === "readOnlyFull") {
            doSync(mode, false);
            return;
        }
        processQuickAdds(0);
    }

    // Quick Adds go first, one by one, at most 10 per cycle.
    function processQuickAdds(sent) {
        var entry = CommandQueue.nextQuickAdd(queue);
        if (!entry || sent >= 10) {
            doSync("sync", !!entry);
            return;
        }
        var localId = entry.localId;
        var text = entry.text;
        queue = CommandQueue.markQuickAddSent(queue, localId, Date.now());
        saveQueue();
        send(function (cb) {
            return TodoistClient.quickAdd(priv.activeToken, text, cb);
        }, function (res) {
            var r = CommandQueue.markQuickAddResult(queue, localId, res.kind);
            queue = r.queue;
            saveQueue();
            recompute();
            if (res.kind === "ok" || res.kind === "client") {
                if (res.kind === "ok") {
                    describeAdded(res.json);
                } else {
                    reportDropped(r.dropped, {});
                }
                processQuickAdds(sent + 1);
                return;
            }
            dispatch({ type: "QUICK_ADD_DONE", kind: res.kind, retryAfterSec: res.retryAfterSec });
        });
    }

    function doSync(mode, moreQuickAdds) {
        var commands = mode === "readOnlyFull" ? [] : CommandQueue.nextSyncBatch(queue, CommandQueue.MAX_BATCH);
        var uuids = [];
        for (var i = 0; i < commands.length; i++) {
            uuids.push(commands[i].uuid);
        }
        priv.lastBatchUuids = uuids;
        var syncToken = mode === "readOnlyFull" ? "*" : store.syncToken;
        send(function (cb) {
            return TodoistClient.sync(priv.activeToken, { syncToken: syncToken, commands: commands }, cb);
        }, function (res) {
            if (res.kind !== "ok") {
                dispatch({ type: "REQUEST_DONE", kind: res.kind, retryAfterSec: res.retryAfterSec, hadCommands: commands.length > 0 });
                return;
            }
            var json = res.json || {};
            var dropped = [];
            if (commands.length) {
                var st = CommandQueue.applySyncStatus(queue, uuids, json.sync_status);
                queue = st.queue;
                dropped = st.dropped;
            }
            var titles = {};
            for (var j = 0; j < dropped.length; j++) {
                var known = store.items[dropped[j].itemId];
                titles[dropped[j].itemId] = known ? TaskStore.plainTitle(known.content) : "";
            }
            if (json.full_sync) {
                log("full sync");
            }
            store = TaskStore.applySyncResponse(store, json, Date.now(), DateUtil.systemOffsetAt);
            queue = CommandQueue.resolveUncertain(queue, store);
            saveStore();
            saveQueue();
            reportDropped(dropped, titles);
            recompute();
            var more = moreQuickAdds || CommandQueue.nextQuickAdd(queue) !== null
                || (commands.length >= CommandQueue.MAX_BATCH && CommandQueue.nextSyncBatch(queue, 1).length > 0);
            dispatch({ type: "REQUEST_DONE", kind: "ok", fullSync: !!json.full_sync, hadCommands: commands.length > 0, moreWork: more });
        });
    }

    function verifyAccount() {
        send(function (cb) {
            return TodoistClient.getUser(priv.activeToken, cb);
        }, function (res) {
            if (res.kind === "ok" && res.json && res.json.id !== undefined && res.json.id !== null) {
                var userId = String(res.json.id);
                var same = store.accountId !== null && store.accountId === userId;
                accountVerified(res.json.full_name || res.json.email || "");
                dispatch({ type: "ACCOUNT_VERIFIED", sameAccount: same });
                return;
            }
            dispatch({ type: "VERIFY_FAILED", kind: res.kind === "ok" ? "server" : res.kind, retryAfterSec: res.retryAfterSec });
        });
    }

    // ---- view + persistence -----------------------------------------------

    function recompute() {
        nowMs = Date.now();
        var v = TaskStore.computeToday(store, queue, nowMs, DateUtil.systemOffsetAt);
        if (v.unparsable !== priv.lastUnparsable) {
            priv.lastUnparsable = v.unparsable;
            if (v.unparsable > 0) {
                warn("tasks with unparsable due dates:", v.unparsable);
            }
        }
        view = v;
        rows = TaskStore.flattenRows(v);
    }

    function saveStore() {
        if (appletId) {
            Storage.save(appletId, "store", TaskStore.serialize(store));
        }
    }

    function saveQueue() {
        if (appletId) {
            Storage.save(appletId, "queue", CommandQueue.serialize(queue));
        }
    }

    function newUuid() {
        return CommandQueue.uuid4(Math.random);
    }

    function describeAdded(task) {
        if (!task) {
            return;
        }
        var due = DateUtil.parseDue(task.due, DateUtil.makeOffsetFn(store.tz, DateUtil.systemOffsetAt));
        if (due && due.dateKey <= view.todayKey) {
            return; // it will show up in the list with the next sync
        }
        var projectId = task.project_id !== undefined && task.project_id !== null ? String(task.project_id) : "";
        var project = store.projects[projectId];
        var projectName = project && projectId !== store.inboxProjectId ? project.name : i18n("Inbox");
        var dueText = task.due && task.due.string ? task.due.string : "";
        showInfo(dueText ? i18nc("task added: project · due date", "Added to %1 · %2", projectName, dueText)
                         : i18n("Added to %1", projectName), false);
    }

    function reportDropped(dropped, titles) {
        if (!dropped || !dropped.length) {
            return;
        }
        for (var i = 0; i < dropped.length; i++) {
            warn("dropped", dropped[i].kind, dropped[i].errorTag || dropped[i].reason || "", dropped[i].itemId || "");
        }
        var d = dropped[0];
        if (d.kind === "close") {
            var title = titles[d.itemId] || "";
            showInfo(title ? i18n("Couldn't complete “%1” — it may have been deleted.", title)
                           : i18n("Couldn't complete a task — it may have been deleted."), true);
        } else {
            showInfo(i18n("Couldn't add “%1”.", d.text), true);
        }
    }

    // ---- timers -----------------------------------------------------------

    Timer {
        id: timeoutTimer
        interval: 15000
        onTriggered: {
            var f = priv.finish;
            var x = priv.xhr;
            if (f) {
                f({ kind: "network", status: 0, json: undefined, retryAfterSec: null });
            }
            if (x) {
                try {
                    x.abort();
                } catch (err) {
                    // ignore
                }
            }
        }
    }
    Timer {
        id: periodicTimer
        interval: 5 * 60 * 1000
        repeat: true
        onTriggered: controller.requestSync("periodic")
    }
    Timer {
        id: retryTimer
        onTriggered: controller.dispatch({ type: "RETRY_FIRED" })
    }
    Timer {
        id: followUpTimer
        onTriggered: controller.requestSync("followUp")
    }
    Timer {
        id: debounceTimer
        interval: 1000
        onTriggered: controller.dispatch({ type: "DEBOUNCE_FIRED" })
    }
    Timer {
        id: infoTimer
        interval: 4000
        onTriggered: controller.infoText = ""
    }
    // Day rollover, "late" markers and "updated N min ago"; also catches sleep/wake within 60 s.
    Timer {
        id: dayTimer
        interval: 60 * 1000
        repeat: true
        running: true
        onTriggered: {
            var oldKey = controller.view.todayKey;
            controller.recompute();
            if (oldKey && controller.view.todayKey !== oldKey) {
                controller.requestSync("dayChanged");
            }
        }
    }

    onTokenChanged: {
        if (!priv.started) {
            return;
        }
        var t = token.trim();
        if (t === priv.activeToken) {
            return;
        }
        priv.activeToken = t;
        if (!t) {
            dispatch({ type: "TOKEN_CLEARED" });
        } else {
            dispatch({ type: "TOKEN_SET", hasCache: TaskStore.hasData(store) });
        }
    }

    Component.onCompleted: {
        if (appletId) {
            var s = Storage.load(appletId, "store");
            var q = Storage.load(appletId, "queue");
            store = s ? TaskStore.deserialize(s) : TaskStore.emptyStore();
            queue = q ? CommandQueue.recoverAfterRestart(CommandQueue.deserialize(q)) : CommandQueue.emptyQueue();
        }
        priv.activeToken = token.trim();
        priv.started = true;
        recompute();
        dispatch({ type: "INIT", hasToken: priv.activeToken !== "", hasCache: TaskStore.hasData(store) });
    }
}
