import QtQuick

import "logic/DateUtil.js" as DateUtil
import "logic/TaskStore.js" as TaskStore
import "logic/CommandQueue.js" as CommandQueue
import "logic/SyncMachine.js" as SyncMachine
import "logic/TodoistClient.js" as TodoistClient
import "logic/Storage.js" as Storage
import "logic/ViewModel.js" as ViewModel
import "logic/ContextRules.js" as ContextRules
import "logic/Reminders.js" as Reminders
import "logic/Goals.js" as Goals

// Thin effect runner around SyncMachine: owns timers, XHRs and LocalStorage I/O.
// It makes no sync decisions of its own; branches here only dispatch on effect type
// or on a request's result kind.
Item {
    id: controller
    visible: false

    // inputs
    property string token: ""
    property string appletId: ""
    property string pinnedView: ""          // config: view this widget starts with ("" = last used)
    property string badgeSource: "today"    // config: "today" | "view" | "none"
    property string customQuery: ""         // config: unsaved filter query shown as its own list
    property string customQueryName: ""
    readonly property var customQueryOption: customQuery.trim() !== ""
        ? { name: customQueryName.trim() || i18n("Custom filter"), query: customQuery.trim() } : null
    // daily goal ring (config) and its data
    property bool showGoal: true
    property var goalStats: null
    property double goalFetchedAt: 0
    property int completedSinceStats: 0
    readonly property var goal: showGoal ? Goals.progress(goalStats, todayView.todayKey, completedSinceStats) : null
    // minutes before a timed task to notify (0 = at the time, -1 = off)
    property int notifyLeadMinutes: 10
    // reminders put off with "Remind me in 10 minutes": { baseKey: untilMs }
    property var snoozed: ({})
    // parents whose sub-tasks are folded away (per instance, persisted)
    property var collapsed: ({})

    // state for the views
    property var machine: SyncMachine.initialState()
    readonly property string phase: machine.phase
    readonly property bool hasCache: machine.hasCache
    readonly property bool syncing: machine.inFlight !== null
    readonly property bool rateLimited: machine.rateLimited
    readonly property double lastSyncAt: machine.lastSyncAt
    property var store: TaskStore.emptyStore()
    property var queue: CommandQueue.emptyQueue()
    // current view
    property string viewKey: "today"
    readonly property var viewSpec: ViewModel.parseSpec(viewKey)
    property var view: ({ spec: { kind: "today", id: "" }, title: "", exists: true, groups: [], pending: [],
                          counts: { total: 0, overdue: 0, pending: 0 }, todayKey: "", nowMinutes: 0,
                          filterFetchedAt: 0, filterMissing: 0, hasFilterResult: true })
    property var todayView: ({ overdue: [], today: [], pending: [], next: null, todayKey: "", nowMinutes: 0, unparsable: 0,
                               counts: { overdue: 0, today: 0, total: 0, pending: 0 } })
    property var rows: []
    property var nav: []
    property var filterResults: ({})
    property var filterErrors: ({})
    readonly property int count: view.counts.total
    readonly property string viewTitle: {
        switch (viewSpec.kind) {
        case "inbox":
            return i18n("Inbox");
        case "upcoming":
            return i18n("Upcoming");
        case "project":
        case "label":
        case "filter":
        case "query":
            return view.title || "";
        default:
            return i18n("Today");
        }
    }
    readonly property int overdueCount: view.counts.overdue
    readonly property int todayCount: todayView.counts.total
    readonly property int todayOverdueCount: todayView.counts.overdue
    readonly property int badgeCount: badgeSource === "none" ? 0 : (badgeSource === "view" ? count : todayCount)
    readonly property bool badgeAlert: badgeSource === "view" ? overdueCount > 0 : todayOverdueCount > 0
    // first upcoming timed task of today, else the first row of the current view
    readonly property var nextTask: viewSpec.kind === "today" ? todayView.next
                                    : (view.groups.length && view.groups[0].rows.length ? view.groups[0].rows[0] : null)
    readonly property int queuedCount: queue.entries.length
    property double nowMs: Date.now()
    property string infoText: ""
    property bool infoIsError: false
    property var projects: []
    // pending delete that can still be undone
    property string undoUuid: ""
    property string undoText: ""

    readonly property int undoMs: 5000
    readonly property int completeUndoMs: 4000
    // incremented to ask the "New task" field to take focus (global shortcut)
    property int focusNewTaskRequest: 0
    property double focusNewTaskAt: 0

    signal accountVerified(string name)
    // a pinned view pointed at a temporary project id that now has its real id
    signal pinnedViewRemapped(string key)
    // a timed task is coming up (main.qml shows the notification)
    signal reminderDue(string itemId, string title, string body, string baseKey)

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
        property bool undoIsCompletion: false
    }

    function log() {
        var args = ["[todoist-plasma]"];
        for (var i = 0; i < arguments.length; i++) {
            args.push(arguments[i]);
        }
        console.log.apply(console, args);
    }

    function warn() {
        var args = ["[todoist-plasma]"];
        for (var i = 0; i < arguments.length; i++) {
            args.push(arguments[i]);
        }
        console.warn.apply(console, args);
    }

    // ---- public API -------------------------------------------------------

    function requestSync(reason) {
        dispatch({ type: "SYNC_REQUESTED", reason: reason });
    }

    // Held back for completeUndoMs so it can be undone from the footer.
    function complete(itemId, title) {
        if (!TaskStore.isValidId(itemId)) {
            return;
        }
        queue = CommandQueue.enqueueClose(queue, itemId, Date.now(), newUuid, completeUndoMs);
        saveQueue();
        recompute();
        var uuid = CommandQueue.closeUuid(queue, itemId);
        if (uuid) {
            completedSinceStats++;
            priv.undoIsCompletion = true;
            undoUuid = uuid;
            undoText = title ? i18n("Completed “%1”", title) : i18n("Completed");
            undoTimer.interval = completeUndoMs + 200;
            undoTimer.restart();
        }
    }

    // Raises due reminders once. The record of shown reminders is shared by all widget instances.
    function checkReminders() {
        if (!priv.started || !priv.activeToken || !TaskStore.hasData(store)) {
            return;
        }
        var day = todayView.todayKey;
        var sent = Reminders.prune(Storage.loadShared("notified") || {}, day);
        var list = Reminders.due(todayView.today, day, todayView.nowMinutes, Date.now(), notifyLeadMinutes, sent, snoozed);
        if (!list.length) {
            return;
        }
        var z = Object.assign({}, snoozed);
        for (var i = 0; i < list.length; i++) {
            sent[list[i].key] = true;
            if (list[i].snoozed) {
                delete z[list[i].baseKey];
            }
        }
        snoozed = z;
        Storage.saveShared("notified", sent);
        for (var j = 0; j < list.length; j++) {
            var r = list[j];
            var when = timeText(r.minutes);
            var body = r.minutes <= todayView.nowMinutes ? i18n("Now · %1", when)
                                                         : i18np("In %1 minute · %2", "In %1 minutes · %2", r.minutes - todayView.nowMinutes, when);
            reminderDue(r.id, r.title, body, r.baseKey);
        }
    }

    function snooze(baseKey) {
        var z = Object.assign({}, snoozed);
        z[baseKey] = Date.now() + Reminders.SNOOZE_MINUTES * 60000;
        snoozed = z;
    }

    function requestNewTaskFocus() {
        focusNewTaskAt = Date.now();
        focusNewTaskRequest++;
    }

    function setView(key) {
        var spec = ViewModel.parseSpec(key);
        var k = ViewModel.specKey(spec);
        if (k !== viewKey) {
            viewKey = k;
            if (appletId) {
                Storage.save(appletId, "lastView", k);
            }
            recompute();
        }
        if (spec.kind === "filter" || spec.kind === "query") {
            requestSync("view");
        }
    }

    function toggleCollapsed(itemId) {
        var c = Object.assign({}, collapsed);
        if (c[itemId]) {
            delete c[itemId];
        } else {
            c[itemId] = true;
        }
        collapsed = c;
        if (appletId) {
            Storage.save(appletId, "collapsed", JSON.stringify(c));
        }
        recompute();
    }

    // -> "" on success, otherwise "empty" | "too_long". date: "YYYY-MM-DD" when adding to a day in Upcoming.
    function addTask(text, date) {
        var context = ContextRules.contextFor(viewSpec, store, date || "");
        var r = CommandQueue.enqueueQuickAdd(queue, text, Date.now(), newUuid, context);
        if (r.error) {
            return r.error;
        }
        queue = r.queue;
        saveQueue();
        recompute();
        requestSync("action");
        return "";
    }

    function enqueueEdit(newQueue) {
        queue = newQueue;
        saveQueue();
        recompute();
        requestSync("action");
    }

    // which: "today" | "tomorrow" | "weekend" | "nextweek"
    function reschedule(itemId, which) {
        var date = DateUtil.quickDate(view.todayKey, which);
        if (date) {
            setDue(itemId, { date: date });
        }
    }

    // due: { date: "YYYY-MM-DD" | "YYYY-MM-DDTHH:MM:00" } | { string: "<Todoist schedule text>" } | null (no date)
    function setDue(itemId, due) {
        if (!TaskStore.isValidId(itemId)) {
            return;
        }
        enqueueEdit(CommandQueue.enqueueUpdate(queue, itemId, { due: due }, Date.now(), newUuid));
    }

    // priority: Todoist API value, 4 = p1 ... 1 = p4
    function setPriority(itemId, priority) {
        if (TaskStore.isValidId(itemId) && priority >= 1 && priority <= 4) {
            enqueueEdit(CommandQueue.enqueueUpdate(queue, itemId, { priority: priority }, Date.now(), newUuid));
        }
    }

    // -> "" | "empty" | "too_long"
    function rename(itemId, text) {
        var t = String(text || "").trim();
        if (!t) {
            return "empty";
        }
        if (t.length > CommandQueue.MAX_QUICK_ADD_LENGTH) {
            return "too_long";
        }
        if (TaskStore.isValidId(itemId)) {
            enqueueEdit(CommandQueue.enqueueUpdate(queue, itemId, { content: t }, Date.now(), newUuid));
        }
        return "";
    }

    // Creates a project (offline-capable: queued with a temporary id) and switches to it.
    // -> "" | "empty" | "too_long"
    function createProject(name, color, parentId) {
        var r = CommandQueue.enqueueProjectAdd(queue, name, color, parentId, Date.now(), newUuid);
        if (r.error) {
            return r.error;
        }
        queue = r.queue;
        saveQueue();
        recompute();
        setView("project:" + r.tempId);
        requestSync("action");
        return "";
    }

    function moveTo(itemId, projectId) {
        if (TaskStore.isValidId(itemId) && TaskStore.isValidId(String(projectId))) {
            enqueueEdit(CommandQueue.enqueueMove(queue, itemId, projectId, Date.now(), newUuid));
        }
    }

    // Deleted from the list at once; sent to Todoist only after the undo window.
    function remove(itemId, title) {
        if (!TaskStore.isValidId(itemId)) {
            return;
        }
        var r = CommandQueue.enqueueDelete(queue, itemId, Date.now(), undoMs, newUuid);
        if (!r.uuid) {
            return;
        }
        queue = r.queue;
        saveQueue();
        recompute();
        undoUuid = r.uuid;
        priv.undoIsCompletion = false;
        undoText = i18n("Deleted “%1”", title);
        undoTimer.interval = undoMs + 200;
        undoTimer.restart();
    }

    function undoDelete() {
        if (!undoUuid) {
            return;
        }
        queue = CommandQueue.cancelEntry(queue, undoUuid);
        saveQueue();
        if (priv.undoIsCompletion && completedSinceStats > 0) {
            completedSinceStats--;
        }
        recompute();
        undoUuid = "";
        undoTimer.stop();
    }

    function copyLink(itemId) {
        if (!TaskStore.isValidId(itemId)) {
            return;
        }
        clipboardHelper.text = "https://app.todoist.com/app/task/" + itemId;
        clipboardHelper.selectAll();
        clipboardHelper.copy();
        clipboardHelper.text = "";
        showInfo(i18n("Link copied"), false);
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

    // Relative day: Yesterday / Today / Tomorrow / weekday (this week) / "d MMM" (/ "d MMM yyyy")
    function dateText(dateKey) {
        var p = DateUtil.splitDateKey(dateKey);
        if (!p) {
            return "";
        }
        var date = new Date(p.y, p.m - 1, p.d);
        var diff = DateUtil.daysBetween(view.todayKey, dateKey);
        if (diff === -1) {
            return i18n("Yesterday");
        }
        if (diff === 0) {
            return i18n("Today");
        }
        if (diff === 1) {
            return i18n("Tomorrow");
        }
        if (diff > 1 && diff < 7) {
            return Qt.formatDate(date, "dddd");
        }
        var thisYear = DateUtil.splitDateKey(view.todayKey);
        return Qt.formatDate(date, thisYear && thisYear.y === p.y ? "d MMM" : "d MMM yyyy");
    }

    // Upcoming day header: "Today · Saturday 3 October"
    function dayHeaderText(dateKey) {
        var p = DateUtil.splitDateKey(dateKey);
        if (!p) {
            return "";
        }
        var full = Qt.formatDate(new Date(p.y, p.m - 1, p.d), "dddd d MMMM");
        var diff = DateUtil.daysBetween(view.todayKey, dateKey);
        if (diff === 0) {
            return i18nc("day header: Today · weekday date", "Today · %1", full);
        }
        if (diff === 1) {
            return i18nc("day header: Tomorrow · weekday date", "Tomorrow · %1", full);
        }
        return full;
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
            filterResults = {};
            filterErrors = {};
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
                    applyContext(entry.context, res.json);
                    describeAdded(entry.context, res.json);
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
        var commands = mode === "readOnlyFull" ? [] : CommandQueue.nextSyncBatch(queue, CommandQueue.MAX_BATCH, Date.now());
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
            // temporary ids (projects created here) -> real ids, everywhere they are referenced
            if (json.temp_id_mapping) {
                queue = CommandQueue.remapTempIds(queue, json.temp_id_mapping);
                var spec = viewSpec;
                if (spec.kind === "project" && json.temp_id_mapping[spec.id]) {
                    var realKey = "project:" + json.temp_id_mapping[spec.id];
                    if (pinnedView === "project:" + spec.id) {
                        pinnedViewRemapped(realKey);
                    }
                    viewKey = realKey;
                    if (appletId) {
                        Storage.save(appletId, "lastView", realKey);
                    }
                }
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
            if (store.accountId) {
                shareAccount(store.accountId, store.accountName);
            }
            queue = CommandQueue.resolveUncertain(queue, store);
            saveStore();
            saveQueue();
            reportDropped(dropped, titles);
            recompute();
            var more = moreQuickAdds || CommandQueue.nextQuickAdd(queue) !== null
                || (commands.length >= CommandQueue.MAX_BATCH && CommandQueue.nextSyncBatch(queue, 1, Date.now()).length > 0);
            var done = function () {
                dispatch({ type: "REQUEST_DONE", kind: "ok", fullSync: !!json.full_sync, hadCommands: commands.length > 0, moreWork: more });
            };
            if (mode === "readOnlyFull") {
                done();
            } else {
                runSteps(afterSyncSteps(), done);
            }
        });
    }

    // Extra reads done inside the same sync cycle (one request in flight at a time).
    function afterSyncSteps() {
        var steps = [];
        if (viewSpec.kind === "filter" && store.filters[viewSpec.id]) {
            var fid = viewSpec.id;
            steps.push(function (next) { fetchFilter(fid, store.filters[fid].query, null, [], 0, next); });
        } else if (viewSpec.kind === "query" && customQueryOption) {
            var q = customQueryOption.query;
            steps.push(function (next) { fetchFilter(ViewModel.QUERY_RESULT_KEY, q, null, [], 0, next); });
        }
        if (showGoal && Goals.needsRefresh(goalStats, goalFetchedAt, Date.now(), todayView.todayKey)) {
            steps.push(fetchStats);
        }
        return steps;
    }

    // Productivity stats for the daily goal ring; on failure the ring just stays hidden.
    function fetchStats(next) {
        send(function (cb) {
            return TodoistClient.productivityStats(priv.activeToken, cb);
        }, function (res) {
            goalFetchedAt = Date.now();
            if (res.kind === "ok") {
                var parsed = Goals.parseStats(res.json, todayView.todayKey, store.dailyGoal);
                if (parsed === null) {
                    warn("unexpected productivity stats shape; daily goal hidden");
                }
                goalStats = parsed;
                completedSinceStats = 0;
            }
            next();
        });
    }

    function runSteps(steps, done) {
        if (!steps.length) {
            done();
            return;
        }
        steps[0](function () { runSteps(steps.slice(1), done); });
    }

    // Saved filters and the custom query are evaluated by Todoist; failures never fail the sync cycle.
    // resultKey: filter id or ViewModel.QUERY_RESULT_KEY
    function fetchFilter(filterId, query, cursor, ids, pages, done) {
        send(function (cb) {
            return TodoistClient.filterTasks(priv.activeToken, query, store.lang || "", cursor, cb);
        }, function (res) {
            var errors = Object.assign({}, filterErrors);
            if (res.kind !== "ok") {
                errors[filterId] = res.kind;
                filterErrors = errors;
                recompute();
                done();
                return;
            }
            var page = TodoistClient.filterPage(res.json);
            var all = ids.slice();
            for (var i = 0; i < page.tasks.length; i++) {
                if (page.tasks[i] && page.tasks[i].id !== undefined && page.tasks[i].id !== null) {
                    all.push(String(page.tasks[i].id));
                }
            }
            store = TaskStore.mergeTasks(store, page.tasks);
            if (page.nextCursor && pages < 4) {
                fetchFilter(filterId, query, page.nextCursor, all, pages + 1, done);
                return;
            }
            delete errors[filterId];
            filterErrors = errors;
            var results = Object.assign({}, filterResults);
            results[filterId] = { ids: all, fetchedAt: Date.now() };
            filterResults = results;
            saveStore();
            if (appletId) {
                Storage.save(appletId, "filters", JSON.stringify(filterResults));
            }
            recompute();
            done();
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
                shareAccount(userId, res.json.full_name || res.json.email || "");
                dispatch({ type: "ACCOUNT_VERIFIED", sameAccount: same });
                return;
            }
            dispatch({ type: "VERIFY_FAILED", kind: res.kind === "ok" ? "server" : res.kind, retryAfterSec: res.retryAfterSec });
        });
    }

    // ---- view + persistence -----------------------------------------------

    function recompute() {
        nowMs = Date.now();
        var t = TaskStore.computeToday(store, queue, nowMs, DateUtil.systemOffsetAt);
        if (t.unparsable !== priv.lastUnparsable) {
            priv.lastUnparsable = t.unparsable;
            if (t.unparsable > 0) {
                warn("tasks with unparsable due dates:", t.unparsable);
            }
        }
        todayView = t;
        var options = { collapsed: collapsed, customQuery: customQueryOption };
        var v = ViewModel.computeView(store, queue, viewSpec, nowMs, DateUtil.systemOffsetAt, filterResults, options);
        if (!v.exists && TaskStore.hasData(store)) {
            // the project/label/filter was deleted or archived in Todoist
            viewKey = "today";
            if (infoText === "") {
                showInfo(i18n("That list no longer exists in Todoist. Showing Today."), false);
            }
            v = ViewModel.computeView(store, queue, viewSpec, nowMs, DateUtil.systemOffsetAt, filterResults, options);
        }
        view = v;
        rows = ViewModel.flattenView(v);
        nav = ViewModel.navList(store, queue, nowMs, DateUtil.systemOffsetAt, filterResults, options);
        // reassign only on change: menus rebuild their items whenever this list is replaced
        var nextProjects = TaskStore.projectList(TaskStore.withPendingProjects(store, queue));
        if (JSON.stringify(nextProjects) !== JSON.stringify(projects)) {
            projects = nextProjects;
        }
    }

    // Lets other widget instances offer this account in their setup screen (token reuse only:
    // caches and queues stay per instance, see the v2.1 plan F3).
    function shareAccount(userId, name) {
        if (!priv.activeToken || !userId) {
            return;
        }
        var current = Storage.loadShared("account");
        if (current && current.token === priv.activeToken && current.userId === userId && current.name === name) {
            return;
        }
        Storage.saveShared("account", { token: priv.activeToken, userId: userId, name: name });
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

    // The view the task was added from decides where it lands (ContextRules); the commands go
    // out uuid-idempotently in this same cycle's /sync request.
    function applyContext(context, task) {
        if (!task || task.id === undefined || task.id === null || !TaskStore.isValidId(String(task.id))) {
            return;
        }
        var cmds = ContextRules.followUps(context, task, view.todayKey, store.inboxProjectId || "");
        for (var i = 0; i < cmds.length; i++) {
            if (cmds[i].kind === "move" && TaskStore.isValidId(cmds[i].projectId)) {
                queue = CommandQueue.enqueueMove(queue, String(task.id), cmds[i].projectId, Date.now(), newUuid);
            } else if (cmds[i].kind === "update") {
                queue = CommandQueue.enqueueUpdate(queue, String(task.id), cmds[i].args, Date.now(), newUuid);
            }
        }
        saveQueue();
    }

    // Tell the user where a task went when it won't appear in the list they added it from.
    function describeAdded(context, task) {
        var kind = context ? context.kind : "today";
        if (!task || !task.due || (kind !== "today" && kind !== "upcoming")) {
            return;
        }
        var due = DateUtil.parseDue(task.due, DateUtil.makeOffsetFn(store.tz, DateUtil.systemOffsetAt));
        var lastVisible = kind === "today" ? view.todayKey : DateUtil.addDaysKey(view.todayKey, ViewModel.UPCOMING_DAYS - 1);
        if (due && due.dateKey <= lastVisible) {
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
        if (d.kind === "project_add") {
            showInfo(/LIMIT/i.test(d.errorTag || "")
                     ? i18n("Couldn't create “%1”: your Todoist plan's project limit is reached.", d.name)
                     : i18n("Couldn't create the project “%1”.", d.name), true);
        } else if (d.kind === "update" || d.kind === "move" || d.kind === "delete") {
            var changed = titles[d.itemId] || "";
            showInfo(changed ? i18n("Couldn't save a change to “%1” — it may have been deleted.", changed)
                             : i18n("Couldn't save a change to a task — it may have been deleted."), true);
        } else if (d.kind === "close") {
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
    // Plain QML has no clipboard API; a hidden TextEdit can copy.
    TextEdit {
        id: clipboardHelper
        visible: false
    }
    Timer {
        id: undoTimer
        interval: controller.undoMs + 200
        onTriggered: {
            controller.undoUuid = "";
            controller.requestSync("action");
        }
    }
    Timer {
        id: infoTimer
        interval: 4000
        onTriggered: controller.infoText = ""
    }
    Timer {
        id: reminderTimer
        interval: 30 * 1000
        repeat: true
        running: true
        onTriggered: controller.checkReminders()
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

    onCustomQueryChanged: {
        if (!priv.started) {
            return;
        }
        var results = Object.assign({}, filterResults);
        delete results[ViewModel.QUERY_RESULT_KEY];
        filterResults = results;
        recompute();
        if (viewSpec.kind === "query") {
            requestSync("view");
        }
    }
    onCustomQueryNameChanged: if (priv.started) recompute()

    onPinnedViewChanged: {
        if (priv.started && pinnedView) {
            setView(pinnedView);
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
        var previous = priv.activeToken;
        priv.activeToken = t;
        if (!t) {
            // disconnecting here also withdraws the offer to other instances
            var shared = Storage.loadShared("account");
            if (shared && shared.token === previous) {
                Storage.saveShared("account", null);
            }
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
            try {
                var f = JSON.parse(Storage.load(appletId, "filters") || "{}");
                filterResults = f && typeof f === "object" ? f : {};
            } catch (err) {
                filterResults = {};
            }
            try {
                var c = JSON.parse(Storage.load(appletId, "collapsed") || "{}");
                collapsed = c && typeof c === "object" ? c : {};
            } catch (err2) {
                collapsed = {};
            }
            // a pinned view is the starting point; otherwise continue where the user left off
            viewKey = ViewModel.specKey(ViewModel.parseSpec(pinnedView || Storage.load(appletId, "lastView") || "today"));
        }
        priv.activeToken = token.trim();
        priv.started = true;
        recompute();
        dispatch({ type: "INIT", hasToken: priv.activeToken !== "", hasCache: TaskStore.hasData(store) });
    }
}
