.pragma library

// Where a task added from a view should land. Quick Add text is sent untouched (what the user
// typed always wins); the view's context is applied afterwards with uuid-idempotent commands.
//
// context (stored on the queued Quick Add, so it survives going offline / switching views):
//   { kind: "today" | "upcoming" | "inbox" | "project" | "label" | "filter",
//     projectId?, labelName?, date? }   date = "YYYY-MM-DD" for a day picked in Upcoming
// task: Quick Add response (Todoist task object).
// -> [{ kind: "update", args } | { kind: "move", projectId }]

function contextFor(spec, store, date) {
    var ctx = { kind: spec.kind };
    if (spec.kind === "project") {
        ctx.projectId = spec.id;
    } else if (spec.kind === "inbox") {
        ctx.projectId = store && store.inboxProjectId ? store.inboxProjectId : "";
    } else if (spec.kind === "label") {
        var label = store && store.labels ? store.labels[spec.id] : null;
        ctx.labelName = label ? label.name : "";
    }
    if (date) {
        ctx.date = date;
    }
    return ctx;
}

function followUps(context, task, todayKey, inboxProjectId) {
    var out = [];
    if (!task || task.id === undefined || task.id === null) {
        return out;
    }
    var ctx = context || { kind: "today" };
    var undated = !task.due;
    var taskProject = task.project_id !== undefined && task.project_id !== null ? String(task.project_id) : "";

    if (undated && (ctx.date || ctx.kind === "today" || ctx.kind === "upcoming")) {
        out.push({ kind: "update", args: { due: { date: ctx.date || todayKey } } });
    }
    // a project chosen with #name in the text lands elsewhere than the Inbox: respect it
    if (ctx.projectId && taskProject && taskProject === inboxProjectId && ctx.projectId !== inboxProjectId) {
        out.push({ kind: "move", projectId: ctx.projectId });
    }
    if (ctx.labelName) {
        var labels = Array.isArray(task.labels) ? task.labels.slice() : [];
        if (labels.indexOf(ctx.labelName) < 0) {
            labels.push(ctx.labelName);
            out.push({ kind: "update", args: { labels: labels } });
        }
    }
    return out;
}
