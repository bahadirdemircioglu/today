.pragma library
.import "DateUtil.js" as DateUtil
.import "TaskStore.js" as TaskStore
.import "Colors.js" as Colors

// Pure view computation for every navigable view (Inbox, Today, Upcoming, project, label,
// filter) plus the navigation list. Works entirely from the local cache (filters: from the
// last server result), so switching views never waits for the network.

var UPCOMING_DAYS = 7;
var MAX_DEPTH = 4;

// Key under which the custom (unsaved) filter query's server results are kept.
var QUERY_RESULT_KEY = "__query";

// "today" | "upcoming" | "inbox" | "query" | "project:<id>" | "label:<id>" | "filter:<id>"
function parseSpec(key) {
    var s = String(key || "");
    if (s === "today" || s === "upcoming" || s === "inbox" || s === "query") {
        return { kind: s, id: "" };
    }
    var m = /^(project|label|filter):([A-Za-z0-9]+)$/.exec(s);
    return m ? { kind: m[1], id: m[2] } : { kind: "today", id: "" };
}

function specKey(spec) {
    return spec.id ? spec.kind + ":" + spec.id : spec.kind;
}

function byOrderThenName(map) {
    var out = [];
    for (var id in map) {
        if (Object.prototype.hasOwnProperty.call(map, id)) {
            out.push({ id: id, value: map[id] });
        }
    }
    out.sort(function (a, b) {
        if ((a.value.order || 0) !== (b.value.order || 0)) {
            return (a.value.order || 0) - (b.value.order || 0);
        }
        var an = String(a.value.name || "").toLowerCase();
        var bn = String(b.value.name || "").toLowerCase();
        return an < bn ? -1 : (an > bn ? 1 : 0);
    });
    return out;
}

function context(store, queue, nowMs, sysOffsetAt) {
    var st = TaskStore.withPendingProjects(store || TaskStore.emptyStore(), queue);
    var offsetAt = DateUtil.makeOffsetFn(st.tz, sysOffsetAt);
    return {
        st: st,
        offsetAt: offsetAt,
        todayKey: DateUtil.dayKeyAt(nowMs, offsetAt),
        nowMinutes: DateUtil.minutesOfDayAt(nowMs, offsetAt)
    };
}

function rowFor(ctx, item) {
    var due = DateUtil.parseDue(item.due, ctx.offsetAt);
    var row = TaskStore.makeRow(ctx.st, item, due, ctx.todayKey, ctx.nowMinutes);
    row.depth = 0;
    return row;
}

function byChildOrder(a, b) {
    if (a.childOrder !== b.childOrder) {
        return a.childOrder - b.childOrder;
    }
    return a.id < b.id ? -1 : (a.id > b.id ? 1 : 0);
}

// Dated first (by date/time), then undated by priority, then manual order.
function byDateThenPriority(a, b) {
    var ad = a.dateKey !== "";
    var bd = b.dateKey !== "";
    if (ad !== bd) {
        return ad ? -1 : 1;
    }
    if (ad) {
        return TaskStore.compareRows(a, b);
    }
    if (a.priority !== b.priority) {
        return b.priority - a.priority;
    }
    return byChildOrder(a, b);
}

// Project tree: rows grouped by section (no-section group first), sub-tasks under their
// parent with increasing depth.
function projectGroups(ctx, items, projectId, collapsed) {
    var inProject = {};
    var id;
    for (id in items) {
        if (Object.prototype.hasOwnProperty.call(items, id) && items[id].projectId === projectId) {
            inProject[id] = items[id];
        }
    }
    var children = {};
    var roots = [];
    for (id in inProject) {
        if (!Object.prototype.hasOwnProperty.call(inProject, id)) {
            continue;
        }
        var parent = inProject[id].parentId;
        if (parent && inProject[parent]) {
            (children[parent] = children[parent] || []).push(inProject[id]);
        } else {
            roots.push(inProject[id]);
        }
    }

    function walk(item, depth, out) {
        var row = rowFor(ctx, item);
        var kids = (children[item.id] || []).slice().sort(byChildOrder);
        row.depth = Math.min(depth, MAX_DEPTH);
        row.childCount = kids.length;
        row.collapsed = kids.length > 0 && !!(collapsed && collapsed[item.id]);
        out.push(row);
        if (row.collapsed) {
            return;
        }
        for (var k = 0; k < kids.length; k++) {
            walk(kids[k], depth + 1, out);
        }
    }

    var bySection = {};
    for (var r = 0; r < roots.length; r++) {
        var sid = roots[r].sectionId && ctx.st.sections[roots[r].sectionId] ? roots[r].sectionId : "";
        (bySection[sid] = bySection[sid] || []).push(roots[r]);
    }
    var groups = [];
    function addGroup(sectionId, label) {
        var list = (bySection[sectionId] || []).slice().sort(byChildOrder);
        var rows = [];
        for (var i = 0; i < list.length; i++) {
            walk(list[i], 0, rows);
        }
        if (rows.length) {
            groups.push({ key: "s:" + (sectionId || "none"), kind: sectionId ? "section" : "none",
                          label: label, dateKey: "", sectionId: sectionId, rows: rows });
        }
    }
    addGroup("", "");
    var sections = byOrderThenName(ctx.st.sections);
    for (var s = 0; s < sections.length; s++) {
        if (sections[s].value.projectId === projectId) {
            addGroup(sections[s].id, sections[s].value.name);
        }
    }
    return groups;
}

function upcomingGroups(ctx, items) {
    var overdue = [];
    var days = {};
    var keys = [];
    for (var d = 0; d < UPCOMING_DAYS; d++) {
        var k = DateUtil.addDaysKey(ctx.todayKey, d);
        keys.push(k);
        days[k] = [];
    }
    var last = keys[keys.length - 1];
    for (var id in items) {
        if (!Object.prototype.hasOwnProperty.call(items, id)) {
            continue;
        }
        var row = rowFor(ctx, items[id]);
        if (!row.dateKey || row.dateKey > last) {
            continue;
        }
        if (row.dateKey < ctx.todayKey) {
            overdue.push(row);
        } else {
            days[row.dateKey].push(row);
        }
    }
    var groups = [];
    if (overdue.length) {
        overdue.sort(TaskStore.compareRows);
        groups.push({ key: "overdue", kind: "overdue", label: "", dateKey: "", sectionId: "", rows: overdue });
    }
    for (var i = 0; i < keys.length; i++) {
        days[keys[i]].sort(TaskStore.compareRows);
        // empty days keep their header (as on the web) so a task can be added to them
        groups.push({ key: "d:" + keys[i], kind: "day", label: "", dateKey: keys[i], sectionId: "", rows: days[keys[i]] });
    }
    return groups;
}

// filterResults: { "<filterId>" | QUERY_RESULT_KEY: { ids: [...], fetchedAt } }
// options: { collapsed: { "<itemId>": true }, customQuery: { name, query } }
function computeView(store, queue, spec, nowMs, sysOffsetAt, filterResults, options) {
    var opts = options || {};
    var ctx = context(store, queue, nowMs, sysOffsetAt);
    var ov = TaskStore.applyOverlay(ctx.st, queue);
    var groups = [];
    var title = "";
    var missing = 0;
    var fetchedAt = 0;
    var exists = true;

    switch (spec.kind) {
    case "today": {
        var t = TaskStore.computeToday(ctx.st, queue, nowMs, sysOffsetAt);
        if (t.overdue.length) {
            groups.push({ key: "overdue", kind: "overdue", label: "", dateKey: "", sectionId: "", rows: t.overdue });
        }
        if (t.today.length) {
            groups.push({ key: "today", kind: "today", label: "", dateKey: ctx.todayKey, sectionId: "", rows: t.today });
        }
        break;
    }
    case "upcoming":
        groups = upcomingGroups(ctx, ov.items);
        break;
    case "inbox":
    case "project": {
        var pid = spec.kind === "inbox" ? ctx.st.inboxProjectId : spec.id;
        var project = pid ? ctx.st.projects[pid] : null;
        exists = !!project;
        title = project && spec.kind === "project" ? project.name : "";
        if (exists) {
            groups = projectGroups(ctx, ov.items, pid, opts.collapsed);
        }
        break;
    }
    case "label": {
        var label = ctx.st.labels[spec.id];
        exists = !!label;
        title = label ? label.name : "";
        var lrows = [];
        if (label) {
            for (var lid in ov.items) {
                if (Object.prototype.hasOwnProperty.call(ov.items, lid) && (ov.items[lid].labels || []).indexOf(label.name) >= 0) {
                    lrows.push(rowFor(ctx, ov.items[lid]));
                }
            }
        }
        lrows.sort(byDateThenPriority);
        if (lrows.length) {
            groups.push({ key: "all", kind: "none", label: "", dateKey: "", sectionId: "", rows: lrows });
        }
        break;
    }
    case "filter":
    case "query": {
        var isQuery = spec.kind === "query";
        var filter = isQuery ? (opts.customQuery && opts.customQuery.query ? opts.customQuery : null) : ctx.st.filters[spec.id];
        exists = !!filter;
        title = filter ? filter.name || "" : "";
        var res = filterResults && filterResults[isQuery ? QUERY_RESULT_KEY : spec.id];
        var frows = [];
        if (res) {
            fetchedAt = res.fetchedAt || 0;
            for (var f = 0; f < res.ids.length; f++) {
                var fit = ov.items[res.ids[f]];
                if (fit) {
                    frows.push(rowFor(ctx, fit));
                } else if (!ctx.st.items[res.ids[f]]) {
                    missing++;   // not cached yet (closed/deleted ones are simply gone)
                }
            }
        }
        if (frows.length) {
            groups.push({ key: "all", kind: "none", label: "", dateKey: "", sectionId: "", rows: frows });
        }
        break;
    }
    default:
        break;
    }

    var total = 0;
    var overdueCount = 0;
    for (var g = 0; g < groups.length; g++) {
        total += groups[g].rows.length;
        if (groups[g].kind === "overdue") {
            overdueCount += groups[g].rows.length;
        }
    }
    var projectColors = {};
    for (var pc in ctx.st.projects) {
        if (Object.prototype.hasOwnProperty.call(ctx.st.projects, pc)) {
            projectColors[pc] = ctx.st.projects[pc].color;
        }
    }
    var labelColorByName = {};
    for (var lc in ctx.st.labels) {
        if (Object.prototype.hasOwnProperty.call(ctx.st.labels, lc)) {
            labelColorByName[ctx.st.labels[lc].name] = ctx.st.labels[lc].color;
        }
    }
    return {
        spec: spec,
        title: title,
        projectColors: projectColors,
        labelColorByName: labelColorByName,
        exists: exists,
        groups: groups,
        pending: ov.pending,
        counts: { total: total, overdue: overdueCount, pending: ov.pending.length },
        todayKey: ctx.todayKey,
        nowMinutes: ctx.nowMinutes,
        filterFetchedAt: fetchedAt,
        filterMissing: missing,
        hasFilterResult: spec.kind === "query" ? !!(filterResults && filterResults[QUERY_RESULT_KEY])
                         : (spec.kind !== "filter" || !!(filterResults && filterResults[spec.id]))
    };
}

// Uniform rows for the QML ListModel (every role present with the same type in every view).
// header: "" | "overdue" | "today" | "section" | "day" | "pending" — label drawn above the row;
// headerText: section name; headerDate: day key (QML formats it, and day headers get a "+").
function flattenView(view) {
    var rows = [];
    var showDate = view.spec.kind !== "today";
    var hasOverdue = false;
    var g;
    for (g = 0; g < view.groups.length; g++) {
        if (view.groups[g].kind === "overdue") {
            hasOverdue = true;
        }
    }
    function header(group) {
        switch (group.kind) {
        case "overdue":
            return "overdue";
        case "today":
            return hasOverdue ? "today" : "";
        case "section":
            return "section";
        case "day":
            return "day";
        default:
            return "";
        }
    }
    for (g = 0; g < view.groups.length; g++) {
        var group = view.groups[g];
        var h = header(group);
        if (!group.rows.length) {
            if (h === "day") {
                rows.push(blank("h:" + group.key, "day", "", group.dateKey));
            }
            continue;
        }
        for (var i = 0; i < group.rows.length; i++) {
            var r = group.rows[i];
            rows.push({
                key: "t:" + r.id,
                kind: "task",
                itemId: r.id,
                title: r.title,
                content: r.content || r.title,
                projectId: r.projectId || "",
                priority: r.priority,
                projectName: view.spec.kind === "project" || view.spec.kind === "inbox" ? "" : (r.projectName || ""),
                dateKey: r.dateKey || "",
                minutes: r.minutes === null || r.minutes === undefined ? -1 : r.minutes,
                isLate: !!r.isLate,
                isRecurring: !!r.isRecurring,
                isOverdue: !!r.isOverdue,
                showDate: showDate && group.kind !== "day",
                depth: r.depth || 0,
                childCount: r.childCount || 0,
                collapsed: !!r.collapsed,
                labelsText: (r.labels || []).join(", "),
                labelColors: labelColorsOf(view.labelColorByName, r.labels || []),
                projectColor: view.spec.kind === "project" || view.spec.kind === "inbox" || !r.projectName ? ""
                              : Colors.hex(view.projectColors[r.projectId] || ""),
                description: (r.description || "").split("\n")[0].slice(0, 200),
                descriptionFull: r.description || "",
                deadlineKey: r.deadline || "",
                deadlineDue: !!r.deadline && r.deadline <= view.todayKey,
                section: group.kind,
                header: i === 0 ? h : "",
                headerText: i === 0 ? group.label : "",
                headerDate: i === 0 ? group.dateKey : ""
            });
        }
    }
    for (var p = 0; p < view.pending.length; p++) {
        var q = blank("q:" + view.pending[p].localId, p === 0 ? "pending" : "", "", "");
        q.kind = "pending";
        q.title = view.pending[p].text;
        q.content = view.pending[p].text;
        q.section = "pending";
        rows.push(q);
    }
    return rows;
}

// "#hex,#hex" aligned with labelsText ("" for a label without a known colour)
function labelColorsOf(byName, labels) {
    var out = [];
    for (var i = 0; i < labels.length; i++) {
        out.push(Colors.hex((byName || {})[labels[i]] || ""));
    }
    return out.join(",");
}

function blank(key, header, headerText, headerDate) {
    return {
        key: key, kind: "header", itemId: "", title: "", content: "", projectId: "", priority: 1,
        projectName: "", dateKey: "", minutes: -1, isLate: false, isRecurring: false, isOverdue: false,
        showDate: false, depth: 0, childCount: 0, collapsed: false, labelsText: "", labelColors: "", projectColor: "", description: "", descriptionFull: "", deadlineKey: "",
        deadlineDue: false, section: header,
        header: header, headerText: headerText, headerDate: headerDate
    };
}

// Navigation entries with counts. filterResults as in computeView.
// -> [{ key, kind, id, name, count, depth }]  (count -1 = unknown)
function navList(store, queue, nowMs, sysOffsetAt, filterResults, options) {
    var opts = options || {};
    var ctx = context(store, queue, nowMs, sysOffsetAt);
    var ov = TaskStore.applyOverlay(ctx.st, queue);
    var perProject = {};
    var perLabel = {};
    var todayCount = 0;
    var upcomingCount = 0;
    var last = DateUtil.addDaysKey(ctx.todayKey, UPCOMING_DAYS - 1);
    for (var id in ov.items) {
        if (!Object.prototype.hasOwnProperty.call(ov.items, id)) {
            continue;
        }
        var it = ov.items[id];
        perProject[it.projectId] = (perProject[it.projectId] || 0) + 1;
        var ls = it.labels || [];
        for (var l = 0; l < ls.length; l++) {
            perLabel[ls[l]] = (perLabel[ls[l]] || 0) + 1;
        }
        var due = DateUtil.parseDue(it.due, ctx.offsetAt);
        if (due && due.dateKey <= ctx.todayKey) {
            todayCount++;
        }
        if (due && due.dateKey <= last) {
            upcomingCount++;
        }
    }
    var out = [
        { key: "inbox", kind: "inbox", id: "", name: "", count: perProject[ctx.st.inboxProjectId] || 0, depth: 0 },
        { key: "today", kind: "today", id: "", name: "", count: todayCount, depth: 0 },
        { key: "upcoming", kind: "upcoming", id: "", name: "", count: upcomingCount, depth: 0 }
    ];
    if (opts.customQuery && opts.customQuery.query) {
        var qres = filterResults && filterResults[QUERY_RESULT_KEY];
        var qcount = -1;
        if (qres) {
            qcount = 0;
            for (var qi = 0; qi < qres.ids.length; qi++) {
                if (ov.items[qres.ids[qi]]) {
                    qcount++;
                }
            }
        }
        out.push({ key: "query", kind: "query", id: "", name: opts.customQuery.name || "", count: qcount, depth: 0 });
    }

    // projects as a tree (sub-projects indented), Inbox excluded
    var projects = byOrderThenName(ctx.st.projects);
    var kids = {};
    var roots = [];
    var p;
    for (p = 0; p < projects.length; p++) {
        if (projects[p].id === ctx.st.inboxProjectId || projects[p].value.isInbox) {
            continue;
        }
        var parent = projects[p].value.parentId;
        if (parent && ctx.st.projects[parent]) {
            (kids[parent] = kids[parent] || []).push(projects[p]);
        } else {
            roots.push(projects[p]);
        }
    }
    function addProject(entry, depth) {
        out.push({ key: "project:" + entry.id, kind: "project", id: entry.id, name: entry.value.name,
                   count: perProject[entry.id] || 0, depth: Math.min(depth, 3) });
        var c = kids[entry.id] || [];
        for (var k = 0; k < c.length; k++) {
            addProject(c[k], depth + 1);
        }
    }
    for (p = 0; p < roots.length; p++) {
        addProject(roots[p], 0);
    }

    var labels = byOrderThenName(ctx.st.labels);
    for (var lb = 0; lb < labels.length; lb++) {
        out.push({ key: "label:" + labels[lb].id, kind: "label", id: labels[lb].id, name: labels[lb].value.name,
                   count: perLabel[labels[lb].value.name] || 0, depth: 0 });
    }
    var filters = byOrderThenName(ctx.st.filters);
    for (var fl = 0; fl < filters.length; fl++) {
        var res = filterResults && filterResults[filters[fl].id];
        var count = -1;
        if (res) {
            count = 0;
            for (var r = 0; r < res.ids.length; r++) {
                if (ov.items[res.ids[r]]) {
                    count++;
                }
            }
        }
        out.push({ key: "filter:" + filters[fl].id, kind: "filter", id: filters[fl].id, name: filters[fl].value.name,
                   count: count, depth: 0 });
    }
    return out;
}
