.pragma library
.import "DateUtil.js" as DateUtil

// Pure task cache: merges Todoist v1 /sync responses (all open tasks, projects, sections,
// labels, filters) and derives the Today view. Other views live in ViewModel.js.
// Never mutates its inputs; every function returns new objects.

var SCHEMA_VERSION = 2;

// Items added this recently are remembered (id/content/addedAt only) even if they have no
// due date, so CommandQueue.resolveUncertain can recognise a Quick Add the server already
// processed although the task itself never enters the Today cache.
var RECENT_WINDOW_MS = 30 * 60 * 1000;

function emptyStore() {
    return {
        v: SCHEMA_VERSION,
        accountId: null,
        accountName: "",
        syncToken: "*",
        lastSyncAt: 0,
        tz: null,
        inboxProjectId: null,
        items: {},
        projects: {},
        sections: {},
        labels: {},
        filters: {},
        orderKeys: {},
        recent: {}
    };
}

var MAP_KEYS = ["items", "projects", "sections", "labels", "filters", "orderKeys", "recent"];

function copyMap(m) {
    var out = {};
    for (var k in m) {
        if (Object.prototype.hasOwnProperty.call(m, k)) {
            out[k] = m[k];
        }
    }
    return out;
}

function copyStore(store) {
    var s = {};
    for (var k in store) {
        if (Object.prototype.hasOwnProperty.call(store, k)) {
            s[k] = store[k];
        }
    }
    for (var i = 0; i < MAP_KEYS.length; i++) {
        s[MAP_KEYS[i]] = copyMap(store[MAP_KEYS[i]] || {});
    }
    return s;
}

function isValidId(id) {
    return typeof id === "string" && /^[A-Za-z0-9]+$/.test(id);
}

// Todoist content is Markdown; we render plain text only.
function plainTitle(content) {
    var s = String(content === undefined || content === null ? "" : content);
    s = s.replace(/!?\[([^\]]*)\]\(([^)]*)\)/g, "$1");      // [text](url), ![alt](src)
    s = s.replace(/<(https?:\/\/[^>\s]+)>/g, "$1");          // <https://autolink>
    s = s.replace(/(\*\*|__|~~)(.+?)\1/g, "$2");             // **bold** __bold__ ~~strike~~
    s = s.replace(/(^|[^\w*])\*(?!\s)([^*]+?)\*(?!\w)/g, "$1$2"); // *italic*
    s = s.replace(/(^|[^\w_])_(?!\s)([^_]+?)_(?!\w)/g, "$1$2");   // _italic_
    s = s.replace(/`([^`]*)`/g, "$1");                       // `code`
    s = s.replace(/^\s*\*\s+/, "");                          // "* " = uncompletable marker
    s = s.replace(/\s+/g, " ").trim();
    return s;
}

function normalizeItem(raw) {
    var due = raw.due ? {
        date: raw.due.date,
        timezone: raw.due.timezone || null,
        isRecurring: !!raw.due.is_recurring,
        string: raw.due.string || ""
    } : null;
    return {
        id: String(raw.id),
        content: raw.content || "",
        projectId: raw.project_id !== undefined && raw.project_id !== null ? String(raw.project_id) : null,
        parentId: raw.parent_id !== undefined && raw.parent_id !== null ? String(raw.parent_id) : null,
        priority: typeof raw.priority === "number" ? raw.priority : 1,
        due: due,
        sectionId: raw.section_id !== undefined && raw.section_id !== null ? String(raw.section_id) : null,
        labels: Array.isArray(raw.labels) ? raw.labels.slice() : [],
        description: typeof raw.description === "string" ? raw.description.split("\n")[0].slice(0, 200) : "",
        dayOrder: typeof raw.day_order === "number" ? raw.day_order : -1,
        childOrder: typeof raw.child_order === "number" ? raw.child_order : 0,
        addedAt: DateUtil.parseIsoUtc(raw.added_at)
    };
}

// resp: parsed /sync JSON. sysOffsetAt: (ms) -> system offset (injected for tests).
function applySyncResponse(store, resp, nowMs, sysOffsetAt) {
    var s = copyStore(store || emptyStore());
    var sys = sysOffsetAt || DateUtil.systemOffsetAt;
    var i;
    if (!resp) {
        return s;
    }
    if (resp.full_sync) {
        s.items = {};
        s.projects = {};
        s.sections = {};
        s.labels = {};
        s.filters = {};
        s.orderKeys = {};
    }

    var items = resp.items || [];
    for (i = 0; i < items.length; i++) {
        var raw = items[i];
        if (!raw || raw.id === undefined || raw.id === null) {
            continue;
        }
        var id = String(raw.id);
        var addedAt = DateUtil.parseIsoUtc(raw.added_at);
        if (addedAt !== null && nowMs - addedAt <= RECENT_WINDOW_MS && !raw.is_deleted) {
            s.recent[id] = { content: raw.content || "", addedAt: addedAt };
        }
        if (raw.checked || raw.is_deleted) {
            delete s.items[id];
        } else {
            s.items[id] = normalizeItem(raw);
        }
    }

    for (var rid in s.recent) {
        if (Object.prototype.hasOwnProperty.call(s.recent, rid) && nowMs - s.recent[rid].addedAt > RECENT_WINDOW_MS) {
            delete s.recent[rid];
        }
    }

    var projects = resp.projects || [];
    for (i = 0; i < projects.length; i++) {
        var p = projects[i];
        if (!p || p.id === undefined || p.id === null) {
            continue;
        }
        if (p.is_deleted || p.is_archived) {
            delete s.projects[String(p.id)];
        } else {
            s.projects[String(p.id)] = {
                name: p.name || "",
                color: p.color || "",
                order: typeof p.child_order === "number" ? p.child_order : 0,
                parentId: p.parent_id !== undefined && p.parent_id !== null ? String(p.parent_id) : null,
                isInbox: !!p.inbox_project
            };
        }
    }

    mergeNamed(s.sections, resp.sections, function (x) {
        return x.is_deleted || x.is_archived;
    }, function (x) {
        return {
            name: x.name || "",
            projectId: x.project_id !== undefined && x.project_id !== null ? String(x.project_id) : null,
            order: typeof x.section_order === "number" ? x.section_order : 0
        };
    });
    mergeNamed(s.labels, resp.labels, function (x) {
        return x.is_deleted;
    }, function (x) {
        return { name: x.name || "", color: x.color || "", order: typeof x.item_order === "number" ? x.item_order : 0 };
    });
    mergeNamed(s.filters, resp.filters, function (x) {
        return x.is_deleted;
    }, function (x) {
        return {
            name: x.name || "",
            query: x.query || "",
            color: x.color || "",
            order: typeof x.item_order === "number" ? x.item_order : 0
        };
    });

    var user = resp.user;
    if (user) {
        if (user.id !== undefined && user.id !== null) {
            s.accountId = String(user.id);
        }
        if (typeof user.full_name === "string") {
            s.accountName = user.full_name;
        }
        if (typeof user.lang === "string") {
            s.lang = user.lang;
        }
        if (user.inbox_project_id !== undefined && user.inbox_project_id !== null) {
            s.inboxProjectId = String(user.inbox_project_id);
        }
        if (user.tz_info) {
            var off = DateUtil.tzInfoOffset(user.tz_info);
            if (off !== null) {
                s.tz = {
                    gmtOffsetMin: off,
                    followSystem: off === sys(nowMs),
                    timezone: user.tz_info.timezone || ""
                };
            }
        }
    }

    var orders = resp.user_item_orders || [];
    for (i = 0; i < orders.length; i++) {
        var o = orders[i];
        if (!o || o.scope !== "day" || String(o.scope_id) !== "0" || o.item_id === undefined || o.item_id === null) {
            continue;
        }
        if (o.is_deleted || o.order_key === null || o.order_key === undefined) {
            delete s.orderKeys[String(o.item_id)];
        } else {
            s.orderKeys[String(o.item_id)] = String(o.order_key);
        }
    }

    // deprecated but still kept in sync by Todoist; used as a fallback order
    var dayOrders = resp.day_orders;
    if (dayOrders && typeof dayOrders === "object") {
        for (var did in dayOrders) {
            if (Object.prototype.hasOwnProperty.call(dayOrders, did) && s.items[did]) {
                var it = copyMap(s.items[did]);
                it.dayOrder = dayOrders[did];
                s.items[did] = it;
            }
        }
    }

    if (typeof resp.sync_token === "string" && resp.sync_token) {
        s.syncToken = resp.sync_token;
    }
    s.lastSyncAt = nowMs;
    return s;
}

// map: target object (mutated; it is already a fresh copy). list: resource array from /sync.
function mergeNamed(map, list, isGone, normalize) {
    if (!Array.isArray(list)) {
        return;
    }
    for (var i = 0; i < list.length; i++) {
        var x = list[i];
        if (!x || x.id === undefined || x.id === null) {
            continue;
        }
        if (isGone(x)) {
            delete map[String(x.id)];
        } else {
            map[String(x.id)] = normalize(x);
        }
    }
}

// Merges task objects from a REST response (same field names as sync items) without touching
// the sync token or other resources. Used for filter results not yet in the cache.
function mergeTasks(store, tasks) {
    var s = copyStore(store || emptyStore());
    for (var i = 0; i < (tasks || []).length; i++) {
        var raw = tasks[i];
        if (!raw || raw.id === undefined || raw.id === null || raw.checked || raw.is_deleted) {
            continue;
        }
        s.items[String(raw.id)] = normalizeItem(raw);
    }
    return s;
}

function sortableDayOrder(v) {
    return typeof v === "number" && v >= 0 ? v : Number.MAX_VALUE;
}

function compareRows(a, b) {
    if (a.dateKey !== b.dateKey) {
        return a.dateKey < b.dateKey ? -1 : 1;
    }
    var at = a.minutes !== null;
    var bt = b.minutes !== null;
    if (at !== bt) {
        return at ? -1 : 1;
    }
    if (at && a.minutes !== b.minutes) {
        return a.minutes - b.minutes;
    }
    var ak = a.orderKey;
    var bk = b.orderKey;
    if (ak !== null || bk !== null) {
        if (ak === null) {
            return 1;
        }
        if (bk === null) {
            return -1;
        }
        if (ak !== bk) {
            return ak < bk ? -1 : 1;
        }
    }
    var ad = sortableDayOrder(a.dayOrder);
    var bd = sortableDayOrder(b.dayOrder);
    if (ad !== bd) {
        return ad < bd ? -1 : 1;
    }
    if (a.priority !== b.priority) {
        return b.priority - a.priority;
    }
    if (a.childOrder !== b.childOrder) {
        return a.childOrder - b.childOrder;
    }
    return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0);
}

// Applies the offline queue to the cache the way the server will once it is sent:
// closed/deleted items disappear, updates/moves are patched in (queue order, later wins).
// -> { items: { id: item }, pending: [{ localId, text, state }] }  (store is not mutated)
function applyOverlay(store, queue) {
    var entries = queue && queue.entries ? queue.entries : [];
    var closing = {};
    var patches = {};
    var pending = [];
    var i;
    for (i = 0; i < entries.length; i++) {
        var e = entries[i];
        if (e.kind === "close" || e.kind === "delete") {
            closing[e.itemId] = true;
        } else if (e.kind === "update" || e.kind === "move") {
            var patch = patches[e.itemId] || {};
            if (e.kind === "move") {
                patch.projectId = e.projectId;
                if (e.sectionId !== undefined) {
                    patch.sectionId = e.sectionId;
                }
                if (e.parentId !== undefined) {
                    patch.parentId = e.parentId;
                }
            } else {
                if (e.args.content !== undefined) {
                    patch.content = e.args.content;
                }
                if (e.args.priority !== undefined) {
                    patch.priority = e.args.priority;
                }
                if (e.args.labels !== undefined) {
                    patch.labels = e.args.labels;
                }
                if (e.args.due !== undefined) {
                    patch.due = e.args.due ? { date: e.args.due.date, isRecurring: false, string: "" } : null;
                }
            }
            patches[e.itemId] = patch;
        } else if (e.kind === "quick_add") {
            pending.push({ localId: e.localId, text: e.text, state: e.state });
        }
    }
    var src = store && store.items ? store.items : {};
    var items = {};
    for (var id in src) {
        if (!Object.prototype.hasOwnProperty.call(src, id) || closing[id]) {
            continue;
        }
        var item = src[id];
        if (patches[id]) {
            item = copyMap(item);
            for (var pk in patches[id]) {
                if (Object.prototype.hasOwnProperty.call(patches[id], pk)) {
                    item[pk] = patches[id][pk];
                }
            }
        }
        items[id] = item;
    }
    return { items: items, pending: pending };
}

// Display row for an item (shared by every view). due: parseDue() result or null.
function makeRow(st, item, due, todayKey, nowMinutes) {
    var project = item.projectId ? (st.projects || {})[item.projectId] : null;
    return {
        id: item.id,
        title: plainTitle(item.content),
        content: item.content,
        priority: item.priority,
        projectId: item.projectId,
        projectName: project && item.projectId !== st.inboxProjectId ? project.name : "",
        sectionId: item.sectionId || null,
        parentId: item.parentId || null,
        labels: item.labels || [],
        description: item.description || "",
        dateKey: due ? due.dateKey : "",
        minutes: due ? due.minutes : null,
        isRecurring: due ? due.isRecurring : false,
        isOverdue: !!due && due.dateKey < todayKey,
        isLate: !!due && due.dateKey === todayKey && due.minutes !== null && due.minutes < nowMinutes,
        orderKey: Object.prototype.hasOwnProperty.call(st.orderKeys || {}, item.id) ? st.orderKeys[item.id] : null,
        dayOrder: item.dayOrder,
        childOrder: item.childOrder
    };
}

// -> { overdue, today, pending, counts, next, todayKey, nowMinutes, unparsable }
function computeToday(store, queue, nowMs, sysOffsetAt) {
    var st = store || emptyStore();
    var offsetAt = DateUtil.makeOffsetFn(st.tz, sysOffsetAt);
    var todayKey = DateUtil.dayKeyAt(nowMs, offsetAt);
    var nowMinutes = DateUtil.minutesOfDayAt(nowMs, offsetAt);
    var ov = applyOverlay(st, queue);
    var pending = ov.pending;
    var i;

    var overdue = [];
    var today = [];
    var unparsable = 0;
    var items = ov.items;
    for (var id in items) {
        if (!Object.prototype.hasOwnProperty.call(items, id)) {
            continue;
        }
        var item = items[id];
        var due = DateUtil.parseDue(item.due, offsetAt);
        if (!due) {
            if (item.due) {
                unparsable++;
            }
            continue;
        }
        if (due.dateKey > todayKey) {
            continue;
        }
        var row = makeRow(st, item, due, todayKey, nowMinutes);
        if (row.isOverdue) {
            overdue.push(row);
        } else {
            today.push(row);
        }
    }
    overdue.sort(compareRows);
    today.sort(compareRows);

    var next = null;
    for (i = 0; i < today.length; i++) {
        if (today[i].minutes !== null && today[i].minutes >= nowMinutes) {
            next = today[i];
            break;
        }
    }
    if (!next) {
        next = overdue.length ? overdue[0] : (today.length ? today[0] : null);
    }

    return {
        overdue: overdue,
        today: today,
        pending: pending,
        counts: {
            overdue: overdue.length,
            today: today.length,
            total: overdue.length + today.length,
            pending: pending.length
        },
        next: next,
        todayKey: todayKey,
        nowMinutes: nowMinutes,
        unparsable: unparsable
    };
}

// Flattens a computeToday() result into uniform rows for a QML ListModel
// (every role always present with the same type). `header` names the section label drawn
// above a row ("" = none): the first overdue row, the first today row (only when overdue
// rows precede it, the big heading already says Today) and the first pending row.
function flattenRows(view) {
    var rows = [];
    function push(r, section, header) {
        rows.push({
            key: "t:" + r.id,
            kind: "task",
            itemId: r.id,
            title: r.title,
            content: r.content || r.title,
            projectId: r.projectId || "",
            priority: r.priority,
            projectName: r.projectName || "",
            dateKey: r.dateKey,
            minutes: r.minutes === null ? -1 : r.minutes,
            isLate: !!r.isLate,
            isRecurring: !!r.isRecurring,
            section: section,
            header: header
        });
    }
    var i;
    for (i = 0; i < view.overdue.length; i++) {
        push(view.overdue[i], "overdue", i === 0 ? "overdue" : "");
    }
    for (i = 0; i < view.today.length; i++) {
        push(view.today[i], "today", i === 0 && view.overdue.length > 0 ? "today" : "");
    }
    for (i = 0; i < view.pending.length; i++) {
        var p = view.pending[i];
        rows.push({
            key: "q:" + p.localId,
            kind: "pending",
            itemId: "",
            title: p.text,
            content: p.text,
            projectId: "",
            priority: 1,
            projectName: "",
            dateKey: "",
            minutes: -1,
            isLate: false,
            isRecurring: false,
            section: "pending",
            header: i === 0 ? "pending" : ""
        });
    }
    return rows;
}

// Projects for a "Move to" menu: Inbox first, then by name. -> [{ id, name, isInbox }]
function projectList(store) {
    var out = [];
    var projects = store && store.projects ? store.projects : {};
    for (var id in projects) {
        if (Object.prototype.hasOwnProperty.call(projects, id)) {
            out.push({ id: id, name: projects[id].name, isInbox: id === store.inboxProjectId });
        }
    }
    out.sort(function (a, b) {
        if (a.isInbox !== b.isInbox) {
            return a.isInbox ? -1 : 1;
        }
        var an = a.name.toLowerCase();
        var bn = b.name.toLowerCase();
        return an < bn ? -1 : (an > bn ? 1 : 0);
    });
    return out;
}

function serialize(store) {
    return JSON.stringify(store);
}

function deserialize(str) {
    var obj;
    try {
        obj = JSON.parse(str);
    } catch (e) {
        return emptyStore();
    }
    if (!obj || typeof obj !== "object" || obj.v !== SCHEMA_VERSION) {
        return emptyStore();
    }
    var base = emptyStore();
    for (var k in obj) {
        if (Object.prototype.hasOwnProperty.call(obj, k)) {
            base[k] = obj[k];
        }
    }
    for (var i = 0; i < MAP_KEYS.length; i++) {
        var key = MAP_KEYS[i];
        base[key] = base[key] && typeof base[key] === "object" ? base[key] : {};
    }
    if (typeof base.syncToken !== "string" || !base.syncToken) {
        base.syncToken = "*";
    }
    return base;
}

function hasData(store) {
    return !!store && store.syncToken !== "*" && store.lastSyncAt > 0;
}
